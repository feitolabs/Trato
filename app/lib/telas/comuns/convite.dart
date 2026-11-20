import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Mensagem pronta do convite. Sem Tratinhos nem promessa. O app ainda não tem um link
/// de loja publicado: por isso a mensagem cita só o nome (acrescentar o link aqui quando existir).
const textoConvite = 'Uso o Trato para contratar profissionais verificados, '
    'com pagamento protegido e sem taxa. Conheça o Trato.';

/// Abre o compartilhamento do aparelho com o [texto]. Lança erro se não for possível.
typedef CompartilharTexto = Future<void> Function(String texto);

Future<void> compartilharNoAparelho(String texto) async {
  final r = await SharePlus.instance.share(ShareParams(text: texto));
  if (r.status == ShareResultStatus.unavailable) {
    throw StateError('compartilhamento indisponível');
  }
}

/// Compartilha um arquivo já salvo (ex.: o extrato em PDF). Lança erro se não for possível.
typedef CompartilharArquivo = Future<void> Function(String caminho);

Future<void> compartilharArquivoNoAparelho(String caminho) async {
  final r = await SharePlus.instance.share(ShareParams(files: [XFile(caminho)]));
  if (r.status == ShareResultStatus.unavailable) {
    throw StateError('compartilhamento indisponível');
  }
}

/// Compartilha o convite; se o compartilhamento falhar ou não existir (teste, desktop),
/// copia o texto e avisa com "Convite copiado!".
Future<void> indicarOTrato(
  BuildContext context, {
  CompartilharTexto compartilhar = compartilharNoAparelho,
}) async {
  final mensagens = ScaffoldMessenger.of(context);
  try {
    await compartilhar(textoConvite);
    return;
  } on Object {
    // cai no copiar
  }
  await Clipboard.setData(const ClipboardData(text: textoConvite));
  mensagens
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Convite copiado!')));
}
