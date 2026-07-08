import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'preoperacional_formulario_page.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

// Importa tu página de validación actual para poder "Saltar" a ella
import 'validacion_page.dart'; 

class PreoperacionalOpcionesPage extends StatefulWidget {
  final Map<String, dynamic> datosServidor;

  const PreoperacionalOpcionesPage({super.key, required this.datosServidor});

  @override
  State<PreoperacionalOpcionesPage> createState() => _PreoperacionalOpcionesPageState();
}

class _PreoperacionalOpcionesPageState extends State<PreoperacionalOpcionesPage> {
  
  bool _subiendoFoto = false;

  // --- NUEVA FUNCIÓN: SELLO DE SEGURIDAD CORPORATIVO COMPLETO ---
  Future<File> _aplicarSelloDeAgua(XFile fotoOriginal) async {
    try {
      // Forzamos extracción de placa limpia en mayúsculas
      String placa = (widget.datosServidor['placa_cabezote'] ?? widget.datosServidor['vehiculo'] ?? "S/P").toString().toUpperCase().trim();
      String fechaHora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      String latLngStr = "Buscando...";

      // 1. Manejo seguro y con tiempo límite para el GPS
      try {
        LocationPermission permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
        }

        if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
          Position posicion = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 5) // Máximo 5 segundos de espera
          );
          latLngStr = "GPS: ${posicion.latitude.toStringAsFixed(6)}, ${posicion.longitude.toStringAsFixed(6)}";
        } else {
          latLngStr = "GPS Sin Permiso";
        }
      } catch (e) {
        debugPrint("Error GPS Físico: $e");
        latLngStr = "GPS No disponible";
      }

      // 2. Construcción del Sello Unificado
      String textoSello = "GCT | PLACA: $placa | FECHA: $fechaHora | $latLngStr";

      final bytes = await fotoOriginal.readAsBytes();
      img.Image? imagen = img.decodeImage(bytes);
      
      if (imagen != null) {
        img.drawString(
          imagen,
          textoSello,
          font: img.arial24,
          x: 20,
          y: imagen.height - 40,
          color: img.ColorRgb8(255, 235, 59), // Amarillo Tránsito/Seguridad para contraste perfecto
        );

        final directorio = await getTemporaryDirectory();
        final rutaNueva = '${directorio.path}/sello_fisico_${placa}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        File archivoModificado = File(rutaNueva);
        await archivoModificado.writeAsBytes(img.encodeJpg(imagen, quality: 85));
        
        return archivoModificado;
      }
    } catch (e) {
      debugPrint("Error aplicando sello en formato papel: $e");
    }
    return File(fotoOriginal.path); 
  }

  // --- FUNCIÓN TOMAR FOTO (ACTUALIZADA CON SELLO E INSERCIÓN SEGURA) ---
  Future<void> _tomarFotoFisico() async {
    if (_subiendoFoto) return;

    final ImagePicker picker = ImagePicker();
    // Forzamos el maxWidth para homologar el tamaño de la imagen y la visualización de la letra
    final XFile? foto = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
    
    if (foto != null) {
      setState(() => _subiendoFoto = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Aplicando seguridad y subiendo evidencia..."), backgroundColor: Colors.orange));

      try {
        // Ejecución del Sello Corporativo
        File archivoFisico = await _aplicarSelloDeAgua(foto);
        
        int driverId = int.tryParse(widget.datosServidor['driver_id']?.toString() ?? "0") ?? 0;
        int tripIdReal = int.tryParse(widget.datosServidor['trip_id']?.toString() ?? "0") ?? 0;
        String celular = widget.datosServidor['celular']?.toString() ?? "";
        String trailer = widget.datosServidor['placa_trailer']?.toString() ?? "";
        String cabezote = widget.datosServidor['placa_cabezote']?.toString() ?? "";
        
        // 1. SUBIR FOTO A FIREBASE (Sube el archivo ya sellado)
        String nombreArchivo = "preoperacional_${driverId}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        Reference ref = FirebaseStorage.instance.ref().child('preoperacionales_fisicos/$nombreArchivo');
        UploadTask uploadTask = ref.putFile(archivoFisico, SettableMetadata(contentType: 'image/jpeg'));
        TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 45));
        String urlPublica = await snapshot.ref.getDownloadURL();

        // 2. ARMAR EL JSON CONTROLADOR
        Map<String, dynamic> jsonPreoperacional = {
          "tipo_registro": "FISICO",
          "fecha_registro": DateTime.now().toIso8601String(),
          "url_foto": urlPublica,
          "comentarios": "Preoperacional físico subido por foto"
        };

        // 3. GUARDAR EN MEMORIA EL JSON Y CAMBIAR LA FASE
        widget.datosServidor['preoperacional_json'] = jsonEncode(jsonPreoperacional);
        widget.datosServidor['fase_viaje'] = 'PREOP_LISTO'; 

        // 4. ACTUALIZAR LA TORRE DE CONTROL (POSTGRESQL - TRANSACCIONAL SIN REESCRITURAS)
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

          // INSERCIÓN DE NUEVA FILA FÍSICA: Evita que se pise y almacena la evidencia de la hoja de forma individual
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
               "0.0000", 
               "0.0000", 
               tripIdReal, 
               jsonEncode(jsonPreoperacional)
             ]
          );
        });

        await conn.close();

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Navegación segura hacia el inicio de ruta
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
          (route) => false,
        );

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error en proceso: $e"), backgroundColor: Colors.red));
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