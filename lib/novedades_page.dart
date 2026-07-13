import 'package:path_provider/path_provider.dart'; // Para guardar el archivo procesado
import 'package:intl/intl.dart';               // Para el formato de fecha
import 'package:image/image.dart' as img;      // Para "dibujar" en la foto
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

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

  // NUEVAS VARIABLES: Guardarán el GPS real de la Novedad
  // 1. NUEVAS VARIABLES DE CONTROL TEXTUAL (Reemplazar desde aquí)
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
      // Si falla por completo el sensor y no hay lectura previa, dejamos nulo el valor
      if (_ultimaLecturaGps == null) {
        _latitudFinal = null;
        _longitudFinal = null;
      }
    }
  }

  Future<void> _tomarFoto() async {
    try {
      setState(() => _enviando = true);
      
      // Forzamos actualización de GPS en el momento de la foto
      await _obtenerGpsReal(forzar: true);

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 70,
        maxWidth: 1200   
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        img.Image? imagenDecodificada = img.decodeImage(bytes);
        
        if (imagenDecodificada != null) {
          String placa = (widget.datosViaje['placa_cabezote'] ?? widget.datosViaje['vehiculo'] ?? "S/P").toString().toUpperCase().trim();
          String tripId = widget.datosViaje['trip_id']?.toString() ?? "0";
          String fechaHora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
          
          // Si el valor es null, la foto dirá el aviso físico, pero la BD mantendrá el concepto puro
          String coordenadasStr = (_latitudFinal == null) 
              ? "COORDENADAS NO DISPONIBLES" 
              : "GPS: $_latitudFinal, $_longitudFinal";

          String marcaAgua = "GCT NOVEDAD | PLACA: $placa | TRIP: $tripId | FECHA: $fechaHora | $coordenadasStr |";

          img.drawString(
            imagenDecodificada, marcaAgua, 
            font: img.arial24, x: 20, y: imagenDecodificada.height - 45, 
            color: img.ColorRgb8(255, 235, 59)
          );

          final File archivoProcesado = File('${tempDir.path}/novedad_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await archivoProcesado.writeAsBytes(img.encodeJpg(imagenDecodificada, quality: 85));

          setState(() {
            _fotosNovedad.add(archivoProcesado);
          });
        }
      }
      setState(() => _enviando = false);
    } catch (e) {
      debugPrint("❌ Error procesando foto de novedad: $e");
      if (mounted) setState(() => _enviando = false);
    }
  }

  // DIÁLOGO DE CONFIRMACIÓN ANTES DE ENVIAR (Previene clics accidentales)
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Esta novedad requiere foto"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _enviando = true);
    
    try {
      // Validamos el GPS antes de insertar (Si se mueve en carretera, calcula la nueva posición)
      await _obtenerGpsReal(forzar: false);

      int tripId = int.tryParse(widget.datosViaje['trip_id']?.toString() ?? "0") ?? 0;
      List<String> urls = [];

      for (var i = 0; i < _fotosNovedad.length; i++) {
        String nombre = "novedad_${tripId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
        final ref = FirebaseStorage.instance.ref().child('evidencias_viajes/$nombre');
        try {
          await ref.putFile(_fotosNovedad[i], SettableMetadata(contentType: 'image/jpeg')).timeout(const Duration(seconds: 45));
        } catch (e) {
          await ref.putFile(_fotosNovedad[i]).timeout(const Duration(seconds: 45));
        } 
        urls.add(await ref.getDownloadURL());
      }

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
          _latitudFinal, // Pasará la coordenada en texto o NULL de forma nativa
          _longitudFinal, // Pasará la coordenada en texto o NULL de forma nativa
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
      onTap: () => _confirmarRegistroNovedad(titulo), // 👈 Cambiado quirúrgicamente para llamar al aviso "¿Enviar?"
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