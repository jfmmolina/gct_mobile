import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:image/image.dart' as img;
import 'package:barcode_scan2/barcode_scan2.dart';

// 👇 IMPORTANTE: Asegúrate de que main.dart está en la misma carpeta
import 'main.dart'; 

class ValidacionViajePage extends StatefulWidget {
  // Recibimos el paquete de datos completo del Login
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
  String _latitudActual = "0.0";
  String _longitudActual = "0.0";

  bool _procesandoFoto = false; 
  bool _subiendoViaje = false;  
  bool _viajeExitoso = false;   

  // --- ESCÁNER DE CÓDIGO ---
  Future<void> _escanearGuia() async {
    try {
      var result = await BarcodeScanner.scan();
      if (result.type == ResultType.Barcode && mounted) {
        setState(() {
          _guiaController.text = result.rawContent;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Código leído"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error escáner: $e"), backgroundColor: Colors.red));
    }
  }

  // --- TOMAR FOTO CON MARCA DE AGUA ---
  Future<void> _tomarFotoReal() async {
    if (_procesandoFoto) return;
    if (_fotosTomadas >= _limiteFotos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Límite de fotos alcanzado"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _procesandoFoto = true);

    try {
      final ImagePicker picker = ImagePicker();
      
      // OBTENER GPS
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission(); 
      if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
        // Timeout corto para que no se quede pensando
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 5));
        if (position != null) {
          setState(() {
            _latitudActual = position!.latitude.toStringAsFixed(6);
            _longitudActual = position!.longitude.toStringAsFixed(6);
          });
        }
      }

      // ABRIR CÁMARA
      final XFile? foto = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 800);

      if (foto != null) {
        final bytes = await foto.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final directory = await getApplicationDocumentsDirectory();
        final File archivoRescatado = File('${tempDir.path}/evidencia_temp.jpg');
        
        // ESTAMPAR FECHA Y GPS
        img.Image? imagenDecodificada = img.decodeImage(bytes);
        if (imagenDecodificada != null) {
          String fechaHora = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
          img.drawString(imagenDecodificada, "$fechaHora | GPS: $_latitudActual, $_longitudActual", font: img.arial24, x: 20, y: imagenDecodificada.height - 40, color: img.ColorRgb8(255, 255, 0));
          await archivoRescatado.writeAsBytes(img.encodeJpg(imagenDecodificada, quality: 85));
        } else {
          await archivoRescatado.writeAsBytes(bytes);
        }

        // GUARDAR EN DISCO
        String nuevoNombre = "GCT_INICIO_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg";
        String nuevaRuta = "${directory.path}/$nuevoNombre";
        await archivoRescatado.copy(nuevaRuta);

        if (mounted) {
          setState(() {
            _listaFotos.add(File(nuevaRuta)); 
            _fotosTomadas++;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error foto: $e");
    } finally {
      if (mounted) setState(() => _procesandoFoto = false);
    }
  }

  // --- SUBIR DATOS Y ACTIVAR VIAJE ---

  // --- FUNCIÓN CORREGIDA: BLINDADA CONTRA CONGELAMIENTOS ---
  Future<void> _subirEvidencias() async {
    // Encendemos la animación de carga
    setState(() => _subiendoViaje = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Guardando evidencia e iniciando ruta..."), backgroundColor: Colors.orange));

    try {
      // 0. EXTRACCIÓN SEGURA DE DATOS (Adentro del Try)
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
      String celular = widget.datosServidor['celular']?.toString() ?? "";
      String trailer = widget.datosServidor['placa_trailer']?.toString() ?? "";
      String cabezote = widget.datosServidor['placa_cabezote']?.toString() ?? "";
      
      String urlPublicaFinal = ""; 

      // 1. SUBIR FOTOS A FIREBASE CON LIMITE DE TIEMPO
      if (_listaFotos.isNotEmpty) {
        List<String> linksGenerados = []; 
        for (int i = 0; i < _listaFotos.length; i++) {
          File archivo = _listaFotos[i];
          String nombreArchivo = "inicio_viaje_${tripIdReal}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
          Reference ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombreArchivo');
          
          // Usamos putData con timeout de 45 seg para que NO se congele jamás
          final imageBytes = await archivo.readAsBytes();
          UploadTask uploadTask = ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
          
          TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
          String urlTemp = await snapshot.ref.getDownloadURL();
          linksGenerados.add(urlTemp);
        }
        urlPublicaFinal = linksGenerados.join(","); 
      }

      // 2. CONECTAR A BASE DE DATOS
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 20)),
      );

      // 3. EJECUTAR TRANSACCIÓN (TODO O NADA)
      await conn.runTx((session) async {
        
        // A. ACTUALIZAR LA TORRE DE CONTROL (active_trips)
        await session.execute(
          r'''
          UPDATE flutter_schema.active_trips
          SET 
            is_running = true,
            current_state = 'ON ROUTE',
            odometer_start = $2,
            tracking_number = $3,
            truck_current_location = $4
          WHERE trip_id = $1
          ''',
          parameters: [
            tripIdReal,                                  // $1
            int.tryParse(_odometroController.text) ?? 0, // $2
            _guiaController.text,                        // $3
            "$_latitudActual,$_longitudActual"           // $4
          ],
        );

        // B. GUARDAR EL ACTA DE ENTREGA (viajes)
        await session.execute(
           r'''
           INSERT INTO flutter_schema.viajes 
           (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud, trip_id, fecha_registro)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP)
           ''',
           parameters: [
             _guiaController.text,      // $1
             _odometroController.text,  // $2
             celular,                   // $3 
             trailer,                   // $4
             cabezote,                  // $5 
             urlPublicaFinal,           // $6
             _latitudActual,            // $7
             _longitudActual,           // $8
             tripIdReal                 // $9 
           ]
        );
      });

      await conn.close();

      // 4. ÉXITO TOTAL
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ ¡VIAJE INICIADO Y GUARDADO!"), backgroundColor: Colors.green));

      setState(() {
        _subiendoViaje = false;
        _viajeExitoso = true; 
      });

    } catch (e) {
      // 5. MANEJO DEL ERROR
      debugPrint("Error al subir: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red));
        
        // Abrimos el candado para que el conductor pueda volver a presionar el botón
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
    return Scaffold(
      appBar: AppBar(title: const Text("Validación de Inicio")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // BANNER DATOS
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

            // DATOS CONDUCTOR
            ListTile(
              leading: const Icon(Icons.person),
              title: Text("Cédula: ${widget.datosServidor['cedula']}"),
              subtitle: Text("Celular: ${widget.datosServidor['celular']}"),
              trailing: IconButton(icon: const Icon(Icons.edit_note, color: Colors.orange), onPressed: () => _editarDato("Celular", "celular")),
            ),

            // DATOS VEHICULO
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

            const SizedBox(height: 20),
            const Text("SU RUTA ASIGNADA:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("${widget.datosServidor['ruta_nombre']}", style: const TextStyle(fontSize: 18, color: Colors.blue)),
            const Divider(), 

            // CAMPOS DE TEXTO
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

            // --- BOTÓN PRINCIPAL (INICIAR) ---
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _viajeExitoso ? Colors.grey : Colors.green),
                onPressed: (_guiaController.text.isNotEmpty && _odometroController.text.isNotEmpty && !_subiendoViaje && !_viajeExitoso)
                  ? () {
                      int odoNuevo = int.tryParse(_odometroController.text) ?? 0;
                      int odoBaseDatos = int.tryParse(widget.datosServidor['odometro_bd']?.toString() ?? "0") ?? 0;
                      if (odoNuevo > odoBaseDatos) {
                        _subirEvidencias();
                      } else {
                        showDialog(context: context, builder: (context) => AlertDialog(title: const Text("⚠️ Kilometraje Inválido"), content: Text("No puedes iniciar con $odoNuevo. Último: $odoBaseDatos."), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CORREGIR"))]));
                      }
                    }
                  : null, 
                child: _subiendoViaje 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                  : Text(_viajeExitoso ? "VIAJE INICIADO ✓" : "INICIAR VIAJE", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),

            // --- BOTÓN OCULTO (IR AL MAPA) ---
            if (_viajeExitoso) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800]),
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text("VER MI RUTA EN EL MAPA", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    // PASAMOS DATOS AL DASHBOARD
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DashboardPage(
                          lat: 4.6097,   
                          lng: -74.0817,
                          datosViaje: widget.datosServidor, // 🔑 LLAVE MAESTRA
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

          ], // Fin Column
        ), // Fin SingleScrollView
      ), // Fin Scaffold
    );
  }
}