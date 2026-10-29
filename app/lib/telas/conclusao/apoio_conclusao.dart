import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// "R$ 1.234,56" a partir de centavos inteiros. Só formata: o cálculo é do backend.
String formatarReais(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final reais = (abs ~/ 100).toString();
  final cents = (abs % 100).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buffer.write('.');
    buffer.write(reais[i]);
  }
  return '${negativo ? '-' : ''}R\$ $buffer,$cents';
}

/// "31/12/2026".
String formatarData(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

/// Esqueleto das telas 18 a 21: barra opcional, conteúdo que rola e rodapé fixo
/// (superfície, largura total) com os botões.
class EstruturaConclusao extends StatelessWidget {
  const EstruturaConclusao({
    super.key,
    required this.children,
    this.rodape,
    this.tituloBarra,
  });

  final List<Widget> children;
  final Widget? rodape;

  /// Sem título, a tela fica sem barra (como a Avaliação).
  final String? tituloBarra;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: tituloBarra == null ? null : AppBar(title: Text(tituloBarra!)),
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

/// Espaço de foto do protótipo (azul claro com legenda). Troca por imagem real depois.
class EspacoFoto extends StatelessWidget {
  const EspacoFoto({super.key, required this.legenda, this.altura = 140, this.largura});

  final String legenda;
  final double altura;
  final double? largura;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
      width: largura,
      padding: const EdgeInsets.all(EspacosTrato.x2),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        color: CoresTrato.azulClaro,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Text(
        legenda,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TipografiaTrato.corpoPequeno.copyWith(
          color: CoresTrato.petroleo,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Linha "rótulo à esquerda, valor à direita" que não estoura com fonte grande.
class LinhaValor extends StatelessWidget {
  const LinhaValor({super.key, required this.rotulo, required this.valor, this.destaque = false});

  final String rotulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final estiloValor = destaque
        ? TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo)
        : TipografiaTrato.corpoForte;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          flex: destaque ? 2 : 3,
          child: Text(
            rotulo,
            style: destaque ? TipografiaTrato.corpoForte : TipografiaTrato.corpo,
          ),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Flexible(
          flex: destaque ? 3 : 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(valor, style: estiloValor, maxLines: 1),
          ),
        ),
      ],
    );
  }
}
