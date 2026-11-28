import 'dart:math';

import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

const kFiltrosStatusForcaMaior = <(String?, String)>[
  ('pendente', 'Pendentes'),
  ('aprovado', 'Aprovados'),
  ('recusado', 'Recusados'),
  (null, 'Todos'),
];

const kDecisoesForcaMaior = {
  'aprovado': 'Aprovar',
  'recusado': 'Recusar',
};

const kAvisoForcaMaior =
    'Fila de solicitações de isenção por evento externo / força maior (Termos 7.8 e 22.6). '
    'Quem tem permissão de decidir disputas analisa e decide; quando o cancelamento envolve '
    'estorno, o servidor confere a alçada financeira.';

const kDecisaoTravadaForcaMaior =
    'O envio anterior ficou sem resposta e pode ter sido gravado. Repita com a mesma decisão e a '
    'mesma justificativa: elas ficam travadas porque uma mudança seria ignorada sem aviso. Se '
    'precisar mudar, confira antes na auditoria se a decisão já foi gravada.';

const _kJustificativaMaxima = 500;

String nomePapelForcaMaior(String papel) => switch (papel) {
      'cliente' => 'Cliente',
      'profissional' => 'Profissional',
      final outro => outro,
    };

String nomeAcaoForcaMaior(String acao) => switch (acao) {
      'reagendar' => 'Reagendar',
      'cancelar' => 'Cancelar',
      final outro => outro,
    };

(String, Tom) chipStatusForcaMaior(String status) => switch (status) {
      'pendente' => ('Pendente', Tom.alerta),
      'aprovado' => ('Aprovado', Tom.ok),
      'recusado' => ('Recusado', Tom.erro),
      final outro => (outro, Tom.neutro),
    };

/// Chave por tentativa de decisão (8 a 120 chars); mantida na repetição após erro sem resposta/5xx.
String gerarChaveForcaMaior([Random? sorteio]) {
  final r = sorteio ?? Random.secure();
  return 'fm-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

String mensagemErroForcaMaior(Object erro) {
  if (erro is ErroApi) {
    return switch (erro.status) {
      403 => '${erro.mensagem} Confira se o seu papel ou alçada permite esta decisão.',
      404 => '${erro.mensagem} Atualize a fila para ver as solicitações atuais.',
      409 => '${erro.mensagem} Atualize a fila para conferir o estado atual.',
      422 => erro.mensagem,
      503 => '${erro.mensagem} Tente novamente em alguns instantes.',
      _ => erro.mensagem,
    };
  }
  return erro.toString();
}

class _TentativaForcaMaior {
  String chave = gerarChaveForcaMaior();
  String? decisao;
  String justificativa = '';
  bool semResposta = false;
}

/// Fila e decisão de solicitações de força maior (Termos 7.8 e 22.6).
class ForcaMaiorTela extends StatefulWidget {
  const ForcaMaiorTela({super.key});

  @override
  State<ForcaMaiorTela> createState() => _ForcaMaiorTelaState();
}

class _ForcaMaiorTelaState extends State<ForcaMaiorTela> {
  String? _status = 'pendente';
  int _versao = 0;
  final Map<String, _TentativaForcaMaior> _tentativas = {};

  Future<void> _abrirDecisao(EventoForcaMaior evento) async {
    final tentativa = _tentativas.putIfAbsent(evento.id, _TentativaForcaMaior.new);
    final decidiu = await mostrarModal<bool>(
      context,
      construir: (_) => _ModalDecidirForcaMaior(
        evento: evento,
        tentativa: tentativa,
        aoGravar: () => _tentativas.remove(evento.id),
      ),
    );
    if (decidiu == true && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final podeDecidir = context.pode(Permissao.disputasDecidir);
    final filtro = (_status, _versao);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Força maior',
          subtitulo: 'Solicitações de isenção por evento externo / força maior (Termos 7.8 e 22.6)',
        ),
        Expanded(
          child: FilaRemota<EventoForcaMaior>(
            key: ValueKey('fila-forca-maior-$_versao'),
            filtro: filtro,
            porPagina: 20,
            chave: (e) => e.id,
            carregar: (deslocamento, limite) => context.api.listarForcaMaior(
              status: _status,
              deslocamento: deslocamento,
              limite: limite,
            ),
            construir: (context, fila) => ListView(
              padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x6),
              children: [
                const BannerInfo(kAvisoForcaMaior, tom: Tom.info),
                const SizedBox(height: EspacosTrato.x3),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final (valor, rotulo) in kFiltrosStatusForcaMaior)
                      ChoiceChip(
                        label: Text(rotulo),
                        selected: _status == valor,
                        onSelected: (_) => setState(() => _status = valor),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x3),
                if (fila.itens.isEmpty)
                  const EstadoVazio('Nenhuma solicitação de força maior com esse filtro.')
                else ...[
                  for (final evento in fila.itens)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                      child: _CartaoForcaMaior(
                        evento,
                        podeDecidir: podeDecidir && evento.status == 'pendente',
                        aoDecidir: () => _abrirDecisao(evento),
                      ),
                    ),
                  RodapeFila(fila, rotuloItens: 'solicitações'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CartaoForcaMaior extends StatelessWidget {
  const _CartaoForcaMaior(
    this.evento, {
    required this.podeDecidir,
    required this.aoDecidir,
  });

  final EventoForcaMaior evento;
  final bool podeDecidir;
  final VoidCallback aoDecidir;

  @override
  Widget build(BuildContext context) {
    final e = evento;
    final (rotuloStatus, tom) = chipStatusForcaMaior(e.status);
    return CartaoSecao(
      titulo: 'Pedido ${e.pedidoId}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ChipEstado(rotuloStatus, tom: tom),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Pedido', e.pedidoId),
          Linha('Solicitante', '${e.solicitanteId} (${nomePapelForcaMaior(e.solicitantePapel)})'),
          Linha('Ação solicitada', nomeAcaoForcaMaior(e.acaoSolicitada)),
          Linha('Descrição', e.descricao),
          Linha(
            'Comprovantes',
            e.comprovantes.isEmpty ? 'Nenhum comprovante anexado' : e.comprovantes.join(', '),
          ),
          Linha('Solicitado em', e.criadoEm == null ? '—' : formatarDataBrasilia(e.criadoEm!)),
          if (e.decididoEm case final em?) Linha('Decidido em', formatarDataBrasilia(em)),
          if (e.justificativaDecisao case final j? when j.trim().isNotEmpty)
            Linha('Justificativa da decisão', j),
          if (podeDecidir) ...[
            const SizedBox(height: EspacosTrato.x2),
            Align(
              alignment: Alignment.centerRight,
              child: BotaoTrato.primario('Decidir', aoPressionar: aoDecidir),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModalDecidirForcaMaior extends StatefulWidget {
  const _ModalDecidirForcaMaior({
    required this.evento,
    required this.tentativa,
    required this.aoGravar,
  });

  final EventoForcaMaior evento;
  final _TentativaForcaMaior tentativa;
  final VoidCallback aoGravar;

  @override
  State<_ModalDecidirForcaMaior> createState() => _ModalDecidirForcaMaiorState();
}

class _ModalDecidirForcaMaiorState extends State<_ModalDecidirForcaMaior> {
  late final _justificativa = TextEditingController(text: widget.tentativa.justificativa);
  late String? _decisao = widget.tentativa.decisao;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _justificativa.dispose();
    super.dispose();
  }

  bool get _valido {
    final tamanho = _justificativa.text.trim().length;
    return _decisao != null && tamanho >= kMotivoMinimo && tamanho <= _kJustificativaMaxima;
  }

  Future<void> _enviar() async {
    if (_enviando || _decisao == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final tentativa = widget.tentativa;
    final decisao = tentativa.decisao = _decisao!;
    final justificativa = tentativa.justificativa = _justificativa.text.trim();
    try {
      final r = await context.api.decidirForcaMaior(
        widget.evento.id,
        decisao: decisao,
        justificativa: justificativa,
        chaveIdempotencia: tentativa.chave,
      );
      widget.aoGravar();
      if (!mounted) return;
      final aviso = r.idempotente
          ? 'Essa decisão já estava registrada. Nada novo foi criado.'
          : (r.status == 'aprovado' ? 'Solicitação aprovada.' : 'Solicitação recusada.');
      mostrarAviso(context, aviso);
      Navigator.of(context).pop(true);
    } catch (e) {
      final status = e is ErroApi ? e.status : null;
      if (status == 409 || status == 422 || (!tentativa.semResposta && (status == 403 || status == 404))) {
        tentativa
          ..chave = gerarChaveForcaMaior()
          ..semResposta = false;
      } else {
        tentativa.semResposta = true;
      }
      if (mounted) {
        setState(() {
          _erro = mensagemErroForcaMaior(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  List<Widget> _formulario() {
    final travado = widget.tentativa.semResposta;
    final e = widget.evento;
    return [
      Linha('Pedido', e.pedidoId),
      Linha('Ação solicitada', nomeAcaoForcaMaior(e.acaoSolicitada)),
      const SizedBox(height: EspacosTrato.x2),
      if (travado) ...[
        const BannerInfo(kDecisaoTravadaForcaMaior, titulo: 'Decisão e justificativa travadas.', tom: Tom.info),
        const SizedBox(height: EspacosTrato.x3),
      ],
      Text('Decisão', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: EspacosTrato.x2),
      Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          for (final item in kDecisoesForcaMaior.entries)
            ChoiceChip(
              label: Text(item.value),
              selected: _decisao == item.key,
              onSelected: travado ? null : (_) => setState(() => _decisao = item.key),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      const SizedBox(height: EspacosTrato.x3),
      TextField(
        controller: _justificativa,
        readOnly: travado,
        minLines: 2,
        maxLines: 5,
        maxLength: _kJustificativaMaxima,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Justificativa',
          helperText: 'Entre $kMotivoMinimo e $_kJustificativaMaxima caracteres',
        ),
      ),
    ];
  }

  List<Widget> _revisao() => [
        Linha('Pedido', widget.evento.pedidoId),
        Linha('Decisão', kDecisoesForcaMaior[_decisao] ?? '—'),
        Linha('Justificativa', _justificativa.text.trim()),
      ];

  @override
  Widget build(BuildContext context) {
    final consequencia = _decisao == 'aprovado' && widget.evento.acaoSolicitada == 'cancelar'
        ? 'Aprovar o cancelamento por força maior pode estornar o pedido conforme a alçada conferida pelo servidor.'
        : 'A decisão fica registrada na auditoria e não pode ser desfeita por esta tela.';
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar decisão de força maior?' : 'Decidir solicitação',
        consequencia: consequencia,
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi possível concluir a decisão.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(_revisando ? _revisao() : _formulario()),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar decisão',
                  carregando: _enviando,
                  rotuloCarregando: 'Enviando',
                  aoPressionar: _enviando ? null : _enviar,
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: _valido
                      ? () => setState(() {
                            _erro = null;
                            _revisando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}
