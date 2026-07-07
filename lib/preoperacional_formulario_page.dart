import 'validacion_page.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class PreoperacionalFormularioPage extends StatefulWidget {
  final Map<String, dynamic> datosServidor;

  const PreoperacionalFormularioPage({super.key, required this.datosServidor});

  @override
  _PreoperacionalFormularioPageState createState() => _PreoperacionalFormularioPageState();
}

class _PreoperacionalFormularioPageState extends State<PreoperacionalFormularioPage> {
  // 11 Preguntas estándar de seguridad
  final List<String> _preguntas = [
    "Estado de llantas y rines",
    "Nivel de aceite y fugas",
    "Luces (Altas, bajas, direccionales)",
    "Frenos y presión de aire",
    "Espejos y vidrios",
    "Cinturones de seguridad",
    "Kit de carretera y extintor",
    "Documentación (SOAT, Tecno)",
    "Limpiaparabrisas y agua",
    "Estado de la carrocería/tráiler",
    "Aseo general del vehículo"
  ];

  late Map<int, String> _respuestas;
  final TextEditingController _observacionesController = TextEditingController();
  
  final List<File> _listaFotos = []; // Cambiado a File para manejar la foto sellada
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;
  bool _procesandoFoto = false;

  @override
  void initState() {
    super.initState();
    _respuestas = {for (var i = 0; i < _preguntas.length; i++) i: 'Bueno'};
  }
  
  // --- NUEVA FUNCIÓN MEJORADA: SELLO DE SEGURIDAD PARA LAS FALLAS ---
  Future<File> _aplicarSelloDeAgua(XFile fotoOriginal) async {
    try {
      String placa = widget.datosServidor['placa_cabezote'] ?? widget.datosServidor['vehiculo'] ?? "S/P";
      String fechaHora = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      String latLngStr = "Buscando...";

      // 1. Manejo seguro y con tiempo límite para el GPS
      try {
        LocationPermission permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
        }

        if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
          Position posicion = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 5) // Máximo 5 segundos
          );
          latLngStr = "Lat: ${posicion.latitude.toStringAsFixed(4)}, Lng: ${posicion.longitude.toStringAsFixed(4)}";
        } else {
          latLngStr = "GPS Sin Permiso";
        }
      } catch (e) {
        debugPrint("Error GPS: $e");
        latLngStr = "GPS No disponible";
      }

      // 2. El texto siempre se armará, haya o no haya señal
      String textoSello = "GCT | $placa | $fechaHora | $latLngStr";

      final bytes = await fotoOriginal.readAsBytes();
      img.Image? imagen = img.decodeImage(bytes);
      
      if (imagen != null) {
        img.drawString(
          imagen,
          textoSello,
          font: img.arial24,
          x: 15,
          y: imagen.height - 35,
          color: img.ColorRgb8(255, 255, 255), // Texto Blanco Corporativo
        );

        final directorio = await getTemporaryDirectory();
        final rutaNueva = '${directorio.path}/falla_${DateTime.now().millisecondsSinceEpoch}.jpg';
        File archivoModificado = File(rutaNueva);
        await archivoModificado.writeAsBytes(img.encodeJpg(imagen, quality: 85));
        
        return archivoModificado;
      }
    } catch (e) {
      debugPrint("Error fatal aplicando sello: $e");
    }
    return File(fotoOriginal.path); // Último recurso de seguridad
  }

  Future<void> _tomarFotoFalla() async {
    if (_listaFotos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Máximo 3 fotos de evidencia")));
      return;
    }
    
    if (_procesandoFoto) return;
    setState(() => _procesandoFoto = true);

    try {
      final XFile? foto = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 800);
      
      if (foto != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Aplicando sello de seguridad corporativo..."), backgroundColor: Colors.orange));
        
        File archivoFallaSellada = await _aplicarSelloDeAgua(foto);
        setState(() => _listaFotos.add(archivoFallaSellada));
      }
    } catch (e) {
      debugPrint("Error capturando foto de falla: $e");
    } finally {
      if (mounted) setState(() => _procesandoFoto = false);
    }
  }

  Future<void> _finalizarCuestionario() async {
    setState(() => _enviando = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Guardando inspección en la nube..."), backgroundColor: Colors.orange));

    try {
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
      List<String> urlsFotos = [];

      // 1. SUBIR FOTOS (Ya selladas) A FIREBASE
      for (var i = 0; i < _listaFotos.length; i++) {
        String nombre = "falla_${tripIdReal}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
        Reference ref = FirebaseStorage.instance.ref().child('preoperacionales_fisicos/$nombre');
        
        UploadTask uploadTask = ref.putFile(
          _listaFotos[i], // Aquí subimos el File directo
          SettableMetadata(contentType: 'image/jpeg')
        );
        
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45)); 
        String url = await snapshot.ref.getDownloadURL();
        urlsFotos.add(url);
      }

      // 2. CONSTRUIR EL JSON BLINDADO
      Map<String, dynamic> jsonFinal = {
        "tipo_registro": "DIGITAL",
        "fecha_registro": DateTime.now().toIso8601String(),
        "respuestas": _respuestas.map((k, v) => MapEntry(_preguntas[k], v)),
        "observaciones": _observacionesController.text,
        "fotos_evidencia": urlsFotos
      };

      // 3. ENVIAR A POSTGRESQL
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      await conn.execute(
        "UPDATE flutter_schema.active_trips SET fase_viaje = 'PREOP_LISTO', fecha_preop_app = CURRENT_TIMESTAMP, preoperacional_data = \$2 WHERE trip_id = \$1",
        parameters: [tripIdReal, jsonEncode(jsonFinal)],
      );
      await conn.close();

      // 4. ACTUALIZAR MEMORIA LOCAL Y SALIR
      widget.datosServidor['fase_viaje'] = 'PREOP_LISTO';
      widget.datosServidor['preoperacional_json'] = jsonEncode(jsonFinal);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      // Teletransportación segura
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
        (route) => false,
      ); 

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error subiendo datos: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Inspección Digital"), backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            const Text("Marque el estado de cada elemento:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            
            // Lista de preguntas
            ...List.generate(_preguntas.length, (index) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${index + 1}. ${_preguntas[index]}", style: const TextStyle(fontWeight: FontWeight.w500)),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile(
                              title: const Text("Bueno"), value: "Bueno", groupValue: _respuestas[index],
                              onChanged: (val) => setState(() => _respuestas[index] = val!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile(
                              title: const Text("Malo"), value: "Malo", groupValue: _respuestas[index],
                              onChanged: (val) => setState(() => _respuestas[index] = val!),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            const Divider(height: 40),

            // Sección de Observaciones y Fotos
            const Text("OBSERVACIONES Y EVIDENCIAS", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _observacionesController,
              maxLines: 3,
              maxLength: 150,
              decoration: const InputDecoration(
                hintText: "Escriba aquí el detalle de cualquier falla encontrada...",
                border: OutlineInputBorder(),
              ),
            ),
            
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton.icon(
                  onPressed: (_enviando || _procesandoFoto) ? null : _tomarFotoFalla,
                  icon: _procesandoFoto 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.camera_alt),
                  label: Text(_procesandoFoto ? "Procesando..." : "Foto (${_listaFotos.length}/3)"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                ),
                if (_listaFotos.isNotEmpty)
                  IconButton(onPressed: () => setState(() => _listaFotos.clear()), icon: const Icon(Icons.delete, color: Colors.red))
              ],
            ),

            const SizedBox(height: 30),
            
            // Botón Final
            SizedBox(
              width: double.infinity, height: 60,
              child: ElevatedButton(
                onPressed: _enviando ? null : _finalizarCuestionario,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                child: _enviando 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("FINALIZAR E ENVIAR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}