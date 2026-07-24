import 'package:flutter/material.dart';
import 'main.dart'; // Para poder navegar al Login después
import 'politicas_privacidad_widget.dart'; // Widget legal estandarizado

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Reemplazo de ícono genérico por Logo Oficial de GCT
              Image.asset(
                'assets/logo_gct.png',
                height: 100,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.security, 
                  size: 80, 
                  color: Colors.blue
                ),
              ),
              const SizedBox(height: 25),
              
              const Text(
                "Configuración Inicial GCT",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              
              const Text(
                "Para operar correctamente, esta aplicación requiere:\n\n"
                "1. Uso de Cámara (para evidencia y novedades).\n"
                "2. GPS (para seguimiento de ruta en tiempo real).\n"
                "3. Aceptación de políticas de manejo de datos.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 25),

              // 2. Enlace interactivo directo a las Políticas Legales Web
              const PoliticasPrivacidadWidget(textColor: Colors.blueAccent),
              
              const SizedBox(height: 15),

              // 3. Checkbox de Aceptación
              CheckboxListTile(
                title: const Text(
                  "Acepto los Términos y Condiciones de uso.",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                value: _aceptoTerminos,
                onChanged: (value) {
                  setState(() => _aceptoTerminos = value ?? false);
                },
              ),
              const SizedBox(height: 20),

              // 4. Botón Continuar
              ElevatedButton(
                onPressed: _aceptoTerminos 
                  ? () => Navigator.pushReplacement(
                      context, 
                      MaterialPageRoute(builder: (context) => const LoginPage())
                    )
                  : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blue[900],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "CONTINUAR A LA APP",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}