import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Abas do financeiro dentro de Pagamentos: alertas, contestações, conciliação do dia, eventos do
/// provedor e fechamento do mês. Tudo é leitura ou registro: nada aqui move dinheiro nem marca
/// "pago" (D13). O backend decide; o painel pede e mostra.

EdgeInsets _margens(BuildContext context) {
  final m = Responsivo.margemLateral(FaixaPainel.de(context));
  return EdgeInsets.fromLTRB(m, EspacosTrato.x4, m, EspacosTrato.x6);
}

Widget _secao(String titulo, List<Widget> itens, {String? vazio}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: EspacosTrato.x5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x3),
        if (itens.isEmpty && vazio != null)
          Text(vazio, style: TipografiaTrato.legenda)
        else
          for (final w in itens) Padding(padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes), child: w),
      ],
    ),
  );
}

String tipoEventoLegivel(String tipo) => switch (tipo) {
      'payment_intent.succeeded' => 'Pagamento confirmado',
      'payment_intent.payment_failed' => 'Pagamento recusado',
      'charge.refunded' => 'Reembolso',
      'payout.paid' => 'Repasse pago',
      'payout.failed' => 'Repasse recusado pelo banco',
      'transfer.reversed' => 'Transferência desfeita',
      'charge.dispute.created' => 'Contestação aberta',
      'charge.dispute.updated' => 'Contestação atualizada',
      'charge.dispute.closed' => 'Contestação encerrada',
      _ => tipo,
    };

// ---------------------------------------------------------------------------------------------
// Alertas

class AbaAlertasFinanceiros extends StatefulWidget {
  const AbaAlertasFinanceiros({super.key});

  @override
  State<AbaAlertasFinanceiros> createState() => _AbaAlertasFinanceirosState();
}

class _AbaAlertasFinanceirosState extends State<AbaAlertasFinanceiros> {
  Future<void> _consultar(PagamentoParado p) async {
    final api = context.api;
    ConsultaCobranca? r;
    final ok = await executar(context, () async => r = await api.consultarCobranca(p.cobrancaId));
    if (!ok || !mounted || r == null) return;
    final pago = r!.statusNoProvedor == 'paga';
    mostrarAviso(context, pago ? 'O provedor já recebeu.' : 'O provedor ainda não recebeu.', detalhe: r!.orientacao);
  }

  @override
  Widget build(BuildContext context) {
    final podeConsultar = context.pode(Permissao.pagamentosConciliar);
    return CarregaDados<AlertasFinanceiros>(
      carregar: context.api.alertasFinanceiros,
      estaVazio: (a) => a.total == 0 && a.contestacoesEmAberto == 0 && a.provedorLigado,
      mensagemVazia: 'Nada travado no dinheiro.',
      detalheVazio: 'Pagamento sem confirmação, repasse que falhou, estorno não enviado e aviso '
          'para revisar aparecem aqui.',
      construir: (context, a, recarregar) => RefreshIndicator(
        onRefresh: recarregar,
        child: ListView(
          padding: _margens(context),
          children: [
            if (!a.provedorLigado)
              const Padding(
                padding: EdgeInsets.only(bottom: EspacosTrato.x4),
                child: BannerInfo(
                  'Sem o provedor ligado, pagamentos parados e estornos não enviados não aparecem.',
                  titulo: 'Provedor de pagamento não configurado.',
                  tom: Tom.alerta,
                ),
              ),
            if (a.contestacoesEmAberto > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
                child: BannerInfo(
                  a.contestacoesEmAberto == 1
                      ? 'Há 1 contestação de cartão em aberto. Veja a aba Contestações.'
                      : 'Há ${a.contestacoesEmAberto} contestações de cartão em aberto. Veja a aba Contestações.',
                  tom: Tom.alerta,
                  icone: Icons.gavel_outlined,
                ),
              ),
            _secao(
              'Pagamentos sem confirmação',
              [
                for (final p in a.pagamentosParados)
                  CartaoLista(
                    titulo: '${p.pedido} · ${formatarReais(p.valorCentavos)}',
                    linhas: [
                      '${p.meio == 'pix' ? 'Pix' : 'Cartão'} · sem confirmação há ${formatarMilhar(p.minutosParado)} min',
                      'Cobrança ${p.cobrancaId}',
                    ],
                    chips: [
                      p.clienteAvisou
                          ? const ChipEstado('Cliente avisou que pagou', tom: Tom.alerta)
                          : const ChipEstado('Sem aviso do cliente'),
                      // Na linha dos chips (e não à direita) para caber no celular.
                      if (podeConsultar)
                        BotaoTrato.link('Consultar no provedor', aoPressionar: () => _consultar(p)),
                    ],
                  ),
              ],
              vazio: 'Nenhum pagamento parado há mais de ${a.minutosPagamentoParado} min.',
            ),
            _secao(
              'Repasses que falharam',
              [for (final e in a.repassesComFalha) _CartaoRevisao(e, tom: Tom.erro)],
              vazio: 'Nenhum repasse com falha.',
            ),
            _secao(
              'Estornos não enviados ao provedor',
              [
                for (final o in a.estornosPendentes)
                  CartaoLista(
                    titulo: '${o.pedido} · ${formatarReais(o.valorCentavos)}',
                    linhas: ['Pedido de estorno de ${formatarData(o.criadaEm)}', 'Cobrança ${o.cobrancaId}'],
                    chips: const [ChipEstado('O sistema tenta de novo sozinho', tom: Tom.info)],
                  ),
              ],
              vazio: 'Nenhum estorno esperando o provedor.',
            ),
            _secao(
              'Avisos do provedor para revisar',
              [for (final e in a.eventosEmRevisao) _CartaoRevisao(e, tom: Tom.alerta)],
              vazio: 'Nenhum aviso para revisar.',
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoRevisao extends StatelessWidget {
  const _CartaoRevisao(this.e, {required this.tom});
  final EventoEmRevisao e;
  final Tom tom;

  @override
  Widget build(BuildContext context) {
    return CartaoLista(
      titulo: tipoEventoLegivel(e.tipo),
      linhas: [e.motivo, 'Recebido em ${formatarData(e.recebidoEm)} · ${e.eventoId}'],
      chips: [ChipEstado(tom == Tom.erro ? 'Precisa de ação' : 'Revisar', tom: tom)],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Contestações

(String, Tom) chipContestacao(String status) => switch (status) {
      'aberta' => ('Mandar provas', Tom.erro),
      'em_analise' => ('Em análise no banco', Tom.alerta),
      'ganha' => ('Ganha', Tom.ok),
      'perdida' => ('Perdida', Tom.erro),
      _ => ('Encerrada', Tom.neutro),
    };

class AbaContestacoes extends StatefulWidget {
  const AbaContestacoes({super.key});

  @override
  State<AbaContestacoes> createState() => _AbaContestacoesState();
}

class _AbaContestacoesState extends State<AbaContestacoes> {
  String _filtro = 'em_aberto';

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<ContestacaoCartao>>(
      carregar: () => context.api.listarContestacoes(),
      construir: (context, todas, recarregar) {
        final abertas = todas.where((c) => c.emAberto).length;
        final lista = _filtro == 'em_aberto' ? todas.where((c) => c.emAberto).toList() : todas;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: EspacosTrato.x4),
            FiltroStatus(
              opcoes: [('em_aberto', 'Em aberto', abertas), ('todas', 'Todas', todas.length)],
              selecionado: _filtro,
              aoMudar: (v) => setState(() => _filtro = v),
            ),
            Expanded(
              child: ListView(
                padding: _margens(context).copyWith(top: 0),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: EspacosTrato.x4),
                    child: BannerInfo(
                      'As provas são enviadas no painel do provedor de pagamento, antes do prazo. '
                      'Se a contestação for perdida, o valor volta ao cliente e sai do Trato; a taxa não volta.',
                      titulo: 'Contestação de cartão.',
                    ),
                  ),
                  if (lista.isEmpty)
                    EstadoVazio(
                      _filtro == 'em_aberto' ? 'Nenhuma contestação em aberto.' : 'Nenhuma contestação.',
                      detalhe: 'Quando um cliente contestar uma compra no cartão, ela aparece aqui.',
                    ),
                  for (final c in lista)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                      child: _CartaoContestacao(c),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CartaoContestacao extends StatelessWidget {
  const _CartaoContestacao(this.c);
  final ContestacaoCartao c;

  @override
  Widget build(BuildContext context) {
    final (texto, tom) = chipContestacao(c.status);
    final prazo = c.prazoProvas;
    final horas = c.horasParaPrazo;
    return CartaoLista(
      titulo: c.pedido,
      linhas: [
        c.motivo,
        if (c.emAberto && prazo != null)
          'Prazo para provas: ${formatarData(prazo)}'
              '${horas == null ? '' : horas < 0 ? ' (vencido)' : ' (faltam ${formatarMilhar(horas)} h)'}',
        if (!c.emAberto && c.encerradaEm != null) 'Encerrada em ${formatarData(c.encerradaEm!)}',
        'Aberta em ${formatarData(c.abertaEm)} · ${c.id}',
      ],
      chips: [
        ChipEstado(texto, tom: tom),
        if (c.emAberto && horas != null && horas <= 48 && horas >= 0)
          const ChipEstado('Prazo perto', tom: Tom.erro),
        if (c.repasseLiberado) const ChipEstado('Repasse já liberado', tom: Tom.alerta),
      ],
      acoes: [
        Text(formatarReais(c.valorCentavos), style: TipografiaTrato.numeroTabular.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Conciliação do dia

(String, Tom) chipSituacao(String situacao) => switch (situacao) {
      'confere' => ('Confere', Tom.ok),
      'so_no_provedor' => ('Só no provedor', Tom.erro),
      'so_no_trato' => ('Só no Trato', Tom.erro),
      _ => ('Valor diferente', Tom.alerta),
    };

String _tipoConciliacao(String tipo) => switch (tipo) {
      'cobranca' => 'Cobrança',
      'estorno' => 'Estorno',
      'contestacao' => 'Contestação',
      _ => tipo,
    };

class AbaConciliacaoDia extends StatefulWidget {
  const AbaConciliacaoDia({super.key, this.hoje});

  /// Só nos testes: o "hoje" fixo.
  final DateTime? hoje;

  @override
  State<AbaConciliacaoDia> createState() => _AbaConciliacaoDiaState();
}

class _AbaConciliacaoDiaState extends State<AbaConciliacaoDia> {
  late final DateTime _hoje = widget.hoje ?? DateTime.now();
  late DateTime _dia = DateTime(_hoje.year, _hoje.month, _hoje.day).subtract(const Duration(days: 1));
  bool _tudo = false;

  Future<void> _escolherDia() async {
    final escolhido = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2026),
      lastDate: DateTime(_hoje.year, _hoje.month, _hoje.day),
      helpText: 'Dia para conferir',
    );
    if (escolhido != null) setState(() => _dia = escolhido);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _margens(context),
      children: [
        Wrap(
          spacing: EspacosTrato.x3,
          runSpacing: EspacosTrato.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Dia ${formatarDia(_dia)} (horário de Brasília)', style: TipografiaTrato.corpoForte),
            BotaoTrato.secundario('Trocar o dia', icone: Icons.event_outlined, aoPressionar: _escolherDia),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        CarregaDados<ConciliacaoDia>(
          key: ValueKey(_dia),
          carregar: () => context.api.conciliacaoDoDia(_dia),
          esqueleto: const EsqueletoCartoes(quantidade: 3),
          construir: (context, r, _) {
            final linhas = _tudo ? r.linhas : r.divergencias;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                r.confere
                    ? const BannerInfo('O extrato do provedor bate com o que o Trato registrou.', titulo: 'Confere.', tom: Tom.ok)
                    : BannerInfo(
                        '${r.divergencias.length} ${r.divergencias.length == 1 ? 'diferença' : 'diferenças'} entre o '
                        'provedor e o Trato. Contestação em aberto aparece aqui até ser encerrada.',
                        titulo: 'Não confere.',
                        tom: Tom.erro,
                      ),
                const SizedBox(height: EspacosTrato.x4),
                LayoutBuilder(builder: (context, c) {
                  final colunas = c.maxWidth >= 720 ? 3 : 1;
                  final largura = (c.maxWidth - (colunas - 1) * EspacosTrato.intervaloCartoes) / colunas;
                  return Wrap(
                    spacing: EspacosTrato.intervaloCartoes,
                    runSpacing: EspacosTrato.intervaloCartoes,
                    children: [
                      SizedBox(
                        width: largura,
                        child: CartaoMetrica(titulo: 'O provedor recebeu', valor: formatarReais(r.cobradoProvedorCentavos)),
                      ),
                      SizedBox(
                        width: largura,
                        child: CartaoMetrica(titulo: 'O Trato registrou', valor: formatarReais(r.cobradoTratoCentavos)),
                      ),
                      SizedBox(
                        width: largura,
                        child: CartaoMetrica(
                          titulo: 'Custo do provedor',
                          valor: formatarReais(r.taxasProvedorCentavos),
                          subtitulo: 'Taxas cobradas no dia',
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: EspacosTrato.x5),
                Row(
                  children: [
                    Expanded(child: Text(_tudo ? 'Tudo do dia' : 'Diferenças', style: TipografiaTrato.secao)),
                    BotaoTrato.link(
                      _tudo ? 'Só as diferenças' : 'Ver tudo do dia',
                      aoPressionar: () => setState(() => _tudo = !_tudo),
                    ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x3),
                if (linhas.isEmpty) Text('Nada para mostrar.', style: TipografiaTrato.legenda),
                for (final l in linhas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                    child: CartaoLista(
                      titulo: '${_tipoConciliacao(l.tipo)} · ${l.pedido ?? l.referencia}',
                      linhas: [
                        'Provedor ${formatarReais(l.valorProvedorCentavos)} · Trato ${formatarReais(l.valorTratoCentavos)}',
                        if (l.diferencaCentavos != 0) 'Diferença ${formatarReais(l.diferencaCentavos)}',
                        if (l.pedido != null) 'Referência ${l.referencia}',
                      ],
                      chips: [ChipEstado(chipSituacao(l.situacao).$1, tom: chipSituacao(l.situacao).$2)],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Eventos do provedor

class AbaEventosProvedor extends StatelessWidget {
  const AbaEventosProvedor({super.key});

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<EventoProvedor>>(
      carregar: () => context.api.listarEventosProvedor(),
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum aviso do provedor ainda.',
      detalheVazio: 'Cada aviso assinado (pagamento, reembolso, repasse, contestação) aparece aqui.',
      construir: (context, eventos, recarregar) => RefreshIndicator(
        onRefresh: recarregar,
        child: ListView(
          padding: _margens(context),
          children: [
            for (final e in eventos)
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                child: CartaoLista(
                  titulo: tipoEventoLegivel(e.tipo),
                  linhas: [
                    'Recebido em ${formatarData(e.recebidoEm)}',
                    [
                      if (e.referencia != null) e.referencia!,
                      if (e.pedidoId != null) 'pedido ${e.pedidoId!.length > 8 ? e.pedidoId!.substring(0, 8) : e.pedidoId}',
                      e.eventoId,
                    ].join(' · '),
                    if (e.revisao != null) e.revisao!,
                  ],
                  chips: [
                    e.revisao != null
                        ? const ChipEstado('Em revisão', tom: Tom.alerta)
                        : const ChipEstado('Processado', tom: Tom.ok),
                  ],
                  acoes: [
                    if (e.valorCentavos != null)
                      Text(formatarReais(e.valorCentavos!), style: TipografiaTrato.numeroTabular),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Fechamento do mês

const rotulosFechamento = [
  ('cobrancas', 'Cobranças recebidas', false),
  ('cobrado_centavos', 'Recebido de clientes (bruto)', true),
  ('devolvido_centavos', 'Devolvido a clientes', true),
  ('entrada_liquida_centavos', 'Entrada líquida de clientes', true),
  ('receita_taxas_centavos', 'Receita do Trato (taxas)', true),
  ('liberado_profissionais_centavos', 'Liberado aos profissionais', true),
  ('retido_fim_centavos', 'Retido ao fim do mês', true),
  ('a_liberar_fim_centavos', 'A liberar ao fim do mês', true),
  ('contestacoes_perdidas_centavos', 'Contestações perdidas', true),
  ('lancamentos', 'Lançamentos no mês', false),
];

String nomeDoMes(String mes) {
  const nomes = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];
  final partes = mes.split('-');
  final n = int.tryParse(partes.length == 2 ? partes[1] : '') ?? 0;
  if (n < 1 || n > 12) return mes;
  return '${nomes[n - 1]} de ${partes[0]}';
}

class AbaFechamentoMes extends StatefulWidget {
  const AbaFechamentoMes({super.key});

  @override
  State<AbaFechamentoMes> createState() => _AbaFechamentoMesState();
}

class _AbaFechamentoMesState extends State<AbaFechamentoMes> {
  String? _mes;
  int _versao = 0;

  Future<void> _fechar(FechamentoMes f) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Fechar ${nomeDoMes(f.mes)}?',
      descricao: 'Os totais ficam gravados e nada mais entra neste mês: correções viram estorno no mês '
          'corrente. Não dá para desfazer.',
      rotuloConfirmar: 'Fechar o mês',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(context, () => api.fecharMes(f.mes, motivo: motivo), sucesso: 'Mês fechado.');
    if (ok) setState(() => _versao++);
  }

  Future<void> _exportar(String mes) async {
    final api = context.api;
    ArquivoPronto? arquivo;
    final ok = await executar(context, () async => arquivo = await api.exportarFechamento(mes));
    if (!ok || arquivo == null) return;
    await launchUrl(Uri.parse(arquivo!.url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final podeFechar = context.pode(Permissao.pagamentosConciliar);
    final podeExportar = context.pode(Permissao.relatoriosExportar);
    return CarregaDados<List<MesFinanceiro>>(
      key: ValueKey('meses-$_versao'),
      carregar: () => context.api.listarMeses(),
      estaVazio: (m) => m.isEmpty,
      construir: (context, meses, _) {
        // Abre no mês mais recente que já pode ser fechado (ou no atual).
        final padrao = meses.firstWhere((m) => m.podeFechar, orElse: () => meses.first).mes;
        final mes = _mes ?? padrao;
        return ListView(
          padding: _margens(context),
          children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                key: ValueKey('mes-$mes'),
                initialValue: mes,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mês'),
                items: [
                  for (final m in meses)
                    DropdownMenuItem(
                      value: m.mes,
                      child: Text('${nomeDoMes(m.mes)}${m.fechado ? ' · fechado' : ''}'),
                    ),
                ],
                onChanged: (v) => setState(() => _mes = v),
              ),
            ),
            const SizedBox(height: EspacosTrato.x4),
            CarregaDados<FechamentoMes>(
              key: ValueKey('$mes#$_versao'),
              carregar: () => context.api.verFechamento(mes),
              esqueleto: const EsqueletoCartoes(quantidade: 2),
              construir: (context, f, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (f.fechado && f.confere == false)
                    const BannerInfo(
                      'Os números de hoje não batem com o retrato gravado. Algo entrou neste mês depois do '
                      'fechamento: chame o time técnico.',
                      titulo: 'Diferença depois do fechamento.',
                      tom: Tom.erro,
                    )
                  else if (f.fechado)
                    BannerInfo(
                      'Fechado em ${f.fechadoEm == null ? '—' : formatarData(f.fechadoEm!)}'
                      '${f.fechadoPorNome == null ? '' : ' por ${f.fechadoPorNome}'}. Nada mais entra neste mês.',
                      titulo: 'Mês fechado.',
                      tom: Tom.ok,
                      icone: Icons.lock_outline,
                    )
                  else
                    BannerInfo(
                      f.podeFechar
                          ? 'Prévia. Confira e feche o mês para o contador.'
                          : 'Prévia. O mês ainda não terminou: só dá para fechar depois do último dia.',
                      titulo: 'Mês aberto.',
                    ),
                  const SizedBox(height: EspacosTrato.x4),
                  CartaoSecao(
                    titulo: 'Totais de ${nomeDoMes(f.mes)}',
                    child: Column(
                      children: [
                        for (final (chave, rotulo, dinheiro) in rotulosFechamento)
                          Linha(
                            rotulo,
                            dinheiro ? formatarReais(f.valores[chave] ?? 0) : formatarMilhar(f.valores[chave] ?? 0),
                          ),
                      ],
                    ),
                  ),
                  if (f.hash != null) ...[
                    const SizedBox(height: EspacosTrato.x2),
                    Text('Registro do fechamento: ${f.hash!.substring(0, 16)}…', style: TipografiaTrato.legenda),
                  ],
                  const SizedBox(height: EspacosTrato.x4),
                  Wrap(
                    spacing: EspacosTrato.x3,
                    runSpacing: EspacosTrato.x2,
                    children: [
                      if (podeFechar && f.podeFechar)
                        BotaoTrato.primario('Fechar o mês', icone: Icons.lock_outline, aoPressionar: () => _fechar(f)),
                      if (podeExportar)
                        BotaoTrato.secundario(
                          'Baixar CSV para o contador',
                          icone: Icons.download_outlined,
                          aoPressionar: () => _exportar(f.mes),
                        ),
                    ],
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  Text(
                    'O custo dos cupons ainda não entra: o pedido não guarda o desconto.',
                    style: TipografiaTrato.legenda,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
