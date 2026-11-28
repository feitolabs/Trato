import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'compensacoes_modal.dart';

const _status = {'aberta': 'Aberta', 'quitada': 'Quitada', 'cancelada': 'Cancelada'};

const _origens = {
  'disputa': 'Decisão de disputa',
  'disputa_contestacao': 'Decisão mudada por contestação',
  'regresso': 'Regresso',
  // Termos 6.9: a parte do material já liberada ao profissional. Não tem disputa.
  'nota_material_contestacao': 'Estorno de material contestado',
};

/// Textos da dívida que o servidor marca como `suspensa` (Termos 8.7). O que fazer vem de `revisao`.
const kDividaSuspensa = 'Uma decisão posterior baixou o reembolso: por enquanto nada é descontado desta dívida.';

const kRevisaoReducao = 'Uma decisão posterior baixou o reembolso e esta dívida precisa ser reduzida. O caminho '
    'é "Reduzir": não cancele para registrar de novo.';

const kReducaoNaoLiberada = 'O servidor não libera a redução agora, para você ou para esta dívida. Não cancele '
    'para registrar de novo.';

const kRevisaoReversao = 'A decisão posterior não deixa valor para esta dívida. O caminho é cancelar: o Trato '
    'assume o valor inteiro.';

const kRevisaoAnalisar = 'A decisão baixou, mas esta dívida ainda cabe na nova decisão: não há redução '
    'obrigatória. Precisa de análise do financeiro. Cancelar faz o Trato assumir tudo.';

const kRevisaoDesconhecida = 'O servidor marcou uma revisão que este painel não reconhece. Leve ao financeiro.';

/// Suspensa sem `revisao`: o servidor não indica redução nem cancelamento.
const kTituloSuspensaSemRevisao = 'Suspensa: analisar com o financeiro';

const kSuspensaSemRevisao = 'Por enquanto nada é descontado desta dívida. Cancelar faz o Trato assumir tudo.';

bool _suspensaSemRevisao(Compensacao c) => c.suspensa && c.revisao == null;

String textoDaRevisao(Compensacao c) => switch (c.revisao) {
      'reducao' => c.podeReduzir ? kRevisaoReducao : '$kRevisaoReducao $kReducaoNaoLiberada',
      'reversao' => kRevisaoReversao,
      'analisar' => kRevisaoAnalisar,
      _ => kRevisaoDesconhecida,
    };

const kCancelarComReducaoPendente = 'ATENÇÃO: a revisão indica reduzir, não cancelar. Ao cancelar, o Trato assume '
    'o valor INTEIRO e depois não dá para registrar o valor menor.';

const kEfeitoDoCancelamento = 'O Trato assume o valor inteiro desta compensação. O estorno ao cliente não é '
    'desfeito e nenhuma dívida menor é criada.';

const kEfeitoDaReducao = 'Não há novo estorno ao cliente. O Trato assume a diferença e o profissional passa a '
    'dever o novo valor. Se já foi descontado mais que isso, o excesso volta a ele, que é avisado. '
    'Não dá para desfazer.';

(String, Tom) _chip(String s) => (
      _status[s] ?? s,
      switch (s) { 'aberta' => Tom.alerta, 'quitada' => Tom.ok, _ => Tom.neutro },
    );

/// Compensações (Termos 8.6): reembolso descontado de repasses futuros do profissional. O painel
/// não calcula nada: valor, descontado, restante e devolvido vêm do backend.
class CompensacoesTela extends StatefulWidget {
  const CompensacoesTela({super.key});

  @override
  State<CompensacoesTela> createState() => _CompensacoesTelaState();
}

class _CompensacoesTelaState extends State<CompensacoesTela> {
  String _profissional = '';
  String _pedido = '';
  String? _situacao;
  bool _revisaoPendente = false;
  int _versao = 0;

  Future<void> _registrar() async {
    await abrirRegistroDeCompensacao(context);
    // Mesmo em erro ou desistência a lista é relida: o servidor é quem sabe o que ficou.
    if (mounted) setState(() => _versao++);
  }

  Widget _campo(String rotulo, ValueChanged<String> aoBuscar) => SizedBox(
        width: 230,
        child: TextField(
          decoration: InputDecoration(labelText: rotulo, helperText: 'Enter para buscar'),
          onSubmitted: (v) => setState(() => aoBuscar(v.trim())),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          _campo('Código do profissional', (v) => _profissional = v),
          _campo('Código do pedido', (v) => _pedido = v),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              initialValue: _situacao,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in _status.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _situacao = v),
            ),
          ),
          FilterChip(
            label: const Text('Revisão pendente'),
            selected: _revisaoPendente,
            onSelected: (v) => setState(() => _revisaoPendente = v),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Compensações',
          subtitulo: 'Reembolso descontado de repasses futuros (Termos 8.6)',
          acoes: [BotaoTrato.primario('Registrar compensação', aoPressionar: _registrar)],
        ),
        Expanded(
          child: FilaRemota<Compensacao>(
            key: ValueKey('fila-compensacoes-$_versao'),
            filtro: (_profissional, _pedido, _situacao, _revisaoPendente),
            esqueleto: const EsqueletoPagina(),
            chave: (c) => c.id,
            carregar: (deslocamento, limite) => context.api.listarCompensacoes(
              profissionalId: _profissional.isEmpty ? null : _profissional,
              pedidoId: _pedido.isEmpty ? null : _pedido,
              status: _situacao,
              revisaoPendente: _revisaoPendente,
              deslocamento: deslocamento,
              limite: limite,
            ),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<Compensacao>(
                      itens: fila.itens,
                      chave: (c) => c.id,
                      mensagemSemItens: 'Nenhuma compensação com esse filtro.',
                      tituloDetalhe: (c) => formatarReais(c.valorCentavos),
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'compensações'),
                      itemBuilder: (context, c, sel) {
                        final (texto, tom) = _chip(c.status);
                        return CartaoLista(
                          titulo: '${formatarReais(c.valorCentavos)} · falta ${formatarReais(c.restanteCentavos)}',
                          linhas: ['Pedido ${c.pedidoId}', 'Criada em ${formatarData(c.criadaEm)}'],
                          chips: [
                            ChipEstado(texto, tom: tom),
                            if (c.suspensa)
                              ChipEstado(_suspensaSemRevisao(c) ? kTituloSuspensaSemRevisao : 'Desconto suspenso',
                                  tom: Tom.erro),
                            if (c.revisao != null) const ChipEstado('Revisão pendente', tom: Tom.alerta),
                            if (c.avisadoEm == null && c.status == 'aberta')
                              const ChipEstado('Sem aviso', tom: Tom.erro),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, c) =>
                          _DetalheCompensacao(key: ValueKey(c.id), inicial: c, aoMudar: fila.recarregar),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetalheCompensacao extends StatefulWidget {
  const _DetalheCompensacao({super.key, required this.inicial, required this.aoMudar});
  final Compensacao inicial;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheCompensacao> createState() => _DetalheCompensacaoState();
}

class _DetalheCompensacaoState extends State<_DetalheCompensacao> {
  /// O que o servidor devolveu na última ação (não há rota de detalhe).
  Compensacao? _atual;
  bool _enviando = false;
  String? _erro;

  @override
  void didUpdateWidget(covariant _DetalheCompensacao antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.inicial != widget.inicial) _atual = null;
  }

  Future<void> _enviar(Future<(Compensacao, String, bool)> Function() chamada) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final (nova, mensagem, atencao) = await chamada();
      if (mounted) {
        setState(() => _atual = nova);
        mostrarAviso(context, mensagem, erro: atencao);
      }
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      try {
        await widget.aoMudar();
      } catch (_) {
        // A releitura da lista falhou: o resultado da ação já está na tela.
      }
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _avisar(Compensacao c) async {
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Avisar o profissional?',
      texto: 'Ele recebe o aviso da compensação de ${formatarReais(c.valorCentavos)} com o motivo. '
          'Depois do aviso, os próximos repasses podem ser descontados.',
      verbo: 'Enviar aviso',
    );
    if (!ok || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final r = await api.avisarCompensacao(c.id);
      return (
        r.compensacao,
        r.avisado ? 'Profissional avisado.' : 'O aviso não saiu. Sem aviso, nada é descontado.',
        !r.avisado,
      );
    });
  }

  Future<void> _reduzir(Compensacao c) async {
    final contestacao = c.revisaoContestacaoId!;
    final maximo = c.reducaoMaximaCentavos!;
    final valor = TextEditingController();
    int? centavos() {
      final v = lerReaisEmCentavos(valor.text);
      return v == null || v <= 0 || v > maximo ? null : v;
    }

    // O máximo é o que o servidor informou; ele confere de novo ao gravar.
    final dados = await pedirFormulario<(String, int, String)>(
      context,
      titulo: 'Reduzir a compensação?',
      consequencia: '$kEfeitoDaReducao Valor que vale hoje: ${formatarReais(c.valorCentavos)}. '
          'Já descontado: ${formatarReais(c.compensadoCentavos)}.',
      rotuloConfirmar: 'Reduzir compensação',
      campos: (ctx, rebuild) => Column(
        children: [
          Linha('Contestação (informada pelo servidor)', contestacao),
          Linha('Novo valor máximo', formatarReais(maximo)),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: valor,
            maxLength: 16,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => rebuild(),
            decoration: InputDecoration(
              labelText: 'Novo valor da compensação',
              prefixText: 'R\$ ',
              counterText: '',
              helperText: centavos() == null ? 'Use vírgula nos centavos.' : 'Vai como ${formatarReais(centavos()!)}',
              errorText: valor.text.trim().isEmpty || centavos() != null
                  ? null
                  : (lerReaisEmCentavos(valor.text) ?? 0) > maximo
                      ? 'Passa do máximo de ${formatarReais(maximo)}'
                      : 'Informe um valor válido maior que zero',
              errorMaxLines: 2,
            ),
          ),
        ],
      ),
      camposValidos: () => centavos() != null,
      resultado: (motivo) => (contestacao, centavos()!, motivo),
    );
    if (dados == null || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final r = await api.reduzirCompensacao(c.id,
          contestacaoId: dados.$1, novoValorCentavos: dados.$2, motivo: dados.$3);
      final devolvido = 'Devolvido ao profissional: ${formatarReais(r.devolvidoCentavos)}.';
      return (
        r.compensacao,
        r.resultado == 'ja_reduzida'
            ? 'Esta redução já tinha sido feita. Nada novo foi gravado. $devolvido'
            : 'Compensação reduzida para ${formatarReais(r.compensacao.valorCentavos)}, sem novo estorno ao cliente. $devolvido',
        false,
      );
    });
  }

  Future<void> _cancelar(Compensacao c) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Cancelar a compensação?',
      descricao: [
        if (c.revisao == 'reducao') kCancelarComReducaoPendente,
        if (c.revisao == 'analisar') kRevisaoAnalisar,
        if (c.revisao == 'reversao') kRevisaoReversao,
        if (_suspensaSemRevisao(c)) '$kTituloSuspensaSemRevisao. $kSuspensaSemRevisao',
        if (c.revisao == null && !c.suspensa) 'Use quando a contestação do profissional foi aceita.',
        'O que já foi descontado (${formatarReais(c.compensadoCentavos)} até agora) volta ao profissional, que é avisado.',
        kEfeitoDoCancelamento,
        'Valor desta compensação: ${formatarReais(c.valorCentavos)}.',
        kRecusaDepoisDoCancelamento,
        'Não dá para desfazer.',
      ].join(' '),
      rotuloConfirmar: 'Cancelar compensação',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final r = await api.cancelarCompensacao(c.id, motivo: motivo);
      return (
        r.compensacao,
        r.resultado == 'ja_cancelada'
            ? 'Esta compensação já estava cancelada. Devolvido: ${formatarReais(r.devolvidoCentavos)}.'
            : 'Compensação cancelada. Devolvido ao profissional: ${formatarReais(r.devolvidoCentavos)}.',
        false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _atual ?? widget.inicial;
    final (texto, tom) = _chip(c.status);
    final semAviso = c.avisadoEm == null && c.status == 'aberta';
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(formatarReais(c.valorCentavos), style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(spacing: EspacosTrato.x2, children: [
          ChipEstado(texto, tom: tom),
          if (c.suspensa && !_suspensaSemRevisao(c)) const ChipEstado('Desconto suspenso', tom: Tom.erro),
        ]),
        const SizedBox(height: EspacosTrato.x3),
        if (c.reduzidoCentavos > 0) ...[
          if (c.valorOriginalCentavos case final original?) Linha('Valor original', formatarReais(original)),
          Linha('Reduzido', formatarReais(c.reduzidoCentavos)),
          Linha('Vale hoje', formatarReais(c.valorCentavos)),
          Linha('Devolvido ao profissional pela redução', formatarReais(c.devolvidoReducaoCentavos)),
        ],
        Linha('Já descontado', formatarReais(c.compensadoCentavos)),
        Linha('Falta descontar', formatarReais(c.restanteCentavos)),
        Linha('Pedido', c.pedidoId),
        Linha('Origem', _origens[c.origem] ?? c.origem),
        Linha('Motivo (o profissional lê)', c.motivo),
        Linha('Criada em', formatarData(c.criadaEm)),
        Linha('Aviso', c.avisadoEm == null ? 'Não enviado' : 'Enviado em ${formatarData(c.avisadoEm!)}'),
        if (c.canceladaEm != null) Linha('Cancelada em', formatarData(c.canceladaEm!)),
        if (c.motivoCancelamento != null) Linha('Motivo do cancelamento', c.motivoCancelamento!),
        if (semAviso) ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo('Sem aviso, nada é descontado.', tom: Tom.alerta),
        ],
        if (c.suspensa) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(
            _suspensaSemRevisao(c) ? kSuspensaSemRevisao : kDividaSuspensa,
            titulo: _suspensaSemRevisao(c) ? '$kTituloSuspensaSemRevisao.' : 'Desconto suspenso.',
            tom: Tom.alerta,
          ),
        ],
        if (c.revisao != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(textoDaRevisao(c), titulo: 'Revisão pendente.', tom: Tom.alerta),
        ],
        if (c.status == 'cancelada') ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo(kRecusaDepoisDoCancelamento, titulo: 'Depois do cancelamento.', tom: Tom.alerta),
        ],
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            if (semAviso && context.pode(Permissao.regressoPropor))
              BotaoTrato.primario('Avisar profissional', aoPressionar: _enviando ? null : () => _avisar(c)),
            if (!_suspensaSemRevisao(c) && c.podeReduzir && c.revisaoContestacaoId != null && c.reducaoMaximaCentavos != null)
              BotaoTrato.primario('Reduzir', aoPressionar: _enviando ? null : () => _reduzir(c)),
            if (c.podeCancelar)
              BotaoTrato.destrutivo('Cancelar compensação', aoPressionar: _enviando ? null : () => _cancelar(c)),
          ],
        ),
        if (c.status != 'cancelada' && !c.podeCancelar)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Text('O servidor não libera cancelar para você. Reduzir e cancelar são só para líder de suporte e administrador.', style: TipografiaTrato.legenda),
          ),
      ],
    );
  }
}
