import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Animação de pulso suave (shimmer) para elementos de esqueleto.
class PulsoEsqueleto extends StatefulWidget {
  const PulsoEsqueleto({super.key, required this.child});

  final Widget child;

  @override
  State<PulsoEsqueleto> createState() => _PulsoEsqueletoState();
}

class _PulsoEsqueletoState extends State<PulsoEsqueleto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controlador = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final Animation<double> _opacidade = Tween<double>(
    begin: 0.45,
    end: 0.90,
  ).animate(CurvedAnimation(parent: _controlador, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacidade, child: widget.child);
  }
}

/// Bloco base de esqueleto com cantos arredondados e cor dos tokens do Trato.
class BlocoEsqueleto extends StatelessWidget {
  const BlocoEsqueleto({
    super.key,
    this.largura,
    this.altura = 16,
    this.raio = EspacosTrato.raioPequeno,
    this.cor,
  });

  final double? largura;
  final double altura;
  final double raio;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largura,
      height: altura,
      decoration: BoxDecoration(
        color: cor ?? CoresTrato.borda.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(raio),
      ),
    );
  }
}

/// Linha de texto em formato de esqueleto.
class LinhaEsqueleto extends StatelessWidget {
  const LinhaEsqueleto({
    super.key,
    this.fracaoLargura = 1.0,
    this.altura = 14,
  });

  /// Fração da largura disponível (ex.: 0.8 para 80%).
  final double fracaoLargura;
  final double altura;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: fracaoLargura.clamp(0.1, 1.0),
      child: BlocoEsqueleto(altura: altura),
    );
  }
}

/// Cartão em formato de esqueleto imitando um [CartaoTrato].
class CartaoEsqueleto extends StatelessWidget {
  const CartaoEsqueleto({
    super.key,
    this.comIcone = true,
    this.linhas = 2,
    this.altura,
  });

  final bool comIcone;
  final int linhas;
  final double? altura;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
      decoration: BoxDecoration(
        color: CoresTrato.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: CoresTrato.borda, width: EspacosTrato.bordaFina),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comIcone) ...[
            const BlocoEsqueleto(
              largura: 40,
              altura: 40,
              raio: EspacosTrato.raioGrande,
            ),
            const SizedBox(width: EspacosTrato.x3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinhaEsqueleto(fracaoLargura: 0.7, altura: 16),
                for (var i = 1; i < linhas; i++) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  LinhaEsqueleto(
                    fracaoLargura: i == linhas - 1 ? 0.45 : 0.85,
                    altura: 12,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista vertical de cartões de esqueleto.
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({
    super.key,
    this.quantidade = 4,
    this.comIcone = true,
    this.padding = const EdgeInsets.all(EspacosTrato.margemTela),
  });

  final int quantidade;
  final bool comIcone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return PulsoEsqueleto(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: quantidade,
        separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
        itemBuilder: (_, __) => CartaoEsqueleto(comIcone: comIcone),
      ),
    );
  }
}

/// Esqueleto completo de uma página do Trato:
/// Cabeçalho, título principal, lista de cartões e botão no rodapé.
class EsqueletoPagina extends StatelessWidget {
  const EsqueletoPagina({
    super.key,
    this.tituloBarra,
    this.comVoltar = true,
    this.cartoes = 3,
  });

  final String? tituloBarra;
  final bool comVoltar;
  final int cartoes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresTrato.creme,
      appBar: AppBar(
        automaticallyImplyLeading: comVoltar,
        backgroundColor: CoresTrato.creme,
        elevation: 0,
        title: tituloBarra != null
            ? Text(
                tituloBarra!,
                style: TipografiaTrato.corpoPequeno.copyWith(
                  color: CoresTrato.textoSecundario,
                ),
              )
            : const BlocoEsqueleto(largura: 80, altura: 14),
      ),
      body: SafeArea(
        child: PulsoEsqueleto(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.margemTela),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: EspacosTrato.x2),
                const LinhaEsqueleto(fracaoLargura: 0.65, altura: 24),
                const SizedBox(height: EspacosTrato.x2),
                const LinhaEsqueleto(fracaoLargura: 0.90, altura: 14),
                const SizedBox(height: EspacosTrato.x4),
                Expanded(
                  child: ListView.separated(
                    itemCount: cartoes,
                    separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                    itemBuilder: (_, __) => const CartaoEsqueleto(),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x3),
                const BlocoEsqueleto(
                  altura: EspacosTrato.alturaBotao,
                  raio: EspacosTrato.raio,
                ),
                const SizedBox(height: EspacosTrato.x3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

