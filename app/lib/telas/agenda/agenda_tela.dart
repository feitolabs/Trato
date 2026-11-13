import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

/// Aba Agenda do profissional: os atendimentos já contratados, agrupados por dia, com o
/// check-in de cada um. Só mostra o que o backend devolveu.
class AgendaTela extends StatelessWidget {
  const AgendaTela({
    super.key,
    required this.carregar,
    this.aoFazerCheckIn,
    this.hoje,
    this.atualizarQuando,
    this.atualizarACada,
  });

  /// Atualiza a agenda sozinha neste intervalo.
  final Duration? atualizarACada;

  final Future<List<Agendamento>> Function() carregar;

  /// Recarrega a agenda quando dispara (ex.: depois de marcar a visita).
  final Listenable? atualizarQuando;
  final ValueChanged<Agendamento>? aoFazerCheckIn;

  /// Dia de "hoje" (para os testes). Padrão: o dia do aparelho.
  final DateTime? hoje;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Agenda',
      comVoltar: false,
      child: CarregadorTela<List<Agendamento>>(
        carregar: carregar,
        atualizarQuando: atualizarQuando,
        atualizarACada: atualizarACada,
        construir: (context, itens, _) => itens.isEmpty
            ? const EstadoVazio(
                icone: Icons.calendar_today_outlined,
                titulo: 'Nada agendado',
                texto: 'Os atendimentos contratados e em andamento aparecem aqui.',
              )
            : _Dias(itens: itens, aoFazerCheckIn: aoFazerCheckIn, hoje: hoje),
      ),
    );
  }
}

/// "Hoje", "Amanhã" ou "Sex, 30/10".
String rotuloDoDia(DateTime dia, DateTime hoje) {
  final d = DateTime(dia.year, dia.month, dia.day);
  final h = DateTime(hoje.year, hoje.month, hoje.day);
  final diferenca = d.difference(h).inDays;
  if (diferenca == 0) return 'Hoje';
  if (diferenca == 1) return 'Amanhã';
  if (diferenca == -1) return 'Ontem';
  const semana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '${semana[d.weekday - 1]}, $dd/$mm';
}

class _Dias extends StatelessWidget {
  const _Dias({required this.itens, required this.aoFazerCheckIn, required this.hoje});

  final List<Agendamento> itens;
  final ValueChanged<Agendamento>? aoFazerCheckIn;
  final DateTime? hoje;

  @override
  Widget build(BuildContext context) {
    final agora = hoje ?? DateTime.now();
    final porDia = <DateTime, List<Agendamento>>{};
    for (final a in itens) {
      porDia.putIfAbsent(DateTime(a.dia.year, a.dia.month, a.dia.day), () => []).add(a);
    }
    final dias = porDia.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        for (final dia in dias) ...[
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x2),
            child: Semantics(
              header: true,
              child: Text(rotuloDoDia(dia, agora).toUpperCase(), style: TipografiaTrato.sobretitulo),
            ),
          ),
          for (final a in porDia[dia]!) ...[
            _CartaoAgendamento(
              agendamento: a,
              aoFazerCheckIn: aoFazerCheckIn == null ? null : () => aoFazerCheckIn!(a),
            ),
            const SizedBox(height: EspacosTrato.x3),
          ],
        ],
      ],
    );
  }
}

class _CartaoAgendamento extends StatelessWidget {
  const _CartaoAgendamento({required this.agendamento, required this.aoFazerCheckIn});

  final Agendamento agendamento;
  final VoidCallback? aoFazerCheckIn;

  @override
  Widget build(BuildContext context) {
    final a = agendamento;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    final tipo = switch (a.estado) {
      EstadoAgendamento.agendado => TipoStatus.info,
      EstadoAgendamento.emAndamento => TipoStatus.destaque,
      EstadoAgendamento.concluido => TipoStatus.sucesso,
    };
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(a.titulo, style: TipografiaTrato.tituloCartao)),
              const SizedBox(width: EspacosTrato.x2),
              ChipStatus(texto: a.estado.rotulo, tipo: tipo),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: CoresTrato.petroleo),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(child: Text(a.horario, style: TipografiaTrato.corpoForte)),
            ],
          ),
          const SizedBox(height: EspacosTrato.x1),
          if (a.local.trim().isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 18, color: CoresTrato.petroleo),
                const SizedBox(width: EspacosTrato.x2),
                Expanded(child: Text(a.local, style: secundario)),
              ],
            ),
          if (a.cliente != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text('Cliente: ${a.cliente}', style: secundario),
          ],
          if (a.podeFazerCheckIn && aoFazerCheckIn != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            BotaoSecundario(
              texto: a.estado == EstadoAgendamento.emAndamento ? 'Concluir serviço' : 'Fazer check-in',
              icone: Icons.place_outlined,
              aoTocar: aoFazerCheckIn,
            ),
          ],
        ],
      ),
    );
  }
}
