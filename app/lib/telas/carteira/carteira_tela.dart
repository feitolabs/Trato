import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional/dinheiro.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';

/// Tela 27 — Carteira do profissional. Só exibe o que o backend devolveu em [dados]:
/// nenhum saldo, taxa ou líquido é calculado aqui. "Sacar via Pix" só chama [aoSacarPix].
class CarteiraTela extends StatelessWidget {
  const CarteiraTela({
    super.key,
    this.dados = DadosExemploCarteira.completo,
    this.aoSacarPix,
    this.aoVerTudo,
    this.aoTentarNovamente,
    this.barraInferior,
    this.soExtrato = false,
  });

  /// D15: a Carteira é só extrato (o Trato não guarda saldo nem faz saque). Esconde os
  /// cartões de saldo e o botão de saque e mostra apenas os lançamentos.
  final bool soExtrato;

  final DadosCarteira dados;
  final VoidCallback? aoSacarPix;
  final VoidCallback? aoVerTudo;
  final VoidCallback? aoTentarNovamente;

  /// Barra de abas do profissional, quando a tela é uma aba (quem liga decide).
  final Widget? barraInferior;

  @override
  Widget build(BuildContext context) {
    final resumo = dados.resumo;
    return Scaffold(
      bottomNavigationBar: barraInferior,
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: EspacosTrato.x5, bottom: EspacosTrato.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Carteira', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x5),
                if (dados.erro != null)
                  _CartaoErro(mensagem: dados.erro!, aoTentarNovamente: aoTentarNovamente)
                else if (resumo != null || soExtrato) ...[
                  if (!soExtrato && resumo != null) ...[
                    _CartaoDisponivel(resumo: resumo, aoSacarPix: aoSacarPix),
                    const SizedBox(height: EspacosTrato.x3),
                    _LinhaSaldos(resumo: resumo),
                    const SizedBox(height: EspacosTrato.x6),
                  ],
                  _CabecalhoExtrato(aoVerTudo: dados.extrato.isEmpty ? null : aoVerTudo),
                  const SizedBox(height: EspacosTrato.x3),
                  if (dados.extrato.isEmpty)
                    const _ExtratoVazio()
                  else
                    _Extrato(itens: dados.extrato),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartaoDisponivel extends StatelessWidget {
  const _CartaoDisponivel({required this.resumo, required this.aoSacarPix});

  final ResumoCarteira resumo;
  final VoidCallback? aoSacarPix;

  @override
  Widget build(BuildContext context) {
    final claro = TipografiaTrato.corpo.copyWith(color: CoresTrato.creme);
    return CartaoTrato(
      escuro: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disponível para saque', style: claro),
          const SizedBox(height: EspacosTrato.x3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Dinheiro.formatar(resumo.disponivelCentavos),
              maxLines: 1,
              style: TipografiaTrato.marcaPequena.copyWith(color: CoresTrato.creme, fontSize: 44),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(resumo.textoPix, style: claro),
          const SizedBox(height: EspacosTrato.x4),
          BotaoSecundario(
            texto: 'Sacar via Pix',
            aoTocar: resumo.disponivelCentavos > 0 ? aoSacarPix : null,
          ),
        ],
      ),
    );
  }
}

class _LinhaSaldos extends StatelessWidget {
  const _LinhaSaldos({required this.resumo});

  final ResumoCarteira resumo;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _CartaoSaldo(
              icone: Icons.lock_outline,
              rotulo: 'Retido',
              cor: CoresTrato.azulTexto,
              centavos: resumo.retidoCentavos,
              texto: resumo.textoRetido,
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: _CartaoSaldo(
              icone: Icons.schedule,
              rotulo: 'A liberar',
              cor: CoresTrato.ambarTexto,
              centavos: resumo.aLiberarCentavos,
              texto: resumo.textoALiberar,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoSaldo extends StatelessWidget {
  const _CartaoSaldo({
    required this.icone,
    required this.rotulo,
    required this.cor,
    required this.centavos,
    required this.texto,
  });

  final IconData icone;
  final String rotulo;
  final Color cor;
  final int centavos;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: EspacosTrato.x4, color: cor),
              const SizedBox(width: EspacosTrato.x1),
              Flexible(
                child: Text(
                  rotulo,
                  style: TipografiaTrato.corpoForte.copyWith(color: cor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Dinheiro.formatar(centavos), style: TipografiaTrato.titulo, maxLines: 1),
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            texto,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
        ],
      ),
    );
  }
}

class _CabecalhoExtrato extends StatelessWidget {
  const _CabecalhoExtrato({required this.aoVerTudo});

  final VoidCallback? aoVerTudo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Extrato por serviço', style: TipografiaTrato.titulo, maxLines: 1),
          ),
        ),
        if (aoVerTudo != null) BotaoLink(texto: 'Ver tudo', aoTocar: aoVerTudo),
      ],
    );
  }
}

class _Extrato extends StatelessWidget {
  const _Extrato({required this.itens});

  final List<ItemExtrato> itens;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        children: [
          for (var i = 0; i < itens.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: EspacosTrato.x3),
                child: Divider(),
              ),
            _LinhaExtrato(item: itens[i]),
          ],
        ],
      ),
    );
  }
}

class _LinhaExtrato extends StatelessWidget {
  const _LinhaExtrato({required this.item});

  final ItemExtrato item;

  @override
  Widget build(BuildContext context) {
    final liberado = item.status == StatusExtrato.liberado;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(item.titulo, style: TipografiaTrato.tituloCartao)),
            const SizedBox(width: EspacosTrato.x3),
            Text(Dinheiro.formatar(item.liquidoCentavos), style: TipografiaTrato.tituloCartao),
          ],
        ),
        Text(item.detalheData, style: secundario),
        const SizedBox(height: EspacosTrato.x1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '${Dinheiro.formatar(item.brutoCentavos)} – ${item.textoTaxa}',
                style: secundario,
              ),
            ),
            const SizedBox(width: EspacosTrato.x2),
            ChipStatus(
              texto: liberado ? 'Liberado' : 'A liberar',
              tipo: liberado ? TipoStatus.sucesso : TipoStatus.alerta,
            ),
          ],
        ),
      ],
    );
  }
}

class _ExtratoVazio extends StatelessWidget {
  const _ExtratoVazio();

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nenhum serviço ainda', style: TipografiaTrato.tituloCartao),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Quando você concluir um serviço, ele aparece aqui com o valor, a taxa e o líquido.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
        ],
      ),
    );
  }
}

class _CartaoErro extends StatelessWidget {
  const _CartaoErro({required this.mensagem, required this.aoTentarNovamente});

  final String mensagem;
  final VoidCallback? aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ChipStatus(texto: 'Erro', tipo: TipoStatus.perigo, icone: Icons.error_outline),
          const SizedBox(height: EspacosTrato.x3),
          Text(mensagem, style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x4),
          BotaoSecundario(texto: 'Tentar de novo', aoTocar: aoTentarNovamente),
        ],
      ),
    );
  }
}
