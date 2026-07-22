import 'dart:io';
import 'dart:typed_data'; // <-- Necesario para Uint8List y ByteData
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class WatermarkService {
  /// Procesa una imagen agregando el logo de GCT y estampando datos clave (Placa, GPS, Fecha)
  static Future<File> aplicarMarcaDeAgua({
    required File imagenOriginal,
    required String textoPlaca,
    required String textoGPS,
    required String fechaHora,
  }) async {
    // 1. Decodificar la imagen tomada por la cámara
    final bytesImagen = await imagenOriginal.readAsBytes();
    img.Image? imagen = img.decodeImage(bytesImagen);

    if (imagen == null) return imagenOriginal; // Resguardo si falla la decodificación

    // 2. Cargar el logo desde assets (Limpio y directo)
    final ByteData logoBytesData = await rootBundle.load('assets/logo_gct.png');
    final Uint8List logoBytes = logoBytesData.buffer.asUint8List();
    img.Image? logo = img.decodeImage(logoBytes);

    // 3. Estampar el Logo en la esquina superior derecha
    if (logo != null) {
      int anchoLogo = (imagen.width * 0.15).toInt();
      img.Image logoRedimensionado = img.copyResize(logo, width: anchoLogo);

      int posX = imagen.width - logoRedimensionado.width - 20;
      int posY = 20;

      img.compositeImage(
        imagen,
        logoRedimensionado,
        dstX: posX,
        dstY: posY,
      );
    }

    // 4. Franja oscura semi-transparente en la parte inferior
    int altoFranja = (imagen.height * 0.12).toInt();
    img.fillRect(
      imagen,
      x1: 0,
      y1: imagen.height - altoFranja,
      x2: imagen.width,
      y2: imagen.height,
      color: img.ColorRgba8(0, 0, 0, 160),
    );

    // 5. Agregar el texto con la Placa, Fecha y GPS
    String overlayTexto = 'PLACA: $textoPlaca\nFECHA: $fechaHora\nGPS: $textoGPS';

    img.drawString(
      imagen,
      overlayTexto,
      font: img.arial24,
      x: 20,
      y: imagen.height - altoFranja + 15,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    // 6. Guardar la imagen procesada
    final tempDir = await getTemporaryDirectory();
    final String tempPath = '${tempDir.path}/evidencia_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final File archivoProcesado = File(tempPath)
      ..writeAsBytesSync(img.encodeJpg(imagen, quality: 85));

    return archivoProcesado;
  }
}