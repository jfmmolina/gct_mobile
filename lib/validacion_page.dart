import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart'; //TOMAR FOTO 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;


class ValidacionViajePage extends StatefulWidget {
  final Map datosServidor; // Datos que vienen de Contabo
  const ValidacionViajePage({super.key, required this.datosServidor});

  @override
  _ValidacionViajePageState createState() => _ValidacionViajePageState();
}

class _ValidacionViajePageState extends State<ValidacionViajePage> {
  final TextEditingController _guiaController = TextEditingController();
  String _mensajeServidor = "";
  final TextEditingController _odometroController = TextEditingController();
  int _fotosTomadas = 0;
  final int _limiteFotos = 4;

  // --- FUNCIÓN DE CAPTURA DE FOTO ---
  
  Future<void> _tomarFotoReal() async {
    // 1. Validar el límite de 4 fotos
    if (_fotosTomadas >= _limiteFotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Límite de 4 fotos alcanzado"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();
    Position? position;

    try {
      // 2. Intentar capturar GPS con tiempo límite de 5 segundos
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint("⏳ El GPS tardó mucho, se usará 0.0");
    }

    // 3. Abrir la cámara
    final XFile? foto = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 70, // Compresión para que no pesen tanto en Contabo
    );

    if (foto != null) {
      setState(() {
        _fotosTomadas++; // Aumentar el contador de fotos
      });

      String placa = "GCT-001"; 
      String fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      String lat = position?.latitude.toStringAsFixed(4) ?? "0.0000";
      String lon = position?.longitude.toStringAsFixed(4) ?? "0.0000";
      
      String nuevoNombre = placa + "_" + fecha + "_Lat" + lat + "_Lon" + lon + ".jpg";
      
      final directory = await getApplicationDocumentsDirectory();
      String nuevaRuta = directory.path + "/" + nuevoNombre;
      await File(foto.path).copy(nuevaRuta);

      print("📸 EVIDENCIA TÉCNICA: " + nuevoNombre);  

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Foto $_fotosTomadas de $_limiteFotos guardada"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
              Future<void> _subirEvidencias() async {
  // 1. Preparamos el JSON con los datos que el conductor editó
  final mapaParaEnviar = {
    "guia": _guiaController.text,
    "odometro": _odometroController.text,
    "celular_nuevo": widget.datosServidor['celular'], // Captura el cambio del icono naranja
    "trailer_nuevo": widget.datosServidor['placa_trailer'], // Captura el nuevo tráiler
    "placa_cabezote": widget.datosServidor['placa_cabezote'],
    "conductor": widget.datosServidor['nombre'],
  };

  try {
    // 2. Aquí es donde el Ingeniero conectará su URL de Flask
    print("Enviando datos a PostgreSQL: $mapaParaEnviar");
    
    // Por ahora, mostraremos un aviso de éxito en el celular
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✅ Datos y fotos sincronizados en Central GCT"),
        backgroundColor: Colors.blue,
      ),
    );
  } catch (e) {
    print("❌ Error al subir: $e");
  }
}

void _editarDato(String titulo, String campo) {
  TextEditingController _tempController = TextEditingController(
    // Si el dato no existe o es nulo, mostrará un espacio vacío en lugar de "null"
    text: widget.datosServidor[campo]?.toString() ?? ""
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Actualizar $titulo"),
      content: TextField(
        controller: _tempController,
        decoration: InputDecoration(hintText: "Ingrese nuevo $titulo"),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
        TextButton(
          onPressed: () {
            setState(() {
              // Actualizamos el dato en la memoria de la App
              widget.datosServidor[campo] = _tempController.text;
            });
            Navigator.pop(context);
          },
          child: const Text("GUARDAR"),
        ),
      ],
    ),
  );
}

@override
Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Validación de Inicio de Viaje")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.blue[900], 
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("EMPRESA / CLIENTE:", 
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(
                  "${widget.datosServidor['empresa_transportadora']} / ${widget.datosServidor['cliente_nombre'] ?? 'ECOPETROL'}", 
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                ),
              ],
            ), // Cierra Column del banner
          ), // Cierra Container azul
          
          Text("Hola, ${widget.datosServidor['nombre']}",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Divider(),
            // 1. Datos Personales
            ListTile(
              leading: const Icon(Icons.person),
              title: Text("Cédula: ${widget.datosServidor['cedula']}"),
              subtitle: Text("Celular: ${widget.datosServidor['celular']}"),
              trailing: IconButton(icon: const Icon(Icons.edit_note, color: Colors.orange), onPressed: () => _editarDato("Celular", "celular,")),
            ),

            // 2. Equipo (Cabezote y Trailer)
            Card(
              color: Colors.blueGrey[50],

              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    const Text("INFORMACIÓN DEL EQUIPO", style: TextStyle(fontWeight: FontWeight.bold)),
                    ListTile(
                      title: Text("Cabezote: ${widget.datosServidor['placa_cabezote']}"),
                      subtitle: Text("Trailer: ${widget.datosServidor['placa_trailer']}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_note, color: Colors.orange),  
                            onPressed: () => _editarDato("Tráiler", "placa_trailer"),
                          ),  
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _tomarFotoReal, //AQUI CONECTAMOS LA FUNCIÓN DE TOMAR FOTO
                            icon: const Icon(Icons.camera_alt, size: 18),
                            label: Text("Foto ($_fotosTomadas/$_limiteFotos)"), 
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder( 
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            // 3. Ruta
            const Text("SU RUTA ASIGNADA:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("${widget.datosServidor['ruta_nombre']}", style: const TextStyle(fontSize: 18, color: Colors.blue)),

            const SizedBox(height: 20),
            // 4. Ingreso de Guía (Obligatorio)
            const Divider(), // Una línea separadora para que se vea ordenado
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: TextField(
                controller: _odometroController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Kilometraje (Odómetro) Actual",
                  prefixIcon: const Icon(Icons.speed, color: Colors.blue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: TextField(
                controller: _guiaController,
                decoration: const InputDecoration(
                  labelText: "Ingrese el # de Guía de Viaje",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            const SizedBox(height: 30),
            // Botón de Inicio
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: (_guiaController.text.isNotEmpty && _odometroController.text.isNotEmpty)
                  ? () {
                      // 1. Capturamos lo que el conductor escribió
                      int odoNuevo = int.tryParse(_odometroController.text) ?? 0;
                      
                      // 2. Capturamos el valor que el sistema ya conoce del servidor
                      // Cambiamos 'odometro_actual' por el nombre exacto que venga de tu DB
                      //int odoBaseDatos = int.tryParse(widget.datosServidor['odometro_actual'].toString()) ?? 0;
                      int odoBaseDatos = 123456789;

                      print("Comparando: Nuevo ($odoNuevo) vs Base de Datos ($odoBaseDatos)");

                      // 3. LA REGLA DE ORO: Solo si el nuevo es estrictamente MAYOR
                      if (odoNuevo > odoBaseDatos) {
                        _subirEvidencias();
                      } else {
                        // Bloqueo inmediato si el valor es menor o igual
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("⚠️ Kilometraje Inválido"),
                            content: Text("No puedes iniciar con $odoNuevo. El último registro es $odoBaseDatos. Por favor, verifica el tablero del vehículo."),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CORREGIR")),
                            ],
                          ),
                        );
                      }
                    }
                  : null, // Si los campos están vacíos, el botón se apaga
                child: const Text("INICIAR VIAJE", 
                  style: TextStyle(color: Colors.white, fontSize: 18)),
              ), // Cierra ElevatedButton
            ), // Cierra SizedBox
          ], // Cierra Column
        ), // Cierra Column
      ), // Cierra SingleChildScrollView
    ); // Cierra Scaffold
  } // Cierra el método build
} // Cierra la clase _ValidacionViajePageState