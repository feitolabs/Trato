import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../comuns/textos_dos_termos.dart';
import '../../dispositivo/relato_bug.dart';
import '../../tema/tema.dart';

/// "Relatar bug": abre o app de e-mail com o relato pronto para [emailRelatoBug]. [tela] diz de
/// onde a pessoa tocou ("Central de ajuda", "Configurações"). Sem app de e-mail, mostra o endereço
/// com o botão "Copiar".
Future<void> relatarBug(
  BuildContext context, {
  required String tela,
  DateTime Function()? agora,
}) async {
  final relato = montarRelatoBug((
    versao: versaoDoApp,
    sistema: sistemaDoAparelho(),
    tela: tela,
    quando: (agora ?? DateTime.now)(),
  ));
  final abriu = await abrirEmailDoRelato(
    uriDoRelato(emailRelatoBug, relato.assunto, relato.corpo),
  );
  if (abriu || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogo) => AlertDialog(
      key: const Key('dialogo-relato-bug'),
      title: const Text('Não achamos um app de e-mail'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Escreva para o endereço abaixo, contando o que aconteceu. '
              '$textoAtendimentoHumano'),
          const SizedBox(height: EspacosTrato.x3),
          SelectableText(emailRelatoBug, style: TipografiaTrato.corpoForte),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(),
          child: const Text('Fechar'),
        ),
        FilledButton(
          key: const Key('copiar-email-bug'),
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: emailRelatoBug));
            if (dialogo.mounted) Navigator.of(dialogo).pop();
          },
          child: const Text('Copiar'),
        ),
      ],
    ),
  );
}
