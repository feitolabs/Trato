import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Roteiro do combinado: perguntas sugeridas no chat do pedido. Texto fixo do app, sempre
/// opcional; tocar numa sugestão só preenche o campo de texto (nunca envia sozinho).

/// Estados em que o serviço ainda não começou: só nesses a faixa aparece.
const _estadosAntesDoServico = {
  'aberto',
  'reservado',
  'orcamento_aceito',
  'pago_e_retido',
  'agendado',
};

bool chatPermiteSugestoes(String? estadoApi) => _estadosAntesDoServico.contains(estadoApi);

String _semAcento(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('â', 'a')
    .replaceAll('ã', 'a')
    .replaceAll('é', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

/// As 4 perguntas do roteiro. A 3ª muda conforme a categoria (Eletricista, Pintura, Câmeras e
/// segurança) e, na versão genérica, conforme quem está falando (cliente ou profissional).
List<String> sugestoesDoChat({required bool souCliente, String? categoria}) {
  final c = _semAcento((categoria ?? '').trim());
  final String terceira;
  if (c.contains('eletric')) {
    terceira = souCliente
        ? 'Preciso deixar o quadro de luz identificado antes da visita?'
        : 'Sabe me dizer se o quadro de luz está identificado?';
  } else if (c.contains('pintura')) {
    terceira = souCliente
        ? 'Preciso mover ou cobrir os móveis antes?'
        : 'Posso mover os móveis ou você prefere deixar cobertos?';
  } else if (c.contains('cameras')) {
    terceira = souCliente
        ? 'Preciso ter internet e tomada perto de onde ficarão as câmeras?'
        : 'Tem internet e tomada perto de onde ficarão as câmeras?';
  } else if (souCliente) {
    terceira = 'Você traz o material ou eu compro?';
  } else {
    terceira = 'O material fica por minha conta ou por sua?';
  }
  return [
    'Como é o acesso ao local? Tem portaria ou hora para entrar?',
    'Tem onde estacionar perto?',
    terceira,
    'Qual horário é melhor para você?',
  ];
}

/// Preferência local do aparelho: "Esconder sugestões" vale por pedido, sem backend.
abstract final class PreferenciaSugestoesChat {
  static String _chave(String pedido) => 'chat_sugestoes_ocultas_$pedido';

  static Future<bool> ocultas(String pedido) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_chave(pedido)) ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> ocultar(String pedido) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_chave(pedido), true);
    } on Object {
      // Sem armazenamento: a faixa só some nesta abertura da tela.
    }
  }
}

class SugestoesChat extends StatelessWidget {
  const SugestoesChat(
      {super.key, required this.sugestoes, required this.aoTocar, required this.aoEsconder});

  final List<String> sugestoes;
  final ValueChanged<String> aoTocar;
  final VoidCallback aoEsconder;

  @override
  Widget build(BuildContext context) {
    if (sugestoes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.margemTela),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sugestões para combinar',
                    style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
                  ),
                ),
                BotaoLink(
                  key: const Key('esconder-sugestoes'),
                  texto: 'Esconder sugestões',
                  aoTocar: aoEsconder,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.margemTela),
            child: Row(
              children: [
                for (final s in sugestoes) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Material(
                      key: ValueKey('sugestao-$s'),
                      color: context.cores.superficie,
                      shape: StadiumBorder(side: BorderSide(color: context.cores.borda)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => aoTocar(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: EspacosTrato.x4,
                            vertical: EspacosTrato.x2,
                          ),
                          child: Text(s, style: TipografiaTrato.corpoPequeno),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
