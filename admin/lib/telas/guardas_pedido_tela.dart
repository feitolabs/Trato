import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

const kTiposGuarda = {'processo': 'Processo', 'investigacao': 'Investigação'};

const kSituacoesRetencao = <String, (String, Tom)>{
  'sem_marco': ('Sem marco para contar o prazo', Tom.neutro),
  'no_prazo': ('Dentro do prazo', Tom.info),
  'bloqueado': ('Bloqueado', Tom.alerta),
  'vencido': ('Prazo vencido', Tom.erro),
};

const kBloqueiosRetencao = {
  'disputa_aberta': 'Disputa aberta',
  'contestacao_disputa_aberta': 'Contestação de decisão de disputa aberta',
  'contestacao_nota_aberta': 'Contestação de nota de material aberta',
  'pagamento_contestado': 'Pagamento contestado',
  'incidente_nao_encerrado': 'Incidente de segurança não encerrado',
  'preservacao_9_6': 'Preservação de registros (Termos 9.6)',
  'guarda_pedido': 'Guarda aberta neste pedido',
  'guarda_usuario': 'Guarda sobre usuário',
};

const kAvisoGuardas = 'Guarda de retenção do pedido (Termos 14.8 e 16.3). Esta tela não apaga nem anonimiza '
    'nada; o prazo e os bloqueios vêm do servidor.';

const kEfeitoAbrirGuarda = 'A guarda fica registrada como bloqueio da retenção dos registros deste pedido até ser '
    'encerrada.';

const kEfeitoEncerrarGuarda = 'Esta guarda deixa de bloquear a retenção. Outros bloqueios continuam valendo. Não dá '
    'para reabrir a mesma guarda.';

const kRepetirGuarda = 'O pedido pode ter sido gravado. Confira a lista antes de repetir.';

const _kMotivoMaximo = 1000;

String nomeTipoGuarda(String t) => kTiposGuarda[t] ?? t;

String _mensagem(Object e) => e is ErroApi ? e.mensagem : 'Não deu para ler a resposta do servidor.';

/// Consulta por ID: DPO e jurídico não têm a busca de pedidos.
class GuardasPedidoTela extends StatefulWidget {
  const GuardasPedidoTela({super.key});

  @override
  State<GuardasPedidoTela> createState() => _GuardasPedidoTelaState();
}

class _GuardasPedidoTelaState extends State<GuardasPedidoTela> {
  final _codigo = TextEditingController();
  String? _pedidoId;
  int _consulta = 0;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  void _consultar() {
    final id = _codigo.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _pedidoId = id;
      _consulta++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina('Guarda de retenção', subtitulo: 'Guardas e retenção de um pedido (Termos 14.8 e 16.3)'),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BannerInfo(kAvisoGuardas, tom: Tom.info),
                const SizedBox(height: EspacosTrato.x3),
                TextField(
                  key: const ValueKey('guarda-pedido'),
                  controller: _codigo,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _consultar(),
                  decoration: const InputDecoration(labelText: 'ID do pedido'),
                ),
                const SizedBox(height: EspacosTrato.x2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BotaoTrato.primario('Consultar', aoPressionar: _codigo.text.trim().isEmpty ? null : _consultar),
                ),
                const SizedBox(height: EspacosTrato.x4),
                if (_pedidoId case final id?)
                  _PainelDoPedido(key: ValueKey('$id-$_consulta'), pedidoId: id)
                else
                  const EstadoVazio('Informe o ID de um pedido para ver as guardas.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Retenção e guardas carregam separadas: a falha de uma não esconde a outra.
class _PainelDoPedido extends StatefulWidget {
  const _PainelDoPedido({super.key, required this.pedidoId});
  final String pedidoId;

  @override
  State<_PainelDoPedido> createState() => _PainelDoPedidoState();
}

class _PainelDoPedidoState extends State<_PainelDoPedido> {
  RetencaoPedido? _retencao;
  List<GuardaPedido>? _guardas;
  String? _erroRetencao;
  String? _erroGuardas;
  bool _iniciou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    _carregarRetencao();
    _carregarGuardas();
  }

  Future<void> _carregarRetencao() async {
    setState(() {
      _retencao = null;
      _erroRetencao = null;
    });
    try {
      final r = await context.api.obterRetencaoPedido(widget.pedidoId);
      if (mounted) setState(() => _retencao = r);
    } catch (e) {
      if (mounted) setState(() => _erroRetencao = _mensagem(e));
    }
  }

  Future<void> _carregarGuardas() async {
    setState(() {
      _guardas = null;
      _erroGuardas = null;
    });
    try {
      final r = await context.api.listarGuardasPedido(widget.pedidoId);
      if (mounted) setState(() => _guardas = r);
    } catch (e) {
      if (mounted) setState(() => _erroGuardas = _mensagem(e));
    }
  }

  /// Depois de qualquer envio, com ou sem sucesso, relê: o servidor sabe o que ficou.
  Future<void> _agir(GuardaPedido? encerrar) async {
    var enviou = false;
    await mostrarModal<void>(
      context,
      largura: 560,
      construir: (_) => _ModalGuarda(pedidoId: widget.pedidoId, encerrar: encerrar, aoEnviar: () => enviou = true),
    );
    if (enviou && mounted) {
      _carregarRetencao();
      _carregarGuardas();
    }
  }

  List<Widget> _falha(String titulo, String erro, VoidCallback tentar) => [
        BannerInfo(erro, titulo: titulo, tom: Tom.erro),
        const SizedBox(height: EspacosTrato.x2),
        Align(alignment: Alignment.centerLeft, child: BotaoTrato.secundario('Tentar novamente', aoPressionar: tentar)),
      ];

  static const _carregando = Padding(
    padding: EdgeInsets.symmetric(vertical: EspacosTrato.x5),
    child: Center(child: CircularProgressIndicator()),
  );

  Widget _cartaoRetencao() {
    final r = _retencao;
    return CartaoSecao(
      titulo: 'Retenção',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_erroRetencao case final erro?)
            ..._falha('Não foi possível carregar a retenção.', erro, _carregarRetencao)
          else if (r == null)
            _carregando
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ChipEstado(kSituacoesRetencao[r.situacao]?.$1 ?? r.situacao,
                  tom: kSituacoesRetencao[r.situacao]?.$2 ?? Tom.neutro),
            ),
            const SizedBox(height: EspacosTrato.x2),
            Linha('Concluído em', r.concluidoEm == null ? '—' : formatarDataBrasilia(r.concluidoEm!)),
            Linha('Prazo de guarda', r.prazoAnos == 1 ? '1 ano' : '${r.prazoAnos} anos'),
            Linha('Guardar até', r.guardaAte == null ? '—' : formatarDataBrasilia(r.guardaAte!)),
            Linha(
              'Bloqueios',
              r.bloqueios.isEmpty ? 'Nenhum' : [for (final b in r.bloqueios) kBloqueiosRetencao[b] ?? b].join('; '),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartaoGuarda(GuardaPedido g) => CartaoSecao(
        titulo: nomeTipoGuarda(g.tipo),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ChipEstado(g.aberta ? 'Aberta' : 'Encerrada', tom: g.aberta ? Tom.alerta : Tom.neutro),
            ),
            const SizedBox(height: EspacosTrato.x2),
            Linha('Motivo da abertura', g.motivo),
            Linha('Aberta em', formatarDataBrasilia(g.criadaEm)),
            Linha('Aberta por', g.criadaPor),
            if (g.encerradaEm case final em?) Linha('Encerrada em', formatarDataBrasilia(em)),
            if (g.encerradaPor case final por?) Linha('Encerrada por', por),
            if (g.aberta) ...[
              const SizedBox(height: EspacosTrato.x2),
              Align(
                alignment: Alignment.centerRight,
                child: BotaoTrato.secundario('Encerrar guarda', aoPressionar: () => _agir(g)),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final guardas = _guardas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cartaoRetencao(),
        const SizedBox(height: EspacosTrato.x4),
        Text('Guardas do pedido ${widget.pedidoId}', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        if (_erroGuardas case final erro?)
          ..._falha('Não foi possível carregar as guardas.', erro, _carregarGuardas)
        else if (guardas == null)
          _carregando
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.primario('Abrir guarda', aoPressionar: () => _agir(null)),
          ),
          const SizedBox(height: EspacosTrato.x3),
          if (guardas.isEmpty)
            const EstadoVazio('Nenhuma guarda registrada neste pedido.')
          else
            for (final g in guardas)
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                child: _cartaoGuarda(g),
              ),
        ],
      ],
    );
  }
}

/// Abre uma guarda ([encerrar] nulo) ou encerra a informada: motivo, revisão e confirmação.
class _ModalGuarda extends StatefulWidget {
  const _ModalGuarda({required this.pedidoId, required this.encerrar, required this.aoEnviar});
  final String pedidoId;
  final GuardaPedido? encerrar;
  final VoidCallback aoEnviar;

  @override
  State<_ModalGuarda> createState() => _ModalGuardaState();
}

class _ModalGuardaState extends State<_ModalGuarda> {
  final _motivo = TextEditingController();
  String? _tipo;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _abrindo => widget.encerrar == null;

  bool get _valido {
    final n = _motivo.text.trim().length;
    return (!_abrindo || _tipo != null) && n >= kMotivoMinimo && n <= _kMotivoMaximo;
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    widget.aoEnviar();
    try {
      final api = context.api;
      final motivo = _motivo.text.trim();
      final String aviso;
      if (_abrindo) {
        final r = await api.abrirGuardaPedido(widget.pedidoId, tipo: _tipo!, motivo: motivo);
        aviso = r.repetida ? 'Já havia uma guarda aberta igual. Nada novo foi criado.' : 'Guarda aberta.';
      } else {
        await api.encerrarGuardaPedido(widget.pedidoId, widget.encerrar!.id, motivo: motivo);
        aviso = 'Guarda encerrada.';
      }
      if (!mounted) return;
      mostrarAviso(context, aviso);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      // Sem código HTTP: a resposta se perdeu ou o servidor falhou no meio.
      final semResposta = e is! ErroApi || (e.status == null && !e.proibido && !e.sessao);
      setState(() {
        _erro = semResposta ? '${_mensagem(e)} $kRepetirGuarda' : _mensagem(e);
        _enviando = false;
        _revisando = false;
      });
    }
  }

  List<Widget> _formulario() => [
        if (_abrindo) ...[
          Text('Tipo', style: TipografiaTrato.etiqueta),
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final t in kTiposGuarda.entries)
                ChoiceChip(
                  label: Text(t.value),
                  selected: _tipo == t.key,
                  onSelected: (_) => setState(() => _tipo = t.key),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        TextField(
          controller: _motivo,
          minLines: 3,
          maxLines: 6,
          maxLength: _kMotivoMaximo,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Motivo',
            helperText: 'Entre $kMotivoMinimo e $_kMotivoMaximo caracteres',
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final g = widget.encerrar;
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando
            ? (_abrindo ? 'Confirmar a abertura?' : 'Confirmar o encerramento?')
            : (_abrindo ? 'Abrir guarda' : 'Encerrar guarda'),
        consequencia: _abrindo ? kEfeitoAbrirGuarda : kEfeitoEncerrarGuarda,
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi concluído.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          Linha('Pedido', widget.pedidoId),
          if (g != null) ...[
            Linha('Tipo', nomeTipoGuarda(g.tipo)),
            Linha('Motivo da abertura', g.motivo),
          ],
          const SizedBox(height: EspacosTrato.x2),
          if (_revisando) ...[
            if (_abrindo) Linha('Tipo', nomeTipoGuarda(_tipo!)),
            Linha(_abrindo ? 'Motivo' : 'Motivo do encerramento', _motivo.text.trim()),
          ] else
            ..._formulario(),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
          ),
          if (_revisando)
            BotaoTrato.primario(
              _abrindo ? 'Confirmar abertura' : 'Confirmar encerramento',
              carregando: _enviando,
              rotuloCarregando: 'Enviando',
              aoPressionar: _enviando ? null : _enviar,
            )
          else
            BotaoTrato.primario(
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
