import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PoliticasPrivacidadWidget extends StatelessWidget {
  final Color textColor;

  const PoliticasPrivacidadWidget({
    super.key, 
    this.textColor = Colors.blueAccent,
  });

  Future<void> _abrirPoliticas(BuildContext context) async {
    final Uri url = Uri.parse('https://gctsatelital.com/legal_info');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el enlace de privacidad')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error abriendo políticas de privacidad: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _abrirPoliticas(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 16, color: textColor),
            const SizedBox(width: 6),
            Flexible( // <-- Esto evita el overflow en fuentes grandes
              child: Text(
                'Políticas de Privacidad y Términos Legales',
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}