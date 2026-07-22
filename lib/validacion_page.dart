import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:barcode_scan2/barcode_scan2.dart';

import 'main.dart'; 
import 'preoperacional_opciones_page.dart';
import 'watermark_service.dart'; // Importamos nuestro servicio unificado

class ValidacionViajePage extends StatefulWidget {
  final Map<String, dynamic> datosServidor; 
  
  const ValidacionViajePage({super.key, required this.datosServidor});

  @override
  _ValidacionViajePageState createState() => _ValidacionViajePageState();
}

class _ValidacionViajePageState extends State<ValidacionViajePage> {
  final TextEditingController _guiaController = TextEditingController();
  final TextEditingController _odometroController = TextEditingController();
  
  int _fotosTomadas = 0;
  final int _limiteFotos = 4;
  final List<File> _listaFotos = []; 
  
  Position? position;
  String _latitudActual = "0.0000";
  String _longitudActual = "0.0000";

  bool _procesandoFoto = false; 
  bool _subiendoViaje = false;  
  bool _viajeExitoso = false;   
  bool _procesandoAceptacion = false; 

  // --- ESCÁNER DE CÓDIGO ---
  Future<void> _escanearGuia() async {
    try {
      var result = await BarcodeScanner.scan();
      if (result.type == ResultType.Barcode && mounted) {
        setState(() {
          _guiaController.text = result.rawContent;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Código leído"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error escáner: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- TOMAR FOTO CON MARCA DE AGUA UNIFICADA (WATERMARK SERVICE) ---
  Future<void> _tomarFotoReal() async {
    if (_procesandoFoto) return;
    if (_fotosTomadas >= _limiteFotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Límite de fotos alcanzado"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _procesandoFoto = true);

    try {
      // 1. Obtención de Coordenadas GPS con alta precisión
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission(); 
      if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high, 
          timeLimit: const Duration(seconds: 5),
        );
        if (position != null) {
          setState(() {
            _latitudActual = position!.latitude.toStringAsFixed(6);
            _longitudActual = position!.longitude.toStringAsFixed(6);
          });
        }
      }

      // 2. Captura con la cámara
      final ImagePicker picker = ImagePicker();
      final XFile? foto = await picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 85, 
        maxWidth: 1280,
      );

      if (foto != null) {
        File archivoTemp = File(foto.path);

        // Preparamos los metadatos para la marca de agua
        String placa = (widget.datosServidor['placa_cabezote'] ?? widget.datosServidor['vehiculo'] ?? "S/P")
            .toString()
            .toUpperCase()
            .trim();
        String fechaHora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        String gpsTexto = "$_latitudActual, $_longitudActual";

        // 3. Procesamos la imagen mediante el WatermarkService (Logo GCT + Sello)
        File fotoProcesada = await WatermarkService.aplicarMarcaDeAgua(
          imagenOriginal: archivoTemp,
          textoPlaca: placa,
          textoGPS: gpsTexto,
          fechaHora: fechaHora,
        );

        if (mounted) {
          setState(() {
            _listaFotos.add(fotoProcesada); 
            _fotosTomadas++;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error procesando foto con marca de agua: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al procesar imagen: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoFoto = false);
    }
  }

  // --- ACEPTAR VIAJE (FASE 1) ---
  Future<void> _aceptarViaje() async {
    setState(() => _procesandoAceptacion = true);
    try {
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
      
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      await conn.execute(
        "UPDATE flutter_schema.active_trips SET fase_viaje = 'ACEPTADO', fecha_aceptado_app = CURRENT_TIMESTAMP WHERE trip_id = \$1",
        parameters: [tripIdReal],
      );
      await conn.close();

      setState(() {
        widget.datosServidor['fase_viaje'] = 'ACEPTADO';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Viaje Aceptado. Ya puede registrar el preoperacional."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error de conexión: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoAceptacion = false);
    }
  }

  // --- SUBIR DATOS Y ACTIVAR VIAJE ---
  Future<void> _subirEvidencias() async {
    setState(() => _subiendoViaje = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Guardando evidencia en base de datos..."), backgroundColor: Colors.orange),
    );

    try {
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
      String celular = widget.datosServidor['celular']?.toString() ?? "";
      String trailer = widget.datosServidor['placa_trailer']?.toString() ?? "";
      String cabezote = widget.datosServidor['placa_cabezote']?.toString() ?? "";
      String preopJsonStr = widget.datosServidor['preoperacional_json']?.toString() ?? '{}';
      
      List<String> linksGenerados = []; 

      // 1. Subida ordenada a Firebase Storage en evidencias_viajes/
      if (_listaFotos.isNotEmpty) {
        for (int i = 0; i < _listaFotos.length; i++) {
          File archivo = _listaFotos[i];
          String nombreArchivo = "inicio_viaje_${tripIdReal}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
          Reference ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombreArchivo');
          
          final imageBytes = await archivo.readAsBytes();
          UploadTask uploadTask = ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
          TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
          String urlTemp = await snapshot.ref.getDownloadURL();
          linksGenerados.add(urlTemp);
        }
      }

      // 2. Conexión e Inserción Segura en PostgreSQL (Transaccional)
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 20)),
      );

      await conn.runTx((session) async {
        // Actualizamos estado general del viaje activo
        await session.execute(
          r'''
          UPDATE flutter_schema.active_trips
          SET 
            is_running = true,
            current_state = 'ON ROUTE',
            fase_viaje = 'EN_RUTA',
            odometer_start = $2,
            tracking_number = $3,
            truck_current_location = $4
          WHERE trip_id = $1
          ''',
          parameters: [
            tripIdReal, 
            int.tryParse(_odometroController.text) ?? 0, 
            _guiaController.text, 
            "$_latitudActual,$_longitudActual"
          ],
        );

        // Registro de evidencias por cada foto tomada
        if (linksGenerados.isNotEmpty) {
          for (String urlFoto in linksGenerados) {
            await session.execute(
               r'''
               INSERT INTO flutter_schema.viajes 
               (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud, trip_id, fecha_registro, preoperacional_data)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, $10)
               ''',
               parameters: [_guiaController.text, _odometroController.text, celular, trailer, cabezote, urlFoto, _latitudActual, _longitudActual, tripIdReal, preopJsonStr]
            );
          }
        } else {
          // Registro de contingencia si inicia viaje sin fotos
          await session.execute(
             r'''
             INSERT INTO flutter_schema.viajes 
             (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud, trip_id, fecha_registro, preoperacional_data)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, $10)
             ''',
             parameters: [_guiaController.text, _odometroController.text, celular, trailer, cabezote, "", _latitudActual, _longitudActual, tripIdReal, preopJsonStr]
          );
        }
      });

      await conn.close();

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ ¡VIAJE INICIADO Y EVIDENCIAS GUARDADAS!"), backgroundColor: Colors.green),
      );

      setState(() {
        _subiendoViaje = false;
        _viajeExitoso = true; 
        widget.datosServidor['fase_viaje'] = 'EN_RUTA'; 
      });

    } catch (e) {
      debugPrint("Error al subir: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error en guardado: $e"), backgroundColor: Colors.red),
        );
        setState(() => _subiendoViaje = false);
      }
    }
  }

  void _editarDato(String titulo, String campo) { 
    TextEditingController tempController = TextEditingController(text: widget.datosServidor[campo]?.toString() ?? "");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Actualizar $titulo"),
        content: TextField(controller: tempController),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () {
              setState(() => widget.datosServidor[campo] = tempController.text);
              Navigator.pop(context);
            },
            child: const Text("GUARDAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String faseActual = widget.datosServidor['fase_viaje']?.toString().toUpperCase() ?? 'ASIGNADO';
    if (_viajeExitoso) faseActual = 'EN_RUTA';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        title: const Text("Validación de Inicio", style: TextStyle(color: Colors.black87, fontSize: 20)),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage())),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity, padding: const EdgeInsets.all(15), margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.blue[900], borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("EMPRESA / CLIENTE:", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text("${widget.datosServidor['empresa_transportadora']} / ${widget.datosServidor['cliente_nombre'] ?? 'ECOPETROL'}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
            Text("Hola, ${widget.datosServidor['nombre']}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.person),
              title: Text("Cédula: ${widget.datosServidor['cedula']}"),
              subtitle: Text("Celular: ${widget.datosServidor['celular']}"),
              trailing: IconButton(icon: const Icon(Icons.edit_note, color: Colors.orange), onPressed: () => _editarDato("Celular", "celular")),
            ),

            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.lightBlue[50], 
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!)
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping, color: Colors.blue, size: 28),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("SU RUTA ASIGNADA:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Text("${widget.datosServidor['ruta_nombre']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 🟢 FASE 1: ASIGNADO
            if (faseActual == 'ASIGNADO') ...[
              const Icon(Icons.notifications_active, size: 60, color: Colors.blue),
              const SizedBox(height: 10),
              const Text("Tienes un nuevo viaje asignado. Confirma de enterado para continuar.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _procesandoAceptacion ? null : _aceptarViaje,
                icon: _procesandoAceptacion ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.thumb_up, size: 24),
                label: Text(_procesandoAceptacion ? "Procesando..." : "👍 ACEPTAR VIAJE", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700], foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            // 🟠 FASE 2: ACEPTADO
            if (faseActual == 'ACEPTADO') ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => PreoperacionalOpcionesPage(datosServidor: widget.datosServidor)));
                },
                icon: const Icon(Icons.fact_check, size: 24),
                label: const Text("📝 Registrar Preoperacional", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800], foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              const Text("Por favor registre su preoperacional antes de ingresar a la zona de carga.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],

            // 🟢 FASE 3: PREOP_LISTO
            if (faseActual == 'PREOP_LISTO') ...[
              Card(
                color: Colors.blueGrey[50],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      const Text("INFORMACIÓN DEL EQUIPO", style: TextStyle(fontWeight: FontWeight.bold)),
                      ListTile(
                        title: Text("Cabezote: ${widget.datosServidor['placa_cabezote']}"),
                        subtitle: Text("Trailer: ${widget.datosServidor['placa_trailer']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit_note, color: Colors.orange), onPressed: () => _editarDato("Tráiler", "placa_trailer")),  
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _procesandoFoto ? null : _tomarFotoReal, 
                              icon: _procesandoFoto ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.camera_alt, size: 18),
                              label: Text(_procesandoFoto ? "..." : "Foto ($_fotosTomadas/$_limiteFotos)"), 
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("DOCUMENTACIÓN DEL VIAJE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_shared, color: Colors.blue),
                        title: Text("Documento ${widget.datosServidor['cliente_nombre'] ?? 'Cliente'}"),
                        subtitle: Text(
                          widget.datosServidor['documento_cliente']?.toString().isNotEmpty == true 
                            ? widget.datosServidor['documento_cliente'].toString() 
                            : "Pendiente desde el servidor",
                          style: TextStyle(
                            color: widget.datosServidor['documento_cliente']?.toString().isNotEmpty == true ? Colors.black87 : Colors.red,
                            fontStyle: widget.datosServidor['documento_cliente']?.toString().isNotEmpty == true ? FontStyle.normal : FontStyle.italic
                          )
                        ),
                      ),
                      
                      const Divider(height: 0),

                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.assignment, color: Colors.orange),
                        title: const Text("Manifiesto RNDC"),
                        subtitle: Text(
                          widget.datosServidor['manifiesto_rndc']?.toString().isNotEmpty == true 
                            ? widget.datosServidor['manifiesto_rndc'].toString() 
                            : "No generado",
                        ),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text("Ver"),
                          onPressed: () async {
                            String urlDoc = widget.datosServidor['url_pdf_manifiesto']?.toString() ?? "";
                            
                            if (urlDoc.isNotEmpty && urlDoc.startsWith("http")) {
                              final Uri uri = Uri.parse(urlDoc);
                              try {
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              } catch (e) {
                                debugPrint("Error al abrir PDF: $e");
                              }
                            } else {
                              if (context.mounted) {
                                showDialog(
                                  context: context, 
                                  builder: (context) => AlertDialog(
                                    title: const Text("⚠️ Documento no disponible"), 
                                    content: const Text("El servidor aún no ha cargado el archivo PDF o la imagen de este manifiesto."), 
                                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("ENTENDIDO"))]
                                  )
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: TextField(
                  controller: _odometroController, keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Kilometraje (Odómetro) Actual", prefixIcon: const Icon(Icons.speed, color: Colors.blue), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: TextField(
                  controller: _guiaController,
                  decoration: InputDecoration(
                    labelText: "Ingrese el # de Guía de Viaje", border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.description),
                    suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner, color: Colors.blue, size: 30), onPressed: _escanearGuia),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: (_odometroController.text.isNotEmpty && !_subiendoViaje)
                    ? () {
                        int odoNuevo = int.tryParse(_odometroController.text) ?? 0;
                        int odoBaseDatos = int.tryParse(widget.datosServidor['odometro_bd']?.toString() ?? "0") ?? 0;
                        if (odoNuevo > odoBaseDatos) {
                          _subirEvidencias();
                        } else {
                          showDialog(
                            context: context, 
                            builder: (context) => AlertDialog(
                              title: const Text("⚠️ Kilometraje Inválido"), 
                              content: Text("No puedes iniciar con $odoNuevo. Último: $odoBaseDatos."), 
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CORREGIR"))]
                            )
                          );
                        }
                      }
                    : null, 
                  child: _subiendoViaje 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                    : const Text("INICIAR VIAJE", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            
            // 🔵 FASE 4: VIAJE EN RUTA (ÉXITO)
            if (faseActual == 'EN_RUTA') ...[
              const SizedBox(height: 20),
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const Text("VIAJE INICIADO CORRECTAMENTE", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text("VER MI RUTA EN EL MAPA", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => DashboardPage(lat: 4.6097, lng: -74.0817, datosViaje: widget.datosServidor)));
                  },
                ),
              ),
            ],

          ],
        ),
      ),
    );
  }
}