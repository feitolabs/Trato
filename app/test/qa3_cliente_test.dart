// QA3 cliente (so teste): telas comuns sob estresse. Skip = 'bug conhecido: QA3-n'.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/ajuda/servico_fake.dart';
import 'apoio/exemplos/telas/mensagens/servico_fake.dart';
import 'apoio/exemplos/telas/notificacoes/servico_fake.dart';

const _tamanhos = {
  'pequeno 320x568': Size(320, 568),
  'deitado 568x320': Size(568, 320),
  'tablet 768x1024': Size(768, 1024),
};

final _hostis = [
  '😀' * 400,
  '\u202e' * 300 + 'texto invertido',
  '<script>alert(1)</script>' * 40,
  "'; DROP TABLE pedidos; --" * 30,
  '   ',
  '',
  'A' * 5000,
  'مرحبا بالعالم ' * 80,
];

Future<void> _abrir(WidgetTester t, Widget tela, Size tam, double escala) async {
  t.view.physicalSize = tam;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _rolar(WidgetTester t) async {
  final lista = find.byType(Scrollable);
  if (lista.evaluate().isEmpty) return;
  for (var i = 0; i < 4; i++) {
    await t.drag(lista.first, const Offset(0, -400));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final e in _tamanhos.entries) {
    final tam = e.value;
    testWidgets('Notificacoes: 500 itens com texto hostil, ${e.key}, fonte 1.3x, sem estouro', (t) async {
      final itens = [
        for (var i = 0; i < 500; i++)
          Notificacao(
            id: 'n$i',
            tipo: TipoNotificacao.values[i % TipoNotificacao.values.length],
            titulo: _hostis[i % _hostis.length],
            texto: _hostis[(i + 3) % _hostis.length],
            quando: _hostis[(i + 5) % _hostis.length].substring(0, 0) + 'ha $i min',
            destinoId: 'p$i',
          ),
      ];
      await _abrir(t, NotificacoesTela(servico: ServicoNotificacoesFake(itens: itens)), tam, 1.3);
      await _rolar(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('Mensagens: 500 conversas com texto hostil, ${e.key}, fonte 1.3x, sem estouro', (t) async {
      final itens = [
        for (var i = 0; i < 500; i++)
          ConversaResumo(
            pedidoId: 'p$i',
            tituloPedido: _hostis[i % _hostis.length],
            interlocutor: _hostis[(i + 1) % _hostis.length],
            iniciais: 'X',
            ultimaMensagem: _hostis[(i + 2) % _hostis.length],
            quando: '10h20',
            naoLidas: i % 7 == 0 ? 99999 : 0,
          ),
      ];
      await _abrir(t, MensagensTela(servico: ServicoMensagensFake(itens: itens)), tam, 1.3);
      await _rolar(t);
      expect(t.takeException(), isNull);
    });
  }

  group('erro de rede: existe saida (Tentar de novo / Voltar)', () {
    final saida = find.textContaining(RegExp('Tentar de novo|Voltar|tentar', caseSensitive: false));
    testWidgets('Notificacoes com falha', (t) async {
      await _abrir(t, NotificacoesTela(servico: ServicoNotificacoesFake(falhar: true)), const Size(390, 844), 1);
      expect(saida, findsWidgets);
    });
    testWidgets('Mensagens com falha', (t) async {
      await _abrir(t, const MensagensTela(servico: ServicoMensagensFake(falhar: true)), const Size(390, 844), 1);
      expect(saida, findsWidgets);
    });
    testWidgets('Ajuda com falha', (t) async {
      await _abrir(t, const AjudaTela(servico: ServicoAjudaFake(falhar: true)), const Size(390, 844), 1);
      expect(saida, findsWidgets);
    });
  });

  group('listas vazias e carregando nao quebram', () {
    testWidgets('Notificacoes vazia e travada', (t) async {
      await _abrir(t, NotificacoesTela(servico: ServicoNotificacoesFake(itens: const [])), const Size(320, 568), 1.3);
      expect(t.takeException(), isNull);
      await _abrir(t, NotificacoesTela(servico: ServicoNotificacoesFake(travar: true)), const Size(320, 568), 1.3);
      expect(t.takeException(), isNull);
    });
    testWidgets('Mensagens vazia', (t) async {
      await _abrir(t, const MensagensTela(servico: ServicoMensagensFake(itens: [])), const Size(320, 568), 1.3);
      expect(t.takeException(), isNull);
    });
  });
}

