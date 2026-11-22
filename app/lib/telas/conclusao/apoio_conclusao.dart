import 'package:flutter/material.dart';

import '../../componentes/imagem_trato.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../profissional/dinheiro.dart';

/// Início de frase: "o profissional" vira "O profissional"; "Maria" continua "Maria".
String primeiraMaiuscula(String texto) =>
    texto.isEmpty ? texto : '${texto[0].toUpperCase()}${texto.substring(1)}';

/// "R$ 1.234,56" a partir de centavos inteiros. Só formata: o cálculo é do backend.
String formatarReais(int centavos) => Dinheiro.formatar(centavos);

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
    this.scrollController,
    this.aoAtualizar,
  });

  final List<Widget> children;
  final Widget? rodape;

  /// Sem título, a tela fica sem barra (como a Avaliação).
  final String? tituloBarra;
  final ScrollController? scrollController;
  final Future<void> Function()? aoAtualizar;

  @override
  Widget build(BuildContext context) {
    final recarregar = aoAtualizar ?? AtualizadorTela.de(context);
    final rolagem = SingleChildScrollView(
      controller: scrollController,
      physics: recarregar != null ? const AlwaysScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x6),
      child: ConteudoResponsivo(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
    return Scaffold(
      appBar: tituloBarra == null ? null : AppBar(title: Text(tituloBarra!)),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: recarregar == null
                  ? rolagem
                  : RefreshIndicator(onRefresh: recarregar, child: rolagem),
            ),
          ),
          if (rodape != null)
            Container(
              width: double.infinity,
              color: context.cores.superficie,
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

/// Espaço de foto do protótipo (azul claro com legenda ou imagem real com preview ao tocar).
class EspacoFoto extends StatelessWidget {
  const EspacoFoto({
    super.key,
    required this.legenda,
    this.altura = 140,
    this.largura,
    this.referencia,
  });

  final String legenda;
  final double altura;
  final double? largura;
  final String? referencia;

  @override
  Widget build(BuildContext context) {
    final ref = referencia ?? legenda;
    final imagemReal = construirImagemReal(ref);
    final textoExibido = rotuloAmigavelFoto(legenda);
    return ToquePreviewImagem(
      referencia: ref,
      legenda: textoExibido,
      child: Container(
        height: altura,
        width: largura,
        clipBehavior: imagemReal != null ? Clip.antiAlias : Clip.none,
        padding: imagemReal != null ? EdgeInsets.zero : const EdgeInsets.all(EspacosTrato.x2),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(
          color: context.cores.azulSuave,
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
        ),
        child: imagemReal != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  imagemReal,
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CoresTrato.overlayFoto,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.zoom_in, size: 16, color: CoresTrato.textoSobreFoto),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: double.infinity,
                      color: CoresTrato.overlayFoto,
                      padding: const EdgeInsets.symmetric(
                        horizontal: EspacosTrato.x2,
                        vertical: EspacosTrato.x1,
                      ),
                      child: Text(
                        textoExibido,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: context.cores.sobrePetroleo,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                legenda,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TipografiaTrato.corpoPequeno.copyWith(
                  color: context.cores.petroleo,
                  fontWeight: FontWeight.w700,
                ),
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
        ? TipografiaTrato.tituloGrande.copyWith(color: context.cores.petroleo)
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
