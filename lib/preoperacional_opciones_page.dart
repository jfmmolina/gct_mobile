import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'preoperacional_formulario_page.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:postgres/postgres.dart';

// Importa tu página de validación actual para poder "Saltar" a ella
import 'validacion_page.dart'; 

class PreoperacionalOpcionesPage extends StatefulWidget {
  final Map<String, dynamic> datosServidor;

  const PreoperacionalOpcionesPage({super.key, required this.datosServidor});

  @override
  State<PreoperacionalOpcionesPage> createState() => _PreoperacionalOpcionesPageState();
}

class _PreoperacionalOpcionesPageState extends State<PreoperacionalOpcionesPage> {
  
  // Función para capturar foto del físico
  bool _subiendoFoto = false;

  Future<void> _tomarFotoFisico() async {
    if (_subiendoFoto) return;

    final ImagePicker picker = ImagePicker();
    final XFile? foto = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    
    if (foto != null) {
      setState(() => _subiendoFoto = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Subiendo evidencia física..."), backgroundColor: Colors.orange));

      try {
        File archivoFisico = File(foto.path);
        int driverId = int.tryParse(widget.datosServidor['driver_id']?.toString() ?? "0") ?? 0;
        int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
        
        // 1. SUBIR FOTO A FIREBASE
        String nombreArchivo = "preoperacional_${driverId}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        Reference ref = FirebaseStorage.instance.ref().child('preoperacionales_fisicos/$nombreArchivo');
        UploadTask uploadTask = ref.putFile(archivoFisico, SettableMetadata(contentType: 'image/jpeg'));
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
        String urlPublica = await snapshot.ref.getDownloadURL();

        // 2. ARMAR EL JSON
        Map<String, dynamic> jsonPreoperacional = {
          "tipo_registro": "FISICO",
          "fecha_registro": DateTime.now().toIso8601String(),
          "url_foto": urlPublica,
          "comentarios": "Preoperacional físico subido por foto"
        };

        // 3. GUARDAR EN MEMORIA EL JSON Y CAMBIAR LA FASE
        widget.datosServidor['preoperacional_json'] = jsonEncode(jsonPreoperacional);
        widget.datosServidor['fase_viaje'] = 'PREOP_LISTO'; 

        // 4. ACTUALIZAR LA TORRE DE CONTROL (POSTGRESQL) - AHORA CON EL BLINDAJE JSON
        final conn = await Connection.open(
          Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
          settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
        );
        await conn.execute(
          "UPDATE flutter_schema.active_trips SET fase_viaje = 'PREOP_LISTO', fecha_preop_app = CURRENT_TIMESTAMP, preoperacional_data = \$2 WHERE trip_id = \$1",
          parameters: [tripIdReal, jsonEncode(jsonPreoperacional)],
        );
        await conn.close();

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Teletransportación segura
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
          (route) => false,
        );

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _subiendoFoto = false);
      }
    }
  }

  // Función para abrir el formulario digital
  void _abrirFormularioDigital() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => PreoperacionalFormularioPage(datosServidor: widget.datosServidor)),
    );
  }

  // Función para omitir y continuar
  Future<void> _omitirPreoperacional() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Omitiendo y actualizando fase..."), backgroundColor: Colors.orange));

    try {
      int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;

      // 1. Armamos un JSON que registre la omisión para tener historial
      Map<String, dynamic> jsonOmitido = {
        "tipo_registro": "OMITIDO",
        "fecha_registro": DateTime.now().toIso8601String(),
        "observaciones": "El conductor omitió el registro preoperacional."
      };

      // 2. Actualizamos la base de datos a PREOP_LISTO
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      await conn.execute(
        "UPDATE flutter_schema.active_trips SET fase_viaje = 'PREOP_LISTO', fecha_preop_app = CURRENT_TIMESTAMP, preoperacional_data = \$2 WHERE trip_id = \$1",
        parameters: [tripIdReal, jsonEncode(jsonOmitido)],
      );
      await conn.close();

      // 3. Actualizamos la memoria del celular
      widget.datosServidor['fase_viaje'] = 'PREOP_LISTO';
      widget.datosServidor['preoperacional_json'] = jsonEncode(jsonOmitido);

      // 4. Teletransportación segura a la pantalla final
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error de conexión: $e"), backgroundColor: Colors.red));
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

            // OPCIÓN 2: FOTO DEL PAPEL
            ElevatedButton.icon(
              onPressed: _subiendoFoto ? null : _tomarFotoFisico,
              icon: _subiendoFoto 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.camera_alt),
              label: Text(_subiendoFoto ? "Subiendo..." : "📸 Tomar Foto del Papel Físico"),
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