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
import 'registrar_guia_page.dart';

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
    setState(() => _mensajeServidor = "Buscando viaje asignado...");

    try {
      final conn = await Connection.open(
        Endpoint(
          host: 'gctsatelital.com', 
          database: 'app_core', 
          username: 'flutter', 
          password: '5cxkdu6lo', 
          port: 5432
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 15)),
      );

      String cedulaIngresada = _cedulaController.text.trim();
      
      final result = await conn.execute(
        r'''SELECT trip_id, driver_cc, driver_name, driver_cellphone, truck_plate, trailer_plate, 
            route_alias, user_preferred_name, customer_name, truck_odometer, mapa_iframe_url, 
            effective_hours, unloading_schedule, loading_schedule, fase_viaje, preoperacional_data,
            documento_cliente, manifiesto_rndc, url_pdf_manifiesto, 
            current_state, permitir_cierre_manual
            FROM flutter_schema.active_trips 
            WHERE driver_cc = $1 
              AND (current_state IS NULL OR current_state != 'FINALIZADO')
            ORDER BY trip_id DESC 
            LIMIT 1''',
        parameters: [cedulaIngresada],
      );

      await conn.close();

      if (result.isNotEmpty) {
        final fila = result[0];
        
        Map<String, dynamic> datosReales = {
          'trip_id': fila[0],
          'cedula': fila[1]?.toString() ?? "",
          'nombre': fila[2]?.toString() ?? "Conductor",
          'celular': fila[3]?.toString() ?? "",
          'placa_cabezote': fila[4]?.toString() ?? "",
          'placa_trailer': fila[5]?.toString() ?? "N/A",
          'ruta_nombre': fila[6]?.toString() ?? "No asignada",
          'empresa_transportadora': fila[7]?.toString() ?? "Transportes GCT",
          'cliente_nombre': fila[8]?.toString() ?? "Cliente", 
          'odometro_bd': fila[9]?.toString() ?? "0",
          'mapa_url': fila[10]?.toString() ?? "",
          'effective_hours': fila[11] ?? 0, 
          'fecha_descargue': fila[12] is DateTime ? fila[12] : DateTime.now().add(const Duration(hours: 24)), 
          'fecha_cargue': fila[13] is DateTime ? fila[13] : DateTime.now(),
          'fase_viaje': fila[14]?.toString() ?? "ASIGNADO",
          'preoperacional_json': fila[15]?.toString() ?? "{}",
          'documento_cliente': fila[16]?.toString() ?? "",
          'manifiesto_rndc': fila[17]?.toString() ?? "",
          'url_pdf_manifiesto': fila[18]?.toString() ?? "",
          'estado_servidor': fila[19]?.toString().trim().toUpperCase() ?? "",
          'permite_cierre': fila[20]?.toString().trim().toUpperCase() == "TRUE",
        };

        setState(() => _mensajeServidor = "¡Viaje encontrado!");

        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ValidacionViajePage(datosServidor: datosReales)));
        });
      } else {
        setState(() => _mensajeServidor = "⚠️ Sin viajes activos.");
      }
    } catch (e) {
      setState(() => _mensajeServidor = "❌ Error de conexión BD.");
      debugPrint("DETALLE ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.wifi_tethering, size: 80, color: Colors.blue),
          const Text("GCT MOBILE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          TextField(controller: _cedulaController, decoration: const InputDecoration(labelText: 'Cédula', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Text(_mensajeServidor, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: _conectarConServidor, child: const Text("INICIAR SESIÓN")),
        ]),
      ),
    );
  }
}

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
  late final WebViewController _webController;

  String sensorName = "Sincronizando...";
  int velocidad = 0;
  String status = "online";

  double porcentajeTiempo = 0.0;
  String tiempoRestanteTexto = "Calculando tiempo...";
  bool permitirFinalizar = false;
  Color colorBarra = Colors.green;

  @override
  void initState() {
    super.initState();
    currentLat = widget.lat;
    currentLng = widget.lng;

    // --- MEJORA 1: LIMPIEZA DEL ENLACE DEL MAPA ---
    String urlMapa = widget.datosViaje['mapa_url']?.toString().trim() ?? "";
    
    // Si viene un iframe completo, extraemos solo el link
    if (urlMapa.contains('src="')) {
      final startIndex = urlMapa.indexOf('src="') + 5;
      final endIndex = urlMapa.indexOf('"', startIndex);
      if (startIndex > 4 && endIndex > startIndex) {
        urlMapa = urlMapa.substring(startIndex, endIndex);
      }
    }

    // Si la URL queda vacía, ponemos un mapa de rescate
    if (urlMapa.isEmpty || !urlMapa.startsWith("http")) {
      urlMapa = "https://www.google.com/maps";
    }

    // --- AQUÍ INSERTAMOS EL DISFRAZ Y EL ESPÍA ---
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white) 
      //..setUserAgent("Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36") // 👈 Disfraz de Chrome
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint("🌐 JS DE LA WEB DICE: ${message.message}");
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            // 👈 Espía que imprimirá los errores en la consola de VS Code
            debugPrint("🚨 ERROR DEL MAPA: ${error.description} | Código: ${error.errorCode}");
          },
        ),
      )
      ..loadRequest(Uri.parse(urlMapa));

    _procesarSeguridad();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _actualizarUbicacion();
      _procesarSeguridad();
    });
  }

  void _procesarSeguridad() {
    final ahora = DateTime.now();
    final inicio = widget.datosViaje['fecha_cargue'] as DateTime;
    final fin = widget.datosViaje['fecha_descargue'] as DateTime;

    final totalViaje = fin.difference(inicio).inSeconds;
    final tiempoPasado = ahora.difference(inicio).inSeconds;
    
    if (totalViaje > 0) {
      porcentajeTiempo = (tiempoPasado / totalViaje).clamp(0.0, 1.0);
    }

    final diff = fin.difference(ahora);
    
    // --- AQUÍ ESTÁ TU LÓGICA MAESTRA ---
    String estadoActu = widget.datosViaje['estado_servidor'] ?? "";
    bool permisoManual = widget.datosViaje['permite_cierre'] ?? false;

    // Se libera si: Tiempo agotado O dice "DESCARGA" O tú pusiste TRUE
    bool debeLiberar = diff.isNegative || 
                       estadoActu.contains("DESCARGA") || 
                       permisoManual == true;

    if (debeLiberar) {
      tiempoRestanteTexto = permisoManual ? "CIERRE AUTORIZADO" : "LLEGADA A DESTINO";
      colorBarra = Colors.red;
      permitirFinalizar = true; 
    } else {
      int h = diff.inHours;
      int m = diff.inMinutes % 60;
      tiempoRestanteTexto = "Quedan: ${h}h ${m}m";
      colorBarra = Colors.green;
      permitirFinalizar = false; 
    }

    if (mounted) setState(() {});
  }

  Future<void> _actualizarUbicacion() async {
    try {
      final resp = await http.get(Uri.parse('https://terminals-sight-miscellaneous-pointing.trycloudflare.com/api/test?t=${DateTime.now().millisecondsSinceEpoch}'));
      if (resp.statusCode == 200) {
        final d = json.decode(resp.body);
        if (mounted) {
          setState(() {
          currentLat = d['lat'];
          currentLng = d['lng'];
          sensorName = d['sensor'];
          velocidad = d['velocidad'];
          status = d['status'];
        });
        }
      }
    } catch (e) { debugPrint("GPS Error: $e"); }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GCT RASTREO"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              // --- MEJORA 2: ESTILO DEL BOTÓN BLOQUEADO ---
              style: ElevatedButton.styleFrom(
                backgroundColor: permitirFinalizar ? Colors.redAccent : Colors.grey[400],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.black38, // Fondo oscuro cuando está bloqueado
                disabledForegroundColor: Colors.white,   // Letra blanca cuando está bloqueado
                padding: const EdgeInsets.symmetric(horizontal: 10)
              ),
              icon: Icon(permitirFinalizar ? Icons.flag : Icons.lock_clock, size: 16),
              label: Text(permitirFinalizar ? "FINALIZAR" : "BLOQUEADO", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              onPressed: permitirFinalizar ? () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => FinalizarViajePage(
                  currentLat: currentLat, currentLng: currentLng,
                  tripId: widget.datosViaje['trip_id'], placa: widget.datosViaje['placa_cabezote'], 
                )));
              } : null,
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. BOTÓN NUEVO: Registrar Guía en Ruta (Azul)
          FloatingActionButton.small(
            heroTag: "btn_guia",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => RegistrarGuiaPage(datosViaje: widget.datosViaje)),
              );
            },
            backgroundColor: Colors.blue[800],
            foregroundColor: Colors.white,
            child: const Icon(Icons.assignment_turned_in),
          ),
          const SizedBox(height: 12),

          // 2. Botón para Recargar el Mapa (Blanco)
          FloatingActionButton.small(
            heroTag: "btn_reload",
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("🔄 Actualizando ruta..."), duration: Duration(seconds: 1))
              );
              _webController.reload(); 
            },
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue[900],
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 12),
          
          // 3. Tu botón rojo de Novedad original (Rojo)
          FloatingActionButton.extended(
            heroTag: "btn_novedad",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NovedadesPage(datosViaje: widget.datosViaje, lat: currentLat, lng: currentLng))),
            backgroundColor: Colors.red,
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
            label: const Text("NOVEDAD", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webController),
          
          // Positioned(
          //   top: 12, left: 15, right: 15,
          //   child: SafeArea(
          //     child: Card(
          //       elevation: 10, 
          //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), 
          //       child: Padding(
          //         padding: const EdgeInsets.all(15.0), 
          //         child: Column(
          //           mainAxisSize: MainAxisSize.min, 
          //           children: [
          //             Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          //               Text("VIGENCIA (${widget.datosViaje['effective_hours']}h)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Colors.blueGrey)),
          //               Text(tiempoRestanteTexto, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: colorBarra)),
          //             ]),
          //             const SizedBox(height: 10),
          //             ClipRRect(
          //               borderRadius: BorderRadius.circular(10),
          //               child: LinearProgressIndicator(
          //                 value: porcentajeTiempo,
          //                 minHeight: 14,
          //                 backgroundColor: Colors.grey[200],
          //                 valueColor: AlwaysStoppedAnimation<Color>(colorBarra),
          //               ),
          //             ),
          //             const SizedBox(height: 15),
          //             Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          //               _stat("Km/h", "$velocidad"),
          //               _stat("ID Viaje", "${widget.datosViaje['trip_id']}"),
          //               _stat("GPS", status.toUpperCase()),
          //             ]),
          //           ]
          //         )
          //       ),
          //     ),
          //   ),
          // ), 
        ],
      ),
    );
  }

  Widget _stat(String l, String v) {
    return Column(children: [
      Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey)),
      Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))
    ]);
  }
}