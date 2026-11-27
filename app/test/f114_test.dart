// TERMOS-APP16: aviso dos Tratinhos antes de encerrar a conta (13.10 e I.11).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/comuns/textos_dos_termos.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'package:trato/telas/lgpd/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/lgpd/servico_fake.dart';
import 'apoio/fontes.dart';

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  if (alvo.evaluate().isEmpty) {
    await t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);
  }
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

class _Servico extends ServicoPrivacidadeFake implements ConsultaDeTratinhos {
  _Servico(this.saldo, {this.falha = false});
  SaldoTratinhos? saldo;
  bool falha;
  Completer<void>? espera;

  @override
  Future<SaldoTratinhos?> saldoDeTratinhos() async {
    await espera?.future;
    if (falha) throw ErroTrato.semInternet;
    return saldo;
  }
}

ServicoPrivacidadeApi _api(Object corpo, [int status = 200, List<String>? caminhos]) =>
    ServicoPrivacidadeApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        caminhos?.add('${r.method} ${r.url.path}');
        return http.Response(jsonEncode(corpo), status,
            headers: const {'content-type': 'application/json'});
      }),
    ));

String _saldoNaTela(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('saldo-no-encerramento'), skipOffstage: false)).data!;

void main() {
  setUpAll(carregarFontesTrato);

  test('lê tratinhos_a_perder em GET/POST /v1/me/exclusao e fallback em /v1/me/moedas', () async {
    final caminhos = <String>[];
    final s = (await _api(
      {'tratinhos_a_perder': 50, 'saldo': 150, 'saldo_profissional': 20, 'valor_moeda_centavos': 1},
      200,
      caminhos,
    ).saldoDeTratinhos())!;
    expect(caminhos, ['GET /v1/me/exclusao', 'GET /v1/me/moedas']);
    expect((s.tratinhosAPerder, s.cliente, s.profissional, s.valorMoedaCentavos), (50, 150, 20, 1));

    // POST /v1/me/exclusao passo 1 devolve token e tratinhos_a_perder (ou ausente no backend antigo).
    final p1 =
        await _api({'token_confirmacao': 'tok1', 'tratinhos_a_perder': 75}).iniciarExclusao();
    expect((p1.tokenConfirmacao, p1.tratinhosAPerder), ('tok1', 75));
    final p1Antigo = await _api({'token_confirmacao': 'tok2'}).iniciarExclusao();
    expect((p1Antigo.tokenConfirmacao, p1Antigo.tratinhosAPerder), ('tok2', null));

    // Campo ausente, 404/503 e erro 500.
    final vazio = (await _api(<String, Object>{}).saldoDeTratinhos())!;
    expect((vazio.tratinhosAPerder, vazio.cliente), (null, null));
    for (final status in [404, 503]) {
      expect(await _api({'detail': 'x'}, status).saldoDeTratinhos(), isNull);
    }
    await expectLater(_api({'detail': 'x'}, 500).saldoDeTratinhos(), throwsA(isA<ErroTrato>()));
  });

  testWidgets('tratinhos_a_perder > 0, 0 e ausente antes da confirmação final', (t) async {
    await _janela(t, const Size(390, 1600), 1);
    for (final (i, caso) in [
      (
        const SaldoTratinhos(tratinhosAPerder: 50, valorMoedaCentavos: 1),
        'Você perderá 50 Tratinhos = R\$ 0,50 ao encerrar a conta por vontade própria.'
      ),
      (
        const SaldoTratinhos(tratinhosAPerder: 0, valorMoedaCentavos: 1),
        'Você não tem Tratinhos disponíveis agora. Eventual saldo não é mantido ao encerrar por vontade própria.'
      ),
      (const SaldoTratinhos(), 'O saldo de Tratinhos não foi informado agora.'),
    ].indexed) {
      final servico = _Servico(caso.$1);
      await t.pumpWidget(_app(ExcluirContaTela(key: ValueKey('1310-$i'), servico: servico)));
      await t.pumpAndSettle();
      expect(find.text(textoTratinhosNoEncerramento, skipOffstage: false), findsOneWidget);
      expect(_saldoNaTela(t), caso.$2);
      await _tocar(t, find.text('Continuar'));
      expect(_saldoNaTela(t), caso.$2);
      expect(servico.exclusoes, 0);
    }
  });

  for (final tamanho in const [Size(390, 844), Size(320, 568)]) {
    for (final fonte in const [1.0, 1.3]) {
      testWidgets('aviso e saldo antes de confirmar (${tamanho.width.toInt()} fonte $fonte)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final s = _Servico(const SaldoTratinhos(cliente: 150, valorMoedaCentavos: 1));
        await t.pumpWidget(_app(ExcluirContaTela(servico: s)));
        await t.pumpAndSettle();
        expect(find.text(textoTratinhosNoEncerramento, skipOffstage: false), findsOneWidget);
        expect(_saldoNaTela(t), 'Seu saldo: 150 Tratinhos = R\$ 1,50.');
        await _tocar(t, find.text('Continuar'));
        // No passo da confirmação o aviso vem antes do botão, e nada foi pedido ainda.
        expect(find.text(textoTratinhosNoEncerramento, skipOffstage: false), findsOneWidget);
        expect(_saldoNaTela(t), contains('150 Tratinhos'));
        expect(s.exclusoes, 0);
        expect(find.textContaining('90 dias', skipOffstage: false), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('duas carteiras, saldo zero, sem o campo e sem a função', (t) async {
    await _janela(t, const Size(390, 1600), 1);
    for (final (i, caso) in [
      (
        const SaldoTratinhos(cliente: 1, profissional: 50),
        'Saldo como cliente: 1 Tratinho.\nSaldo como profissional: 50 Tratinhos.'
      ),
      (const SaldoTratinhos(cliente: 0), 'Você não tem Tratinhos agora.'),
      (const SaldoTratinhos(), 'O saldo de Tratinhos não foi informado agora.'),
      (null, 'O saldo de Tratinhos não foi informado agora.'),
    ].indexed) {
      await t.pumpWidget(_app(ExcluirContaTela(key: ValueKey(i), servico: _Servico(caso.$1))));
      await t.pumpAndSettle();
      expect(_saldoNaTela(t), caso.$2);
    }
  });

  testWidgets('carregando, erro com nova tentativa; o erro não impede encerrar', (t) async {
    await _janela(t, const Size(390, 1600), 1);
    final s = _Servico(const SaldoTratinhos(cliente: 3), falha: true)..espera = Completer<void>();
    await t.pumpWidget(_app(ExcluirContaTela(servico: s)));
    await t.pump();
    expect(_saldoNaTela(t), 'Conferindo o seu saldo de Tratinhos…');
    s.espera!.complete();
    await t.pumpAndSettle();
    expect(_saldoNaTela(t), 'Não deu para ver o seu saldo de Tratinhos agora.');
    await _tocar(t, find.text('Continuar'));
    await t.enterText(find.byType(TextField), ExcluirContaTela.palavraConfirmacao);
    await t.pump();
    s.falha = false;
    await _tocar(t, find.text('Tentar de novo'));
    expect(_saldoNaTela(t), 'Seu saldo: 3 Tratinhos.');
    await _tocar(t, find.widgetWithText(FilledButton, 'Excluir minha conta'));
    expect(s.exclusoes, 1);
  });
}
