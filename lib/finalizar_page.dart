import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:postgres/postgres.dart';
import 'setup_page.dart'; // Para devolvernos al Login al terminar


class FinalizarViajePage extends StatefulWidget {
  final double currentLat;
  final double currentLng;
  final String placa; 

  const FinalizarViajePage({
    super.key, 
    required this.currentLat, 
    required this.currentLng,
    this.placa = "TTR578" // ⚠️ OJO: Aquí luego pondremos la variable real
  });

  @override
  State<FinalizarViajePage> createState() => _FinalizarViajePageState();
}

class _FinalizarViajePageState extends State<FinalizarViajePage> {
  final TextEditingController _odometroController = TextEditingController();
  final TextEditingController _comentariosController = TextEditingController();
  File? _imagenCumplido;
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;

  // 📸 FUNCIÓN CÁMARA
  Future<void> _tomarFoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 40, 
        maxWidth: 800
      );
      if (photo != null) {
        setState(() {
          _imagenCumplido = File(photo.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al abrir cámara. Verifique permisos.")),
      );
    }
  }

  // 🏁 FUNCIÓN FINALIZAR Y LIBERAR
  Future<void> _finalizarViaje() async {
    if (_odometroController.text.isEmpty || _imagenCumplido == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Obligatorio: Odómetro y Foto del Cumplido"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // 🔥 COMANDO DE LIBERACIÓN 🔥
      await conn.execute(
        r'''
        UPDATE flutter_schema.active_trips 
        SET status = 'COMPLETED', end_date = CURRENT_TIMESTAMP, end_lat = $1, end_lng = $2, end_odometer = $3, cumplido_check = TRUE
        WHERE truck_plate = $4 AND status = 'ACTIVE'
        ''',
        parameters: [
          widget.currentLat.toString(),
          widget.currentLng.toString(),
          int.tryParse(_odometroController.text) ?? 0,
          widget.placa,
        ],
      );

      await conn.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Viaje Finalizado. ¡Buen trabajo!"), backgroundColor: Colors.green));
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SetupPage()), (route) => false);
      }
    } catch (e) {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FINALIZAR VIAJE"), backgroundColor: Colors.redAccent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.assignment_turned_in, size: 70, color: Colors.green),
            const SizedBox(height: 15),
            const Text("Adjunte la evidencia para cerrar el viaje", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            
            TextField(
              controller: _odometroController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Odómetro Final (Km)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed)),
            ),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _tomarFoto,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                child: _imagenCumplido == null
                    ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, size: 50), Text("Tocar para FOTO CUMPLIDO")])
                    : Image.file(_imagenCumplido!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 30),

            _enviando 
              ? const CircularProgressIndicator()
              : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], minimumSize: const Size(double.infinity, 50)),
                  onPressed: _finalizarViaje,
                  icon: const Icon(Icons.flag, color: Colors.white),
                  label: const Text("FINALIZAR Y SALIR", style: TextStyle(color: Colors.white, fontSize: 18)),
                )
          ],
        ),
      ),
    );
  }
}