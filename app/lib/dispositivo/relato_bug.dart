import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

/// Para onde vai o relato de bug.
const emailRelatoBug = 'suporte@tratofeitolabs.com.br';

/// Versão do app que vai no relato. Deve acompanhar o `version:` do `pubspec.yaml` (um teste
/// confere). Uma compilação pode trocar com `--dart-define=TRATO_VERSAO=0.1.50+51`.
const versaoDoApp = String.fromEnvironment('TRATO_VERSAO', defaultValue: '0.1.37+38');

/// "0.1.37+38" vira ("0.1.37", "38"). Sem o "+", o build fica vazio.
(String, String) separarVersao(String v) {
  final i = v.indexOf('+');
  return i < 0 ? (v, '') : (v.substring(0, i), v.substring(i + 1));
}

/// O que o relato leva do aparelho. Nada de dado pessoal (CPF, telefone, e-mail, token).
typedef DadosDoRelato = ({String versao, String sistema, String tela, DateTime quando});

String _dois(int n) => n.toString().padLeft(2, '0');

String _quandoTexto(DateTime q) {
  final d = q.toLocal();
  final fuso = d.timeZoneOffset;
  final sinal = fuso.isNegative ? '-' : '+';
  final h = fuso.inHours.abs();
  final m = fuso.inMinutes.abs() % 60;
  return '${_dois(d.day)}/${_dois(d.month)}/${d.year} ${_dois(d.hour)}:${_dois(d.minute)} '
      '(UTC$sinal${_dois(h)}:${_dois(m)})';
}

/// Monta o assunto e o corpo do e-mail de relato de bug. Os três campos em branco ficam para
/// a pessoa preencher no app de e-mail.
({String assunto, String corpo}) montarRelatoBug(DadosDoRelato d) => (
      assunto: 'Relato de bug (app Trato)',
      corpo: [
        'O que aconteceu:',
        '',
        '',
        'O que eu esperava:',
        '',
        '',
        'Passos para repetir:',
        '1. ',
        '',
        '',
        '--- Dados do app (pode apagar o que não quiser enviar) ---',
        'Versão do app: ${d.versao}',
        'Aparelho: ${d.sistema}',
        'Tela: ${d.tela}',
        'Data e hora: ${_quandoTexto(d.quando)}',
      ].join('\n'),
    );

/// "Android 14", "iOS 17.2" ou o que o sistema informar. O modelo do aparelho não entra: ler
/// o modelo pede um pacote a mais.
String sistemaDoAparelho() {
  try {
    final nome = switch (Platform.operatingSystem) {
      'android' => 'Android',
      'ios' => 'iOS',
      final outro => outro,
    };
    return '$nome (${Platform.operatingSystemVersion})';
  } on Object {
    return 'não informado';
  }
}

/// `mailto:` com assunto e corpo (espaço como %20: o "+" de `queryParameters` aparece literal em
/// vários apps de e-mail).
Uri uriDoRelato(String destinatario, String assunto, String corpo) => Uri.parse(
    'mailto:$destinatario?subject=${Uri.encodeComponent(assunto)}&body=${Uri.encodeComponent(corpo)}');

/// Abre o app de e-mail com o relato. Troque em testes. `false` = nenhum app abriu.
typedef AbrirEmailComCorpo = Future<bool> Function(Uri mailto);

AbrirEmailComCorpo abrirEmailDoRelato = _abrirReal;

Future<bool> _abrirReal(Uri mailto) async {
  try {
    return await launchUrl(mailto, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}
