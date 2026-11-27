/// Termos 12.1: o prazo para avaliar vem do servidor (`GET /v1/pedidos/{id}/avaliacao`). O app
/// só mostra: não calcula prazo nenhum.
library;

import 'formato_aparelho.dart';

class PrazoAvaliacao {
  const PrazoAvaliacao({this.ate, this.encerrado = false, this.bonusMoedas});

  /// Campo ausente (servidor antigo) vira "sem prazo conhecido": a tela fica como antes.
  factory PrazoAvaliacao.deJson(Map<String, dynamic> j) {
    final ate = j['avaliar_ate'];
    final bonus = j['bonus_moedas'];
    return PrazoAvaliacao(
      bonusMoedas: bonus is num && bonus > 0 ? bonus.toInt() : null,
      ate: ate is String ? DateTime.tryParse(ate)?.toLocal() : null,
      encerrado: j['prazo_encerrado'] == true,
    );
  }

  static const desconhecido = PrazoAvaliacao();

  /// Último instante para avaliar.
  final DateTime? ate;
  final bool encerrado;

  /// Tratinhos que avaliar rende agora. Nulo: o servidor não informou (a tela não cita número).
  final int? bonusMoedas;
}

const textoPrazoEncerrado = 'O prazo para avaliar este serviço terminou.';

/// "Você pode avaliar até 25/12/2026, 14:30."
String textoAvaliarAte(DateTime ate) => 'Você pode avaliar até '
    '${ate.day.toString().padLeft(2, '0')}/${ate.month.toString().padLeft(2, '0')}/${ate.year}, '
    '${horaDoAparelho(ate)}.';
