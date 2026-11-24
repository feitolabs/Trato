import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../dados/config_publica.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/foco_rolagem.dart';
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
  });

  final VoidCallback aoBuscar;
  final DadosInicio? dados;
  final VoidCallback? aoAbrirNotificacoes;
  final VoidCallback? aoNovoPedido;
  final ValueChanged<PedidoEmAndamento>? aoAbrirPedidoEmAndamento;
  final ValueChanged<CategoriaServico>? aoAbrirCategoria;
  final VoidCallback? aoVerTodasCategorias;

  @override
  Widget build(BuildContext context) {
    final nome = dados?.nome ?? '';
    final andamento = dados?.emAndamento;
    final grade = dados == null
        ? const <CategoriaServico>[]
        : [
            ...([
              for (final c in dados!.categorias)
                if (c.nome != 'Ver todas') c,
            ]..sort((a, b) => compararAlfabeticoPtBr(a.nome, b.nome)))
                .take(7),
            if (dados!.categorias.isNotEmpty) const CategoriaServico('Ver todas', Icons.grid_view),
          ];
    final recarregar = AtualizadorTela.de(context);
    final conteudo = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: EspacosTrato.x4,
        bottom: BarraAbasFlutuante.folgaInferior(context) + EspacosTrato.x4,
      ),
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
                      style:
                          TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x1),
                    Text('O que você precisa hoje?', style: TipografiaTrato.tituloGrande),
                  ],
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              _BotaoSino(
                aoTocar: aoAbrirNotificacoes,
                naoLidas: dados?.notificacoesNaoLidas ?? 0,
              ),
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
                const ChipStatus(
                  texto: 'Orçamento grátis · 0% de taxa',
                  tipo: TipoStatus.destaque,
                ),
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  'Descreva o problema',
                  style: TipografiaTrato.titulo.copyWith(color: context.cores.sobrePetroleo),
                ),
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  'Receba até ${ConfigPublica.atual.limiteOrcamentos} orçamentos de '
                  'profissionais com identidade verificada. '
                  'O pagamento é protegido pelo app até você confirmar o serviço.',
                  style: TipografiaTrato.corpo.copyWith(color: context.cores.sobrePetroleo),
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
                    style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
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
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ConteudoResponsivo(
          child: recarregar == null
              ? conteudo
              : RefreshIndicator(onRefresh: recarregar, child: conteudo),
        ),
      ),
    );
  }
}

class _BotaoSino extends StatelessWidget {
  const _BotaoSino({required this.aoTocar, this.naoLidas = 0});

  final VoidCallback? aoTocar;
  final int naoLidas;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final icone = Icon(Icons.notifications_none, color: c.texto);
    return Semantics(
      button: true,
      label: 'Notificações',
      value: naoLidas > 0 ? '$naoLidas não lidas' : null,
      excludeSemantics: true,
      child: Material(
        color: c.superficie,
        shape: CircleBorder(side: BorderSide(color: c.borda)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: aoTocar,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: naoLidas > 0
                  ? Badge.count(
                      count: naoLidas,
                      maxCount: 99,
                      backgroundColor: c.laranja,
                      textColor: context.cores.petroleo,
                      child: icone,
                    )
                  : icone,
            ),
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

  /// Com a fonte ampliada (1,3x), 4 colunas deixam ~75 dp por nome e "condicionado" não cabe:
  /// vira 3 por linha, com o nome em até 2 linhas e reticências.
  static int _colunas(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(12) / 12 > 1.15 ? 3 : 4;

  @override
  Widget build(BuildContext context) {
    final porLinha = _colunas(context);
    return Column(
      children: [
        for (var inicio = 0; inicio < itens.length; inicio += porLinha) ...[
          if (inicio > 0) const SizedBox(height: EspacosTrato.x2),
          // Cartões da mesma linha com a mesma altura, tenha o nome 1 ou 2 linhas.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = inicio; i < inicio + porLinha; i++) ...[
                  if (i > inicio) const SizedBox(width: EspacosTrato.x2),
                  Expanded(
                    child: i < itens.length
                        ? _Categoria(categoria: itens[i], aoTocar: aoTocar)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
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
        color: context.cores.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(color: context.cores.borda),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(categoria.icone, color: context.cores.petroleo),
                const SizedBox(height: EspacosTrato.x2),
                // Mesmo tamanho em todas: nome longo quebra em 2 linhas em vez de encolher a fonte.
                Text(
                  categoria.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
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
