import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Esqueleto das telas de pedido e orçamento: barra (título pequeno e ações), conteúdo que
/// rola e rodapé fixo (superfície, largura total) com os botões.
class EstruturaPedido extends StatelessWidget {
  const EstruturaPedido({
    super.key,
    required this.children,
    this.rodape,
    this.tituloBarra,
    this.acoesBarra,
  });

  final List<Widget> children;
  final Widget? rodape;
  final String? tituloBarra;
  final List<Widget>? acoesBarra;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: tituloBarra == null ? null : Text(tituloBarra!),
        actions: acoesBarra,
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x6),
                child: ConteudoResponsivo(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              ),
            ),
          ),
          if (rodape != null)
            Container(
              width: double.infinity,
              color: CoresTrato.superficie,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  child: ConteudoResponsivo(child: rodape!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Faixa azul-suave com ícone e texto (relógio, aviso). [texto] aceita trechos em negrito.
class AvisoInfo extends StatelessWidget {
  const AvisoInfo({super.key, required this.texto, this.icone = Icons.schedule});

  final InlineSpan texto;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: CoresTrato.azulSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: CoresTrato.azulTexto),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
                children: [texto],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip em pílula que liga/desliga ou escolhe uma opção (petróleo quando marcado).
class ChipOpcao extends StatelessWidget {
  const ChipOpcao({super.key, required this.texto, required this.marcado, required this.aoTocar});

  final String texto;
  final bool marcado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: marcado,
      child: Material(
        color: marcado ? CoresTrato.petroleo : CoresTrato.superficie,
        shape: StadiumBorder(
          side: BorderSide(color: marcado ? CoresTrato.petroleo : CoresTrato.borda),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x5,
              vertical: EspacosTrato.x4,
            ),
            child: Text(
              texto,
              style: TipografiaTrato.corpoForte.copyWith(
                color: marcado ? CoresTrato.creme : CoresTrato.petroleo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Título de seção do formulário ("O que precisa ser feito?").
class RotuloSecao extends StatelessWidget {
  const RotuloSecao(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: TipografiaTrato.corpoForte);
}
