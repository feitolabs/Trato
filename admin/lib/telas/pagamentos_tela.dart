import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.3 — pagamentos e conciliação. SOMENTE LEITURA (D15, RN-06): sem saldo próprio e sem saque.
/// Mostra o espelho do que o provedor de pagamento confirmou.
class PagamentosTela extends StatefulWidget {
  const PagamentosTela({super.key});

  @override
  State<PagamentosTela> createState() => _PagamentosTelaState();
}

class _PagamentosTelaState extends State<PagamentosTela> {
  PeriodoSelecionado _periodo = const PeriodoSelecionado.dias(30);
  int _versao = 0;

  static (String, Tom) chip(StatusProvedor s) => switch (s) {
        StatusProvedor.aguardandoConfirmacao => ('Em andamento', Tom.alerta),
        StatusProvedor.confirmado => ('Confirmado', Tom.ok),
        StatusProvedor.falhou => ('Falhou', Tom.erro),
        StatusProvedor.reembolsado => ('Reembolsado', Tom.info),
        StatusProvedor.reembolsadoParcial => ('Reembolsado em parte', Tom.info),
      };

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Pagamentos e conciliação',
          subtitulo: 'Extrato espelho do provedor de pagamento',
          acoes: [FiltroPeriodo(selecionado: _periodo, aoMudar: (p) => setState(() => _periodo = p))],
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsivo.margemLateral(FaixaPainel.de(context))),
          child: const BannerInfo(
            'O Trato não guarda saldo nem faz saque. Esta tela mostra o que o provedor confirmou; '
            'cobranças e repasses são criados lá.',
            titulo: 'Somente leitura.',
            icone: Icons.visibility_outlined,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Expanded(
          child: CarregaDados<(ResumoConciliacao, List<LancamentoEspelho>)>(
            key: ValueKey('${_periodo.hashCode}#$_versao'),
            carregar: () async {
              final dias = _periodo.diasAteHoje();
              final r = await api.resumoConciliacao(dias: dias);
              final e = await api.extrato(dias: dias);
              return (r, [for (final l in e) if (_periodo.contem(l.data)) l]);
            },
            estaVazio: (d) => d.$2.isEmpty,
            mensagemVazia: 'Nenhum lançamento no extrato.',
            detalheVazio: 'Quando o provedor confirmar uma cobrança, ela aparece aqui.',
            construir: (context, dados, recarregar) => _Conteudo(
              resumo: dados.$1,
              extrato: dados.$2,
              aoConciliar: () => setState(() => _versao++),
            ),
          ),
        ),
      ],
    );
  }
}

class _Conteudo extends StatefulWidget {
  const _Conteudo({required this.resumo, required this.extrato, required this.aoConciliar});
  final ResumoConciliacao resumo;
  final List<LancamentoEspelho> extrato;
  final VoidCallback aoConciliar;

  @override
  State<_Conteudo> createState() => _ConteudoState();
}

class _ConteudoState extends State<_Conteudo> {
  String? _tipo;
  String? _status;

  Future<void> _conciliar(LancamentoEspelho l) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Conciliar a divergência do pedido ${l.pedido}?',
      descricao: 'A divergência fica marcada como conciliada. Nenhum valor é movimentado: só o registro muda.',
      rotuloConfirmar: 'Conciliar',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => api.conciliarDivergencia(l.id, motivo: motivo),
      sucesso: 'Divergência conciliada.',
    );
    if (ok) widget.aoConciliar();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resumo;
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final celular = FaixaPainel.de(context).ehCelular;
    final linhas = [
      for (final l in widget.extrato)
        if ((_tipo == null || l.tipo == _tipo) &&
            (_status == null ||
                (_status == 'divergencia' ? l.divergente : PagamentosStatus.codigo(l.status) == _status)))
          l,
    ];
    final temTaxa = widget.extrato.any((l) => l.taxaCentavos != null);
    final podeConciliar = context.pode(Permissao.pagamentosConciliar);

    return ListView(
      padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x6),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final colunas = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
            final largura = (c.maxWidth - (colunas - 1) * EspacosTrato.intervaloCartoes) / colunas;
            return Wrap(
              spacing: EspacosTrato.intervaloCartoes,
              runSpacing: EspacosTrato.intervaloCartoes,
              children: [
                SizedBox(
                  width: largura,
                  child: CartaoMetrica(
                    titulo: 'Confirmado',
                    valor: formatarReais(r.confirmadoCentavos),
                    subtitulo: '${formatarMilhar(r.cobrancas)} cobranças',
                  ),
                ),
                SizedBox(
                  width: largura,
                  child: CartaoMetrica(
                    titulo: 'Reembolsado',
                    valor: formatarReais(r.estornadoCentavos),
                    subtitulo: '${formatarMilhar(r.reembolsos)} reembolsos',
                  ),
                ),
                SizedBox(
                  width: largura,
                  child: CartaoMetrica(
                    titulo: 'Em andamento',
                    valor: formatarReais(r.emAndamentoCentavos),
                    subtitulo: 'Pagamentos retidos até o serviço acabar',
                  ),
                ),
                SizedBox(
                  width: largura,
                  child: CartaoMetrica(
                    titulo: 'Divergências',
                    valor: '${r.divergencias}',
                    subtitulo: '${formatarReais(r.valorDivergenteCentavos)} a conciliar',
                    tom: r.divergencias > 0 ? Tom.alerta : Tom.neutro,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text('Atualizado em ${formatarData(r.atualizadoEm)}', style: TipografiaTrato.legenda),
        const SizedBox(height: EspacosTrato.x5),
        Row(
          children: [
            Expanded(child: Text('Extrato', style: TipografiaTrato.secao)),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        BarraFiltros(
          filtros: [
            DropdownButtonFormField<String?>(
                key: ValueKey('tipo-$_tipo'),
                initialValue: _tipo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'Cobrança', child: Text('Cobrança')),
                  DropdownMenuItem(value: 'Repasse', child: Text('Repasse')),
                  DropdownMenuItem(value: 'Reembolso', child: Text('Reembolso')),
                  DropdownMenuItem(value: 'Taxa', child: Text('Taxa')),
                ],
                onChanged: (v) => setState(() => _tipo = v),
              ),
            DropdownButtonFormField<String?>(
                key: ValueKey('status-$_status'),
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'confirmado', child: Text('Confirmado')),
                  DropdownMenuItem(value: 'andamento', child: Text('Em andamento')),
                  DropdownMenuItem(value: 'reembolsado', child: Text('Reembolsado')),
                  DropdownMenuItem(value: 'divergencia', child: Text('Divergência')),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (linhas.isEmpty)
          const Padding(padding: EdgeInsets.all(EspacosTrato.x6), child: EstadoVazio('Nada com esses filtros.'))
        else
          // A tabela precisa de ~960 px; abaixo disso (celular, tablet, janela estreita) vira cartões.
          LayoutBuilder(
            builder: (context, c) {
              if (celular || c.maxWidth < 960) {
                return Column(
                  children: [
                    for (final l in linhas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                        child: _CartaoLancamento(l, podeConciliar: podeConciliar, aoConciliar: () => _conciliar(l)),
                      ),
                  ],
                );
              }
              return CartaoSecao(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _CabecalhoTabela(temTaxa: temTaxa),
                    for (final l in linhas)
                      _LinhaTabela(
                        l,
                        temTaxa: temTaxa,
                        podeConciliar: podeConciliar,
                        aoConciliar: () => _conciliar(l),
                      ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          'Uma divergência só fica conciliada com motivo registrado. Taxa e líquido aparecem em cada pedido.',
          style: TipografiaTrato.legenda,
        ),
      ],
    );
  }
}

/// Código do filtro de status de um lançamento.
abstract final class PagamentosStatus {
  static String codigo(StatusProvedor s) => switch (s) {
        StatusProvedor.confirmado => 'confirmado',
        StatusProvedor.aguardandoConfirmacao => 'andamento',
        StatusProvedor.reembolsado || StatusProvedor.reembolsadoParcial => 'reembolsado',
        StatusProvedor.falhou => 'andamento',
      };
}

const _flex = [13, 11, 13, 15, 14, 12, 11, 14, 10];

class _CabecalhoTabela extends StatelessWidget {
  const _CabecalhoTabela({required this.temTaxa});
  final bool temTaxa;

  @override
  Widget build(BuildContext context) {
    Widget c(String t, int i, {bool direita = false}) => Expanded(
          flex: _flex[i],
          child: Text(t, textAlign: direita ? TextAlign.right : TextAlign.left, style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
      child: Row(
        children: [
          c('Data', 0),
          c('Tipo', 1),
          c('Pedido', 2),
          c('ID no provedor', 3),
          c('Status', 4),
          c('Valor', 5, direita: true),
          if (temTaxa) c('Taxa Trato', 6, direita: true),
          if (temTaxa) c('Líquido profissional', 7, direita: true),
          c('Ações', 8, direita: true),
        ],
      ),
    );
  }
}

class _LinhaTabela extends StatelessWidget {
  const _LinhaTabela(this.l, {required this.temTaxa, required this.podeConciliar, required this.aoConciliar});
  final LancamentoEspelho l;
  final bool temTaxa;
  final bool podeConciliar;
  final VoidCallback aoConciliar;

  @override
  Widget build(BuildContext context) {
    final (texto, tom) = _PagamentosTelaState.chip(l.status);
    Widget c(Widget w, int i) => Expanded(flex: _flex[i], child: w);
    Widget num(String t, int i) => c(
          Text(t, textAlign: TextAlign.right, style: TipografiaTrato.numeroTabular),
          i,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
      child: Row(
        children: [
          c(Text(formatarData(l.data), style: TipografiaTrato.corpo), 0),
          c(Text(l.tipo, style: TipografiaTrato.corpo), 1),
          c(Text(l.pedido, style: TipografiaTrato.corpoForte), 2),
          c(Text(l.refProvedor, style: TipografiaTrato.corpo, overflow: TextOverflow.ellipsis), 3),
          c(
            Align(
              alignment: Alignment.centerLeft,
              child: l.divergente
                  ? const ChipEstado('Divergência', tom: Tom.erro)
                  : ChipEstado(texto, tom: tom),
            ),
            4,
          ),
          num(formatarReais(l.valorCentavos), 5),
          if (temTaxa) num(l.taxaCentavos == null ? '—' : formatarReais(l.taxaCentavos!), 6),
          if (temTaxa) num(l.liquidoCentavos == null ? '—' : formatarReais(l.liquidoCentavos!), 7),
          c(
            Align(
              alignment: Alignment.centerRight,
              child: l.divergente && podeConciliar
                  ? BotaoTrato.link('Conciliar', aoPressionar: aoConciliar)
                  : const SizedBox.shrink(),
            ),
            8,
          ),
        ],
      ),
    );
  }
}

class _CartaoLancamento extends StatelessWidget {
  const _CartaoLancamento(this.l, {required this.podeConciliar, required this.aoConciliar});
  final LancamentoEspelho l;
  final bool podeConciliar;
  final VoidCallback aoConciliar;

  @override
  Widget build(BuildContext context) {
    final (texto, tom) = _PagamentosTelaState.chip(l.status);
    return CartaoLista(
      titulo: '${l.tipo} · ${l.pedido}',
      linhas: [
        formatarData(l.data),
        l.refProvedor,
        if (l.taxaCentavos != null) 'Taxa Trato ${formatarReais(l.taxaCentavos!)}',
        if (l.liquidoCentavos != null) 'Líquido profissional ${formatarReais(l.liquidoCentavos!)}',
      ],
      chips: [
        l.divergente ? const ChipEstado('Divergência', tom: Tom.erro) : ChipEstado(texto, tom: tom),
        if (l.divergente && podeConciliar) BotaoTrato.link('Conciliar', aoPressionar: aoConciliar),
      ],
      acoes: [Text(formatarReais(l.valorCentavos), style: TipografiaTrato.numeroTabular.copyWith(fontWeight: FontWeight.w700))],
    );
  }
}
