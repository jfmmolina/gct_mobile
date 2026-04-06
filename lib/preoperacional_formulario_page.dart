import 'dart:convert';
import 'package:flutter/material.dart';
import 'validacion_page.dart'; 

class PreoperacionalFormularioPage extends StatefulWidget {
  final Map<String, dynamic> datosServidor;

  const PreoperacionalFormularioPage({super.key, required this.datosServidor});

  @override
  State<PreoperacionalFormularioPage> createState() => _PreoperacionalFormularioPageState();
}

class _PreoperacionalFormularioPageState extends State<PreoperacionalFormularioPage> {
  bool _guardando = false;

  final List<Map<String, dynamic>> _preguntas = [
    {"id": "docs", "titulo": "1. Documentos del Vehículo", "desc": "SOAT, Tecnomecánica y Tarjeta", "valor": "Bueno"},
    {"id": "luces", "titulo": "2. Luces y Visibilidad", "desc": "Faros, direccionales, frenos", "valor": "Bueno"},
    {"id": "frenos", "titulo": "3. Frenos y Aire", "desc": "Sin fugas de aire, pedal funcional", "valor": "Bueno"},
    {"id": "llantas", "titulo": "4. Llantas y Repuesto", "desc": "Labrado profundo y presión", "valor": "Bueno"},
    {"id": "fugas", "titulo": "5. Fugas de Fluidos", "desc": "Cero goteos de aceite o agua", "valor": "Bueno"},
    {"id": "quinta", "titulo": "6. Quinta Rueda", "desc": "Enganche y mangueras conectadas", "valor": "Bueno"},
    {"id": "cinturon", "titulo": "7. Cinturones", "desc": "Anclajes firmes y sin cortes", "valor": "Bueno"},
    {"id": "extintor", "titulo": "8. Extintor", "desc": "Cargado (presión verde) y vigente", "valor": "Bueno"},
    {"id": "kit", "titulo": "9. Kit de Carretera", "desc": "Botiquín, tacos, y absorbente", "valor": "Bueno"},
    {"id": "conductor", "titulo": "10. Estado Conductor", "desc": "Licencia vigente y descansado", "valor": "Bueno"},
    {"id": "gps", "titulo": "11. GPS Satelital", "desc": "Equipo transmitiendo correctamente", "valor": "Bueno"},
  ];

  final TextEditingController _comentariosController = TextEditingController();

  Future<void> _guardarYContinuar() async {
    setState(() => _guardando = true);

    try {
      // 1. ARMAR EL JSON CON LAS RESPUESTAS
      Map<String, dynamic> jsonPreoperacional = {
        "tipo_registro": "DIGITAL",
        "fecha_registro": DateTime.now().toIso8601String(),
        "observaciones": _comentariosController.text,
        "respuestas": {}
      };

      for (var p in _preguntas) {
        jsonPreoperacional["respuestas"][p['id']] = p['valor'];
      }

      // 2. GUARDAR EN MEMORIA
      widget.datosServidor['preoperacional_json'] = jsonEncode(jsonPreoperacional);

      // Simulamos un pequeño tiempo de carga visual
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Preoperacional Digital adjuntado al viaje"), backgroundColor: Colors.green));
      
      // 3. REGRESAR AL VIAJE
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: widget.datosServidor)),
      );

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error interno: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Preoperacional Digital"), backgroundColor: Colors.blue[900], foregroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _preguntas.length,
              itemBuilder: (context, index) {
                final p = _preguntas[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 15),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['titulo'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(p['desc'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: "Bueno", label: Text("Bueno", style: TextStyle(fontSize: 12)), icon: Icon(Icons.check_circle, size: 16, color: Colors.green)),
                            ButtonSegment(value: "Malo", label: Text("Malo", style: TextStyle(fontSize: 12)), icon: Icon(Icons.cancel, size: 16, color: Colors.red)),
                            ButtonSegment(value: "N/A", label: Text("N/A", style: TextStyle(fontSize: 12)), icon: Icon(Icons.remove_circle, size: 16, color: Colors.grey)),
                          ],
                          selected: {p['valor']},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() => p['valor'] = newSelection.first);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _comentariosController,
                  decoration: const InputDecoration(labelText: "Observaciones (Opcional)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.comment)),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: _guardando ? null : _guardarYContinuar,
                    icon: _guardando ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
                    label: Text(_guardando ? "GUARDANDO..." : "GUARDAR Y CONTINUAR", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}