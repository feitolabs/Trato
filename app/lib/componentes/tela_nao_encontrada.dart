import 'package:flutter/material.dart';

import '../dados/erros.dart';
import '../telas/fluxo/navegacao_casca.dart';
import '../tema/tema.dart';
import 'botoes.dart';

/// Frases da tela "não encontrado", uma por caso.
abstract final class TextosNaoEncontrado {
  static const pedido = 'Este pedido não existe mais ou foi cancelado.';
  static const orcamento = 'Este orçamento não existe mais ou o pedido foi cancelado.';
  static const conversa = 'Esta conversa não está mais disponível.';
  static const recorrencia = 'Este serviço recorrente não existe mais ou foi cancelado.';
  static const perfil = 'Este perfil não está mais disponível.';
  static const aditivo = 'Esta cobrança extra não existe mais ou o pedido foi cancelado.';
}

/// O que o servidor pediu não existe (404) ou não é desta conta (403).
bool ehNaoEncontrado(Object? erro) =>
    erro is ErroTrato &&
    (erro.tipo == TipoErro.naoEncontrado || erro.codigoHttp == 404 || erro.codigoHttp == 403);

/// "Ops, não encontramos isso": o Tratinho confuso, o motivo e a volta.
class TelaNaoEncontrada extends StatelessWidget {
  const TelaNaoEncontrada({super.key, required this.texto, this.aoVoltarInicio});

  static const titulo = 'Ops, não encontramos isso';
  static const mascote = 'assets/mascote/tratinho-confuso.webp';

  /// O que não foi encontrado (ver [TextosNaoEncontrado]).
  final String texto;

  /// Sem valor, volta à primeira tela e abre a aba Início.
  final VoidCallback? aoVoltarInicio;

  void _voltarAoInicio(BuildContext context) {
    Navigator.of(context).popUntil((rota) => rota.isFirst);
    ControladorCasca.selecionarAba(0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final podeVoltar = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, limites) => SingleChildScrollView(
            padding: const EdgeInsets.all(EspacosTrato.x6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (limites.maxHeight - EspacosTrato.x6 * 2).clamp(0.0, double.infinity),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Semantics(
                          image: true,
                          label: 'Tratinho confuso',
                          child: Image.asset(
                            mascote,
                            width: 180,
                            height: 180,
                            excludeFromSemantics: true,
                            errorBuilder: (_, __, ___) => const SizedBox.square(dimension: 180),
                          ),
                        ),
                      ),
                      const SizedBox(height: EspacosTrato.x5),
                      Semantics(
                        header: true,
                        child: Text(
                          titulo,
                          textAlign: TextAlign.center,
                          style: TipografiaTrato.titulo.copyWith(color: c.texto),
                        ),
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                      Text(
                        texto,
                        textAlign: TextAlign.center,
                        style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x6),
                      BotaoPrimario(
                        texto: 'Voltar ao início',
                        aoTocar: aoVoltarInicio ?? () => _voltarAoInicio(context),
                      ),
                      if (podeVoltar) ...[
                        const SizedBox(height: EspacosTrato.x3),
                        BotaoSecundario(
                          texto: 'Voltar',
                          aoTocar: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
