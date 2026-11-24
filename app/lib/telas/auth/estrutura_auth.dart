import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Esqueleto das telas de entrada: barra com voltar (e "Passo X de 2"), conteúdo que rola
/// e um rodapé fixo (botão ou link) embaixo.
class EstruturaAuth extends StatelessWidget {
  const EstruturaAuth({
    super.key,
    required this.children,
    this.rodape,
    this.tituloBarra,
    this.comVoltar = true,
    this.scrollController,
    this.rodapeFixoComTeclado = true,
  });

  final List<Widget> children;
  final Widget? rodape;
  final String? tituloBarra;
  final bool comVoltar;
  final ScrollController? scrollController;

  /// Com o teclado aberto, `false` leva o rodapé para dentro da rolagem (no fim): serve quando o
  /// rodapé é só um link e o botão principal está no conteúdo; assim ele não rouba espaço do botão.
  final bool rodapeFixoComTeclado;

  @override
  Widget build(BuildContext context) {
    final rodapeNoScroll =
        rodape != null && !rodapeFixoComTeclado && MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: comVoltar,
      child: Scaffold(
        appBar: comVoltar || tituloBarra != null
            ? AppBar(title: tituloBarra == null ? null : Text(tituloBarra!))
            : null,
        body: SafeArea(
          child: ConteudoResponsivo(
            margem: EspacosTrato.margemOnboarding,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...children,
                        if (rodapeNoScroll) ...[
                          const SizedBox(height: EspacosTrato.x4),
                          Center(child: rodape!),
                        ],
                      ],
                    ),
                  ),
                ),
                if (rodape != null && !rodapeNoScroll) ...[
                  rodape!,
                  const SizedBox(height: EspacosTrato.x4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Erro vindo do serviço de login (senha errada, sem internet...). Some quando [mensagem] é nula.
class MensagemErroAuth extends StatelessWidget {
  const MensagemErroAuth(this.mensagem, {super.key});

  final String? mensagem;

  @override
  Widget build(BuildContext context) {
    if (mensagem == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
      // Leitor de tela anuncia o erro assim que ele aparece.
      child: Semantics(
        liveRegion: true,
        child: Text(
          mensagem!,
          style: TipografiaTrato.corpo.copyWith(color: context.cores.vermelhoTexto),
        ),
      ),
    );
  }
}
