import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

// Aseguramos el nombre correcto de la vista de validación de inicio
import 'validacion_page.dart'; 
import 'watermark_service.dart';

class PreoperacionalFormularioPage extends StatefulWidget {
  final Map<String, dynamic> datosServidor;

  const PreoperacionalFormularioPage({super.key, required this.datosServidor});

  @override
  _PreoperacionalFormularioPageState createState() => _PreoperacionalFormularioPageState();
}

class _PreoperacionalFormularioPageState extends State<PreoperacionalFormularioPage> {
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
  
  final List<File> _listaFotos = []; 
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;
  bool _procesandoFoto = false;

  @override
  void initState() {
    super.initState();
    _respuestas = {for (var i = 0; i < _preguntas.length; i++) i: 'Bueno'};
  }
  
  // --- TOMAR FOTO DE EVIDENCIA/FALLA CON MARCA DE AGUA CORPORATIVA ---
  Future<void> _tomarFotoFalla() async {
    if (_listaFotos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Máximo 3 fotos de evidencia"))
      );
      return;
    }
    
    if (_procesandoFoto) return;
    setState(() => _procesandoFoto = true);

    try {
      String latLngStr = "0.0000, 0.0000";
      try {
        LocationPermission permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
        }

        if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
          Position posicion = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5)
          );
          latLngStr = "${posicion.latitude.toStringAsFixed(6)}, ${posicion.longitude.toStringAsFixed(6)}";
        }
      } catch (e) {
        debugPrint("Error GPS Preoperacional: $e");
      }

      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 85, 
        maxWidth: 1280
      );
      
      if (foto != null) {
        String placa = (widget.datosServidor['placa_cabezote'] ?? widget.datosServidor['vehiculo'] ?? "S/P")
            .toString()
            .toUpperCase()
            .trim();
        String fechaHora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

        File fotoSellada = await WatermarkService.aplicarMarcaDeAgua(
          imagenOriginal: File(foto.path),
          textoPlaca: placa,
          textoGPS: latLngStr,
          fechaHora: fechaHora,
        );

        if (mounted) {
          setState(() => _listaFotos.add(fotoSellada));
        }
      }
    } catch (e) {
      debugPrint("Error capturando foto de falla: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al capturar foto: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoFoto = false);
    }
  }

  // --- FINALIZAR E INSERCIÓN MULTI-REGISTRO EN BASE DE DATOS ---
  Future<void> _finalizarCuestionario() async {
    setState(() => _enviando = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Guardando inspección en la nube..."), backgroundColor: Colors.orange)
    );

    try {
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
      String celular = widget.datosServidor['celular']?.toString() ?? "";
      String trailer = widget.datosServidor['placa_trailer']?.toString() ?? "";
      String cabezote = widget.datosServidor['placa_cabezote']?.toString() ?? "";
      List<String> urlsFotos = [];

      // 1. Subida de fotos a Firebase Storage
      for (var i = 0; i < _listaFotos.length; i++) {
        String nombre = "falla_${tripIdReal}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
        Reference ref = FirebaseStorage.instance.ref().child('preoperacionales_fisicos/$nombre');
        
        final bytes = await _listaFotos[i].readAsBytes();
        UploadTask uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45)); 
        String url = await snapshot.ref.getDownloadURL();
        urlsFotos.add(url);
      }

      // 2. Construir JSON
      Map<String, dynamic> jsonFinal = {
        "tipo_registro": "DIGITAL",
        "fecha_registro": DateTime.now().toIso8601String(),
        "respuestas": _respuestas.map((k, v) => MapEntry(_preguntas[k], v)),
        "observaciones": _observacionesController.text,
        "fotos_evidencia": urlsFotos
      };

      // 3. Conexión a PostgreSQL
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      await conn.runTx((session) async {
        await session.execute(
          "UPDATE flutter_schema.active_trips SET fase_viaje = 'PREOP_LISTO', fecha_preop_app = CURRENT_TIMESTAMP, preoperacional_data = \$2 WHERE trip_id = \$1",
          parameters: [tripIdReal, jsonEncode(jsonFinal)],
        );

        if (urlsFotos.isNotEmpty) {
          for (String urlFotoFalla in urlsFotos) {
            await session.execute(
               r'''
               INSERT INTO flutter_schema.viajes 
               (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud, trip_id, fecha_registro, preoperacional_data)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, $10)
               ''',
               parameters: [
                 "FALLA_PREOP", 
                 "0", 
                 celular, 
                 trailer, 
                 cabezote, 
                 urlFotoFalla, 
                 "0.0000", 
                 "0.0000", 
                 tripIdReal, 
                 jsonEncode(jsonFinal)
               ]
            );
          }
        }
      });

      await conn.close();

      widget.datosServidor['fase_viaje'] = 'PREOP_LISTO';
      widget.datosServidor['preoperacional_json'] = jsonEncode(jsonFinal);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      // Redirección hacia la página de validación (ValidacionViajePage)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
        (route) => false,
      ); 

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error subiendo datos: $e"), backgroundColor: Colors.red)
        );
      }
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
                  label: Text(_procesandoFoto ? "Procesando Marca..." : "Foto (${_listaFotos.length}/3)"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                ),
                if (_listaFotos.isNotEmpty)
                  IconButton(onPressed: () => setState(() => _listaFotos.clear()), icon: const Icon(Icons.delete, color: Colors.red))
              ],
            ),

            const SizedBox(height: 30),
            
            SizedBox(
              width: double.infinity, height: 60,
              child: ElevatedButton(
                onPressed: _enviando ? null : _finalizarCuestionario,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                child: _enviando 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("FINALIZAR Y ENVIAR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}