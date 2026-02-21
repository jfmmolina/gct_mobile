import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Para la foto de la placa

class ValidacionViajePage extends StatefulWidget {
  final Map datosServidor; // Datos que vienen de Contabo
  ValidacionViajePage({required this.datosServidor});

  @override
  _ValidacionViajePageState createState() => _ValidacionViajePageState();
}

class _ValidacionViajePageState extends State<ValidacionViajePage> {
  final TextEditingController _guiaController = TextEditingController();
  bool _datosConfirmados = false;

  // Función para capturar foto si hay discrepancia en la placa
  Future<void> _tomarFotoPlaca() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      print("Foto de placa capturada: ${pickedFile.path}");
      // Aquí enviarías la foto al servidor de Contabo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Validación de Inicio de Viaje")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Hola, ${widget.datosServidor['nombre']}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Divider(),
            
            // 1. Datos Personales
            ListTile(
              leading: Icon(Icons.person),
              title: Text("Cédula: ${widget.datosServidor['cedula']}"),
              subtitle: Text("Celular: ${widget.datosServidor['celular']}"),
              trailing: IconButton(icon: Icon(Icons.edit_note, color: Colors.orange), onPressed: () {}),
            ),

            // 2. Equipo (Cabezote y Trailer)
            Card(
              color: Colors.blueGrey[50],
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Column(
                  children: [
                    Text("INFORMACIÓN DEL EQUIPO", style: TextStyle(fontWeight: FontWeight.bold)),
                    ListTile(
                      title: Text("Cabezote: ${widget.datosServidor['placa_cabezote']}"),
                      subtitle: Text("Trailer: ${widget.datosServidor['placa_trailer']}"),
                      trailing: ElevatedButton.icon(
                        onPressed: _tomarFotoPlaca, 
                        icon: Icon(Icons.camera_alt), 
                        label: Text("Reportar Error")
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),
            // 3. Ruta
            Text("SU RUTA ASIGNADA:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("${widget.datosServidor['ruta_nombre']}", style: TextStyle(fontSize: 18, color: Colors.blue)),

            SizedBox(height: 20),
            // 4. Ingreso de Guía (Obligatorio)
            TextField(
              controller: _guiaController,
              decoration: InputDecoration(
                labelText: "Ingrese el # de Guía de Viaje",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description)
              ),
              onChanged: (val) => setState(() {}),
            ),

            SizedBox(height: 30),
            // Botón de Inicio
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _guiaController.text.isNotEmpty 
                  ? () {
                      // Aquí navegas al DashboardPage que ya tienes
                      Navigator.pushReplacementNamed(context, '/mapa');
                    } 
                  : null, // Se deshabilita si no hay guía
                child: Text("INICIAR VIAJE", style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            )
          ],
        ),
      ),
    );
  }
}