import 'package:flutter/material.dart';
import 'main.dart'; // Para poder navegar al Login después

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  bool _aceptoTerminos = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              "Configuración Inicial GCT",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              "Para operar correctamente, esta aplicación requiere:\n\n"
              "1. Uso de Cámara (para reporte de novedades).\n"
              "2. GPS (para seguimiento de ruta).\n"
              "3. Aceptación de políticas de manejo de datos.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            CheckboxListTile(
              title: const Text("Acepto los Términos y Condiciones de uso."),
              value: _aceptoTerminos,
              onChanged: (value) {
                setState(() => _aceptoTerminos = value!);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _aceptoTerminos 
                ? () => Navigator.pushReplacement(
                    context, MaterialPageRoute(builder: (context) => const LoginPage()))
                : null,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text("CONTINUAR A LA APP"),
            ),
          ],
        ),
      ),
    );
  }
}