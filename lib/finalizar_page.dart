import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'setup_page.dart'; 

class FinalizarViajePage extends StatefulWidget {
  final double currentLat;
  final double currentLng;
  final int tripId;   
  final String placa; 

  const FinalizarViajePage({
    super.key, 
    required this.currentLat, 
    required this.currentLng,
    required this.tripId, 
    required this.placa,
  });

  @override
  State<FinalizarViajePage> createState() => _FinalizarViajePageState();
}

class _FinalizarViajePageState extends State<FinalizarViajePage> {
  final TextEditingController _odometroController = TextEditingController();
  final TextEditingController _comentariosController = TextEditingController();
  File? _fotoFinal;
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;

  Future<void> _tomarFoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 70, 
        maxWidth: 1000
      );

      if (photo != null) {
        setState(() => _enviando = true);

        final bytes = await photo.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        
        img.Image? imagenDecodificada = img.decodeImage(bytes);
        
        if (imagenDecodificada != null) {
          // Marca de agua específica para el Fin de Viaje
          String fechaHora = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
          String coordenadas = "GPS: ${widget.currentLat.toStringAsFixed(5)}, ${widget.currentLng.toStringAsFixed(5)}";
          String marcaAgua = "GCT FIN VIAJE | $fechaHora | $coordenadas";

          img.drawString(
            imagenDecodificada, 
            marcaAgua, 
            font: img.arial24, 
            x: 20, 
            y: imagenDecodificada.height - 50, 
            color: img.ColorRgb8(255, 255, 0)
          );

          final File archivoProcesado = File('${tempDir.path}/cierre_temp.jpg');
          await archivoProcesado.writeAsBytes(img.encodeJpg(imagenDecodificada, quality: 85));

          setState(() {
            _fotoFinal = archivoProcesado;
            _enviando = false;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error foto final: $e");
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _finalizarTodo() async {
    if (_fotoFinal == null || _odometroController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Foto y odómetro obligatorios"), 
        backgroundColor: Colors.orange
      ));
      return;
    }

    setState(() => _enviando = true);
    
    // Banner de paciencia para el conductor
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("⏳ Finalizando viaje... No cierre la app"), 
      backgroundColor: Colors.blue,
      duration: Duration(seconds: 10),
    ));

    try {
      // 1. SUBIR FOTO A FIREBASE CON TIMEOUT DE 60s
      String urlFoto = "";
      final ref = FirebaseStorage.instance.ref().child('evidencias_viajes/cierre_${widget.tripId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      // 👇 Aquí está el blindaje contra el error "se quedó pensando"
      await ref.putFile(_fotoFinal!, SettableMetadata(contentType: 'image/jpeg')).timeout(const Duration(seconds: 60));

      urlFoto = await ref.getDownloadURL();

      // 2. CONECTAR A LA BASE DE DATOS DE GCT
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // 3. EJECUTAR CIERRE EN LA BASE DE DATOS
      await conn.runTx((session) async {
        // Registrar el reporte final
        await session.execute(
          r'''INSERT INTO flutter_schema.trip_reports 
          (trip_id, reason, comment, lat, lng, report_img, report_date) 
          VALUES ($1, 'FINALIZADO', $2, $3, $4, $5, CURRENT_TIMESTAMP)''',
          parameters: [
            widget.tripId, 
            "Odómetro Final: ${_odometroController.text}. ${_comentariosController.text}", 
            widget.currentLat.toString(), 
            widget.currentLng.toString(), 
            urlFoto
          ],
        );

        // Apagar el viaje en active_trips
        await session.execute(
          r"UPDATE flutter_schema.active_trips SET current_state = 'FINALIZADO', is_running = false WHERE trip_id = $1",
          parameters: [widget.tripId],
        );
      });

      await conn.close();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✅ VIAJE FINALIZADO CON ÉXITO"), 
          backgroundColor: Colors.green
        ));
        
        // Volver al inicio de forma limpia
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SetupPage()), 
          (route) => false
        );
      }
      
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("❌ Error al cerrar: $e"), 
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FINALIZAR VIAJE"), backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.flag_circle, size: 80, color: Colors.redAccent),
            Text("Viaje #${widget.tripId} - Placa: ${widget.placa}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(controller: _odometroController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Odómetro Final (Km)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed))),
            const SizedBox(height: 15),
            TextField(controller: _comentariosController, decoration: const InputDecoration(labelText: "Comentarios (Opcional)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.comment))),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _tomarFoto,
              child: Container(
                height: 200, width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                child: _fotoFinal != null ? Image.file(_fotoFinal!, fit: BoxFit.cover) : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, size: 50, color: Colors.grey), Text("Tocar para foto obligatoria")]),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.red[800], foregroundColor: Colors.white),
              onPressed: _enviando ? null : _finalizarTodo,
              icon: _enviando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.check_circle),
              label: Text(_enviando ? " FINALIZANDO..." : "CONFIRMAR FIN DE VIAJE"),
            ),
          ],
        ),
      ),
    );
  }
}