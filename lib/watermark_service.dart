import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

enum TipoEvidencia {
  fallaPreoperacional,
  guiaCargue,
  novedadRuta,
  cierreViaje,
  estandar
}

class WatermarkService {
  static Future<File> aplicarMarcaDeAgua({
    required File imagenOriginal,
    String? placa,
    String? textoPlaca,
    String? gps,
    String? textoGPS,
    String? fechaHora,
    dynamic tripId, // Permite int o String sin fallar
    String? numeroGuia,
    TipoEvidencia tipo = TipoEvidencia.estandar,
  }) async {
    final String placaFinal = (placa ?? textoPlaca ?? 'N/A').trim().toUpperCase();
    final String gpsFinal = (gps ?? textoGPS ?? 'GPS No disp.').trim();
    
    // Convertir tripId de forma segura
    String tripIdFinal = 'N/A';
    if (tripId != null && tripId.toString().trim().isNotEmpty && tripId.toString() != 'null') {
      tripIdFinal = tripId.toString().trim();
    }

    // Cargar los bytes del logo en el hilo principal
    Uint8List? logoBytes;
    try {
      final logoData = await rootBundle.load('assets/logo_gct.png');
      logoBytes = logoData.buffer.asUint8List();
    } catch (e) {
      debugPrint("⚠️ No se pudo cargar assets/logo_gct.png: $e");
    }

    return compute(_procesarImagenBytes, {
      'path': imagenOriginal.path,
      'placa': placaFinal,
      'gps': gpsFinal,
      'tripId': tripIdFinal,
      'numeroGuia': numeroGuia,
      'tipo': tipo.index,
      'logoBytes': logoBytes,
    });
  }

  static Future<File> _procesarImagenBytes(Map<String, dynamic> params) async {
    final String path = params['path'];
    final String placa = params['placa'];
    final String gps = params['gps'];
    final String tripId = params['tripId'];
    final String? numeroGuia = params['numeroGuia'];
    final TipoEvidencia tipo = TipoEvidencia.values[params['tipo']];
    final Uint8List? logoBytes = params['logoBytes'];

    final bytes = await File(path).readAsBytes();
    img.Image? foto = img.decodeImage(bytes);
    if (foto == null) return File(path);

    foto = img.bakeOrientation(foto);

    // 1. LOGO TRANSPARENTE (Top-Right)
    if (logoBytes != null) {
      try {
        img.Image? logo = img.decodeImage(logoBytes);
        if (logo != null) {
          int logoWidth = (foto.width * 0.20).round();
          logo = img.copyResize(logo, width: logoWidth);
          
          int posX = foto.width - logo.width - 25;
          int posY = 25;
          
          img.compositeImage(foto, logo, dstX: posX, dstY: posY);
        }
      } catch (e) {
        debugPrint("Error al estampar logo: $e");
      }
    }

    // 2. BANNER CONTEXTUAL (Top-Left)
    if (tipo == TipoEvidencia.fallaPreoperacional) {
      _dibujarBannerFalla(foto, tripId);
    } else if (tipo == TipoEvidencia.novedadRuta) {
      _dibujarBannerAlerta(foto, "NOVEDAD EN RUTA | TRIP: $tripId");
    } else if (tipo == TipoEvidencia.guiaCargue) {
      _dibujarBannerInfo(foto, "GUIA DE CARGUE | TRIP: $tripId");
    }

    // 3. TEXTO MARCA DE AGUA FLOTANTE EN 2 LÍNEAS (Bottom-Left)
    String fechaActual = DateTime.now().toString().substring(0, 19);
    String tipoEtiqueta = _obtenerEtiquetaTipo(tipo);
    
    // Línea 1: Contexto de Negocio
    String linea1 = "$tipoEtiqueta | PLACA: $placa | TRIP ID: $tripId";
    if (numeroGuia != null && numeroGuia.isNotEmpty) {
      linea1 += " | GUIA: $numeroGuia";
    }

    // Línea 2: Trazabilidad Técnica (Fecha + Coordenadas GPS siempre visibles)
    String linea2 = "FECHA: $fechaActual | GPS: $gps";

    int marginX = 20;
    int marginYLinea1 = foto.height - 75;
    int marginYLinea2 = foto.height - 40;

    // --- RENDER LÍNEA 1 ---
    // Sombra Negra
    img.drawString(foto, linea1, font: img.arial24, x: marginX + 2, y: marginYLinea1 + 2, color: img.ColorRgb8(0, 0, 0));
    // Texto Blanco
    img.drawString(foto, linea1, font: img.arial24, x: marginX, y: marginYLinea1, color: img.ColorRgb8(255, 255, 255));

    // --- RENDER LÍNEA 2 (GPS / Fecha) ---
    // Sombra Negra
    img.drawString(foto, linea2, font: img.arial24, x: marginX + 2, y: marginYLinea2 + 2, color: img.ColorRgb8(0, 0, 0));
    // Texto Amarillo
    img.drawString(foto, linea2, font: img.arial24, x: marginX, y: marginYLinea2, color: img.ColorRgb8(255, 235, 59));

    // Guardar fotografía final
    final File archivoResultado = File(path);
    await archivoResultado.writeAsBytes(img.encodeJpg(foto, quality: 88));
    return archivoResultado;
  }

  static String _obtenerEtiquetaTipo(TipoEvidencia tipo) {
    switch (tipo) {
      case TipoEvidencia.fallaPreoperacional:
        return "INSPECCION DIGITAL";
      case TipoEvidencia.guiaCargue:
        return "GUIA DE CARGUE";
      case TipoEvidencia.novedadRuta:
        return "NOVEDAD EN RUTA";
      case TipoEvidencia.cierreViaje:
        return "CIERRE DE VIAJE";
      default:
        return "EVIDENCIA DIGITAL";
    }
  }

  // --- BANNERS FLOTANTES SUPERIORES ---
  static void _dibujarBannerFalla(img.Image foto, String tripId) {
    int anchoBanner = (foto.width * 0.55).round();
    int altoBanner = 75;

    img.fillRect(
      foto,
      x1: 20,
      y1: 20,
      x2: 20 + anchoBanner,
      y2: 20 + altoBanner,
      color: img.ColorRgba8(255, 193, 7, 210),
    );

    img.drawString(
      foto,
      "FALLA PREOPERACIONAL",
      font: img.arial24,
      x: 35,
      y: 30,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.drawString(
      foto,
      "TRIP ID: $tripId",
      font: img.arial24,
      x: 35,
      y: 55,
      color: img.ColorRgb8(0, 0, 0),
    );
  }

  static void _dibujarBannerAlerta(img.Image foto, String texto) {
    img.fillRect(
      foto,
      x1: 20,
      y1: 20,
      x2: 550,
      y2: 80,
      color: img.ColorRgba8(220, 53, 69, 210),
    );
    img.drawString(
      foto,
      texto,
      font: img.arial24,
      x: 35,
      y: 40,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  static void _dibujarBannerInfo(img.Image foto, String texto) {
    img.fillRect(
      foto,
      x1: 20,
      y1: 20,
      x2: 550,
      y2: 80,
      color: img.ColorRgba8(13, 110, 253, 210),
    );
    img.drawString(
      foto,
      texto,
      font: img.arial24,
      x: 35,
      y: 40,
      color: img.ColorRgb8(255, 255, 255),
    );
  }
}