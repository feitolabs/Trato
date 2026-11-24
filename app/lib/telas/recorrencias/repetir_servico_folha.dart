import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../pedido_novo/pecas_pedido.dart' show ChipOpcao;
import '../profissional/dinheiro.dart';
import 'modelos.dart';

/// Escolhe o dia da 1ª visita. Os testes trocam por um fake.
typedef EscolherDiaRecorrencia = Future<DateTime?> Function(BuildContext context);

/// Escolhe a hora da visita ([inicial] é a sugestão). Os testes trocam por um fake.
typedef EscolherHoraRecorrencia = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay inicial,
);

Future<DateTime?> _diaPadrao(BuildContext context) {
  final hoje = DateTime.now();
  final base = DateTime(hoje.year, hoje.month, hoje.day);
  return showDatePicker(
    context: context,
    initialDate: base.add(const Duration(days: 7)),
    firstDate: base,
    lastDate: base.add(const Duration(days: 365)),
  );
}

Future<TimeOfDay?> _horaPadrao(BuildContext context, TimeOfDay inicial) =>
    showTimePicker(context: context, initialTime: inicial);

/// "Repetir este serviço": frequência, data e hora da 1ª visita (horário de Brasília) e valor por
/// visita. Devolve a proposta ou nulo se a pessoa fechar. O valor já vem preenchido quando se sabe.
Future<PropostaRecorrencia?> mostrarFolhaRepetirServico(
  BuildContext context, {
  int? valorInicialCentavos,
  EscolherDiaRecorrencia? escolherDia,
  EscolherHoraRecorrencia? escolherHora,
  DateTime Function()? agora,
}) {
  return showModalBottomSheet<PropostaRecorrencia>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FolhaRepetirServico(
      valorInicialCentavos: valorInicialCentavos,
      escolherDia: escolherDia ?? _diaPadrao,
      escolherHora: escolherHora ?? _horaPadrao,
      agora: agora ?? DateTime.now,
    ),
  );
}

class FolhaRepetirServico extends StatefulWidget {
  const FolhaRepetirServico({
    super.key,
    required this.escolherDia,
    required this.escolherHora,
    required this.agora,
    this.valorInicialCentavos,
  });

  final int? valorInicialCentavos;
  final EscolherDiaRecorrencia escolherDia;
  final EscolherHoraRecorrencia escolherHora;
  final DateTime Function() agora;

  @override
  State<FolhaRepetirServico> createState() => _FolhaRepetirServicoState();
}

class _FolhaRepetirServicoState extends State<FolhaRepetirServico> {
  late final TextEditingController _valor = TextEditingController(
    text: widget.valorInicialCentavos == null ? '' : Dinheiro.paraCampo(widget.valorInicialCentavos!),
  );
  var _frequencia = FrequenciaRecorrencia.semanal;
  DateTime? _dia;
  TimeOfDay? _hora;
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  String _horaTexto(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';

  Future<void> _escolherDia() async {
    final d = await widget.escolherDia(context);
    if (d != null && mounted) setState(() => _dia = d);
  }

  Future<void> _escolherHora() async {
    final h = await widget.escolherHora(context, _hora ?? const TimeOfDay(hour: 9, minute: 0));
    if (h != null && mounted) setState(() => _hora = h);
  }

  void _enviar() {
    final dia = _dia;
    final hora = _hora;
    if (dia == null || hora == null) {
      setState(() => _erro = 'Escolha o dia e a hora da primeira visita.');
      return;
    }
    final primeira = deBrasilia(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    if (!primeira.isAfter(widget.agora().toUtc())) {
      setState(() => _erro = 'Escolha uma data no futuro.');
      return;
    }
    int? centavos;
    final texto = _valor.text.trim();
    if (texto.isNotEmpty) {
      centavos = Dinheiro.lerCentavos(texto);
      if (centavos == null || centavos <= 0) {
        setState(() => _erro = 'Informe um valor válido por visita.');
        return;
      }
    } else if (widget.valorInicialCentavos != null) {
      setState(() => _erro = 'Informe o valor de cada visita.');
      return;
    }
    Navigator.of(context).pop(
      (frequencia: _frequencia, proximaVisita: primeira, valorCentavos: centavos),
    );
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
              Text('Repetir este serviço', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'A outra pessoa aceita ou recusa. Cada visita vira um pedido que o cliente '
                'aprova e paga.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              Text('Com que frequência?', style: TipografiaTrato.corpoForte),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (final f in FrequenciaRecorrencia.values)
                    ChipOpcao(
                      key: ValueKey('frequencia-${f.codigo}'),
                      texto: f.rotulo,
                      marcado: _frequencia == f,
                      aoTocar: () => setState(() => _frequencia = f),
                    ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              Text('Primeira visita (horário de Brasília)', style: TipografiaTrato.corpoForte),
              const SizedBox(height: EspacosTrato.x2),
              Row(
                children: [
                  Expanded(
                    child: BotaoSecundario(
                      key: const ValueKey('repetir-dia'),
                      texto: _dia == null
                          ? 'Escolher o dia'
                          : '${_dia!.day.toString().padLeft(2, '0')}/'
                              '${_dia!.month.toString().padLeft(2, '0')}/${_dia!.year}',
                      aoTocar: _escolherDia,
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  Expanded(
                    child: BotaoSecundario(
                      key: const ValueKey('repetir-hora'),
                      texto: _hora == null ? 'Escolher a hora' : _horaTexto(_hora!),
                      aoTocar: _escolherHora,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              TextField(
                key: const ValueKey('repetir-valor'),
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: TipografiaTrato.corpo,
                decoration: InputDecoration(
                  labelText: 'Valor por visita',
                  prefixText: 'R\$ ',
                  helperText: widget.valorInicialCentavos == null
                      ? 'Se ficar em branco, vale o valor do serviço concluído.'
                      : 'Já preenchido com o valor do serviço. Você pode mudar.',
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: EspacosTrato.x2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _erro!,
                    key: const ValueKey('erro-repetir'),
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
