import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/resumo_pedidos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const _resumo = ResumoPedidos(
    futurosCancelados: 3, emAndamento: 1, emAndamentoIds: ['ped-andamento'], futurosPendentesIds: ['ped-pendente']);

Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Finder _modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);

Finder _avisoNoModal() => find.descendant(of: _modal(), matching: _contem(kPedidosCancelados));

Medida _suspensao({ResumoPedidos? pedidos, bool vigente = true, String tipo = 'suspensao'}) => Medida(
      id: 'med-1',
      protocolo: 'MED-EXEMPLO-1',
      usuarioId: 'u-101',
      usuarioNome: 'Paulo (exemplo)',
      tipo: tipo,
      motivoAoUsuario: 'Texto (exemplo)',
      motivoCompleto: 'Texto (exemplo)',
      clausulas: const ['9.2'],
      inicioEm: DateTime(2026, 11, 20),
      efeito: 'Efeito (exemplo)',
      comoContestar: 'Como contestar (exemplo)',
      vigente: vigente,
      pedidos: pedidos,
    );

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escrever(WidgetTester tester, String rotulo, String texto) async {
  // Só o campo do modal: no celular ele é uma folha, e a tela tem filtro com o mesmo rótulo.
  final campo = find.descendant(of: _modal(), matching: find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

Future<void> _aplicarSuspensao(WidgetTester tester) async {
  await _clicar(tester, find.text('Aplicar medida').first);
  await _escrever(tester, 'Código da conta', 'u-101');
  await _clicar(tester, find.byType(DropdownButtonFormField<String>));
  await tester.tap(find.text('Suspensão').last);
  await tester.pumpAndSettle();
  expect(_avisoNoModal(), findsOneWidget);
  expect(_contem('não são tratados automaticamente'), findsNothing);
  await _escrever(tester, 'Motivo (o usuário lê)', 'Ofensa registrada na conversa');
  await _escrever(tester, 'Cláusulas dos Termos', '9.2');
  await _clicar(tester, find.text('Revisar medida'));
  expect(_avisoNoModal(), findsOneWidget);
  await _clicar(tester, find.text('Confirmar e aplicar'));
}

void main() {
  for (final largura in [360.0, 1280.0]) {
    testWidgets('aplicar suspensão mostra resumo e códigos (largura $largura)', (tester) async {
      final api = ApiFake()..medidas = [_suspensao(pedidos: _resumo)];
      await abrirPainel(tester, papel: 'mediador', api: api, largura: largura, altura: 800);
      if (largura < 600) {
        await tester.tap(find.byKey(const ValueKey('menu-mais')));
        await tester.pumpAndSettle();
        await tocarNoMais(tester, 'medidas');
      } else {
        await irPara(tester, 'medidas');
      }
      await _aplicarSuspensao(tester);
      expect(find.text('Pedidos desta conta'), findsOneWidget);
      expect(find.descendant(of: _modal(), matching: find.text('Futuros cancelados')), findsOneWidget);
      expect(find.descendant(of: _modal(), matching: find.text('ped-andamento')), findsOneWidget);
      expect(find.descendant(of: _modal(), matching: find.text('ped-pendente')), findsOneWidget);
      await _clicar(tester, find.text('Fechar'));
      expect(find.text('Pedidos desta conta'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('backend antigo: sem os campos pede conferência manual', (tester) async {
    final api = ApiFake()..medidas = [_suspensao()];
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
    await _aplicarSuspensao(tester);
    expect(find.text('Pedidos desta conta'), findsOneWidget);
    expect(_contem(kResumoNaoInformado), findsWidgets);
    expect(find.text('Futuros cancelados'), findsNothing);
  });

  testWidgets('detalhe: suspensão em vigor mostra resumo; encerrada não', (tester) async {
    for (final (medida, esperado) in [
      (_suspensao(pedidos: _resumo), findsOneWidget),
      (_suspensao(pedidos: const ResumoPedidos(), vigente: false), findsNothing),
      (_suspensao(pedidos: const ResumoPedidos(), tipo: 'bloqueio_preventivo'), findsNothing),
    ]) {
      await tester.pumpWidget(const SizedBox());
      final api = ApiFake()..medidas = [medida];
      await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
      await _clicar(tester, find.textContaining('Paulo (exemplo)').first);
      expect(find.text('Pedidos da conta (Termos 20.6)'), esperado);
    }
  });

  testWidgets('bloquear na busca avisa antes e mostra o resumo depois', (tester) async {
    final api = ApiFake()..resumoDoBloqueio = _resumo;
    final alvo = api.usuariosFake.first;
    api.definirStatusUsuarioFake(alvo.id, 'ativo');
    await abrirPainel(tester, papel: 'administrador', api: api, secao: 'busca');
    await _clicar(tester, find.text('Alterar status'));
    expect(_contem(kPedidosCancelados), findsNothing);
    await _clicar(tester, find.text('Ativo (acesso normal)'));
    await tester.tap(find.text('Bloqueado (acesso negado)').last);
    await tester.pumpAndSettle();
    expect(_contem(kPedidosCancelados), findsOneWidget);
    await _escrever(tester, 'Motivo interno (o usuário não vê)', 'Fraude confirmada na análise');
    await _escrever(tester, 'Motivo que o usuário vai ler', 'Ofensa registrada na conversa');
    await _escrever(tester, 'Cláusulas dos Termos', '9.2');
    await tester.pumpAndSettle();
    await _clicar(tester, find.text('Alterar status').last);
    expect(find.text('Pedidos desta conta'), findsOneWidget);
    expect(find.descendant(of: _modal(), matching: find.text('ped-andamento')), findsOneWidget);
    await _clicar(tester, find.text('Fechar'));
    expect(tester.takeException(), isNull);
  });

  test('API lê os 4 campos e aceita resposta sem eles', () async {
    Map<String, Object?> corpo = {
      'pedidos_futuros_cancelados': 2,
      'pedidos_em_andamento': 1,
      'pedidos_em_andamento_ids': ['a'],
      'pedidos_futuros_pendentes_ids': ['b'],
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        return http.Response(jsonEncode(corpo), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final r = (await api.alterarStatusUsuario('u1', status: 'bloqueado', motivo: 'motivo interno'))!;
    expect((r.futurosCancelados, r.emAndamento), (2, 1));
    expect(r.emAndamentoIds, ['a']);
    expect(r.futurosPendentesIds, ['b']);
    corpo = {};
    expect(await api.alterarStatusUsuario('u1', status: 'bloqueado', motivo: 'motivo interno'), isNull);
  });

  test('só suspensão e encerramento cancelam pedidos', () {
    expect(['suspensao', 'encerramento'].every(medidaCancelaPedidos), isTrue);
    expect(['aviso', 'restricao', 'bloqueio_preventivo', 'trava_saque', 'remocao_conteudo'].any(medidaCancelaPedidos),
        isFalse);
  });
}
