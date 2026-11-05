import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/telas/comuns/formato_aparelho.dart';

// Regressão (04/11/2026): a Agenda do profissional mostrava o nome do estado ("Pago e retido")
// no lugar do horário, porque o app ignorava a `janela` que o backend devolve.

Map<String, dynamic> _pedido({Map<String, dynamic>? janela}) => {
      'id': 'ab12cd34',
      'estado': 'agendado',
      'estado_nome': 'Agendado',
      'cliente_id': 'c1',
      'profissional_id': 'p1',
      'aberto_em': '2026-11-04T12:00:00Z',
      'janela': janela,
      'concluido_em': null,
      'acoes_permitidas': <String>[],
      'codigo_inicio': null,
      'codigo_conclusao': null,
    };

void main() {
  test('com visita marcada, o rótulo traz dia e hora no horário do aparelho', () {
    final p = PedidoApi.deJson(
      _pedido(janela: {'inicio': '2026-11-06T12:00:00Z', 'fim': '2026-11-06T14:00:00Z'}),
    );
    expect(p.janelaInicio, isNotNull);
    final i = DateTime.parse('2026-11-06T12:00:00Z');
    final f = DateTime.parse('2026-11-06T14:00:00Z');
    expect(
      p.janelaRotulo,
      '${diaMesDoAparelho(i)} · ${horaDoAparelho(i)} às ${horaDoAparelho(f)}',
    );
  });

  test('sem visita marcada, não há rótulo (a tela avisa em vez de inventar horário)', () {
    final p = PedidoApi.deJson(_pedido());
    expect(p.janelaInicio, isNull);
    expect(p.janelaRotulo, isNull);
  });
}
