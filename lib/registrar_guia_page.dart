import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:barcode_scan2/barcode_scan2.dart';

class RegistrarGuiaPage extends StatefulWidget {
  final Map<String, dynamic> datosViaje;

  const RegistrarGuiaPage({super.key, required this.datosViaje});

  @override
  State<RegistrarGuiaPage> createState() => _RegistrarGuiaPageState();
}

class _RegistrarGuiaPageState extends State<RegistrarGuiaPage> {
  final TextEditingController _guiaController = TextEditingController();
  File? _fotoGuia;
  final ImagePicker _picker = ImagePicker();
  bool _guardando = false;

  // 1. ESCANEAR CÓDIGO DE BARRAS (Igual a Validación)
  Future<void> _escanearCodigo() async {
    try {
      var result = await BarcodeScanner.scan();
      if (result.type == ResultType.Barcode && mounted) {
        setState(() {
          _guiaController.text = result.rawContent;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Código leído con éxito"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error de escáner: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  // 2. TOMAR FOTO DE LA GUÍA (Formato simple y comprimido)
  Future<void> _tomarFoto() async {
    try {
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
        maxWidth: 800,
      );
      if (foto != null) {
        setState(() {
          _fotoGuia = File(foto.path);
        });
      }
    } catch (e) {
      debugPrint("❌ Error al abrir cámara: $e");
    }
  }

  // 3. SUBIR A BASE DE DATOS Y FIREBASE
  Future<void> _guardarDatos() async {
    if (_guiaController.text.trim().isEmpty && _fotoGuia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Debe escanear la guía o tomar la foto"), backgroundColor: Colors.orange)
      );
      return;
    }

    setState(() => _guardando = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Guardando guía en el sistema..."), backgroundColor: Colors.blue)
    );

    try {
      int tripId = int.tryParse(widget.datosViaje['trip_id']?.toString() ?? "0") ?? 0;
      String urlFotoPublica = "";

      // Si tomó foto, la subimos a Firebase
      if (_fotoGuia != null) {
        String nombre = "guia_ruta_${tripId}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombre');
        
        UploadTask uploadTask = ref.putFile(_fotoGuia!, SettableMetadata(contentType: 'image/jpeg'));
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
        urlFotoPublica = await snapshot.ref.getDownloadURL();
      }

      // Conectamos a PostgreSQL para actualizar las dos tablas
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // Actualizamos tracking_number en active_trips e insertamos/actualizamos en viajes
      await conn.runTx((session) async {
        await session.execute(
          "UPDATE flutter_schema.active_trips SET tracking_number = \$1 WHERE trip_id = \$2",
          parameters: [_guiaController.text.trim(), tripId],
        );

        if (urlFotoPublica.isNotEmpty) {
          await session.execute(
            "UPDATE flutter_schema.viajes SET guia = \$1, foto_evidencia = \$2 WHERE trip_id = \$3",
            parameters: [_guiaController.text.trim(), urlFotoPublica, tripId],
          );
        } else {
          await session.execute(
            "UPDATE flutter_schema.viajes SET guia = \$1 WHERE trip_id = \$3",
            parameters: [_guiaController.text.trim(), tripId],
          );
        }
      });

      await conn.close();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Guía registrada correctamente"), backgroundColor: Colors.green)
        );
        Navigator.pop(context); // Regresa al mapa automáticamente
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al guardar: $e"), backgroundColor: Colors.red)
        );
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("REGISTRAR GUÍA DE VIAJE"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PASO 1: El Número o Escáner
            const Text("PASO 1: LEER EL CÓDIGO DE LA GUÍA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: _guiaController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "Número de Guía",
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description, size: 28),
                suffixIcon: IconButton(
                  icon: Icon(Icons.qr_code_scanner, color: Colors.blue[800], size: 36),
                  onPressed: _escanearCodigo,
                ),
              ),
            ),
            
            const SizedBox(height: 35),

            // PASO 2: La Foto
            const Text("PASO 2: TOMAR FOTO DE LA GUÍA (PAPEL)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _guardando ? null : _tomarFoto,
                icon: const Icon(Icons.camera_alt, size: 26),
                label: const Text("ABRIR CÁMARA Y TOMAR FOTO", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700], foregroundColor: Colors.white),
              ),
            ),
            
            if (_fotoGuia != null) ...[
              const SizedBox(height: 15),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_fotoGuia!, height: 180, fit: BoxFit.cover),
                ),
              ),
            ],

            const SizedBox(height: 40),
            const Divider(thickness: 1.5),
            const SizedBox(height: 20),

            // PASO 3: Botón de Enviar Gigante
            SizedBox(
              width: double.infinity,
              height: 65,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardarDatos,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _guardando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("GUARDAR Y VOLVER AL MAPA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}