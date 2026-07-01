import 'package:path_provider/path_provider.dart'; // Para guardar el archivo procesado
import 'package:intl/intl.dart';               // Para el formato de fecha
import 'package:image/image.dart' as img;      // Para "dibujar" en la foto
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:image_picker/image_picker.dart';

class NovedadesPage extends StatefulWidget {
  final Map<String, dynamic> datosViaje;
  final double lat;
  final double lng;

  const NovedadesPage({
    super.key, 
    required this.datosViaje, 
    required this.lat, 
    required this.lng
  });

  @override
  State<NovedadesPage> createState() => _NovedadesPageState();
}

class _NovedadesPageState extends State<NovedadesPage> {
  final TextEditingController _comentarioController = TextEditingController();
  final List<File> _fotosNovedad = [];
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;

  Future<void> _tomarFoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 70, // Compresión inicial
        maxWidth: 1000    // Tamaño máximo para no saturar la red
      );

      if (photo != null) {
        setState(() => _enviando = true); // Usamos el indicador de carga

        final bytes = await photo.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        
        // Decodificamos la imagen para trabajar en ella
        img.Image? imagenDecodificada = img.decodeImage(bytes);
        
        if (imagenDecodificada != null) {
          // 1. Preparamos el texto extrayendo placa y viaje
          String placa = widget.datosViaje['placa_cabezote']?.toString() ?? "SIN_PLACA";
          String tripId = widget.datosViaje['trip_id']?.toString() ?? "0";
          String fechaHora = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
          String coordenadas = "GPS: ${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}";
          
          // Construimos la nueva marca de agua
          String marcaAgua = "GCT NOVEDAD | $placa | $tripId | $fechaHora | $coordenadas";

          // 2. Dibujamos la marca de agua (Letras amarillas en la parte inferior)
          img.drawString(
            imagenDecodificada, 
            marcaAgua, 
            font: img.arial24, 
            x: 20, 
            y: imagenDecodificada.height - 50, 
            color: img.ColorRgb8(255, 255, 0) // Amarillo brillante
          );

          // 3. Guardamos la imagen procesada en un archivo temporal
          final File archivoProcesado = File('${tempDir.path}/novedad_temp.jpg');
          await archivoProcesado.writeAsBytes(img.encodeJpg(imagenDecodificada, quality: 85));

          setState(() {
            _fotosNovedad.add(archivoProcesado);
            _enviando = false;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error procesando foto de novedad: $e");
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _registrarNovedad(String motivo) async {
    if ((motivo == "Falla Mecánica" || motivo == "Vía Bloqueada") && _fotosNovedad.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Esta novedad requiere foto"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _enviando = true);
    
    try {
      int tripId = int.tryParse(widget.datosViaje['trip_id']?.toString() ?? "0") ?? 0;
      List<String> urls = [];

      // 1. SUBIDA DIRECTA A FIREBASE (Igual a Validación)
      for (var i = 0; i < _fotosNovedad.length; i++) {
        String nombre = "novedad_${tripId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
        final ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombre');

        // Reintento automático: Si falla por red, lo intenta una segunda vez
        try {
          await ref.putFile(
            _fotosNovedad[i], 
            SettableMetadata(contentType: 'image/jpeg')
          ).timeout(const Duration(seconds: 60)); // Aumentamos a 60 segundos por precaución
        } catch (e) {
          // Segundo intento si el primero falla por señal débil
          await ref.putFile(_fotosNovedad[i]).timeout(const Duration(seconds: 60));
        } 
  
        urls.add(await ref.getDownloadURL());
      }

      // 2. CONEXIÓN BASE DE DATOS
      final conn = await Connection.open(
        Endpoint(host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      await conn.execute(
        r'''INSERT INTO flutter_schema.trip_reports 
        (trip_id, driver_id, reason, comment, lat, lng, report_img, report_date) 
        VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)''',
        parameters: [
          tripId,
          int.tryParse(widget.datosViaje['cedula']?.toString() ?? "0") ?? 0,
          motivo,
          _comentarioController.text,
          widget.lat.toString(),
          widget.lng.toString(),
          urls.join(',')
        ],
      );

      await conn.close();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Novedad registrada"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red));
        setState(() => _enviando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Obtenemos el trip_id para mostrarlo
    String tripIdDisplay = widget.datosViaje['trip_id']?.toString() ?? "N/A";

    return Scaffold(
      appBar: AppBar(
        title: const Text("REPORTE DE NOVEDADES"), 
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. Encabezado Visual Decorativo
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_late, size: 50, color: Colors.orange),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Registrar Evento", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("Viaje activo #$tripIdDisplay", style: TextStyle(color: Colors.grey[700])),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // 2. Campo de Comentario
            TextField(
              controller: _comentarioController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: "Comentario (Opcional)",
                prefixIcon: const Icon(Icons.edit_note, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 15),

            // 3. Botón de Foto Decorado
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _enviando ? null : _tomarFoto,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _fotosNovedad.isEmpty 
                    ? "CAPTURAR EVIDENCIA FOTOGRÁFICA"
                    : "EVIDENCIA CAPTURADA (${_fotosNovedad.length})"
                ),
              ),
            ),
            
            // Vista previa de la foto (si hay)
            if (_fotosNovedad.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_fotosNovedad.first, height: 100, fit: BoxFit.cover),
                ),
              ),

            const Divider(height: 50, thickness: 1),
            
            // 4. Sección de Botones de Novedad Decorados
            Text("SELECCIONE EL MOTIVO DE LA NOVEDAD", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 20),

            if (_enviando)
              const Column(
                children: [
                  CircularProgressIndicator(color: Colors.orange),
                  SizedBox(height: 10),
                  Text("Subiendo evidencia y registrando...", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                ],
              ),

            if (!_enviando)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, // 2 columnas
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 1.6, // Proporción de los botones
                children: [
                  _botonDecorado("Tráfico", Icons.traffic, Colors.orange),
                  _botonDecorado("Falla Mecánica", Icons.car_repair, Colors.purple),
                  _botonDecorado("Vía Bloqueada", Icons.remove_road, Colors.red),
                  _botonDecorado("Descanso", Icons.coffee, Colors.blue),
                  _botonDecorado("Almuerzo", Icons.restaurant, Colors.green),
                  _botonDecorado("Pernoctar", Icons.hotel, Colors.indigo),
                ],
              ),
              const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // Widget auxiliar para crear botones decorados con iconos
  Widget _botonDecorado(String titulo, IconData icono, Color color) {
    return InkWell(
      onTap: () => _registrarNovedad(titulo),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 35, color: color),
            const SizedBox(height: 8),
            Text(
              titulo, 
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }
}