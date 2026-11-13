import 'package:url_launcher/url_launcher.dart';

/// Abre o endereço no app de mapas do aparelho (ou no navegador). Devolve se conseguiu abrir.
/// O endereço só chega ao profissional depois da contratação.
Future<bool> abrirNoMapa(String consulta) async {
  final endereco = consulta.trim();
  if (endereco.isEmpty) return false;
  final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': endereco});
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}
