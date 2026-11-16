import 'package:url_launcher/url_launcher.dart';

/// Abre o app de e-mail do aparelho com o destinatário e o assunto preenchidos. Troque em testes.
typedef AbrirEmail = Future<bool> Function(String destinatario, String assunto);

AbrirEmail abrirEmail = _abrirEmailReal;

Future<bool> _abrirEmailReal(String destinatario, String assunto) async {
  final uri = Uri(
    scheme: 'mailto',
    path: destinatario,
    queryParameters: {'subject': assunto},
  );
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
