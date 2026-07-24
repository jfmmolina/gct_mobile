import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'watermark_service.dart'; // Servicio unificado con logo GCT y marca de agua

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

  String? _latitudFinal;
  String? _longitudFinal;
  DateTime? _ultimaLecturaGps;

  @override
  void initState() {
    super.initState();
    // Disparamos la búsqueda de GPS de inmediato al abrir la pantalla para ganar tiempo
    _obtenerGpsReal(forzar: false);
  }

  // FUNCIÓN UNIFICADA PARA CAPTURA DE GPS REAL
  Future<void> _obtenerGpsReal({required bool forzar}) async {
    // Si no es forzado y ya tenemos una lectura de hace menos de 45 segundos, la reutilizamos
    if (!forzar && _ultimaLecturaGps != null && 
        DateTime.now().difference(_ultimaLecturaGps!).inSeconds < 45) {
      return;
    }

    try {
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission(); 
      
      if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
        // Intento rápido con la última posición conocida
        Position? ultimaConocida = await Geolocator.getLastKnownPosition();
        if (ultimaConocida != null) {
          _latitudFinal = ultimaConocida.latitude.toStringAsFixed(6);
          _longitudFinal = ultimaConocida.longitude.toStringAsFixed(6);
        }

        // Consulta al sensor en tiempo real (máximo 5 segundos de espera)
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium, 
          timeLimit: const Duration(seconds: 5)
        );
        
        _latitudFinal = position.latitude.toStringAsFixed(6);
        _longitudFinal = position.longitude.toStringAsFixed(6);
        _ultimaLecturaGps = DateTime.now();
      }
    } catch (e) {
      debugPrint("⚠️ No se pudo obtener señal GPS fresca: $e");
      if (_ultimaLecturaGps == null) {
        _latitudFinal = null;
        _longitudFinal = null;
      }
    }
  }

  // TOMAR FOTO CON WATERMARK SERVICE (LOGO GCT + DATOS)
  Future<void> _tomarFoto() async {
    try {
      setState(() => _enviando = true);
      
      // Forzamos actualización de GPS en el momento de la foto
      await _obtenerGpsReal(forzar: true);

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 85,
        maxWidth: 1280   
      );

      if (photo != null) {
        String placa = (widget.datosViaje['placa_cabezote'] ?? widget.datosViaje['vehiculo'] ?? "S/P")
            .toString()
            .toUpperCase()
            .trim();

        String coordenadasStr = (_latitudFinal == null)
            ? "${widget.lat}, ${widget.lng}"
            : "$_latitudFinal, $_longitudFinal";

        dynamic tripIdReal = widget.datosViaje['trip_id'] ?? widget.datosViaje['id_viaje'];

        // Aplicamos la marca de agua corporativa
        File fotoSellada = await WatermarkService.aplicarMarcaDeAgua(
          imagenOriginal: File(photo.path),
          placa: placa,
          gps: coordenadasStr,
          tripId: tripIdReal,
          tipo: TipoEvidencia.novedadRuta,
        );

        if (mounted) {
          setState(() {
            _fotosNovedad.add(fotoSellada); // 👈 Usa la variable fotoSellada
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error procesando foto de novedad: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al capturar foto: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // DIÁLOGO DE CONFIRMACIÓN ANTES DE ENVIAR
  void _confirmarRegistroNovedad(String motivo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text("Confirmar Reporte"),
            ],
          ),
          content: Text("¿Está seguro que desea reportar la novedad de tipo \"$motivo\"?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
              onPressed: () {
                Navigator.pop(context);
                _registrarNovedad(motivo);
              },
              child: const Text("CONFIRMAR", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _registrarNovedad(String motivo) async {
    if ((motivo == "Falla Mecánica" || motivo == "Vía Bloqueada") && _fotosNovedad.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Esta novedad requiere foto de evidencia"), backgroundColor: Colors.orange)
      );
      return;
    }

    setState(() => _enviando = true);
    
    try {
      await _obtenerGpsReal(forzar: false);

      int tripId = int.tryParse(widget.datosViaje['trip_id']?.toString() ?? "0") ?? 0;
      List<String> urls = [];

      // Subida de fotos selladas a evidencias_viajes/ en Firebase Storage
      for (var i = 0; i < _fotosNovedad.length; i++) {
        String nombre = "novedad_${tripId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
        final ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombre');
        
        final bytes = await _fotosNovedad[i].readAsBytes();
        UploadTask uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
        
        String url = await snapshot.ref.getDownloadURL();
        urls.add(url);
      }

      // Conexión y guardado en PostgreSQL
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
          _latitudFinal,
          _longitudFinal,
          urls.join(',')
        ],
      );

      await conn.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Novedad registrada correctamente"), backgroundColor: Colors.green)
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al registrar novedad: $e"), backgroundColor: Colors.red)
        );
        setState(() => _enviando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            
            if (_fotosNovedad.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_fotosNovedad.first, height: 100, fit: BoxFit.cover),
                ),
              ),

            const Divider(height: 50, thickness: 1),
            
            Text("SELECCIONE EL MOTIVO DE LA NOVEDAD", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 20),

            if (_enviando)
              const Column(
                children: [
                  CircularProgressIndicator(color: Colors.orange),
                  SizedBox(height: 10),
                  Text("Procesando y registrando...", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                ],
              ),

            if (!_enviando)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, 
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 1.6, 
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

  Widget _botonDecorado(String titulo, IconData icono, Color color) {
    return InkWell(
      onTap: () => _confirmarRegistroNovedad(titulo),
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