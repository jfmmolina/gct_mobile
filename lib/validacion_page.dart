  import 'main.dart'; // 👈 IMPORTANTE para que reconozca el DashboardPage
  import 'dart:io';
  import 'package:firebase_storage/firebase_storage.dart';
  import 'package:postgres/postgres.dart';
  import 'package:path_provider/path_provider.dart';
  import 'package:geolocator/geolocator.dart';
  import 'package:intl/intl.dart';
  import 'package:image_picker/image_picker.dart'; //TOMAR FOTO 
  import 'package:flutter/material.dart';
  import 'package:image/image.dart' as img; // 👈 NUEVO: Herramienta para estampar
  import 'package:url_launcher/url_launcher.dart'; // 👈 NUEVO: Para abrir el mapa
  import 'package:barcode_scan2/barcode_scan2.dart';


  class ValidacionViajePage extends StatefulWidget {
    final Map datosServidor; // Datos que vienen de Contabo
    const ValidacionViajePage({super.key, required this.datosServidor});

    @override
    _ValidacionViajePageState createState() => _ValidacionViajePageState();
  }

  class _ValidacionViajePageState extends State<ValidacionViajePage> {
    final TextEditingController _guiaController = TextEditingController();
    final String _mensajeServidor = "";
    final TextEditingController _odometroController = TextEditingController();
    int _fotosTomadas = 0;
    final int _limiteFotos = 4;
    List<File> _listaFotos = []; // 👈 NUEVO: Lista para guardar todas las fotos
    Position? position;
    String _latitudActual = "0.0";
    String _longitudActual = "0.0";

    bool _procesandoFoto = false; // 👈 NUEVO: Nuestro candado de seguridad
    
    bool _subiendoViaje = false;  // 👈 NUEVO: Muestra que está cargando
    bool _viajeExitoso = false;   // 👈 NUEVO: Bloquea el botón al terminar

  // --- FUNCIÓN ACTUALIZADA: LECTOR DE CÓDIGO DE BARRAS (MODERNO) ---
  Future<void> _escanearGuia() async {
    try {
      // Abre la cámara con el escáner moderno
      var result = await BarcodeScanner.scan();

      // Si el escaneo fue un éxito y no se canceló
      if (result.type == ResultType.Barcode && mounted) {
        setState(() {
          // Ponemos el texto escaneado (rawContent) en la caja de texto
          _guiaController.text = result.rawContent;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Código leído exitosamente"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al usar escáner: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

    // --- FUNCIÓN DE CAPTURA DE FOTO ---
    
    Future<void> _tomarFotoReal() async {
      // 1. Candado de seguridad: Si ya está procesando una foto, ignorar el toque
      if (_procesandoFoto) return;

      // 2. Validar el límite de 4 fotos
      if (_fotosTomadas >= _limiteFotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ Límite de 4 fotos alcanzado"), backgroundColor: Colors.orange),
        );
        return;
      }

      // 3. 🔒 CERRAMOS EL CANDADO antes de empezar
      setState(() {
        _procesandoFoto = true;
      });

      // Envolvemos todo en un Try-Finally para asegurar que el candado siempre se abra
      try {
        final ImagePicker picker = ImagePicker();

        // --- 📍 INICIO BLOQUE GPS ---
        LocationPermission permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission(); 
        }

        if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10), 
          );
          if (position != null) {
            setState(() {
              _latitudActual = position!.latitude.toStringAsFixed(6);
              _longitudActual = position!.longitude.toStringAsFixed(6);
            });
          }
        }
        // --- FIN BLOQUE GPS ---

        // --- 📸 INICIO BLOQUE CAMARA ---
        final XFile? foto = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 85,
          maxWidth: 1000,
          maxHeight: 1000,
          requestFullMetadata: false, 
        );

        if (foto != null) {
          final bytes = await foto.readAsBytes();
          final tempDir = await getTemporaryDirectory();
          final directory = await getApplicationDocumentsDirectory();

          final File archivoRescatado = File('${tempDir.path}/evidencia_temp.jpg');
          img.Image? imagenDecodificada = img.decodeImage(bytes);

          if (imagenDecodificada != null) {
            String fechaHora = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
            String marcaDeAgua = "FECHA: $fechaHora | GPS: $_latitudActual, $_longitudActual";

            img.drawString(
              imagenDecodificada, marcaDeAgua, font: img.arial24,
              x: 20, y: imagenDecodificada.height - 40, color: img.ColorRgb8(255, 255, 0), 
            );

            List<int> bytesEstampados = img.encodeJpg(imagenDecodificada, quality: 90);
            await archivoRescatado.writeAsBytes(bytesEstampados);
          } else {
            await archivoRescatado.writeAsBytes(bytes);
          }

          String placa = "GCT-001";
          String fecha = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
          String lat = position?.latitude.toStringAsFixed(4) ?? "0.0000";
          String lon = position?.longitude.toStringAsFixed(4) ?? "0.0000";
          String nuevoNombre = "${placa}_${fecha}_Lat${lat}_Lon$lon.jpg";
          String nuevaRuta = "${directory.path}/$nuevoNombre";

          await archivoRescatado.copy(nuevaRuta);

          if (mounted) {
            setState(() {
              _listaFotos.add(File(nuevaRuta)); 
              _fotosTomadas++;
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Foto $_fotosTomadas de $_limiteFotos guardada"), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        debugPrint("❌ Error al tomar foto: $e");
      } finally {
        // 4. 🔓 ABRIMOS EL CANDADO pase lo que pase
        if (mounted) {
          setState(() {
            _procesandoFoto = false;
          });
        }
      }
    }



    Future<void> _subirEvidencias() async {
      String? urlPublicaFinal; 

      // 🔒 1. CERRAMOS EL CANDADO DE CARGA
      setState(() {
      _subiendoViaje = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏳ Subiendo evidencias a la nube..."), backgroundColor: Colors.orange)
      );

      try {
      // A. SUBIR A FIREBASE
      if (_listaFotos.isNotEmpty) {
        List<String> linksGenerados = []; 
        for (int i = 0; i < _listaFotos.length; i++) {
          File archivo = _listaFotos[i];
          String nombreArchivo = "viaje_${widget.datosServidor['placa_cabezote']}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
          Reference ref = FirebaseStorage.instance.ref().child('evidencias/$nombreArchivo');
          
          final imageBytes = await archivo.readAsBytes();
          UploadTask uploadTask = ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
          
          TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
          String urlTemp = await snapshot.ref.getDownloadURL();
          linksGenerados.add(urlTemp); 
          print("✅ Foto ${i + 1} subida a Firebase: $urlTemp");
        }
        urlPublicaFinal = linksGenerados.join(", ");
      }

      // B. GUARDAR EN CONTABO
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 45)),
      );

      await conn.execute(
        r'INSERT INTO flutter_schema.viajes (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
        parameters: [
          _guiaController.text, _odometroController.text, widget.datosServidor['celular']?.toString()??"",
          widget.datosServidor['placa_trailer']?.toString()??"", widget.datosServidor['placa_cabezote']?.toString()??"",
          urlPublicaFinal, _latitudActual, _longitudActual,
        ],
      );
      await conn.close();

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).hideCurrentSnackBar(); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ ¡Viaje y Fotos sincronizados exitosamente!"), backgroundColor: Colors.blue)
      );

      // 🔒 2. ÉXITO TOTAL: BLOQUEAMOS EL BOTÓN PARA SIEMPRE
      setState(() {
        _subiendoViaje = false;
        _viajeExitoso = true; 
      });

      } catch (e) {
      print("❌ Error total: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error de red: $e"), backgroundColor: Colors.red)
      );
      
      // 🔓 3. SI HAY ERROR, ABRIMOS EL CANDADO PARA QUE PUEDA REINTENTAR
      setState(() {
        _subiendoViaje = false; 
      });
    }
  }

  Future<void> _abrirMapaRuta() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Buscando mapa de ruta..."), backgroundColor: Colors.orange)
    );

    try {
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // ⚠️ NOTA PARA JUAN: Asegúrate de que el nombre de la columna sea correcto (ej. "share_url" o "link_mapa")
      // Aquí estamos buscando en la tabla 'active_trips' usando la placa del cabezote como filtro.
      
      final result = await conn.execute(
        r'SELECT mapa_iframe_url FROM flutter_schema.active_trips WHERE mapa_iframe_url IS NOT NULL LIMIT 1',
      );

      await conn.close();

      if (result.isNotEmpty && result[0][0] != null) {
        String urlMapa = result[0][0].toString();
        final Uri url = Uri.parse(urlMapa);
        
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Abrimos el link en el navegador nativo del celular
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw 'No se pudo abrir el enlace';
        }
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ El mapa de este viaje aún no está listo"), backgroundColor: Colors.orange)
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error al cargar mapa: $e"), backgroundColor: Colors.red)
      );
    }
  }


  void _editarDato(String titulo, String campo) { 
    TextEditingController tempController = TextEditingController(
      // Si el dato no existe o es nulo, mostrará un espacio vacío en lugar de "null"
      text: widget.datosServidor[campo]?.toString() ?? ""
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Actualizar $titulo"),
        content: TextField(
          controller: tempController,
          decoration: InputDecoration(hintText: "Ingrese nuevo $titulo"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () {
              setState(() {
                // Actualizamos el dato en la memoria de la App
                widget.datosServidor[campo] = tempController.text;
              });
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
        appBar: AppBar(title: const Text("Validación de Inicio de Viaje")),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.blue[900], 
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("EMPRESA / CLIENTE:", 
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(
                    "${widget.datosServidor['empresa_transportadora']} / ${widget.datosServidor['cliente_nombre'] ?? 'ECOPETROL'}", 
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                ],
              ), // Cierra Column del banner
            ), // Cierra Container azul
            
            Text("Hola, ${widget.datosServidor['nombre']}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
              // 1. Datos Personales
              ListTile(
                leading: const Icon(Icons.person),
                title: Text("Cédula: ${widget.datosServidor['cedula']}"),
                subtitle: Text("Celular: ${widget.datosServidor['celular']}"),
                trailing: IconButton(icon: const Icon(Icons.edit_note, color: Colors.orange), onPressed: () => _editarDato("Celular", "celular,")),
              ),

              // 2. Equipo (Cabezote y Trailer)
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
                            IconButton(
                              icon: const Icon(Icons.edit_note, color: Colors.orange),  
                              onPressed: () => _editarDato("Tráiler", "placa_trailer"),
                            ),  
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              // Si está procesando, apagamos el botón pasándole 'null'
                              onPressed: _procesandoFoto ? null : _tomarFotoReal, 
                              icon: _procesandoFoto 
                                  // Muestra un circulito de carga si está procesando
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  // Muestra la cámara si está libre
                                  : const Icon(Icons.camera_alt, size: 18),
                              label: Text(_procesandoFoto ? "Procesando..." : "Foto ($_fotosTomadas/$_limiteFotos)"), 
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[800],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder( 
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              // 3. Ruta
              const Text("SU RUTA ASIGNADA:", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("${widget.datosServidor['ruta_nombre']}", style: const TextStyle(fontSize: 18, color: Colors.blue)),

              const SizedBox(height: 20),
              // 4. Ingreso de Guía (Obligatorio)
              const Divider(), // Una línea separadora para que se vea ordenado
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  controller: _odometroController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Kilometraje (Odómetro) Actual",
                    prefixIcon: const Icon(Icons.speed, color: Colors.blue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  controller: _guiaController,
                  decoration: InputDecoration( // Quita el "const" de aquí para que funcione el botón
                    labelText: "Ingrese el # de Guía de Viaje",
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.description),
                    // 🚀 NUEVO: Botón de escáner dentro del campo de texto
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.blue, size: 30),
                      onPressed: _escanearGuia,
                    ),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(height: 30),


                  // Botón de Inicio
                SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // Si ya se envió, se pone gris. Si no, verde.
                    backgroundColor: _viajeExitoso ? Colors.grey : Colors.green
                  ),
                  // Si está cargando, o ya fue exitoso, o le faltan datos, bloqueamos el botón (null)
                  onPressed: (_guiaController.text.isNotEmpty && _odometroController.text.isNotEmpty && !_subiendoViaje && !_viajeExitoso)
                    ? () {
                        int odoNuevo = int.tryParse(_odometroController.text) ?? 0;
                        // 👈 NUEVO: Leemos el odómetro que viene de la base de datos
                        int odoBaseDatos = int.tryParse(widget.datosServidor['odometro_bd']?.toString() ?? "0") ?? 0;

                        if (odoNuevo > odoBaseDatos) {
                          _subirEvidencias();
                        } else {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("⚠️ Kilometraje Inválido"),
                              content: Text("No puedes iniciar con $odoNuevo. El último registro es $odoBaseDatos. Por favor, verifica el tablero del vehículo."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text("CORREGIR")),
                              ],
                            ),
                          );
                        }
                      }
                    : null, 
                  // Cambiamos el contenido del botón dependiendo de su estado
                  child: _subiendoViaje 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _viajeExitoso ? "VIAJE INICIADO ✓" : "INICIAR VIAJE", 
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                      ), // 👈 CIERRE DEL TEXTO
                ), // 👈 CIERRE DEL ELEVATED BUTTON
              ), // 👈 CIERRE DEL SIZED BOX

              // 🚀 NUEVO: BOTÓN DE MAPA OCULTO (Solo aparece si _viajeExitoso es true)
              // Reemplaza todo el bloque del "if (_viajeExitoso)" por esto:
                if (_viajeExitoso) ...[
                  const SizedBox(height: 20),
                    SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800]),
                    icon: const Icon(Icons.map, color: Colors.white),
                    label: const Text("VER MI RUTA EN EL MAPA", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      
                    // 👇 AQUÍ ESTÁ EL CAMBIO IMPORTANTE 👇
                    onPressed: () {
                    Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                    builder: (context) => const DashboardPage(
                      lat: 4.6097,   // Coordenadas iniciales
                      lng: -74.0817, 
                      ),
                    ),
            );},
          ),
        ),
      ],  

            ], // Cierra Column
          ), // Cierra Column
        ), // Cierra SingleChildScrollView
      ); // Cierra Scaffold
    } // Cierra el método build
  } // Cierra la clase _ValidacionViajePageState