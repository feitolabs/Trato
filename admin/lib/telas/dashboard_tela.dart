import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// Painel executivo (RF-DAS-01 a RF-DAS-05).
class DashboardTela extends StatefulWidget {
  const DashboardTela({super.key});

  @override
  State<DashboardTela> createState() => _DashboardTelaState();
}

class _DashboardTelaState extends State<DashboardTela> {
  PeriodoSelecionado _periodo = const PeriodoSelecionado.dias(30);

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final p = _periodo;
    final dias = p.diasAteHoje();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Painel executivo',
          subtitulo: 'Comparação com o período anterior de mesma duração.',
          acoes: [FiltroPeriodo(selecionado: p, aoMudar: (v) => setState(() => _periodo = v))],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarregaDados<MetricasDashboard>(
                  key: ValueKey('metricas-${p.hashCode}'),
                  carregar: () => api.metricasDashboard(dias: dias, inicio: p.inicio, fim: p.fim),
                  esqueleto: const SizedBox(height: 180, child: EsqueletoCartoes()),
                  construir: (context, m, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Indicadores(metricas: m, periodo: p),
                      const SizedBox(height: EspacosTrato.intervaloCartoes),
                      _Atalhos(metricas: m),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x4),
                CarregaDados<SeriesDashboard>(
                  key: ValueKey('series-${p.hashCode}'),
                  carregar: () => api.seriesDashboard(dias: dias, inicio: p.inicio, fim: p.fim),
                  esqueleto: const SizedBox(height: 320, child: EsqueletoLista(linhas: 2)),
                  construir: (context, s, _) => LayoutBuilder(
                    builder: (context, c) {
                      final historico = _CartaoPedidosPorDia(pontos: s.historicoDias);
                      final funil = _CartaoFunil(funil: s.funil);
                      if (c.maxWidth < 900) {
                        return Column(children: [
                          historico,
                          const SizedBox(height: EspacosTrato.intervaloCartoes),
                          funil,
                        ]);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: historico),
                          const SizedBox(width: EspacosTrato.intervaloCartoes),
                          Expanded(flex: 2, child: funil),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Variação percentual sobre o período anterior. Nulo quando não há base de comparação.
double? variacaoPct(num atual, num anterior) => anterior == 0 ? null : (atual - anterior) / anterior * 100;

class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.metricas, required this.periodo});
  final MetricasDashboard metricas;
  final PeriodoSelecionado periodo;

  @override
  Widget build(BuildContext context) {
    final m = metricas;
    final rotulo = 'vs. ${periodo.duracaoEmDias} dias anteriores';
    final cartoes = [
      CartaoMetrica(
        titulo: 'GMV',
        valor: formatarReais(m.gmvCentavos),
        icone: Icons.payments_outlined,
        ajuda: 'Soma dos pedidos pagos no período.',
        subtitulo: 'Soma dos pedidos pagos no período',
        variacaoPct: variacaoPct(m.gmvCentavos, m.gmvAnteriorCentavos),
        rotuloComparacao: rotulo,
      ),
      CartaoMetrica(
        titulo: 'Receita Trato',
        valor: formatarReais(m.receitaTaxaCentavos),
        icone: Icons.trending_up,
        ajuda: 'Soma das taxas retidas em serviços concluídos.',
        subtitulo: 'Soma das taxas retidas em serviços concluídos',
        variacaoPct: variacaoPct(m.receitaTaxaCentavos, m.receitaTaxaAnteriorCentavos),
        rotuloComparacao: rotulo,
      ),
      CartaoMetrica(
        titulo: 'Pedidos ativos',
        valor: formatarMilhar(m.pedidosAtivos),
        icone: Icons.assignment_outlined,
        ajuda: 'Pedidos criados no período que seguem abertos, em proposta ou em execução.',
        subtitulo: 'Abertos, em proposta ou em execução',
        variacaoPct: variacaoPct(m.pedidosAtivos, m.pedidosAtivosAnterior),
        rotuloComparacao: rotulo,
      ),
      CartaoMetrica(
        titulo: 'Base de usuários',
        valor: formatarMilhar(m.baseUsuarios),
        icone: Icons.people_outline,
        ajuda: 'Clientes e profissionais com conta ativa.',
        subtitulo: 'Clientes e profissionais com conta ativa',
        variacaoPct: variacaoPct(m.baseUsuarios, m.baseUsuariosAnterior),
        rotuloComparacao: rotulo,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final colunas = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        // Linhas de mesma altura: cada cartão estica até o mais alto da linha.
        return Column(
          children: [
            for (var i = 0; i < cartoes.length; i += colunas) ...[
              if (i > 0) const SizedBox(height: EspacosTrato.intervaloCartoes),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + colunas; j++) ...[
                      if (j > i) const SizedBox(width: EspacosTrato.intervaloCartoes),
                      Expanded(child: j < cartoes.length ? cartoes[j] : const SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Cards extras do RF-DAS-05: o que está esperando alguém da equipe.
class _Atalhos extends StatelessWidget {
  const _Atalhos({required this.metricas});
  final MetricasDashboard metricas;

  @override
  Widget build(BuildContext context) {
    Widget item(String rotulo, int n, bool atencao) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
            decoration: BoxDecoration(
              color: CoresTrato.fundoSuperficie,
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
              border: Border.all(color: CoresTrato.bordaSuave),
            ),
            child: Row(
              children: [
                Expanded(child: Text(rotulo, style: TipografiaTrato.corpo)),
                Text(
                  '$n',
                  style: TipografiaTrato.secao.copyWith(color: atencao && n > 0 ? CoresTrato.avisoTexto : CoresTrato.textoPadrao),
                ),
              ],
            ),
          ),
        );
    return LayoutBuilder(builder: (context, c) {
      final itens = [
        item('Verificações pendentes', metricas.profissionaisPendentes, true),
        item('Disputas abertas', metricas.disputasAbertas, true),
        item('Alertas de risco abertos', metricas.alertasRiscoAbertos, true),
      ];
      if (c.maxWidth < 700) {
        return Column(children: [
          for (final i in itens) ...[SizedBox(width: double.infinity, child: Row(children: [i])), const SizedBox(height: EspacosTrato.x2)],
        ]);
      }
      return Row(children: [
        for (var i = 0; i < itens.length; i++) ...[
          if (i > 0) const SizedBox(width: EspacosTrato.intervaloCartoes),
          itens[i],
        ],
      ]);
    });
  }
}

/// Barras diárias com eixos legíveis e estado explícito para dias sem dados (RF-DAS-04).
class _CartaoPedidosPorDia extends StatelessWidget {
  const _CartaoPedidosPorDia({required this.pontos});
  final List<PontoSerieDashboard> pontos;

  static const _alturaBarras = 180.0;

  @override
  Widget build(BuildContext context) {
    final maior = pontos.isEmpty ? 0 : pontos.map((p) => p.pedidos).reduce((a, b) => a > b ? a : b);
    // Eixo vertical em passos redondos (0, 20, 40, 60...).
    final passo = maior <= 5 ? 1 : (maior <= 20 ? 5 : (maior <= 60 ? 20 : ((maior / 4).ceil() ~/ 10 + 1) * 10));
    final topo = maior == 0 ? passo : ((maior / passo).ceil()) * passo;
    final marcas = [for (var v = 0; v <= topo; v += passo) v];
    final semDados = pontos.where((p) => p.pedidos == 0).length;
    // Mostra o rótulo do dia de tantos em tantos, para não amontoar.
    final cada = pontos.length <= 10 ? 1 : (pontos.length <= 31 ? 3 : 7);

    return CartaoSecao(
      titulo: 'Pedidos criados por dia',
      acao: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Legenda(CoresTrato.primaria, 'Pedidos'),
          if (semDados > 0) ...[
            const SizedBox(width: EspacosTrato.x3),
            const _Legenda(CoresTrato.bordaSuave, 'Sem dados'),
          ],
        ],
      ),
      child: pontos.isEmpty
          ? const SizedBox(height: _alturaBarras, child: EstadoVazio('Sem dados no período'))
          : Semantics(
              label: 'Gráfico de barras: pedidos criados por dia',
              child: Column(
                children: [
                  SizedBox(
                    height: _alturaBarras,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 32,
                          child: Stack(
                            children: [
                              for (final v in marcas)
                                Positioned(
                                  bottom: v / topo * (_alturaBarras - 8) - 8,
                                  right: EspacosTrato.x2,
                                  child: Text('$v', style: TipografiaTrato.legenda),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              for (final v in marcas)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: v / topo * (_alturaBarras - 8),
                                  child: Container(height: 1, color: CoresTrato.bordaSuave),
                                ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (final p in pontos)
                                    Expanded(
                                      child: Tooltip(
                                        message: '${_dia(p.data)}: ${p.pedidos} '
                                            '${p.pedidos == 1 ? 'pedido' : 'pedidos'}',
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                                          child: Container(
                                            height: p.pedidos == 0 ? 3 : p.pedidos / topo * (_alturaBarras - 8),
                                            decoration: BoxDecoration(
                                              color: p.pedidos == 0 ? CoresTrato.bordaSuave : CoresTrato.primaria,
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  Row(
                    children: [
                      const SizedBox(width: 32),
                      for (var i = 0; i < pontos.length; i++)
                        Expanded(
                          child: i % cada == 0 || i == pontos.length - 1
                              ? Text(
                                  _diaCurto(pontos[i].data),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  softWrap: false,
                                  style: TipografiaTrato.legenda,
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  static String _dia(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}/${iso.substring(5, 7)}' : iso;
  static String _diaCurto(String iso) => iso.length >= 10 ? iso.substring(8, 10) : iso;
}

class _Legenda extends StatelessWidget {
  const _Legenda(this.cor, this.texto);
  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: EspacosTrato.x1),
        Text(texto, style: TipografiaTrato.legenda),
      ],
    );
  }
}

/// Funil em tons do primário, do mais escuro (início) ao mais claro, com contagem e percentual.
class _CartaoFunil extends StatelessWidget {
  const _CartaoFunil({required this.funil});
  final List<EtapaFunilDashboard> funil;

  @override
  Widget build(BuildContext context) {
    return CartaoSecao(
      titulo: 'Funil de conversão',
      child: funil.isEmpty
          ? const SizedBox(height: 120, child: EstadoVazio('Sem dados no período'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < funil.length; i++) ...[
                  Row(
                    children: [
                      Expanded(child: Text(funil[i].etapa, style: TipografiaTrato.corpoForte)),
                      Text(
                        '${formatarMilhar(funil[i].quantidade)} · ${funil[i].taxaConversaoPct.round()}%',
                        style: TipografiaTrato.numeroTabular,
                      ),
                    ],
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(
                        children: [
                          Container(height: 14, width: c.maxWidth, color: CoresTrato.neutroFundo),
                          Container(
                            height: 14,
                            width: c.maxWidth * (funil[i].taxaConversaoPct / 100).clamp(0.02, 1.0),
                            color: CoresTrato.funil[i.clamp(0, CoresTrato.funil.length - 1)],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                Text(
                  'Percentual em relação aos pedidos criados. Tons do primário, do mais escuro (início) ao mais claro.',
                  style: TipografiaTrato.legenda,
                ),
              ],
            ),
    );
  }
}
