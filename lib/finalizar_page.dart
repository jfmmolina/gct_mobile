import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'setup_page.dart'; 
import 'watermark_service.dart'; // Servicio unificado con logo GCT y marca de agua

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
  bool _procesandoFoto = false;

  // --- TOMAR FOTO DE CIERRE CON MARCA DE AGUA CORPORATIVA ---
  Future<void> _tomarFoto() async {
    if (_procesandoFoto) return;
    setState(() => _procesandoFoto = true);

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 85, 
        maxWidth: 1280
      );

      if (photo != null) {
        String placaLimpia = widget.placa.toUpperCase().trim();
        String fechaHora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        String coordenadas = "${widget.currentLat.toStringAsFixed(6)}, ${widget.currentLng.toStringAsFixed(6)}";

        // Aplicamos la marca de agua corporativa con Logo GCT y metadatos
        File fotoSellada = await WatermarkService.aplicarMarcaDeAgua(
          imagenOriginal: File(photo.path),
          textoPlaca: placaLimpia,
          textoGPS: coordenadas,
          fechaHora: fechaHora,
        );

        if (mounted) {
          setState(() {
            _fotoFinal = fotoSellada;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error foto final: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al capturar foto: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoFoto = false);
    }
  }

  // --- FINALIZAR VIAJE Y REGISTRAR EN FIREBASE / POSTGRESQL ---
  Future<void> _finalizarTodo() async {
    if (_fotoFinal == null || _odometroController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Foto y odómetro obligatorios"), 
        backgroundColor: Colors.orange
      ));
      return;
    }

    setState(() => _enviando = true);
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("⏳ Finalizando viaje... No cierre la app"), 
      backgroundColor: Colors.blue,
      duration: Duration(seconds: 10),
    ));

    try {
      // 1. SUBIR FOTO A FIREBASE STORAGE EN evidencias_viajes/
      String urlFoto = "";
      String nombreArchivo = "cierre_${widget.tripId}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombreArchivo');
      
      final bytes = await _fotoFinal!.readAsBytes();
      UploadTask uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 60));

      urlFoto = await snapshot.ref.getDownloadURL();

      // 2. CONECTAR A LA BASE DE DATOS DE GCT
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // 3. EJECUTAR CIERRE TRANSACCIONAL EN LA BASE DE DATOS
      await conn.runTx((session) async {
        // Registrar el reporte final de cierre
        await session.execute(
          r'''INSERT INTO flutter_schema.trip_reports 
          (trip_id, reason, comment, lat, lng, report_img, report_date) 
          VALUES ($1, 'FINALIZADO', $2, $3, $4, $5, CURRENT_TIMESTAMP)''',
          parameters: [
            widget.tripId, 
            "Odómetro Final: ${_odometroController.text.trim()}. ${_comentariosController.text.trim()}", 
            widget.currentLat.toStringAsFixed(6), 
            widget.currentLng.toStringAsFixed(6), 
            urlFoto
          ],
        );

        // Actualizar estado en active_trips
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
        
        // Volver a la pantalla inicial limpiando la pila
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SetupPage()), 
          (route) => false
        );
      }
      
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("❌ Error al cerrar viaje: $e"), 
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("FINALIZAR VIAJE"), 
        backgroundColor: Colors.redAccent, 
        foregroundColor: Colors.white
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.flag_circle, size: 80, color: Colors.redAccent),
            Text("Viaje #${widget.tripId} - Placa: ${widget.placa}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            TextField(
              controller: _odometroController, 
              keyboardType: TextInputType.number, 
              decoration: const InputDecoration(
                labelText: "Odómetro Final (Km)", 
                border: OutlineInputBorder(), 
                prefixIcon: Icon(Icons.speed)
              )
            ),
            const SizedBox(height: 15),
            
            TextField(
              controller: _comentariosController, 
              decoration: const InputDecoration(
                labelText: "Comentarios (Opcional)", 
                border: OutlineInputBorder(), 
                prefixIcon: Icon(Icons.comment)
              )
            ),
            const SizedBox(height: 20),
            
            GestureDetector(
              onTap: (_enviando || _procesandoFoto) ? null : _tomarFoto,
              child: Container(
                height: 200, 
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200], 
                  border: Border.all(color: Colors.grey), 
                  borderRadius: BorderRadius.circular(10)
                ),
                child: _procesandoFoto
                    ? const Center(child: CircularProgressIndicator())
                    : _fotoFinal != null 
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.file(_fotoFinal!, fit: BoxFit.cover),
                          ) 
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center, 
                            children: [
                              Icon(Icons.camera_alt, size: 50, color: Colors.grey), 
                              SizedBox(height: 8),
                              Text("Tocar para foto obligatoria de cierre", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 30),
            
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50), 
                backgroundColor: Colors.red[800], 
                foregroundColor: Colors.white
              ),
              onPressed: (_enviando || _procesandoFoto) ? null : _finalizarTodo,
              icon: _enviando 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.check_circle),
              label: Text(_enviando ? " FINALIZANDO VIAJE..." : "CONFIRMAR FIN DE VIAJE", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}