import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'preoperacional_formulario_page.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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

        // 3. GUARDAR EN MEMORIA
        widget.datosServidor['preoperacional_json'] = jsonEncode(jsonPreoperacional);

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Foto procesada. Continúe con el viaje."), backgroundColor: Colors.green));
        
        _irAValidacionViaje();

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error subiendo foto: $e"), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _subiendoFoto = false);
      }
    }
  }

  // Función para omitir y continuar
  void _irAValidacionViaje() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
    );
  }

  // Función para abrir el formulario digital (Lo haremos en el Paso 2)
  void _abrirFormularioDigital() {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (context) => PreoperacionalFormularioPage(datosServidor: widget.datosServidor)),
  );
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
              onPressed: _subiendoFoto ? null : _tomarFotoFisico, // Bloquea si está subiendo
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
              onPressed: _irAValidacionViaje,
              icon: const Icon(Icons.skip_next, color: Colors.grey),
              label: const Text("Omitir y continuar al viaje", style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}