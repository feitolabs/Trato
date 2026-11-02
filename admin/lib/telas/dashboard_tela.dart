import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// Módulo 1 — Dashboard Executivo & KPIs em Tempo Real
class DashboardTela extends StatefulWidget {
  const DashboardTela({super.key});

  @override
  State<DashboardTela> createState() => _DashboardTelaState();
}

class _DashboardTelaState extends State<DashboardTela> {
  int _dias = 7;

  @override
  Widget build(BuildContext context) {
    final api = context.api;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: CabecalhoPagina(
                  'Dashboard Executivo',
                  subtitulo: 'Visão geral em tempo real de faturamento, liquidez e conversão',
                ),
              ),
              DropdownButton<int>(
                value: _dias,
                items: const [
                  DropdownMenuItem(value: 7, child: Text('Últimos 7 dias')),
                  DropdownMenuItem(value: 14, child: Text('Últimos 14 dias')),
                  DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _dias = v);
                },
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x4),

          // KPIs Principais
          CarregaDados<MetricasDashboard>(
            carregar: api.metricasDashboard,
            construir: (context, m, _) => _SecaoKpis(metricas: m),
          ),

          const SizedBox(height: EspacosTrato.x6),

          // Séries Temporais e Funil de Conversão
          CarregaDados<SeriesDashboard>(
            key: ValueKey('series-$_dias'),
            carregar: () => api.seriesDashboard(dias: _dias),
            construir: (context, s, _) => LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 900) {
                  return Column(
                    children: [
                      _CartaoHistorico(pontos: s.historicoDias),
                      const SizedBox(height: EspacosTrato.x4),
                      _CartaoFunil(funil: s.funil),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _CartaoHistorico(pontos: s.historicoDias)),
                    const SizedBox(width: EspacosTrato.x4),
                    Expanded(flex: 2, child: _CartaoFunil(funil: s.funil)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SecaoKpis extends StatelessWidget {
  const _SecaoKpis({required this.metricas});
  final MetricasDashboard metricas;

  @override
  Widget build(BuildContext context) {
    final m = metricas;
    return LayoutBuilder(
      builder: (context, c) {
        final largura = c.maxWidth;
        final colunas = largura > 1100 ? 4 : (largura > 700 ? 2 : 1);
        final itemWidth = (largura - (colunas - 1) * EspacosTrato.x4) / colunas;

        return Wrap(
          spacing: EspacosTrato.x4,
          runSpacing: EspacosTrato.x4,
          children: [
            SizedBox(
              width: itemWidth,
              child: _KpiCard(
                titulo: 'GMV Transacionado',
                valor: formatarReais(m.gmvCentavos),
                subtitulo: 'Volume total movimentado',
                icone: Icons.payments_outlined,
                corIcone: Colors.teal,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _KpiCard(
                titulo: 'Receita Trato',
                valor: formatarReais(m.receitaTaxaCentavos),
                subtitulo: 'Taxa de intermediação retida',
                icone: Icons.trending_up,
                corIcone: Colors.green,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _KpiCard(
                titulo: 'Pedidos Ativos',
                valor: '${m.pedidosTotal}',
                subtitulo: '${m.pedidosConcluidos} concluídos · ${m.pedidosDisputa} em disputa',
                icone: Icons.assignment_outlined,
                corIcone: Colors.blue,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _KpiCard(
                titulo: 'Base de Usuários',
                valor: '${m.clientesTotal + m.profissionaisTotal}',
                subtitulo: '${m.profissionaisTotal} prestadores · ${m.profissionaisPendentes} na fila',
                icone: Icons.people_outline,
                corIcone: Colors.orange,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.icone,
    required this.corIcone,
  });

  final String titulo;
  final String valor;
  final String subtitulo;
  final IconData icone;
  final Color corIcone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: corIcone.withValues(alpha: 0.15),
                  radius: 20,
                  child: Icon(icone, color: corIcone, size: 22),
                ),
                const Spacer(),
                Text(titulo, style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario)),
              ],
            ),
            const SizedBox(height: EspacosTrato.x3),
            Text(valor, style: TipografiaTrato.tituloGrande.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: EspacosTrato.x1),
            Text(subtitulo, style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario)),
          ],
        ),
      ),
    );
  }
}

class _CartaoHistorico extends StatelessWidget {
  const _CartaoHistorico({required this.pontos});
  final List<PontoSerieDashboard> pontos;

  @override
  Widget build(BuildContext context) {
    final maxGmv = pontos.isEmpty ? 1 : pontos.map((p) => p.gmvCentavos).reduce((a, b) => a > b ? a : b);
    final divisor = maxGmv == 0 ? 1 : maxGmv;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: CoresTrato.azulTexto),
                const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: Text(
                    'Evolução de Pedidos & Faturamento Diário',
                    style: TipografiaTrato.tituloCartao,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EspacosTrato.x4),
            SizedBox(
              height: 220,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final p in pontos)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${p.pedidos}', style: TipografiaTrato.legenda.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              height: ((p.gmvCentavos / divisor) * 140).clamp(12.0, 140.0),
                              decoration: BoxDecoration(
                                color: CoresTrato.petroleo,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              p.data.length >= 5 ? p.data.substring(5) : p.data,
                              style: TipografiaTrato.legenda.copyWith(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoFunil extends StatelessWidget {
  const _CartaoFunil({required this.funil});
  final List<EtapaFunilDashboard> funil;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, color: CoresTrato.laranja),
                const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: Text(
                    'Funil de Conversão do App',
                    style: TipografiaTrato.tituloCartao,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EspacosTrato.x4),
            for (final f in funil) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      f.etapa,
                      style: TipografiaTrato.corpoPequeno.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  Text('${f.quantidade} (${f.taxaConversaoPct.toStringAsFixed(1)}%)', style: TipografiaTrato.corpoPequeno),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (f.taxaConversaoPct / 100).clamp(0.05, 1.0),
                  minHeight: 10,
                  backgroundColor: CoresTrato.creme,
                  color: CoresTrato.petroleo,
                ),
              ),
              const SizedBox(height: EspacosTrato.x3),
            ],
          ],
        ),
      ),
    );
  }
}
