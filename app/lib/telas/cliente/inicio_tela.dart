import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../servicos/servicos_recentes_tela.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';

/// Tela 8 do protótipo: Início do cliente. [aoBuscar] leva à aba Buscar.
///
/// Os dados vêm de [dados] (catálogo e pedidos); cada atalho chama o callback correspondente,
/// que quem liga as rotas transforma em tela. Sem [dados], mostra os textos do protótipo.
class InicioTela extends StatelessWidget {
  const InicioTela({
    super.key,
    required this.aoBuscar,
    this.dados,
    this.aoAbrirNotificacoes,
    this.aoNovoPedido,
    this.aoAbrirPedidoEmAndamento,
    this.aoAbrirCategoria,
    this.aoVerTodasCategorias,
    this.aoAbrirServico,
    this.aoVerServicos,
  });

  final VoidCallback aoBuscar;
  final DadosInicio? dados;
  final VoidCallback? aoAbrirNotificacoes;
  final VoidCallback? aoNovoPedido;
  final ValueChanged<PedidoEmAndamento>? aoAbrirPedidoEmAndamento;
  final ValueChanged<CategoriaServico>? aoAbrirCategoria;
  final VoidCallback? aoVerTodasCategorias;
  final ValueChanged<ServicoRecente>? aoAbrirServico;
  final VoidCallback? aoVerServicos;

  @override
  Widget build(BuildContext context) {
    final nome = dados?.nome ?? nomeDoCliente;
    final andamento = dados == null ? pedidoEmAndamento : dados!.emAndamento;
    final recentes = dados?.recentes ?? servicosRecentes;
    final grade = dados == null
        ? categorias
        : [
            ...dados!.categorias.take(7),
            if (dados!.categorias.isNotEmpty) const CategoriaServico('Ver todas', Icons.grid_view),
          ];
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome.isEmpty ? 'Olá' : 'Olá, $nome',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: CoresTrato.textoSecundario),
                          ),
                          const SizedBox(height: EspacosTrato.x1),
                          Text('O que você precisa hoje?', style: TipografiaTrato.tituloGrande),
                        ],
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    _BotaoSino(aoTocar: aoAbrirNotificacoes),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x6),
                GestureDetector(
                  onTap: aoBuscar,
                  behavior: HitTestBehavior.opaque,
                  child: const AbsorbPointer(
                    child: CampoTrato(
                      rotulo: 'Buscar',
                      dica: 'Serviço ou profissional',
                      iconeInicio: Icons.search,
                    ),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x5),
                CartaoTrato(
                  escuro: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Descreva o problema',
                        style: TipografiaTrato.titulo.copyWith(color: CoresTrato.creme),
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                      Text(
                        'Receba até 5 orçamentos de profissionais com identidade verificada. '
                        'O pagamento é processado por parceiro e acompanhado no app.',
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.creme),
                      ),
                      const SizedBox(height: EspacosTrato.x5),
                      BotaoSecundario(
                        texto: 'Pedir orçamento',
                        aoTocar: aoNovoPedido,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x4),
                if (andamento != null)
                  CartaoTrato(
                    aoTocar: aoAbrirPedidoEmAndamento == null
                        ? null
                        : () => aoAbrirPedidoEmAndamento!(andamento),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(andamento.titulo, style: TipografiaTrato.tituloCartao),
                        const SizedBox(height: EspacosTrato.x2),
                        Text(
                          andamento.situacao,
                          style:
                              TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                        ),
                        if (andamento.aviso.isNotEmpty) ...[
                          const SizedBox(height: EspacosTrato.x2),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ChipStatus(texto: andamento.aviso, tipo: TipoStatus.destaque),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: EspacosTrato.x6),
                Text('Categorias', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                _GradeCategorias(
                  itens: grade,
                  aoTocar: (c) {
                    if (c.nome == 'Ver todas') {
                      aoVerTodasCategorias?.call();
                    } else {
                      aoAbrirCategoria?.call(c);
                    }
                  },
                ),
                if (recentes.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x6),
                  Row(
                    children: [
                      Expanded(child: Text('Serviços recentes', style: TipografiaTrato.titulo)),
                      if (aoVerServicos != null)
                        BotaoLink(texto: 'Ver todos', aoTocar: aoVerServicos),
                    ],
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  for (final servico in recentes) ...[
                    CartaoServicoRecente(
                      servico: servico,
                      aoTocar: () => aoAbrirServico?.call(servico),
                    ),
                    const SizedBox(height: EspacosTrato.x3),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotaoSino extends StatelessWidget {
  const _BotaoSino({required this.aoTocar});

  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Notificações',
      child: Material(
        color: CoresTrato.superficie,
        shape: const CircleBorder(side: BorderSide(color: CoresTrato.borda)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: aoTocar,
          child: const SizedBox.square(
            dimension: 48,
            child: Icon(Icons.notifications_none, color: CoresTrato.petroleo),
          ),
        ),
      ),
    );
  }
}

/// 4 categorias por linha. O rótulo encolhe em vez de quebrar.
class _GradeCategorias extends StatelessWidget {
  const _GradeCategorias({required this.itens, required this.aoTocar});

  final List<CategoriaServico> itens;
  final ValueChanged<CategoriaServico> aoTocar;

  static const _porLinha = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var inicio = 0; inicio < itens.length; inicio += _porLinha) ...[
          if (inicio > 0) const SizedBox(height: EspacosTrato.x2),
          Row(
            children: [
              for (var i = inicio; i < inicio + _porLinha; i++) ...[
                if (i > inicio) const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: i < itens.length
                      ? _Categoria(categoria: itens[i], aoTocar: aoTocar)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Categoria extends StatelessWidget {
  const _Categoria({required this.categoria, required this.aoTocar});

  final CategoriaServico categoria;
  final ValueChanged<CategoriaServico> aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      button: true,
      child: Material(
        color: CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: const BorderSide(color: CoresTrato.borda),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: () => aoTocar(categoria),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x1,
              vertical: EspacosTrato.x3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(categoria.icone, color: CoresTrato.petroleo),
                const SizedBox(height: EspacosTrato.x2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    categoria.nome,
                    maxLines: 1,
                    style: TipografiaTrato.corpoPequeno.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
