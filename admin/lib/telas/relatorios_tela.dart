import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/auditoria_texto.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Relatórios fiscais e contábeis (RF-REL-01 a RF-REL-04).
class RelatoriosTela extends StatefulWidget {
  const RelatoriosTela({super.key});

  @override
  State<RelatoriosTela> createState() => _RelatoriosTelaState();
}

class _RelatoriosTelaState extends State<RelatoriosTela> {
  PeriodoSelecionado _periodo = const PeriodoSelecionado.dias(30);
  String? _cidadeId;
  String _formato = 'excel_br';
  List<CidadeAdmin> _cidades = const [];
  String? _gerando;
  int _versaoHistorico = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final c = await context.api.listarCidades();
        if (mounted) setState(() => _cidades = c);
      } catch (_) {
        // sem permissão para listar cidades: o filtro fica só em "Todas as cidades"
      }
    });
  }

  (DateTime, DateTime) _intervalo() {
    final hoje = DateTime.now();
    if (_periodo.personalizado) return (_periodo.inicio!, _periodo.fim!);
    return (hoje.subtract(Duration(days: _periodo.dias!)), hoje);
  }

  Future<void> _exportar(String tipo, String nome) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Exportar $nome?',
      descricao: 'O arquivo CSV sai com os filtros escolhidos. Quem exportou, os filtros e a data ficam na auditoria.',
      rotuloConfirmar: 'Exportar CSV',
    );
    if (motivo == null || !mounted) return;
    final (ini, fim) = _intervalo();
    setState(() => _gerando = tipo);
    RelatorioPronto? pronto;
    final ok = await executar(context, () async {
      pronto = await api.solicitarRelatorio(
        tipo,
        inicio: ini,
        fim: fim,
        cidadeId: _cidadeId,
        formato: _formato,
        motivo: motivo,
      );
    });
    if (!mounted) return;
    setState(() {
      _gerando = null;
      if (ok) _versaoHistorico++;
    });
    final r = pronto;
    if (!ok || r == null) return;
    mostrarAviso(
      context,
      'Relatório pronto.',
      detalhe: '${formatarMilhar(r.linhas)} linhas · ${r.colunas} colunas. O download começa agora.',
    );
    await launchUrl(Uri.parse(r.url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final podeAuditoria = context.pode(Permissao.auditoriaVer);
    final podePessoais = context.pode(Permissao.dadosPessoaisRevelar);
    final relatorios = [
      (
        'financeiro',
        'Extrato Financeiro e Fiscal',
        'Cobranças, taxas retidas, reembolsos e repasses do período, por pedido.',
        podePessoais ? 'Inclui CPF para papéis autorizados' : 'Sem CPF: seu papel não revela dados pessoais',
      ),
      (
        'pedidos',
        'Relatório Geral de Pedidos',
        'Todos os pedidos com categoria, cidade, status, valores e datas de cada etapa.',
        'Sem dados pessoais',
      ),
      (
        'repasses',
        'Relatório de Repasses (PIX)',
        'Repasses confirmados pelo provedor com identificador da transação.',
        'Valores do provedor, sem chave PIX',
      ),
    ];
    return ListView(
      padding: EdgeInsets.only(bottom: EspacosTrato.x6, left: 0, right: 0),
      children: [
        const CabecalhoPagina(
          'Relatórios fiscais',
          subtitulo: 'Toda exportação fica registrada na auditoria com quem exportou, os filtros e a data.',
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: margem),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CartaoSecao(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final periodo = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Período', style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo)),
                        const SizedBox(height: EspacosTrato.x2),
                        FiltroPeriodo(selecionado: _periodo, aoMudar: (p) => setState(() => _periodo = p)),
                      ],
                    );
                    final cidade = SeletorTrato<String?>(
                      rotulo: 'Cidade',
                      valor: _cidadeId,
                      opcoes: [
                        (null, 'Todas as cidades'),
                        for (final c in _cidades) (c.id, '${c.nome} - ${c.uf}'),
                      ],
                      aoMudar: (v) => setState(() => _cidadeId = v),
                    );
                    final formato = SeletorTrato<String>(
                      rotulo: 'Formato',
                      valor: _formato,
                      opcoes: const [
                        ('excel_br', 'Excel em português (; e vírgula decimal)'),
                        ('padrao', 'Padrão (, e ponto decimal)'),
                      ],
                      aoMudar: (v) => setState(() => _formato = v),
                    );
                    if (c.maxWidth < 900) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          periodo,
                          const SizedBox(height: EspacosTrato.x4),
                          cidade,
                          const SizedBox(height: EspacosTrato.x3),
                          formato,
                        ],
                      );
                    }
                    // Período à esquerda; cidade e formato dividem o resto, alinhados pelo topo dos campos.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        periodo,
                        const SizedBox(width: EspacosTrato.x4),
                        Expanded(child: cidade),
                        const SizedBox(width: EspacosTrato.x3),
                        Expanded(child: formato),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: EspacosTrato.intervaloCartoes),
              const BannerInfo(
                'CSV em UTF-8 com BOM: abre direto no Excel em português. Colunas com CPF ou outro dado pessoal '
                'só aparecem para papéis autorizados.',
              ),
              const SizedBox(height: EspacosTrato.intervaloCartoes),
              LayoutBuilder(
                builder: (context, c) {
                  final colunas = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
                  final largura = (c.maxWidth - (colunas - 1) * EspacosTrato.intervaloCartoes) / colunas;
                  return Wrap(
                    spacing: EspacosTrato.intervaloCartoes,
                    runSpacing: EspacosTrato.intervaloCartoes,
                    children: [
                      for (final r in relatorios)
                        SizedBox(
                          width: largura,
                          child: CartaoSecao(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.$2, style: TipografiaTrato.secao),
                                const SizedBox(height: EspacosTrato.x1),
                                Text(r.$3, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo)),
                                const SizedBox(height: EspacosTrato.x2),
                                Text(r.$4, style: TipografiaTrato.legenda),
                                const SizedBox(height: EspacosTrato.x4),
                                BotaoTrato.primario(
                                  'Exportar CSV',
                                  icone: IconesTrato.exportar,
                                  aoPressionar: _gerando == null ? () => _exportar(r.$1, r.$2) : null,
                                  carregando: _gerando == r.$1,
                                  rotuloCarregando: 'Gerando',
                                ),
                                if (_gerando == r.$1)
                                  const Padding(
                                    padding: EdgeInsets.only(top: EspacosTrato.x2),
                                    child: Text('Gerando em segundo plano. Avisamos quando estiver pronto.'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (podeAuditoria) ...[
                const SizedBox(height: EspacosTrato.x5),
                Text('Exportações recentes', style: TipografiaTrato.secao),
                const SizedBox(height: EspacosTrato.x3),
                SizedBox(
                  height: 280,
                  child: CarregaDados<PaginaAuditoria>(
                    key: ValueKey('exportacoes-$_versaoHistorico'),
                    carregar: () => context.api.listarAuditoria(acao: 'relatorio.', limite: 10),
                    estaVazio: (p) => p.itens.isEmpty,
                    mensagemVazia: 'Nenhuma exportação ainda',
                    detalheVazio: 'As exportações feitas aparecem aqui, com quem exportou e os filtros.',
                    esqueleto: const EsqueletoLista(linhas: 2),
                    construir: (context, p, _) => ListView.separated(
                      itemCount: p.itens.length,
                      separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
                      itemBuilder: (context, i) {
                        final e = p.itens[i];
                        final d = e.detalhes;
                        final filtros = [
                          if (d['inicio'] != null && d['fim'] != null) '${_br(d['inicio'])} a ${_br(d['fim'])}',
                          'todas as cidades',
                        ].join(' · ');
                        return CartaoLista(
                          titulo: descreverAcao(e),
                          linhas: [
                            '${descreverAtor(e)} · ${formatarData(e.ocorridaEm)}',
                            'Filtros: $filtros',
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _br(Object? iso) {
    final d = DateTime.tryParse('$iso');
    return d == null ? '$iso' : formatarDia(d);
  }
}
