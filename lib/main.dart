import 'firebase_options.dart'; // 👈 Agrega esta línea al inicio 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // <--- IMPORTANTE PARA EL MOVIMIENTO
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'validacion_page.dart';
import 'setup_page.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:postgres/postgres.dart'; // 👈 NUEVO: Para conectarnos a Contabo en el Login
import 'finalizar_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Prepara el motor de Flutter
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform,);            // Conecta con tu google-services.json
  
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,      // Quita la etiqueta roja de "debug"
    home: SetupPage(),                      // Arranca en la página de Setup
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
    setState(() {
      _mensajeServidor = "Buscando viaje asignado...";
    });

    try {
      // 1. NOS CONECTAMOS A CONTABO
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // 2. BUSCAMOS EN LA TABLA active_trips USANDO LA CÉDULA (driver_id)
      // Nota: Convertimos la cédula ingresada a número porque en la BD es un integer
      // 2. BUSCAMOS EN LA TABLA active_trips USANDO LA CÉDULA (driver_cc)
      int cedulaIngresada = int.tryParse(_cedulaController.text) ?? 0;
      
      final result = await conn.execute(
        r'SELECT driver_cc, driver_name, driver_cellphone, truck_plate, trailer_plate, route_alias, user_preferred_name, customer_name, truck_odometer FROM flutter_schema.active_trips WHERE driver_cc = $1 LIMIT 1',
        parameters: [cedulaIngresada], // ⚠️ Nota: Si driver_cc en tu BD es texto (VARCHAR), cámbialo a: [_cedulaController.text]
      );

      await conn.close();

      // 3. SI ENCONTRAMOS UN VIAJE, EMPAQUETAMOS LOS DATOS
      if (result.isNotEmpty) {
        final fila = result[0];
        
        // 🚀 CORRECCIÓN: Los índices actualizados del 0 al 8
        Map<String, dynamic> datosReales = {
          'cedula': fila[0]?.toString() ?? "",              // 0: driver_cc
          'nombre': fila[1]?.toString() ?? "Conductor",     // 1: driver_name
          'celular': fila[2]?.toString() ?? "",             // 2: driver_cellphone
          'placa_cabezote': fila[3]?.toString() ?? "",      // 3: truck_plate
          'placa_trailer': fila[4]?.toString() ?? "N/A",    // 4: trailer_plate
          'ruta_nombre': fila[5]?.toString() ?? "No asignada", // 5: route_alias
          'empresa_transportadora': fila[6]?.toString() ?? "Transportes GCT", // 6: user_preferred_name (NUEVO)
          'cliente_nombre': fila[7]?.toString() ?? "Cliente",                 // 7: customer_name 
          'odometro_bd': fila[8]?.toString() ?? "0",        // 8: truck_odometer 
        };

        setState(() {
          _mensajeServidor = "¡Viaje encontrado! Hola, ${datosReales['nombre']}";
        });

        // 4. VIAJAMOS A LA PANTALLA DE VALIDACIÓN
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: datosReales))
          );
        });

      } else {
        // SI LA CÉDULA NO TIENE VIAJES ACTIVOS
        setState(() {
          _mensajeServidor = "⚠️ No hay viajes activos para esta cédula.";
        });
      }

    } catch (e) {
      setState(() {
        _mensajeServidor = "❌ Error de conexión con la base de datos.";
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
        
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
              icon: const Icon(Icons.flag, size: 18),
              label: const Text("FINALIZAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: () {
                // Navegamos a la pantalla de cierre
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FinalizarViajePage(
                      currentLat: currentLat,
                      currentLng: currentLng,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarAlertaNovedad,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
        label: const Text("REPORTAR NOVEDAD", style: TextStyle(color: Colors.white)),
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
// --- VARIABLE PARA EL COMENTARIO ---
  final TextEditingController _comentarioController = TextEditingController();
  
  // --- FUNCIÓN 1: EL MENÚ EMERGENTE DE NOVEDADES (CON CAJA DE TEXTO) ---
  // --- FUNCIÓN 1: EL MENÚ EMERGENTE DE NOVEDADES (ACTUALIZADO) ---
  void _mostrarAlertaNovedad() {
    _comentarioController.clear(); 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 50),
              const SizedBox(height: 10),
              const Text(
                "Usted se ha detenido por más de 5 minutos en un lugar no autorizado",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              
              TextField(
                controller: _comentarioController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: "Escriba un comentario (Opcional)",
                  prefixIcon: const Icon(Icons.edit_note, color: Colors.blue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLength: 100,
              ),
              
              const SizedBox(height: 10),
              const Text("Seleccione el motivo principal:", style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 15),
              
              Wrap(
                spacing: 20, 
                runSpacing: 15, 
                alignment: WrapAlignment.center,
                children: [
                  _botonNovedad(Icons.traffic, "Tráfico", Colors.orange),
                  _botonNovedad(Icons.remove_road, "Vía Bloqueada", Colors.red),
                  _botonNovedad(Icons.car_repair, "Falla Mecánica", Colors.purple), 
                  _botonNovedad(Icons.coffee, "Descanso", Colors.blue),
                  _botonNovedad(Icons.restaurant, "Almuerzo", Colors.green),
                  _botonNovedad(Icons.hotel, "Pernoctar", Colors.indigo),
                ],
              ),
            ],
          ),
        );
      }
    );
  }

  // --- FUNCIÓN 2: DISEÑO DE LOS BOTONES GRANDES ---
  Widget _botonNovedad(IconData icono, String titulo, Color color) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Cierra el menú
        _enviarNovedad(titulo); // Envía a Contabo
      },
      borderRadius: BorderRadius.circular(15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 35, 
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icono, color: color, size: 35),
          ),
          const SizedBox(height: 8),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  // --- FUNCIÓN 3: ENVIAR A CONTABO (TABLA INTERMEDIA) ---
  Future<void> _enviarNovedad(String motivo) async {
    String comentario = _comentarioController.text;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("⏳ Registrando $motivo..."), backgroundColor: Colors.orange),
    );

    try {
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com', database: 'app_core', username: 'flutter', password: '5cxkdu6lo', port: 5432,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      // INSERTAMOS EN LA TABLA NUEVA (novedades_viaje)
      await conn.execute(
        r'''
        INSERT INTO flutter_schema.novedades_viaje 
        (placa_cabezote, motivo, comentario, latitud, longitud, fecha_reporte) 
        VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
        ''',
        parameters: [
          "TTR578", // ⚠️ Recuerda cambiar esto por la variable real luego
          motivo, 
          comentario, 
          currentLat.toString(), 
          currentLng.toString()
        ],
      );

      await conn.close();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Novedad registrada en el historial"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error al subir novedad: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

} // <--- ESTA ES LA LLAVE FINAL QUE CIERRA LA CLASE _DashboardPageState


