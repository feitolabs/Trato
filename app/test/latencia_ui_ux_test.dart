import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/otimista.dart';
import 'package:trato/tema/tema.dart';

void main() {
  group('Princípio 1: Skeleton Loading nas páginas', () {
    testWidgets('renderiza esqueleto de página com blocos de layout e rodapé', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: const EsqueletoPagina(tituloBarra: 'Carregando pedido', cartoes: 3),
        ),
      );

      expect(find.text('Carregando pedido'), findsOneWidget);
      expect(find.byType(CartaoEsqueleto), findsNWidgets(3));
      expect(find.byType(LinhaEsqueleto), findsWidgets);
      expect(find.byType(BlocoEsqueleto), findsWidgets);
    });

    testWidgets('renderiza esqueleto de lista de cartões', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: const Scaffold(body: EsqueletoLista(quantidade: 4)),
        ),
      );

      expect(find.byType(CartaoEsqueleto), findsNWidgets(4));
    });
  });

  group('Princípio 2: Esperas longas (> 10s) mostram progresso e tempo restante', () {
    testWidgets('exibe barra de progresso, tempo decorrido e estimativa restante', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: const Scaffold(
            body: ProgressoEsperaLonga(
              titulo: 'Sincronizando dados...',
              segundosIniciaisDecorridos: 10,
              segundosEstimadosTotal: 25,
            ),
          ),
        ),
      );

      expect(find.text('Sincronizando dados...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Decorrido: 10s'), findsOneWidget);
      expect(find.text('Tempo restante: ~15s'), findsOneWidget);

      // Avança 2 segundos no relógio virtual
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Decorrido: 12s'), findsOneWidget);
      expect(find.text('Tempo restante: ~13s'), findsOneWidget);
    });
  });

  group('Princípio 3: Em toques, atualize primeiro, sincronize depois (Optimistic UI)', () {
    test('executarOtimista: atualiza imediatamente e conclui com sucesso', () async {
      var itemCurtido = false;
      var sincronizou = false;

      final sucesso = await executarOtimista(
        aoAtualizarLocal: () => itemCurtido = true,
        sincronizar: () async {
          expect(itemCurtido, isTrue); // "atualize primeiro" já refletido
          sincronizou = true;
        },
        aoReverter: () => itemCurtido = false,
      );

      expect(sucesso, isTrue);
      expect(itemCurtido, isTrue);
      expect(sincronizou, isTrue);
    });

    test('executarOtimista: reverte o estado se o backend falhar', () async {
      var contador = 10;
      Object? erroCapturado;

      final sucesso = await executarOtimista(
        aoAtualizarLocal: () => contador = 11, // incremento otimista na hora do toque
        sincronizar: () async => throw Exception('Falha na rede 503'),
        aoReverter: () => contador = 10, // restaura o valor prévio
        aoFalhar: (e) => erroCapturado = e,
      );

      expect(sucesso, isFalse);
      expect(contador, 10); // revertido para 10
      expect(erroCapturado.toString(), contains('503'));
    });

    test('ControladorOtimista: notifica alteração antes da confirmação e confirma após sync', () async {
      final ctrl = ControladorOtimista<String>('Original');
      final estadosRecebidos = <String>[];
      ctrl.addListener(() => estadosRecebidos.add(ctrl.valor));

      final completer = Completer<void>();
      final futuro = ctrl.atualizar('Otimista', (v) => completer.future);

      // Na hora: já reflete o novo valor
      expect(ctrl.valor, 'Otimista');
      expect(ctrl.valorConfirmado, 'Original');
      expect(ctrl.sincronizando, isTrue);

      completer.complete();
      await futuro;

      // Após sync: valor confirmado
      expect(ctrl.valor, 'Otimista');
      expect(ctrl.valorConfirmado, 'Otimista');
      expect(ctrl.sincronizando, isFalse);
    });
  });

  group('Princípio 4: Latência orquestrada (< 1s nada, 1-10s esqueleto, > 10s progresso)', () {
    testWidgets('fase 1: abaixo de 1s não mostra nada (evita flicker)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CarregamentoLatencia()),
        ),
      );

      // No início (0s): nada é renderizado (SizedBox.shrink)
      expect(find.byType(EsqueletoPagina), findsNothing);
      expect(find.byType(ProgressoEsperaLonga), findsNothing);
    });

    testWidgets('fase 2: entre 1s e 10s exibe o esqueleto da página', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CarregamentoLatencia()),
        ),
      );

      // Avança para 1 segundo: transita para esqueleto
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EsqueletoPagina), findsOneWidget);
      expect(find.byType(ProgressoEsperaLonga), findsNothing);
    });

    testWidgets('fase 3: acima de 10s exibe progresso e tempo restante', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CarregamentoLatencia()),
        ),
      );

      // Avança mais 9 segundos (total 10s): transita para espera longa com tempo restante
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(ProgressoEsperaLonga), findsOneWidget);
    });
  });
}

