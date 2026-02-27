  import 'dart:io';
  import 'package:firebase_storage/firebase_storage.dart';
  import 'package:postgres/postgres.dart';
  import 'package:path_provider/path_provider.dart';
  import 'package:geolocator/geolocator.dart';
  import 'package:intl/intl.dart';
  import 'package:image_picker/image_picker.dart'; //TOMAR FOTO 
  import 'package:flutter/material.dart';
  import 'package:image/image.dart' as img; // 👈 NUEVO: Herramienta para estampar


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
    File? _fotoArchivo; // Para guardar la referencia a la imagen
    Position? position;
    String _latitudActual = "0.0";
    String _longitudActual = "0.0";

    // --- FUNCIÓN DE CAPTURA DE FOTO ---
    
    Future<void> _tomarFotoReal() async {
      // 1. Validar el límite de 4 fotos
      if (_fotosTomadas >= _limiteFotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Límite de 4 fotos alcanzado"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final ImagePicker picker = ImagePicker();
      //Position? position; para remover

    try {
        // 1. REVISAR PERMISOS DE GPS EN PANTALLA
        LocationPermission permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission(); // Muestra el cartelito al usuario
        }

        // 2. SOLO SI DIO PERMISO, BUSCAMOS EL SATÉLITE
        if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
          
          // Le damos 10 segundos en lugar de 5 para asegurar que lo encuentre
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10), 
          );
          
          if (position != null) {
            setState(() {
              _latitudActual = position!.latitude.toStringAsFixed(6);
              _longitudActual = position!.longitude.toStringAsFixed(6);
            });
            print("📍 EXITO GPS: Lat $_latitudActual, Lon $_longitudActual"); // Para verlo en consola
          }
        } else {
          print("⚠️ El conductor no dio permiso de GPS.");
        }

      } catch (e) {
        debugPrint("⏳ El GPS tardó mucho o falló: $e");
      }

      // 3. Abrir la cámara
      final XFile? foto = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 1000,
        maxHeight: 1000,
        requestFullMetadata: false, // Compresión para que no pesen tanto en Contabo
      );

      if (foto != null) {
        // 1. Rescate inmediato de bytes (Sin usar variables intermedias peligrosas)

        final bytes = await foto.readAsBytes();
        
        final tempDir = await getTemporaryDirectory();
        final directory = await getApplicationDocumentsDirectory();

        // 🚀 2. NUEVO: MAGIA PARA ESTAMPAR LA FOTO
        final File archivoRescatado = File('${tempDir.path}/evidencia_temp.jpg');
        
        // Decodificamos la foto en la memoria
        img.Image? imagenDecodificada = img.decodeImage(bytes);

        if (imagenDecodificada != null) {
          // Preparamos el texto (Fecha, Hora y GPS)
          String fechaHora = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
          String marcaDeAgua = "FECHA: $fechaHora | GPS: $_latitudActual, $_longitudActual";

          // Dibujamos el texto sobre la foto (Letra amarilla, abajo a la izquierda)
          img.drawString(
            imagenDecodificada,
            marcaDeAgua,
            font: img.arial24,
            x: 20, // Margen izquierdo
            y: imagenDecodificada.height - 40, // Margen inferior
            color: img.ColorRgb8(255, 255, 0), // 255, 255, 0 es color Amarillo
          );

          // Volvemos a empaquetar la foto ya con el texto estampado
          List<int> bytesEstampados = img.encodeJpg(imagenDecodificada, quality: 90);
          await archivoRescatado.writeAsBytes(bytesEstampados);
        } else {
          // Si falla la estampa por alguna razón, guarda la foto original
          await archivoRescatado.writeAsBytes(bytes);
          print("❌ ERROR: La librería no pudo leer la foto para estamparla");
        }
        

        // 3. Preparamos la ruta técnica
        String placa = "GCT-001"; 
        String fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
        String lat = position?.latitude.toStringAsFixed(4) ?? "0.0000";
        String lon = position?.longitude.toStringAsFixed(4) ?? "0.0000";
        String nuevoNombre = "${placa}_${fecha}_Lat${lat}_Lon$lon.jpg";
        String nuevaRuta = "${directory.path}/$nuevoNombre";

        // 4. COPIA SEGURA: Usamos la variable local 'archivoRescatado' (NUNCA _fotoArchivo!)
        await archivoRescatado.copy(nuevaRuta);
        debugPrint("📸 EVIDENCIA TECNICA: $nuevoNombre");

        // 5. ACTUALIZACIÓN DE ESTADO: Aquí es donde el botón se pone verde fuerte
        if (mounted) {
          setState(() {
            _fotoArchivo = archivoRescatado; // Aquí le damos el valor final
            _fotosTomadas++;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Foto $_fotosTomadas de $_limiteFotos guardada"),
            backgroundColor: Colors.green,
          ),
        );
      }
    }

 Future<void> _subirEvidencias() async {
    String? urlPublica;

    // 1. BANNER NARANJA: Le avisa al usuario que no debe tocar nada
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Subiendo evidencias a la nube..."), backgroundColor: Colors.orange)
    );

    try {

      // A. SUBIR A FIREBASE PRIMERO
      if (_fotoArchivo != null) {
        File archivo = _fotoArchivo!;
        String nombreArchivo = "viaje_${widget.datosServidor['placa_cabezote']}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        Reference ref = FirebaseStorage.instance.ref().child('evidencias/$nombreArchivo');
        
        // 🚀 EL TRUCO MAGISTRAL: Leer el archivo en Bytes (RAM) para saltar bloqueos de Android
        final imageBytes = await archivo.readAsBytes();
        
        // 🚀 Usamos putData en lugar de putFile y le decimos que es una imagen JPEG
        UploadTask uploadTask = ref.putData(
          imageBytes, 
          SettableMetadata(contentType: 'image/jpeg')
        );
        
        // Mantenemos el timeout de protección
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
        urlPublica = await snapshot.ref.getDownloadURL();
        print("✅ Foto subida a Firebase: $urlPublica");
      }


      // B. GUARDAR TODO EN CONTABO (PostgreSQL)
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com',
          database: 'app_core',
          username: 'flutter',
          password: '5cxkdu6lo', 
          port: 5432,
        ),
        // 3. Aumentamos el tiempo a 45 segundos por si la red del celular es lenta
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 45)),
      );

      await conn.execute(
        r'INSERT INTO flutter_schema.viajes (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
        parameters: [
          _guiaController.text,
          _odometroController.text,
          widget.datosServidor['celular']?.toString()??"",
          widget.datosServidor['placa_trailer']?.toString()??"",
          widget.datosServidor['placa_cabezote']?.toString()??"",
          urlPublica, 
          _latitudActual,
          _longitudActual,
        ],
      );

      await conn.close();

      if (!mounted) return;
      // 4. BANNER AZUL DE ÉXITO
      ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Borra el aviso naranja
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ ¡Viaje y Foto sincronizados exitosamente!"), backgroundColor: Colors.blue)
      );
    } catch (e) {
      print("❌ Error total: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error de red: $e"), backgroundColor: Colors.red)
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
                              onPressed: _tomarFotoReal, //AQUI CONECTAMOS LA FUNCIÓN DE TOMAR FOTO
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: Text("Foto ($_fotosTomadas/$_limiteFotos)"), 
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
                  decoration: const InputDecoration(
                    labelText: "Ingrese el # de Guía de Viaje",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: (_guiaController.text.isNotEmpty && _odometroController.text.isNotEmpty)
                    ? () {
                        // 1. Capturamos lo que el conductor escribió
                        int odoNuevo = int.tryParse(_odometroController.text) ?? 0;
                        
                        // 2. Capturamos el valor que el sistema ya conoce del servidor
                        // Cambiamos 'odometro_actual' por el nombre exacto que venga de tu DB
                        //int odoBaseDatos = int.tryParse(widget.datosServidor['odometro_actual'].toString()) ?? 0;
                        int odoBaseDatos = 123456789;

                        print("Comparando: Nuevo ($odoNuevo) vs Base de Datos ($odoBaseDatos)");

                        // 3. LA REGLA DE ORO: Solo si el nuevo es estrictamente MAYOR
                        if (odoNuevo > odoBaseDatos) {
                          _subirEvidencias();
                        } else {
                          // Bloqueo inmediato si el valor es menor o igual
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
                    : null, // Si los campos están vacíos, el botón se apaga
                  child: const Text("INICIAR VIAJE", 
                    style: TextStyle(color: Colors.white, fontSize: 18)),
                ), // Cierra ElevatedButton
              ), // Cierra SizedBox
            ], // Cierra Column
          ), // Cierra Column
        ), // Cierra SingleChildScrollView
      ); // Cierra Scaffold
    } // Cierra el método build
  } // Cierra la clase _ValidacionViajePageState