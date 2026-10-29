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
  });

  final List<Widget> children;
  final Widget? rodape;
  final String? tituloBarra;
  final bool comVoltar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: comVoltar || tituloBarra != null
          ? AppBar(title: tituloBarra == null ? null : Text(tituloBarra!))
          : null,
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
              if (rodape != null) ...[
                rodape!,
                const SizedBox(height: EspacosTrato.x4),
              ],
            ],
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
      child: Text(
        mensagem!,
        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.vermelhoTexto),
      ),
    );
  }
}
