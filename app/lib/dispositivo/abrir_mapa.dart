import 'package:url_launcher/url_launcher.dart';

/// Abre um ponto no app de mapas do aparelho. Troque em testes.
typedef AbrirMapa = Future<bool> Function(double latitude, double longitude, String rotulo);

AbrirMapa abrirNoMapa = _abrirNoMapaReal;

Future<bool> _abrirNoMapaReal(double latitude, double longitude, String rotulo) async {
  final ponto = '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
  final geo = Uri.parse('geo:$ponto?q=$ponto(${Uri.encodeComponent(rotulo)})');
  final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$ponto');
  try {
    if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return true;
  } catch (_) {}
  try {
    return await launchUrl(web, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
