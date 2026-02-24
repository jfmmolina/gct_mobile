import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // <--- IMPORTANTE PARA EL MOVIMIENTO
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'validacion_page.dart';
import 'setup_page.dart'; 

void main() {
  runApp( const MaterialApp(
    debugShowCheckedModeBanner: false, // Esto quita la etiqueta roja de "debug"
    home:  SetupPage(), 
  ));
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _cedulaController = TextEditingController();
  String _mensajeServidor = "Esperando conexión...";
  double _latitudActual = 6.2442;
  double _longitudActual = -75.5812;

  Future<void> _conectarConServidor() async {
    setState(() { _mensajeServidor = "Conectando a Linux..."; });
    try {
      final respuesta = await http.get(Uri.parse('https://terminals-sight-miscellaneous-pointing.trycloudflare.com/api/test?t=${_cedulaController.text}'));
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body);
        setState(() {
          _mensajeServidor = "¡ÉXITO! Recibiendo datos de ${datos['sensor']}";
          _latitudActual = datos['lat'];  
          _longitudActual = datos['lng'];
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: datos)));
        });
      }
    } catch (e) {
      setState(() { _mensajeServidor = "Error de conexión en puerto 8080"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering, size: 80, color: Colors.blue),
            const Text("GCT MOBILE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(controller: _cedulaController, decoration: const InputDecoration(labelText: 'Cédula', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Text(_mensajeServidor, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _conectarConServidor,
              child: const Text("PROBAR CONEXIÓN CON LINUX"),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final double lat;
  final double lng;
  const DashboardPage({super.key, required this.lat, required this.lng});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late double currentLat;
  late double currentLng;
  Timer? _timer;
  final MapController _mapController = MapController();

  // Variables para la tarjeta informativa
  String sensorName = "Cargando...";
  int velocidad = 0;
  String status = "online";

  @override
  void initState() {
    super.initState();
    currentLat = widget.lat;
    currentLng = widget.lng;
    // Iniciar el rastreo automático cada 5 segundos
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) => _actualizarUbicacion());
  }

  Future<void> _actualizarUbicacion() async {
    try {
      final respuesta = await http.get(Uri.parse('https://terminals-sight-miscellaneous-pointing.trycloudflare.com/api/test?t=${DateTime.now().millisecondsSinceEpoch}'));
      //final respuesta = await http.get(Uri.parse('https://thought-tattoo-nobody-lbs.trycloudflare.com/api/test'));
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body);
        if (mounted) {
          setState(() {
            currentLat = datos['lat'];
            currentLng = datos['lng'];
            sensorName = datos['sensor'];
            velocidad = datos['velocidad'];
            status = datos['status'];
          });
          if (mounted) {
          setState(() {
            currentLat = datos['lat'];
            currentLng = datos['lng'];
            sensorName = datos['sensor'];
            velocidad = datos['velocidad'];
            status = datos['status'];
          });
          
          // ESTA ES LA LÍNEA MÁGICA:
          _mapController.move(LatLng(currentLat, currentLng), _mapController.camera.zoom);
        }
        }
      }
    } catch (e) {
      debugPrint("Error de actualización: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GCT - RASTREO EN VIVO"),
        backgroundColor: Colors.blue[900],
      ),
      body: Stack(
        children: [
          // NIVEL 1: EL MAPA
          FlutterMap(
            mapController: _mapController, 
            options: MapOptions(
              initialCenter: LatLng(currentLat, currentLng),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gct.mobile',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(currentLat, currentLng),
                    width: 80,
                    height: 80,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 45),
                  ),
                ],
              ),
            ],
          ),
          // NIVEL 2: LA TARJETA FLOTANTE (DASHBOARD)
          // NIVEL 2: LA TARJETA FLOTANTE RESPONSIVA
Positioned(
  top: 10,
  left: 10,
  right: 10,
  child: SafeArea( // Asegura que no se tape con el notch del celular
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Si la pantalla es angosta (celular), usamos menos padding y fuentes pequeñas
        bool esCelular = constraints.maxWidth < 600;
        
        return Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          color: Colors.white.withOpacity(0.92),
          child: Padding(
            padding: EdgeInsets.all(esCelular ? 10.0 : 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      sensorName, 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: esCelular ? 14 : 18
                      )
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green, 
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Text(
                        status.toUpperCase(), 
                        style: const TextStyle(color: Colors.white, fontSize: 9)
                      ),
                    ),
                  ],
                ),
                const Divider(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoItem("Velocidad", "$velocidad km/h", Colors.blue, esCelular),
                    _buildInfoItem("Latitud", currentLat.toStringAsFixed(4), Colors.black87, esCelular),
                    _buildInfoItem("Longitud", currentLng.toStringAsFixed(4), Colors.black87, esCelular),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  ),
), // Cierre de SafeArea
    ], // Cierre de Stack children
  ), // Cierre de Stack
); // Cierre de Scaffold
} // <--- ESTA LLAVE CIERRA EL MÉTODO BUILD (Línea 249 aprox)

// --- LA FUNCIÓN DE APOYO VA AQUÍ, TOTALMENTE FUERA DEL BUILD ---
Widget _buildInfoItem(String label, String value, Color color, bool esCelular) {
  return Column(
    children: [
      Text(
        label,
        style: TextStyle(fontSize: esCelular ? 10 : 12, color: Colors.grey[600]),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: esCelular ? 13 : 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );
}

} // <--- ESTA ES LA LLAVE FINAL QUE CIERRA LA CLASE _DashboardPageState



























