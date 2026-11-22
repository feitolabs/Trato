import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho;
import '../profissional/dinheiro.dart';
import 'modelos.dart';
import 'regra_liberacao.dart';

/// Tela 27 — Carteira do profissional. Só exibe o que o backend devolveu em [dados]:
/// nenhum saldo, taxa ou líquido é calculado aqui. O repasse é automático: não há botão de saque.
class CarteiraTela extends StatelessWidget {
  const CarteiraTela({
    super.key,
    required this.dados,
    this.aoVerTudo,
    this.aoTentarNovamente,
    this.barraInferior,
    this.soExtrato = true,
    this.aoAbrirItem,
    this.aoConfigurarRecebimento,
    this.aoBaixarExtratoPdf,
    this.aoCarregarMais,
    this.temMaisExtrato = false,
    this.carregandoMais = false,
  });

  /// Toque numa linha do extrato: abre o detalhe dos valores do pedido.
  final ValueChanged<ItemExtrato>? aoAbrirItem;

  /// Abre a tela de cadastro/alteração da conta de recebimento (chave Pix / banco).
  final VoidCallback? aoConfigurarRecebimento;

  /// Baixa o extrato mensal em PDF diretamente no app.
  final VoidCallback? aoBaixarExtratoPdf;
  final VoidCallback? aoCarregarMais;
  final bool temMaisExtrato;
  final bool carregandoMais;

  /// D15: a Carteira é só extrato (o Trato não guarda saldo nem faz saque). Esconde os
  /// cartões de saldo e o botão de saque e mostra apenas os lançamentos.
  final bool soExtrato;

  final DadosCarteira dados;
  final VoidCallback? aoVerTudo;
  final VoidCallback? aoTentarNovamente;

  /// Barra de abas do profissional, quando a tela é uma aba (quem liga decide).
  final Widget? barraInferior;

  @override
  Widget build(BuildContext context) {
    final resumo = dados.resumo;
    final recarregar = AtualizadorTela.de(context);
    final corpo = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
              _CartaoDisponivel(
                resumo: resumo,
                contaCadastrada: dados.contaRecebimento?.cadastrada == true,
                aoAlterarConta: aoConfigurarRecebimento,
              ),
              const SizedBox(height: EspacosTrato.x3),
              _LinhaSaldos(resumo: resumo),
              const SizedBox(height: EspacosTrato.x4),
            ],
            Text(
              'Repasse automático: após a liberação, o valor cai automaticamente na sua conta cadastrada.',
              key: const Key('aviso-repasse-automatico'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x1),
            RegraLiberacao(libera: dados.proximaLiberacao, chave: const Key('regra-liberacao')),
            if (dados.tratinhosPendentesTexto != null) ...[
              const SizedBox(height: EspacosTrato.x1),
              Text(
                dados.tratinhosPendentesTexto!,
                key: const Key('tratinhos-pendentes-carteira'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
              ),
            ],
            const SizedBox(height: EspacosTrato.x4),
            if (aoConfigurarRecebimento != null &&
                dados.contaRecebimento?.cadastrada == true) ...[
              _CartaoContaRecebimento(
                conta: dados.contaRecebimento,
                aoTocar: aoConfigurarRecebimento!,
              ),
              const SizedBox(height: EspacosTrato.x5),
            ],
            _CabecalhoExtrato(
              aoVerTudo: dados.extrato.isEmpty ? null : aoVerTudo,
              aoBaixarPdf: aoBaixarExtratoPdf,
            ),
            const SizedBox(height: EspacosTrato.x3),
            if (dados.extrato.isEmpty)
              const _ExtratoVazio()
            else ...[
              _Extrato(itens: dados.extrato, aoAbrir: aoAbrirItem),
              if (temMaisExtrato && aoCarregarMais != null) ...[
                const SizedBox(height: EspacosTrato.x3),
                Center(
                  child: carregandoMais
                      ? const Padding(
                          padding: EdgeInsets.all(EspacosTrato.x2),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : BotaoLink(texto: 'Carregar mais', aoTocar: aoCarregarMais),
                ),
              ],
            ],
          ],
        ],
      ),
    );
    return Scaffold(
      bottomNavigationBar: barraInferior,
      body: SafeArea(
        child: ConteudoResponsivo(
          child: recarregar == null ? corpo : RefreshIndicator(onRefresh: recarregar, child: corpo),
        ),
      ),
    );
  }
}

class _CartaoDisponivel extends StatelessWidget {
  const _CartaoDisponivel({
    required this.resumo,
    required this.contaCadastrada,
    required this.aoAlterarConta,
  });

  final ResumoCarteira resumo;
  final bool contaCadastrada;
  final VoidCallback? aoAlterarConta;

  @override
  Widget build(BuildContext context) {
    final claro = TipografiaTrato.corpo.copyWith(color: context.cores.sobrePetroleo);
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
              style: TipografiaTrato.marcaPequena.copyWith(color: context.cores.sobrePetroleo, fontSize: 44),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(resumo.textoPix, style: claro),
          if (aoAlterarConta != null) ...[
            const SizedBox(height: EspacosTrato.x4),
            BotaoSecundario(
              key: const Key('botao-alterar-conta'),
              texto: contaCadastrada
                  ? 'Alterar conta de recebimento'
                  : 'Cadastrar conta de recebimento',
              aoTocar: aoAlterarConta,
            ),
          ],
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
              cor: context.cores.azulTexto,
              centavos: resumo.retidoCentavos,
              texto: resumo.textoRetido,
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: _CartaoSaldo(
              icone: Icons.schedule,
              rotulo: 'A liberar',
              cor: context.cores.ambarTexto,
              centavos: resumo.aLiberarCentavos,
              texto:
                  'Repasse do dinheiro: ${resumo.proximaLiberacao == null ? resumo.textoALiberar : diaMesDoAparelho(resumo.proximaLiberacao!)}',
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
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
          ),
        ],
      ),
    );
  }
}

class _CabecalhoExtrato extends StatelessWidget {
  const _CabecalhoExtrato({required this.aoVerTudo, this.aoBaixarPdf});

  final VoidCallback? aoVerTudo;
  final VoidCallback? aoBaixarPdf;

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
        if (aoBaixarPdf != null) BotaoLink(texto: 'PDF mensal', aoTocar: aoBaixarPdf),
        if (aoVerTudo != null) BotaoLink(texto: 'Ver tudo', aoTocar: aoVerTudo),
      ],
    );
  }
}

class _CartaoContaRecebimento extends StatelessWidget {
  const _CartaoContaRecebimento({required this.conta, required this.aoTocar});

  final ContaRecebimento? conta;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cadastrada = conta?.cadastrada == true;
    final resumo = conta?.resumoExibicao ?? conta?.chavePixMascarada;
    return CartaoTrato(
      child: Row(
        children: [
          Icon(Icons.account_balance_outlined, color: context.cores.petroleo),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cadastrada ? 'Conta de recebimento ativa' : 'Cadastre sua conta Pix',
                  style: TipografiaTrato.tituloCartao,
                ),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  cadastrada && (resumo ?? '').isNotEmpty
                      ? resumo!
                      : 'Informe sua chave Pix para receber os repasses liberados.',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
                ),
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x2),
          BotaoLink(
            texto: cadastrada ? 'Alterar' : 'Cadastrar',
            aoTocar: aoTocar,
          ),
        ],
      ),
    );
  }
}

class _Extrato extends StatelessWidget {
  const _Extrato({required this.itens, this.aoAbrir});

  final List<ItemExtrato> itens;
  final ValueChanged<ItemExtrato>? aoAbrir;

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
            InkWell(
              onTap: aoAbrir == null || itens[i].pedidoId == null ? null : () => aoAbrir!(itens[i]),
              child: _LinhaExtrato(item: itens[i]),
            ),
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
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
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
                item.textoTaxa == 'Estorno' ? 'Estorno' : 'Sem taxa',
                style: secundario,
              ),
            ),
            const SizedBox(width: EspacosTrato.x2),
            ChipStatus(
              texto: liberado ? 'Confirmado' : 'A liberar',
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
            'Quando você concluir um serviço, ele aparece aqui com o valor que você recebe, sem taxa.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
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
