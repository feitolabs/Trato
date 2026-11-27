import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'comprovantes_modal.dart';
import 'provas_modal.dart';

/// Fila de "Cliente ausente" (Termos 7.6 e 7.4). O painel só pede e mostra: prazo, limite de
/// retenção, arrependimento e reembolso são decididos pelo backend, que recusa o que não vale.
class AusenciasTela extends StatelessWidget {
  const AusenciasTela({super.key});

  static (String, Tom) chip(CasoAusencia c, {DateTime? agora}) {
    if (c.contestacaoAberta) return ('Contestação aberta', Tom.erro);
    if (c.esperaConfirmacao) return ('Retenção a confirmar', Tom.alerta);
    if (c.semResposta(agora ?? DateTime.now())) return ('Sem justificativa no prazo', Tom.erro);
    return switch (c.status) {
      CasoAusencia.emAnalise => ('Para analisar', Tom.info),
      CasoAusencia.aguardandoJustificativa => ('Aguardando o cliente', Tom.alerta),
      CasoAusencia.aguardandoEspera => ('Em espera no local', Tom.neutro),
      CasoAusencia.aceita => ('Justificativa aceita', Tom.ok),
      CasoAusencia.recusada => ('Justificativa recusada', Tom.neutro),
      CasoAusencia.expirada => ('Encerrado sem justificativa', Tom.neutro),
      _ => ('Situação não reconhecida', Tom.neutro),
    };
  }

  static String prazo(CasoAusencia c) {
    if (c.contestacaoAberta) return 'Responder contestação até ${formatarData(c.contestacao!.responderAte)}';
    if (c.esperaConfirmacao && c.contestarAte != null) return 'Contestação até ${formatarData(c.contestarAte!)}';
    final ate = c.justificativaAte;
    return ate == null ? 'Sem prazo informado' : 'Prazo do cliente: ${formatarData(ate)}';
  }

  /// Prazo mais antigo primeiro; caso sem prazo vai para o fim.
  static List<CasoAusencia> porPrazo(List<CasoAusencia> casos) {
    final longe = DateTime(9999);
    DateTime limite(CasoAusencia c) =>
        (c.contestacaoAberta
            ? c.contestacao!.responderAte
            : c.esperaConfirmacao
                ? c.contestarAte ?? c.justificativaAte
                : c.justificativaAte) ??
        longe;
    return [...casos]..sort((a, b) => limite(a).compareTo(limite(b)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina('Cliente ausente', subtitulo: 'Casos em aberto, pelo prazo mais próximo'),
        Expanded(
          child: CarregaDados<List<CasoAusencia>>(
            esqueleto: const EsqueletoPagina(),
            atualizarSozinho: true,
            carregar: context.api.listarAusencias,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhum caso de cliente ausente.',
            detalheVazio: 'Quando um profissional registrar "Cliente ausente", o caso aparece aqui.',
            construir: (context, lista, recarregarFila) => MestreDetalhe<CasoAusencia>(
              itens: porPrazo(lista),
              chave: (c) => c.pedidoId,
              tituloDetalhe: (c) => c.pedido,
              itemBuilder: (context, c, sel) {
                final (texto, tom) = chip(c);
                return CartaoLista(
                  titulo: c.pedido,
                  linhas: [
                    if (c.clienteNome != null || c.profissionalNome != null)
                      '${c.clienteNome ?? 'Cliente'} × ${c.profissionalNome ?? 'Profissional'}',
                    prazo(c),
                    'Chegada ${formatarData(c.chegadaEm)}',
                  ],
                  chips: [ChipEstado(texto, tom: tom)],
                  selecionado: sel,
                );
              },
              detalheBuilder: (context, c) => CarregaDados<CasoAusencia>(
                key: ValueKey('ausencia-${c.pedidoId}'),
                esqueleto: const EsqueletoPagina(),
                atualizarSozinho: true,
                carregar: () => context.api.obterAusencia(c.pedidoId),
                construir: (context, caso, recarregar) => DetalheAusencia(
                  key: ValueKey(c.pedidoId),
                  caso: caso,
                  aoMudar: () async {
                    await recarregar();
                    await recarregarFila();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A fila não informa se a conta do cliente está bloqueada: o aviso é sempre condicional.
const kAvisoAceitarBloqueado = 'Se a conta do cliente estiver bloqueada, aceitar a justificativa deixa o pedido '
    'parado, sem nova decisão desta ausência. A fila não informa o bloqueio: confira a conta antes.';

class DetalheAusencia extends StatefulWidget {
  const DetalheAusencia({super.key, required this.caso, required this.aoMudar});

  final CasoAusencia caso;
  final Future<void> Function() aoMudar;

  @override
  State<DetalheAusencia> createState() => _DetalheAusenciaState();
}

class _DetalheAusenciaState extends State<DetalheAusencia> {
  bool? _aceitar;
  final _justificativa = TextEditingController();
  final _valor = TextEditingController();
  final _motivoRetencao = TextEditingController();
  /// Escolhidos na lista do pedido: id e rótulo (os links não ficam aqui).
  Map<String, String> _comprovantes = {};
  bool _tentou = false;
  bool _enviando = false;
  Object? _recusa;

  @override
  void dispose() {
    _justificativa.dispose();
    _valor.dispose();
    _motivoRetencao.dispose();
    _resposta.dispose();
    _novoValor.dispose();
    super.dispose();
  }

  /// Campo vazio = sem retenção. `null` = texto que não é um valor.
  int? get _retencao {
    if (_aceitar != false || _valor.text.trim().isEmpty) return 0;
    return lerReaisEmCentavos(_valor.text);
  }

  bool get _temRetencao => (_retencao ?? 0) > 0;

  List<String> get _listaComprovantes => _comprovantes.keys.toList();

  bool get _justificativaCurta => _justificativa.text.trim().length < kMotivoMinimo;
  bool get _motivoRetencaoCurto => _temRetencao && _motivoRetencao.text.trim().length < kMotivoMinimo;
  bool get _faltaComprovante => _temRetencao && _listaComprovantes.isEmpty;

  Future<void> _escolherComprovantes() async {
    final r = await abrirComprovantes(context, widget.caso.pedidoId, widget.caso.pedido, _comprovantes);
    if (r != null && mounted) setState(() => _comprovantes = r);
  }

  Future<bool> _confirmacao(String titulo, String texto, String verbo, {bool destrutivo = false}) async {
    final r = await mostrarModal<bool>(
      context,
      construir: (ctx) => CorpoModal(
        titulo: titulo,
        consequencia: texto,
        filhos: const [AvisoAuditoria()],
        acoes: [
          BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(ctx).pop(false)),
          destrutivo
              ? BotaoTrato.destrutivo(verbo, aoPressionar: () => Navigator.of(ctx).pop(true))
              : BotaoTrato.primario(verbo, aoPressionar: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    return r ?? false;
  }

  /// Trava o segundo clique, envia e, dando certo ou não, busca o caso de novo.
  Future<void> _enviar(Future<CasoAusencia> Function() chamada) async {
    setState(() {
      _enviando = true;
      _recusa = null;
    });
    final api = context.api;
    try {
      final r = await chamada();
      if (mounted) {
        final n = api.ultimoRegistroAuditoria;
        mostrarAviso(context, _resultado(r),
            detalhe: n == null ? null : 'Registro de auditoria nº ${formatarMilhar(n)}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _recusa = e);
        // O motivo do modal não é guardado: o aviso não promete texto mantido.
        mostrarAviso(context, e.toString(), erro: true, detalhe: 'Confira o caso atualizado antes de repetir.');
      }
    } finally {
      await widget.aoMudar();
      if (mounted) setState(() => _enviando = false);
    }
  }

  static String _resultado(CasoAusencia r) {
    final revisao = r.contestacao;
    if (revisao != null && revisao.status != ContestacaoAusencia.aberta && r.esperaConfirmacao) {
      return 'Contestação respondida (${revisao.status}). Falta confirmar o cancelamento.';
    }
    if (r.status == CasoAusencia.aceita) return 'Justificativa aceita. O pedido segue agendado, sem custo.';
    if (r.cancelamentoStatus == CasoAusencia.propostaRetencao) {
      return 'Retenção mostrada ao cliente. Falta confirmar o cancelamento.';
    }
    final reembolso = r.reembolsoCentavos;
    return reembolso == null
        ? 'Decisão registrada.'
        : 'Pedido cancelado. Reembolso registrado: ${formatarReais(reembolso)}.';
  }

  Future<void> _decidir() async {
    if (_enviando) return;
    setState(() => _tentou = true);
    final aceitar = _aceitar;
    final retencao = _retencao;
    if (aceitar == null || retencao == null || _justificativaCurta || _motivoRetencaoCurto || _faltaComprovante) {
      return;
    }
    final texto = aceitar
        ? 'O pedido segue agendado para remarcar sem custo ao cliente. $kAvisoAceitarBloqueado'
        : retencao > 0
            ? 'Retenção proposta: ${formatarReais(retencao)}. O cliente vê o valor, o motivo e os comprovantes. '
                'O cancelamento só acontece quando a retenção for confirmada.'
            : 'O pedido é cancelado agora, sem retenção, e o sistema pede o reembolso do valor pago.';
    final ok = await _confirmacao(
      aceitar ? 'Aceitar a justificativa?' : 'Recusar a justificativa?',
      texto,
      aceitar ? 'Aceitar justificativa' : (retencao > 0 ? 'Mostrar retenção ao cliente' : 'Cancelar e reembolsar'),
      destrutivo: !aceitar && retencao == 0,
    );
    if (!ok || !mounted) return;
    final api = context.api;
    final comRetencao = retencao > 0;
    await _enviar(() => api.decidirAusencia(
          widget.caso.pedidoId,
          aceitarJustificativa: aceitar,
          justificativa: _justificativa.text.trim(),
          retencaoCentavos: retencao,
          retencaoJustificativa: comRetencao ? _motivoRetencao.text.trim() : null,
          retencaoComprovantes: comRetencao ? _listaComprovantes : const [],
        ));
  }

  Future<void> _confirmarCancelamento({required bool retirar}) async {
    if (_enviando) return;
    final retido = widget.caso.retencaoCentavos ?? 0;
    final valor = formatarReais(retido);
    final motivo = await pedirMotivo(
      context,
      titulo: retirar ? 'Cancelar sem retenção?' : 'Confirmar o cancelamento com retenção?',
      descricao: retirar
          ? 'O pedido é cancelado sem retenção${retido > 0 ? ' (a de $valor é retirada)' : ''}: '
              'o sistema pede o reembolso ao cliente.'
          : 'O pedido é cancelado retendo $valor, o valor já mostrado ao cliente. Não dá para desfazer.',
      rotuloConfirmar: retirar ? 'Cancelar sem retenção' : 'Confirmar com retenção',
      destrutivo: !retirar,
    );
    if (motivo == null || !mounted || _enviando) return;
    final api = context.api;
    await _enviar(() => api.confirmarAusencia(widget.caso.pedidoId, retirarRetencao: retirar, motivo: motivo));
  }

  /// Depois de um 409 com retenção: zera o valor e abre a mesma confirmação, sem retenção.
  Future<void> _decidirSemRetencao() async {
    _valor.clear();
    setState(() {});
    await _decidir();
  }

  bool get _recusou409 => switch (_recusa) { ErroApi(status: 409) => true, _ => false };

  /// A recusa do backend fica junto dos botões da ação.
  List<Widget> _bannerRecusa() => [
        if (_recusa case final recusa?) ...[
          BannerInfo(recusa.toString(), titulo: _tituloRecusa(recusa), tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
      ];

  String? _resultadoRevisao;
  final _resposta = TextEditingController();
  final _novoValor = TextEditingController();

  int? get _novaRetencao {
    final v = lerReaisEmCentavos(_novoValor.text);
    return v == null || v <= 0 ? null : v;
  }

  bool get _respostaCurta => _resposta.text.trim().length < kMotivoMinimo;

  Future<void> _decidirContestacao() async {
    if (_enviando) return;
    setState(() => _tentou = true);
    final resultado = _resultadoRevisao;
    final novo = resultado == 'alterada' ? _novaRetencao : null;
    if (resultado == null || _respostaCurta || (resultado == 'alterada' && novo == null)) return;
    final atual = formatarReais(widget.caso.retencaoCentavos ?? 0);
    final ok = await _confirmacao(
      'Responder a contestação?',
      switch (resultado) {
        'mantida' => 'A retenção de $atual é mantida. O cliente recebe a sua resposta.',
        'alterada' => 'A retenção passa de $atual para ${formatarReais(novo!)}. O cliente recebe a sua resposta.',
        _ => 'A retenção de $atual é revertida. O cliente recebe a sua resposta.',
      },
      'Enviar resposta',
    );
    if (!ok || !mounted || _enviando) return;
    final api = context.api;
    await _enviar(() => api.decidirContestacaoAusencia(widget.caso.pedidoId,
        resultado: resultado, resposta: _resposta.text.trim(), retencaoCentavos: novo));
  }

  static String _tituloRecusa(Object e) => switch (e is ErroApi ? e.status : null) {
        403 => 'Sem permissão.',
        409 => 'O caso mudou ou não pode ser decidido agora.',
        503 => 'Recurso indisponível no servidor.',
        _ => 'O servidor não aceitou a ação.',
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.caso;
    final agora = DateTime.now();
    final (textoChip, tomChip) = AusenciasTela.chip(c, agora: agora);
    final semResposta = c.semResposta(agora);
    final decidivel = c.status == CasoAusencia.emAnalise || semResposta;
    final podeDecidir = context.pode(Permissao.disputasDecidir);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: EspacosTrato.x3,
          runSpacing: EspacosTrato.x2,
          children: [
            Text(c.pedido, style: TipografiaTrato.titulo),
            ChipEstado(textoChip, tom: tomChip),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (c.clienteNome != null) Linha('Cliente', c.clienteNome!),
        if (c.profissionalNome != null) Linha('Profissional', c.profissionalNome!),
        if (c.valorServicoCentavos != null) Linha('Valor do serviço', formatarReais(c.valorServicoCentavos!)),
        Linha('Chegada ao local', formatarData(c.chegadaEm)),
        if (c.registradaEm != null) Linha('Ausência registrada', formatarData(c.registradaEm!)),
        if (c.justificativaAte != null) Linha('Cliente justifica até', formatarData(c.justificativaAte!)),
        if (c.justificativaEnviadaEm != null) Linha('Justificativa enviada', formatarData(c.justificativaEnviadaEm!)),
        Linha('Justificativa', c.justificativaTexto ?? 'Nenhuma justificativa enviada.'),
        if (c.anexos.isNotEmpty) Linha('Anexos da justificativa', '${c.anexos.length}'),
        if (c.decisao != null) Linha('Motivo do analista', c.decisao!),
        if ((c.retencaoCentavos ?? 0) > 0) ...[
          Linha('Retenção proposta', formatarReais(c.retencaoCentavos!)),
          Linha('Motivo da retenção', c.retencaoJustificativa ?? 'Não informado'),
          Linha('Comprovantes', '${c.retencaoComprovantes.length}'),
        ],
        if (c.contestarAte != null) Linha('Cliente contesta até', formatarData(c.contestarAte!)),
        if (c.reembolsoCentavos != null) Linha('Reembolso', formatarReais(c.reembolsoCentavos!)),
        const SizedBox(height: EspacosTrato.x3),
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoTrato.secundario('Ver provas', aoPressionar: () => abrirProvas(context, c.pedidoId, c.pedido)),
        ),
        if (c.contestacao case final contestacao?) ..._dadosDaContestacao(contestacao),
        const SizedBox(height: EspacosTrato.x4),
        if (!podeDecidir || (!decidivel && !c.esperaConfirmacao && !c.contestacaoAberta)) ..._bannerRecusa(),
        if (!decidivel && !c.esperaConfirmacao && !c.contestacaoAberta)
          BannerInfo(
            c.status == CasoAusencia.aguardandoJustificativa
                ? 'O cliente ainda está no prazo para justificar. A decisão abre quando ele enviar ou o prazo acabar.'
                : 'Este caso não tem ação pendente no painel.',
          )
        else if (!podeDecidir)
          const BannerInfo('Seu papel acompanha o caso, mas não decide.')
        else if (c.contestacaoAberta)
          ..._formularioContestacao()
        else if (c.esperaConfirmacao)
          ..._confirmacaoDaRetencao()
        else
          ..._formulario(semResposta),
      ],
    );
  }

  List<Widget> _dadosDaContestacao(ContestacaoAusencia x) => [
        const SizedBox(height: EspacosTrato.x4),
        Text('Contestação do cliente', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        if (x.protocolo != null) Linha('Protocolo', x.protocolo!),
        Linha('Situação', x.status),
        Linha('Aberta em', formatarData(x.abertaEm)),
        Linha('Responder até', formatarData(x.responderAte)),
        Linha('O que o cliente disse', x.texto),
        if (x.resposta != null) Linha('Resposta', x.resposta!),
        if (x.decididaEm != null) Linha('Respondida em', formatarData(x.decididaEm!)),
      ];

  List<Widget> _formularioContestacao() => [
        const BannerInfo(
          'Quem decidiu a ausência não responde a contestação (Termos 8.7). Nada é cobrado até outro '
          'analista responder.',
          tom: Tom.alerta,
        ),
        const SizedBox(height: EspacosTrato.x3),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final (valor, rotulo) in const [
              ('mantida', 'Manter retenção'),
              ('alterada', 'Reduzir retenção'),
              ('revertida', 'Reverter retenção'),
            ])
              ChoiceChip(
                label: Text(rotulo),
                selected: _resultadoRevisao == valor,
                onSelected: _enviando ? null : (_) => setState(() => _resultadoRevisao = valor),
                labelStyle: TipografiaTrato.etiqueta,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        if (_tentou && _resultadoRevisao == null)
          Text('Escolha uma resposta.', style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto)),
        if (_resultadoRevisao == 'alterada') ...[
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: _novoValor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Nova retenção',
              prefixText: 'R\$ ',
              helperText: 'Use vírgula nos centavos. O servidor confere o valor.',
              errorText: _novoValor.text.trim().isNotEmpty && lerReaisEmCentavos(_novoValor.text) == null
                  ? kErroReais
                  : (_tentou && _novaRetencao == null ? 'Informe um valor maior que zero' : null),
              errorMaxLines: 3,
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _resposta,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Resposta fundamentada (o cliente recebe)',
            errorText: _tentou && _respostaCurta ? 'Escreva ao menos $kMotivoMinimo caracteres' : null,
          ),
        ),
        const AvisoAuditoria(),
        const SizedBox(height: EspacosTrato.x3),
        ..._bannerRecusa(),
        Align(
          alignment: Alignment.centerRight,
          child: BotaoTrato.primario('Revisar resposta',
              aoPressionar: _enviando ? null : _decidirContestacao,
              carregando: _enviando,
              rotuloCarregando: 'Enviando'),
        ),
      ];

  List<Widget> _confirmacaoDaRetencao() {
    final temRetencao = (widget.caso.retencaoCentavos ?? 0) > 0;
    final ate = widget.caso.contestarAte;
    return [
      BannerInfo(
        !temRetencao
            ? 'Não há mais valor retido. Confirme o cancelamento.'
            : widget.caso.contestacao == null && ate != null
                ? 'A retenção já foi mostrada ao cliente, que pode contestar até ${formatarData(ate)}. '
                    'Confirmar com retenção só vale depois desse prazo; antes, o servidor recusa.'
                : 'A contestação foi respondida. Confirme o cancelamento com a retenção ou retire a retenção.',
        tom: Tom.alerta,
      ),
      const SizedBox(height: EspacosTrato.x3),
      const AvisoAuditoria(),
      const SizedBox(height: EspacosTrato.x3),
      ..._bannerRecusa(),
      if (_recusou409 && temRetencao) ...[
        Text('Para seguir sem retenção, use "Cancelar sem retenção".', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x3),
      ],
      Wrap(
        alignment: WrapAlignment.end,
        spacing: EspacosTrato.x3,
        runSpacing: EspacosTrato.x3,
        children: [
          BotaoTrato.secundario('Cancelar sem retenção',
              aoPressionar: _enviando ? null : () => _confirmarCancelamento(retirar: true)),
          if (temRetencao)
            BotaoTrato.destrutivo('Confirmar com retenção',
                aoPressionar: _enviando ? null : () => _confirmarCancelamento(retirar: false)),
        ],
      ),
    ];
  }

  List<Widget> _formulario(bool semResposta) {
    TextStyle erro() => TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto);
    return [
      const Divider(),
      const SizedBox(height: EspacosTrato.x3),
      Text('Decisão', style: TipografiaTrato.secao),
      const SizedBox(height: EspacosTrato.x3),
      Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          // Sem justificativa enviada não há o que aceitar.
          for (final (valor, rotulo) in [
            if (!semResposta) (true, 'Aceitar'),
            (false, 'Recusar'),
          ])
            ChoiceChip(
              label: Text(rotulo),
              selected: _aceitar == valor,
              onSelected: _enviando ? null : (_) => setState(() => _aceitar = valor),
              labelStyle: TipografiaTrato.etiqueta,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      if (_tentou && _aceitar == null) Text('Escolha uma decisão.', style: erro()),
      if (_aceitar == true) ...[
        const SizedBox(height: EspacosTrato.x3),
        const BannerInfo(kAvisoAceitarBloqueado, tom: Tom.alerta),
      ],
      const SizedBox(height: EspacosTrato.x3),
      TextField(
        controller: _justificativa,
        minLines: 3,
        maxLines: 5,
        maxLength: 1000,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Motivo',
          helperText: 'Pelo menos $kMotivoMinimo caracteres',
          errorText: _tentou && _justificativaCurta ? 'Escreva ao menos $kMotivoMinimo caracteres' : null,
        ),
      ),
      if (_aceitar == false) ...[
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _valor,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Retenção por custos comprovados (opcional)',
            prefixText: 'R\$ ',
            helperText: 'Use vírgula nos centavos. Vazio = sem retenção. O servidor confere o limite.',
            helperMaxLines: 2,
            errorText: _retencao == null ? kErroReais : null,
            errorMaxLines: 3,
          ),
        ),
        if (_temRetencao) ...[
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: _motivoRetencao,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Justificativa da retenção (o cliente vê)',
              errorText:
                  _tentou && _motivoRetencaoCurto ? 'Escreva ao menos $kMotivoMinimo caracteres' : null,
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text('Comprovantes dos custos (o cliente vê)', style: TipografiaTrato.corpoForte),
          for (final rotulo in _comprovantes.values) Text('• $rotulo', style: TipografiaTrato.corpo),
          if (_tentou && _faltaComprovante)
            Text('Escolha ao menos um comprovante.',
                style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto)),
          const SizedBox(height: EspacosTrato.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.secundario('Escolher comprovantes',
                aoPressionar: _enviando ? null : _escolherComprovantes),
          ),
        ],
      ],
      const SizedBox(height: EspacosTrato.x4),
      const AvisoAuditoria(),
      const SizedBox(height: EspacosTrato.x3),
      ..._bannerRecusa(),
      if (_recusou409 && _temRetencao) ...[
        Align(
          alignment: Alignment.centerRight,
          child: BotaoTrato.secundario('Decidir sem retenção',
              aoPressionar: _enviando ? null : _decidirSemRetencao),
        ),
        const SizedBox(height: EspacosTrato.x3),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: BotaoTrato.primario(
          'Revisar decisão',
          aoPressionar: _enviando ? null : _decidir,
          carregando: _enviando,
          rotuloCarregando: 'Registrando',
        ),
      ),
    ];
  }
}
