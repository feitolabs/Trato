import 'dart:async';

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/formato_aparelho.dart';
import 'modelos.dart';

/// "Qui, 05/11 · 14:00 às 16:00" (no relógio do aparelho).
String textoJanelaReagendamento(DateTime inicio, DateTime fim) {
  const dias = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  final i = inicio.toLocal();
  return '${dias[i.weekday - 1]}, ${diaMesDoAparelho(i)} · ${horaDoAparelho(i)} às ${horaDoAparelho(fim)}';
}

/// Escolhe o dia da nova data. Os testes trocam por um fake.
typedef EscolherDiaReagendamento = Future<DateTime?> Function(BuildContext context);

/// Escolhe uma hora ([inicial] é a sugestão). Os testes trocam por um fake.
typedef EscolherHoraReagendamento = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay inicial,
);

Future<DateTime?> _diaPadrao(BuildContext context) {
  final hoje = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: DateTime(hoje.year, hoje.month, hoje.day).add(const Duration(days: 1)),
    firstDate: DateTime(hoje.year, hoje.month, hoje.day),
    lastDate: DateTime(hoje.year, hoje.month, hoje.day).add(const Duration(days: 180)),
  );
}

Future<TimeOfDay?> _horaPadrao(BuildContext context, TimeOfDay inicial) =>
    showTimePicker(context: context, initialTime: inicial);

/// Proposta de nova data: dia, hora de início e de fim e motivo (opcional).
typedef PropostaReagendamento = ({DateTime inicio, DateTime fim, String? motivo});

Future<PropostaReagendamento?> mostrarFolhaReagendar(
  BuildContext context, {
  EscolherDiaReagendamento? escolherDia,
  EscolherHoraReagendamento? escolherHora,
  DateTime Function()? agora,
}) {
  return showModalBottomSheet<PropostaReagendamento>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FolhaReagendar(
      escolherDia: escolherDia ?? _diaPadrao,
      escolherHora: escolherHora ?? _horaPadrao,
      agora: agora ?? DateTime.now,
    ),
  );
}

class FolhaReagendar extends StatefulWidget {
  const FolhaReagendar({
    super.key,
    required this.escolherDia,
    required this.escolherHora,
    required this.agora,
  });

  final EscolherDiaReagendamento escolherDia;
  final EscolherHoraReagendamento escolherHora;
  final DateTime Function() agora;

  @override
  State<FolhaReagendar> createState() => _FolhaReagendarState();
}

class _FolhaReagendarState extends State<FolhaReagendar> {
  final _motivo = TextEditingController();
  DateTime? _dia;
  TimeOfDay? _inicio;
  TimeOfDay? _fim;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  DateTime _juntar(DateTime dia, TimeOfDay h) => DateTime(dia.year, dia.month, dia.day, h.hour, h.minute);

  String _hora(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';

  Future<void> _escolherDia() async {
    final d = await widget.escolherDia(context);
    if (d != null && mounted) setState(() => _dia = d);
  }

  Future<void> _escolherInicio() async {
    final h = await widget.escolherHora(context, _inicio ?? const TimeOfDay(hour: 9, minute: 0));
    if (h != null && mounted) setState(() => _inicio = h);
  }

  Future<void> _escolherFim() async {
    final h = await widget.escolherHora(
      context,
      _fim ?? (_inicio ?? const TimeOfDay(hour: 9, minute: 0)).replacing(hour: ((_inicio?.hour ?? 9) + 2) % 24),
    );
    if (h != null && mounted) setState(() => _fim = h);
  }

  void _enviar() {
    final dia = _dia;
    final inicio = _inicio;
    final fim = _fim;
    if (dia == null || inicio == null || fim == null) {
      setState(() => _erro = 'Escolha o dia, a hora de início e a hora de fim.');
      return;
    }
    final i = _juntar(dia, inicio);
    final f = _juntar(dia, fim);
    if (!f.isAfter(i)) {
      setState(() => _erro = 'A hora de fim precisa ser depois da hora de início.');
      return;
    }
    if (!i.isAfter(widget.agora())) {
      setState(() => _erro = 'Escolha uma data no futuro.');
      return;
    }
    final motivo = _motivo.text.trim();
    Navigator.of(context).pop((inicio: i, fim: f, motivo: motivo.isEmpty ? null : motivo));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(EspacosTrato.x5, 0, EspacosTrato.x5, EspacosTrato.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Propor nova data', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'A outra pessoa aceita ou recusa. O pedido continua como está até lá.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              BotaoSecundario(
                key: const ValueKey('reagendar-dia'),
                texto: _dia == null
                    ? 'Escolher o dia'
                    : 'Dia: ${diaMesDoAparelho(_dia!)}/${_dia!.year}',
                aoTocar: _escolherDia,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Row(
                children: [
                  Expanded(
                    child: BotaoSecundario(
                      key: const ValueKey('reagendar-inicio'),
                      texto: _inicio == null ? 'Hora de início' : 'Início ${_hora(_inicio!)}',
                      aoTocar: _escolherInicio,
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  Expanded(
                    child: BotaoSecundario(
                      key: const ValueKey('reagendar-fim'),
                      texto: _fim == null ? 'Hora de fim' : 'Fim ${_hora(_fim!)}',
                      aoTocar: _escolherFim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              TextField(
                key: const ValueKey('reagendar-motivo'),
                controller: _motivo,
                maxLines: 3,
                minLines: 2,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                style: TipografiaTrato.corpo,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  hintText: 'Ex.: imprevisto no trabalho',
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: EspacosTrato.x2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _erro!,
                    key: const ValueKey('erro-reagendar'),
                    style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
                  ),
                ),
              ],
              const SizedBox(height: EspacosTrato.x4),
              BotaoPrimario(texto: 'Enviar proposta', aoTocar: _enviar),
              const SizedBox(height: EspacosTrato.x2),
              BotaoSecundario(texto: 'Cancelar', aoTocar: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reagendamento dentro do pedido: botão "Reagendar" quando não há proposta pendente; e, havendo,
/// o card para aceitar/recusar (quem recebeu) ou aguardar/cancelar (quem propôs).
/// Serve ao cliente (tela do pedido) e ao profissional (folha de ações): só recebe as chamadas.
class SecaoReagendamento extends StatefulWidget {
  const SecaoReagendamento({
    super.key,
    required this.carregar,
    required this.propor,
    required this.aceitar,
    required this.recusar,
    this.meuId,
    this.aoMudar,
    this.intervalo,
    this.escolherDia,
    this.escolherHora,
    this.agora,
  });

  final Future<List<Reagendamento>> Function() carregar;
  final Future<void> Function(DateTime inicio, DateTime fim, String? motivo) propor;
  final Future<void> Function(String reagendamentoId) aceitar;

  /// Recusar (quem recebeu) ou cancelar a própria proposta: a mesma rota do backend.
  final Future<void> Function(String reagendamentoId) recusar;

  /// Id do usuário logado, para saber se a proposta pendente é dele.
  final String? meuId;

  /// Depois de propor, aceitar ou recusar (ex.: atualizar o pedido na tela).
  final VoidCallback? aoMudar;

  /// Atualiza sozinho neste intervalo (ver a resposta da outra parte). Nulo = só ao abrir/agir.
  final Duration? intervalo;
  final EscolherDiaReagendamento? escolherDia;
  final EscolherHoraReagendamento? escolherHora;
  final DateTime Function()? agora;

  @override
  State<SecaoReagendamento> createState() => _SecaoReagendamentoState();
}

class _SecaoReagendamentoState extends State<SecaoReagendamento> {
  List<Reagendamento>? _itens;
  String? _erroCarga;
  String? _erroAcao;
  var _ocupado = false;
  var _carregando = false;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _carregar();
    final intervalo = widget.intervalo;
    if (intervalo != null) {
      _relogio = Timer.periodic(intervalo, (_) => _carregar(silencioso: true));
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (_carregando) return;
    _carregando = true;
    if (!silencioso && mounted) setState(() => _erroCarga = null);
    try {
      final itens = await widget.carregar();
      if (mounted) setState(() => _itens = itens);
    } on Object {
      // Em segundo plano mantém o que já está na tela; ao abrir, mostra o erro.
      if (mounted && !silencioso && _itens == null) {
        setState(() => _erroCarga = 'Não foi possível ver as propostas de nova data agora.');
      }
    } finally {
      _carregando = false;
    }
  }

  Reagendamento? get _pendente => _itens?.where((r) => r.pendente).firstOrNull;

  Future<void> _agir(Future<void> Function() acao) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _erroAcao = null;
    });
    try {
      await acao();
      widget.aoMudar?.call();
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erroAcao = e.mensagem);
    } on Object {
      if (mounted) setState(() => _erroAcao = 'Não foi possível concluir agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    await _carregar(silencioso: true);
  }

  Future<void> _propor() async {
    final proposta = await mostrarFolhaReagendar(
      context,
      escolherDia: widget.escolherDia,
      escolherHora: widget.escolherHora,
      agora: widget.agora,
    );
    if (proposta == null || !mounted) return;
    await _agir(() => widget.propor(proposta.inicio, proposta.fim, proposta.motivo));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    if (_erroCarga != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _erroCarga!,
            style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
          ),
          BotaoLink(texto: 'Tentar de novo', aoTocar: _carregar),
        ],
      );
    }
    if (_itens == null) return const SizedBox.shrink();
    final pendente = _pendente;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendente == null)
          BotaoLink(
            key: const ValueKey('reagendar'),
            texto: 'Reagendar',
            aoTocar: _ocupado ? null : _propor,
          )
        else
          _CartaoProposta(
            proposta: pendente,
            minha: widget.meuId != null && pendente.propostoPor == widget.meuId,
            ocupado: _ocupado,
            aoAceitar: () => _agir(() => widget.aceitar(pendente.id)),
            aoRecusar: () => _agir(() => widget.recusar(pendente.id)),
          ),
        if (_erroAcao != null) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(
            _erroAcao!,
            key: const ValueKey('erro-reagendamento'),
            style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
          ),
        ],
      ],
    );
  }
}

class _CartaoProposta extends StatelessWidget {
  const _CartaoProposta({
    required this.proposta,
    required this.minha,
    required this.ocupado,
    required this.aoAceitar,
    required this.aoRecusar,
  });

  final Reagendamento proposta;

  /// A proposta é do usuário logado (aguarda a outra parte).
  final bool minha;
  final bool ocupado;
  final VoidCallback aoAceitar;
  final VoidCallback aoRecusar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return CartaoTrato(
      key: const ValueKey('cartao-reagendamento'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            minha ? 'Aguardando resposta sobre a nova data' : 'Nova data proposta',
            style: TipografiaTrato.corpoForte,
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            textoJanelaReagendamento(proposta.inicio, proposta.fim),
            key: const ValueKey('janela-reagendamento'),
            style: TipografiaTrato.corpo,
          ),
          if (proposta.motivo.trim().isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              'Motivo: ${proposta.motivo.trim()}',
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
            ),
          ],
          const SizedBox(height: EspacosTrato.x3),
          if (minha)
            BotaoSecundario(
              key: const ValueKey('cancelar-proposta'),
              texto: 'Cancelar proposta',
              aoTocar: ocupado ? null : aoRecusar,
            )
          else ...[
            BotaoPrimario(
              key: const ValueKey('aceitar-nova-data'),
              texto: 'Aceitar nova data',
              carregando: ocupado,
              aoTocar: ocupado ? null : aoAceitar,
            ),
            const SizedBox(height: EspacosTrato.x2),
            BotaoSecundario(
              key: const ValueKey('recusar-nova-data'),
              texto: 'Recusar',
              aoTocar: ocupado ? null : aoRecusar,
            ),
          ],
        ],
      ),
    );
  }
}
