import 'package:url_launcher/url_launcher.dart';

/// Abre um endereço da web no navegador. Troque em testes. `false` = não abriu.
typedef AbrirLink = Future<bool> Function(Uri endereco);

AbrirLink abrirLink = _abrirReal;

Future<bool> _abrirReal(Uri endereco) async {
  try {
    return await launchUrl(endereco, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}
