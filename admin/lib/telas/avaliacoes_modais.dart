import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';
import 'avaliacoes_tela.dart';

Future<bool> abrirDecidirRevisao(BuildContext context, RevisaoAvaliacao r) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalDecidirRevisao(r)) ?? false;

Future<bool> abrirOcultarAvaliacao(BuildContext context, {String avaliacaoId = ''}) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalOcultarAvaliacao(avaliacaoId)) ?? false;

Future<bool> abrirReverterOcultacao(BuildContext context, {String avaliacaoId = ''}) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalReverterOcultacao(avaliacaoId)) ?? false;

mixin _EnvioAvaliacao<T extends StatefulWidget> on State<T> {
  bool enviando = false;
  bool revisando = false;
  String? erro;

  Future<void> enviar(Future<String> Function() chamada) async {
    if (enviando) return;
    setState(() {
      enviando = true;
      erro = null;
    });
    try {
      final aviso = await chamada();
      if (!mounted) return;
      mostrarAviso(context, aviso);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          erro = e.toString();
          enviando = false;
          revisando = false;
        });
      }
    }
  }

  Widget montar({
    required String titulo,
    required String consequencia,
    required List<Widget> formulario,
    required List<Widget> revisao,
    required bool valido,
    required String verbo,
    required VoidCallback confirmar,
    bool destrutivo = false,
  }) {
    final aoConfirmar = enviando ? null : confirmar;
    return PopScope(
      canPop: !enviando,
      child: CorpoModal(
        titulo: titulo,
        consequencia: consequencia,
        filhos: [
          if (erro != null) ...[
            BannerInfo(erro!, titulo: 'Não foi feito.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(revisando ? revisao : formulario),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: enviando
                ? null
                : () => revisando ? setState(() => revisando = false) : Navigator.of(context).pop(false),
          ),
          if (!revisando)
            BotaoTrato.primario('Revisar', aoPressionar: valido ? () => setState(() => revisando = true) : null)
          else if (destrutivo)
            BotaoTrato.destrutivo(verbo, carregando: enviando, rotuloCarregando: 'Enviando', aoPressionar: aoConfirmar)
          else
            BotaoTrato.primario(verbo, carregando: enviando, rotuloCarregando: 'Enviando', aoPressionar: aoConfirmar),
        ],
      ),
    );
  }

  Widget texto(String rotulo, TextEditingController c,
          {int maximo = 2000, int linhas = 1, String? ajuda, String? falha}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: ajuda,
            helperMaxLines: 2,
            errorText: falha,
            counterText: '',
          ),
        ),
      );

  Widget escolha(String rotulo, String valor, Map<String, String> opcoes, ValueChanged<String> aoMudar) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: DropdownButtonFormField<String>(
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo),
          items: [for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => aoMudar(v ?? valor)),
        ),
      );
}

class _ModalDecidirRevisao extends StatefulWidget {
  const _ModalDecidirRevisao(this.revisao);
  final RevisaoAvaliacao revisao;

  @override
  State<_ModalDecidirRevisao> createState() => _ModalDecidirRevisaoState();
}

class _ModalDecidirRevisaoState extends State<_ModalDecidirRevisao> with _EnvioAvaliacao {
  String _status = 'aceita';
  String _ocultarMotivo = 'ofensa_ou_ilegal';
  final _resposta = TextEditingController();
  final _mesmoAnalista = TextEditingController();

  bool get _exigeOcultarMotivo => _status == 'aceita' && widget.revisao.tipo == 'revisao';
  bool get _permiteMesmoAnalista => _status == 'aceita' && widget.revisao.tipo == 'contestacao_ocultacao';

  @override
  void dispose() {
    _resposta.dispose();
    _mesmoAnalista.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resp = _resposta.text.trim();
    final mesmo = _mesmoAnalista.text.trim();
    final mesmoInvalido = _permiteMesmoAnalista && mesmo.isNotEmpty && mesmo.length < kMotivoMinimo;
    return montar(
      titulo: revisando ? 'Confirmar decisão?' : 'Decidir revisão ${widget.revisao.protocolo}',
      consequencia: _status == 'aceita'
          ? (widget.revisao.tipo == 'contestacao_ocultacao'
              ? 'Aceitar a contestação reverte a ocultação ativa da avaliação.'
              : 'Aceitar o pedido de revisão oculta a avaliação pelo motivo escolhido (Termos 12.6).')
          : 'Recusar mantém a avaliação como está e registra a resposta para o solicitante.',
      verbo: 'Confirmar decisão',
      valido: resp.length >= kMotivoMinimo && !mesmoInvalido,
      confirmar: () => enviar(() async {
        await context.api.decidirRevisaoAvaliacao(
          widget.revisao.id,
          status: _status,
          resposta: resp,
          ocultarMotivo: _exigeOcultarMotivo ? _ocultarMotivo : null,
          mesmoAnalistaJustificativa: _permiteMesmoAnalista && mesmo.isNotEmpty ? mesmo : null,
        );
        return 'Decisão registrada.';
      }),
      formulario: [
        escolha('Decisão', _status, const {'aceita': 'Aceitar pedido', 'recusada': 'Recusar pedido'},
            (v) => _status = v),
        if (_exigeOcultarMotivo)
          escolha('Motivo da ocultação', _ocultarMotivo, kMotivosOcultacaoAvaliacao, (v) => _ocultarMotivo = v),
        texto('Resposta', _resposta, linhas: 3, maximo: 2000, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
        if (_permiteMesmoAnalista)
          texto(
            'Justificativa do mesmo analista (opcional)',
            _mesmoAnalista,
            linhas: 2,
            maximo: 1000,
            ajuda: 'Exigida se você mesmo ocultou a avaliação (Termos 20.5)',
            falha: mesmoInvalido ? 'Escreva ao menos $kMotivoMinimo caracteres ou deixe em branco' : null,
          ),
      ],
      revisao: [
        Linha('Decisão', _status == 'aceita' ? 'Aceitar pedido' : 'Recusar pedido'),
        if (_exigeOcultarMotivo)
          Linha('Motivo da ocultação', rotuloAvaliacao(kMotivosOcultacaoAvaliacao, _ocultarMotivo)),
        Linha('Resposta', resp),
        if (_permiteMesmoAnalista && mesmo.isNotEmpty) Linha('Justificativa do mesmo analista', mesmo),
      ],
    );
  }
}

class _ModalOcultarAvaliacao extends StatefulWidget {
  const _ModalOcultarAvaliacao(this.avaliacaoIdInicial);
  final String avaliacaoIdInicial;

  @override
  State<_ModalOcultarAvaliacao> createState() => _ModalOcultarAvaliacaoState();
}

class _ModalOcultarAvaliacaoState extends State<_ModalOcultarAvaliacao> with _EnvioAvaliacao {
  late final _avaliacaoId = TextEditingController(text: widget.avaliacaoIdInicial);
  String _motivo = 'ofensa_ou_ilegal';
  final _explicacao = TextEditingController();

  @override
  void dispose() {
    _avaliacaoId.dispose();
    _explicacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _avaliacaoId.text.trim();
    final exp = _explicacao.text.trim();
    return montar(
      titulo: revisando ? 'Confirmar ocultação?' : 'Ocultar avaliação',
      consequencia: 'A avaliação deixa de aparecer no aplicativo e a ocultação fica registrada na auditoria.',
      verbo: 'Confirmar ocultação',
      destrutivo: true,
      valido: id.isNotEmpty && exp.length >= kMotivoMinimo,
      confirmar: () => enviar(() async {
        await context.api.ocultarAvaliacao(id, motivo: _motivo, explicacao: exp);
        return 'Avaliação ocultada.';
      }),
      formulario: [
        texto('Código da avaliação', _avaliacaoId, maximo: 64),
        escolha('Motivo', _motivo, kMotivosOcultacaoAvaliacao, (v) => _motivo = v),
        texto('Explicação', _explicacao, linhas: 3, maximo: 2000, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
      ],
      revisao: [
        Linha('Avaliação', id),
        Linha('Motivo', rotuloAvaliacao(kMotivosOcultacaoAvaliacao, _motivo)),
        Linha('Explicação', exp),
      ],
    );
  }
}

class _ModalReverterOcultacao extends StatefulWidget {
  const _ModalReverterOcultacao(this.avaliacaoIdInicial);
  final String avaliacaoIdInicial;

  @override
  State<_ModalReverterOcultacao> createState() => _ModalReverterOcultacaoState();
}

class _ModalReverterOcultacaoState extends State<_ModalReverterOcultacao> with _EnvioAvaliacao {
  late final _avaliacaoId = TextEditingController(text: widget.avaliacaoIdInicial);
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _avaliacaoId.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _avaliacaoId.text.trim();
    final mot = _motivo.text.trim();
    return montar(
      titulo: revisando ? 'Confirmar reversão?' : 'Reverter ocultação',
      consequencia: 'A ocultação ativa é revertida e a avaliação volta ao estado anterior.',
      verbo: 'Confirmar reversão',
      valido: id.isNotEmpty && mot.length >= kMotivoMinimo,
      confirmar: () => enviar(() async {
        await context.api.reverterOcultacaoAvaliacao(id, motivo: mot);
        return 'Ocultação revertida.';
      }),
      formulario: [
        texto('Código da avaliação', _avaliacaoId, maximo: 64),
        texto('Motivo', _motivo, linhas: 3, maximo: 2000, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
      ],
      revisao: [
        Linha('Avaliação', id),
        Linha('Motivo', mot),
      ],
    );
  }
}
