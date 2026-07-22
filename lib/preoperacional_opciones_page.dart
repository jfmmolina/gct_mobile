import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'preoperacional_formulario_page.dart';
import 'validacion_page.dart'; // Asegúrate de apuntar a tu clase de validación (p. ej., ValidacionViajePage)
import 'watermark_service.dart'; // Servicio unificado con logo GCT y marca de agua

class PreoperacionalOpcionesPage extends StatefulWidget {
  final Map<String, dynamic> datosServidor;

  const PreoperacionalOpcionesPage({super.key, required this.datosServidor});

  @override
  State<PreoperacionalOpcionesPage> createState() => _PreoperacionalOpcionesPageState();
}

class _PreoperacionalOpcionesPageState extends State<PreoperacionalOpcionesPage> {
  bool _subiendoFoto = false;

  // --- FUNCIÓN TOMAR FOTO DEL PREOPERACIONAL FÍSICO CON WATERMARK SERVICE ---
  Future<void> _tomarFotoFisico() async {
    if (_subiendoFoto) return;

    final ImagePicker picker = ImagePicker();
    final XFile? foto = await picker.pickImage(
      source: ImageSource.camera, 
      imageQuality: 85, 
      maxWidth: 1280
    );
    
    if (foto != null) {
      setState(() => _subiendoFoto = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏳ Aplicando marca de agua y subiendo evidencia..."), backgroundColor: Colors.orange)
      );

      try {
        // 1. Obtención de Coordenadas GPS con tiempo límite
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
          debugPrint("Error GPS Físico: $e");
        }

        // 2. Aplicación de la Marca de Agua Corporativa (Logo GCT + Datos)
        String placa = (widget.datosServidor['placa_cabezote'] ?? widget.datosServidor['vehiculo'] ?? "S/P")
            .toString()
            .toUpperCase()
            .trim();
        String fechaHora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

        File archivoSello = await WatermarkService.aplicarMarcaDeAgua(
          imagenOriginal: File(foto.path),
          textoPlaca: placa,
          textoGPS: latLngStr,
          fechaHora: fechaHora,
        );
        
        int driverId = int.tryParse(widget.datosServidor['driver_id']?.toString() ?? "0") ?? 0;
        int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
        String celular = widget.datosServidor['celular']?.toString() ?? "";
        String trailer = widget.datosServidor['placa_trailer']?.toString() ?? "";
        String cabezote = widget.datosServidor['placa_cabezote']?.toString() ?? "";
        
        // 3. SUBIR FOTO A FIREBASE STORAGE (preoperacionales_fisicos/)
        String nombreArchivo = "preoperacional_${driverId}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        Reference ref = FirebaseStorage.instance.ref().child('preoperacionales_fisicos/$nombreArchivo');
        
        final bytes = await archivoSello.readAsBytes();
        UploadTask uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
        String urlPublica = await snapshot.ref.getDownloadURL();

        // 4. ARMAR EL JSON CONTROLADOR
        Map<String, dynamic> jsonPreoperacional = {
          "tipo_registro": "FISICO",
          "fecha_registro": DateTime.now().toIso8601String(),
          "url_foto": urlPublica,
          "comentarios": "Preoperacional físico subido por foto"
        };

        // 5. GUARDAR EN MEMORIA EL JSON Y CAMBIAR LA FASE
        widget.datosServidor['preoperacional_json'] = jsonEncode(jsonPreoperacional);
        widget.datosServidor['fase_viaje'] = 'PREOP_LISTO'; 

        // 6. ACTUALIZAR TORRE DE CONTROL (POSTGRESQL)
        final conn = await Connection.open(
          Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
          settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
        );

        await conn.runTx((session) async {
          // Registro en la tabla de control de viajes
          await session.execute(
            "UPDATE flutter_schema.active_trips SET fase_viaje = 'PREOP_LISTO', fecha_preop_app = CURRENT_TIMESTAMP, preoperacional_data = \$2 WHERE trip_id = \$1",
            parameters: [tripIdReal, jsonEncode(jsonPreoperacional)],
          );

          // Inserción individual de la evidencia física
          await session.execute(
             r'''
             INSERT INTO flutter_schema.viajes 
             (guia, odometro, celular, trailer, placa_cabezote, foto_evidencia, latitud, longitud, trip_id, fecha_registro, preoperacional_data)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, $10)
             ''',
             parameters: [
               "HOJA_PREOP", 
               "0", 
               celular, 
               trailer, 
               cabezote, 
               urlPublica, 
               latLngStr.split(',')[0].trim(), 
               latLngStr.contains(',') ? latLngStr.split(',')[1].trim() : "0.0000", 
               tripIdReal, 
               jsonEncode(jsonPreoperacional)
             ]
          );
        });

        await conn.close();

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Navegación de retorno al flujo principal
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
          (route) => false,
        );

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Error en proceso: $e"), backgroundColor: Colors.red)
          );
        }
      } finally {
        if (mounted) setState(() => _subiendoFoto = false);
      }
    }
  }

  // Abrir formulario digital
  void _abrirFormularioDigital() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => PreoperacionalFormularioPage(datosServidor: widget.datosServidor)),
    );
  }

  // Omitir registro preoperacional
  Future<void> _omitirPreoperacional() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Omitiendo y actualizando fase..."), backgroundColor: Colors.orange)
    );

    try {
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;

      Map<String, dynamic> jsonOmitido = {
        "tipo_registro": "OMITIDO",
        "fecha_registro": DateTime.now().toIso8601String(),
        "observaciones": "El conductor omitió el registro preoperacional."
      };

      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      await conn.execute(
        "UPDATE flutter_schema.active_trips SET fase_viaje = 'PREOP_LISTO', fecha_preop_app = CURRENT_TIMESTAMP, preoperacional_data = \$2 WHERE trip_id = \$1",
        parameters: [tripIdReal, jsonEncode(jsonOmitido)],
      );
      await conn.close();

      widget.datosServidor['fase_viaje'] = 'PREOP_LISTO';
      widget.datosServidor['preoperacional_json'] = jsonEncode(jsonOmitido);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
        (route) => false,
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error de conexión: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inspección Preoperacional"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.fact_check, size: 80, color: Colors.blueGrey),
            const SizedBox(height: 20),
            const Text(
              "¿Cómo desea registrar su preoperacional hoy?",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),

            // OPCIÓN 1: DIGITAL
            ElevatedButton.icon(
              onPressed: _abrirFormularioDigital,
              icon: const Icon(Icons.touch_app),
              label: const Text("📝 Llenar Formulario Digital"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 18)
              ),
            ),
            const SizedBox(height: 15),

            // OPCIÓN 2: FOTO DEL PAPEL FÍSICO
            ElevatedButton.icon(
              onPressed: _subiendoFoto ? null : _tomarFotoFisico,
              icon: _subiendoFoto 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.camera_alt),
              label: Text(_subiendoFoto ? "Procesando Marca de Agua..." : "📸 Tomar Foto del Papel Físico"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 18)
              ),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),

            // OPCIÓN 3: OMITIR
            TextButton.icon(
              onPressed: _omitirPreoperacional,
              icon: const Icon(Icons.skip_next, color: Colors.grey),
              label: const Text("Omitir y continuar al viaje", style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}