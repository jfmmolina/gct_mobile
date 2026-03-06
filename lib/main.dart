import 'package:webview_flutter/webview_flutter.dart';
import 'novedades_page.dart';
import 'dart:io';
import 'firebase_options.dart'; 
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 
import 'validacion_page.dart';
import 'setup_page.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:postgres/postgres.dart'; 
import 'finalizar_page.dart';
import 'package:firebase_storage/firebase_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); 
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);            
  
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,     
    home: SetupPage(),                      
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

  Future<void> _conectarConServidor() async {
    setState(() {
      _mensajeServidor = "Buscando viaje asignado...";
    });

    try {
      // 1. CONEXIÓN BD
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // 2. BUSQUEDA CON TRIP_ID
      int cedulaIngresada = int.tryParse(_cedulaController.text) ?? 0;
      
      final result = await conn.execute(
        r'SELECT trip_id, driver_cc, driver_name, driver_cellphone, truck_plate, trailer_plate, route_alias, user_preferred_name, customer_name, truck_odometer, mapa_iframe_url FROM flutter_schema.active_trips WHERE driver_cc = $1 LIMIT 1',
          parameters: [cedulaIngresada],
      );

      await conn.close();

      // 3. PROCESAR RESULTADO
      if (result.isNotEmpty) {
        final fila = result[0];
        
        Map<String, dynamic> datosReales = {
          'trip_id': fila[0],                   // 0: trip_id (IMPORTANTE)
          'cedula': fila[1]?.toString() ?? "",  // 1: driver_cc
          'nombre': fila[2]?.toString() ?? "Conductor",
          'celular': fila[3]?.toString() ?? "",
          'placa_cabezote': fila[4]?.toString() ?? "",
          'placa_trailer': fila[5]?.toString() ?? "N/A",
          'ruta_nombre': fila[6]?.toString() ?? "No asignada",
          'empresa_transportadora': fila[7]?.toString() ?? "Transportes GCT",
          'cliente_nombre': fila[8]?.toString() ?? "Cliente", 
          'odometro_bd': fila[9]?.toString() ?? "0",
          'mapa_url': fila[10]?.toString() ?? "",        
        };

        setState(() {
          _mensajeServidor = "¡Viaje encontrado! Hola, ${datosReales['nombre']}";
        });

        // 4. NAVEGAR
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: datosReales))
          );
        });

      } else {
        setState(() {
          _mensajeServidor = "⚠️ No hay viajes activos para esta cédula.";
        });
      }

    } catch (e) {
      setState(() {
        _mensajeServidor = "❌ Error de conexión: $e";
      });
      debugPrint("Error de Login: $e");
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
              child: const Text("INICIAR SESIÓN"),
            ),
          ],
        ),
      ),
    );
  }
}

// --- DASHBOARD CON MAPA REAL GCT ---
class DashboardPage extends StatefulWidget {
  final double lat;
  final double lng;
  final Map<String, dynamic> datosViaje; 

  const DashboardPage({super.key, required this.lat, required this.lng, required this.datosViaje});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late double currentLat;
  late double currentLng;
  Timer? _timer;
  
  // Controlador para el mapa de ruta real
  late final WebViewController _webController;

  String sensorName = "Cargando...";
  int velocidad = 0;
  String status = "online";

  @override
  void initState() {
    super.initState();
    currentLat = widget.lat;
    currentLng = widget.lng;

    // Configuración del mapa real usando la URL de la base de datos
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(widget.datosViaje['mapa_url'] ?? "https://google.com"));

    _timer = Timer.periodic(const Duration(seconds: 5), (timer) => _actualizarUbicacion());
  }

  Future<void> _actualizarUbicacion() async {
    try {
      final respuesta = await http.get(Uri.parse('https://terminals-sight-miscellaneous-pointing.trycloudflare.com/api/test?t=${DateTime.now().millisecondsSinceEpoch}'));
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

  Widget _buildInfoItem(String label, String value, Color color, bool esCelular) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: esCelular ? 10 : 12, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontSize: esCelular ? 13 : 16, fontWeight: FontWeight.bold, color: color))
      ]
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GCT - RASTREO EN VIVO"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
              ),
              icon: const Icon(Icons.flag, size: 18),
              label: const Text("FINALIZAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => FinalizarViajePage(
                    currentLat: currentLat, 
                    currentLng: currentLng,
                    tripId: widget.datosViaje['trip_id'], 
                    placa: widget.datosViaje['placa_cabezote'], 
                  ))
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NovedadesPage(
                datosViaje: widget.datosViaje,
                lat: currentLat,
                lng: currentLng,
              ),
            ),
          );
        },
        backgroundColor: Colors.red,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
        label: const Text("REPORTAR NOVEDAD", style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          // MAPA REAL (WebView)
          WebViewWidget(controller: _webController),

          // TARJETA DE INFORMACIÓN (Encima del mapa)
          Positioned(
            top: 10, left: 10, right: 10,
            child: SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
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
                            Text(sensorName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: esCelular ? 14 : 18)), 
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
                              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)), 
                              child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 9))
                            )
                          ]
                        ),
                        const Divider(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround, 
                          children: [
                            _buildInfoItem("Velocidad", "$velocidad km/h", Colors.blue, esCelular), 
                            _buildInfoItem("Latitud", currentLat.toStringAsFixed(4), Colors.black87, esCelular), 
                            _buildInfoItem("Longitud", currentLng.toStringAsFixed(4), Colors.black87, esCelular)
                          ]
                        ),
                      ]
                    )
                  ),
                );
              }),
            ),
          ), 
        ],
      ),
    );
  }
}