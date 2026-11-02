import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../componentes/base.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';

/// Módulo 7 — Exportação de Relatórios Fiscais e Contábeis (CSV)
class RelatoriosTela extends StatelessWidget {
  const RelatoriosTela({super.key});

  Future<void> _baixar(BuildContext context, String url, String nome) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!ok && context.mounted) {
      mostrarAviso(context, 'Não foi possível iniciar o download de $nome.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.api;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabecalhoPagina(
            'Relatórios Fiscais & Contábeis',
            subtitulo: 'Exportação consolidada em CSV para a contabilidade da Feito Labs e auditoria',
          ),
          const SizedBox(height: EspacosTrato.x6),
          LayoutBuilder(
            builder: (context, c) {
              final colunas = c.maxWidth > 900 ? 3 : (c.maxWidth > 600 ? 2 : 1);
              final larguraItem = (c.maxWidth - (colunas - 1) * EspacosTrato.x4) / colunas;

              return Wrap(
                spacing: EspacosTrato.x4,
                runSpacing: EspacosTrato.x4,
                children: [
                  SizedBox(
                    width: larguraItem,
                    child: _CartaoRelatorio(
                      titulo: 'Extrato Financeiro & Fiscal',
                      descricao:
                          'Contém todas as transações, receita da taxa Trato retida, valores líquidos, métodos de pagamento e status.',
                      icone: Icons.receipt_long_outlined,
                      corIcone: Colors.teal,
                      nomeArquivo: 'relatorio_financeiro.csv',
                      aoBaixar: () => _baixar(context, api.urlRelatorioFinanceiroCsv(), 'Relatório Financeiro'),
                    ),
                  ),
                  SizedBox(
                    width: larguraItem,
                    child: _CartaoRelatorio(
                      titulo: 'Relatório Geral de Pedidos',
                      descricao:
                          'Visão completa de pedidos realizados, clientes, profissionais alocados, categoria, cidade e valores.',
                      icone: Icons.assignment_outlined,
                      corIcone: Colors.blue,
                      nomeArquivo: 'relatorio_pedidos.csv',
                      aoBaixar: () => _baixar(context, api.urlRelatorioPedidosCsv(), 'Relatório de Pedidos'),
                    ),
                  ),
                  SizedBox(
                    width: larguraItem,
                    child: _CartaoRelatorio(
                      titulo: 'Relatório de Repasses (PIX)',
                      descricao:
                          'Detalhamento de transferências efetuadas aos profissionais parceiros para conciliação bancária.',
                      icone: Icons.payments_outlined,
                      corIcone: Colors.orange,
                      nomeArquivo: 'relatorio_repasses.csv',
                      aoBaixar: () => _baixar(context, api.urlRelatorioRepassesCsv(), 'Relatório de Repasses'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: EspacosTrato.x8),
          Card(
            color: CoresTrato.azulSuave,
            child: Padding(
              padding: const EdgeInsets.all(EspacosTrato.x4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: CoresTrato.azulTexto),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(
                    child: Text(
                      'Os relatórios são exportados no formato CSV com codificação UTF-8 com BOM, prontos para importação no Microsoft Excel, Google Planilhas ou sistemas de gestão contábil.',
                      style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoRelatorio extends StatelessWidget {
  const _CartaoRelatorio({
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.corIcone,
    required this.nomeArquivo,
    required this.aoBaixar,
  });

  final String titulo;
  final String descricao;
  final IconData icone;
  final Color corIcone;
  final String nomeArquivo;
  final VoidCallback aoBaixar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: corIcone.withValues(alpha: 0.15),
              radius: 24,
              child: Icon(icone, color: corIcone, size: 28),
            ),
            const SizedBox(height: EspacosTrato.x3),
            Text(titulo, style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              descricao,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x4),
            Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
                  ),
                  onPressed: aoBaixar,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Exportar CSV'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
