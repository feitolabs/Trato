// TERMOS-APP1: o app segue os Termos v1.2 (e-mails, 12.4, 13.2, 15.2, 4.1 e 9.2).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/repositorios.dart' show PreferenciaNotificacao;
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/carteira/avaliar_cliente_tela.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/notificacoes/preferencias_notificacoes_tela.dart';
import 'package:trato/telas/pedidos/atendimento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(
      theme: TemaTrato.claro,
      builder: (c, f) => EscalaFonteLimitada(child: f!),
      home: tela,
    );

class _Preferencias extends RepositorioNotificacoesFake {
  List<PreferenciaNotificacao>? salvas;

  @override
  Future<List<PreferenciaNotificacao>> carregarPreferencias() async => const [
        // Desligadas no servidor: a tela mostra ligadas e grava ligadas.
        PreferenciaNotificacao(categoria: 'pagamentos', app: false, email: false),
        PreferenciaNotificacao(categoria: 'disputas', app: false, email: false),
        PreferenciaNotificacao(categoria: 'agenda'),
      ];

  @override
  Future<List<PreferenciaNotificacao>> salvarPreferencias(
      List<PreferenciaNotificacao> itens) async {
    salvas = List.of(itens);
    return itens;
  }
}


void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  test('e-mails: nenhum endereço antigo em lib/ e assets/', () {
    final antigos = RegExp(r'@(tratofeito\.com\.br|trato\.app\.br)');
    for (final pasta in ['lib', 'assets']) {
      for (final f in Directory(pasta).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') && !f.path.endsWith('.md')) continue;
        expect(antigos.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    }
    expect(File('assets/legal/politica-de-privacidade.md').readAsStringSync(),
        contains('privacidade@tratofeitolabs.com.br'));
  });

  test('12.4 e 13.2: sem "cinco estrelas" na ilustração e Tratinhos não são "moeda"', () {
    expect(File('lib/telas/onboarding/ilustracoes_cliente.dart').readAsStringSync(),
        isNot(contains('avalie com cinco estrelas')));
    expect(File('lib/telas/ajuda/servico_ajuda_local.dart').readAsStringSync(),
        isNot(contains('moeda de desconto')));
  });

  testWidgets('12.4: a avaliação do profissional avisa que vale qualquer nota', (t) async {
    await _janela(t, _tamanhos.last, 1.3);
    await t.pumpWidget(_app(const AvaliacaoTela(
      dados: DadosAvaliacao(
        nomeProfissional: 'Carlos',
        valorLiberadoCentavos: 42500,
        criterios: ['Qualidade'],
        gorjetasCentavos: [],
        bonusDisponivel: true,
        bonusMoedas: 50,
        valorMoedaCentavos: 1,
      ),
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('Vale para qualquer nota', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('12.4: a avaliação do cliente avisa que vale qualquer nota', (t) async {
    await _janela(t, _tamanhos.last, 1.3);
    await t.pumpWidget(_app(AvaliarClienteTela(
      pedidoNumero: '#AB12',
      aoEnviar: (_, __) async => 0,
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('com qualquer nota', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('15.2: disputa e pagamento ficam ligados no app e no e-mail ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final repo = _Preferencias();
        await t.pumpWidget(_app(PreferenciasNotificacoesTela(repositorio: repo)));
        await t.pumpAndSettle();
        final lista = find.byType(Scrollable).first;
        SwitchListTile chave(String k) => t.widget<SwitchListTile>(find.byKey(Key(k)));

        for (final categoria in ['pagamentos', 'disputas']) {
          await t.scrollUntilVisible(find.byKey(Key('switch-email-$categoria')), 150,
              scrollable: lista);
          for (final canal in ['app', 'email']) {
            expect(chave('switch-$canal-$categoria').value, isTrue);
            expect(chave('switch-$canal-$categoria').onChanged, isNull);
          }
          expect(find.byKey(Key('aviso-obrigatorio-$categoria'), skipOffstage: false),
              findsOneWidget);
        }

        // Categoria comum continua livre; ao gravar, as obrigatórias vão ligadas.
        await t.scrollUntilVisible(find.byKey(const Key('switch-email-agenda')), 150,
            scrollable: lista);
        await t.ensureVisible(find.byKey(const Key('switch-email-agenda')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('switch-email-agenda')));
        await t.pumpAndSettle();
        expect(repo.salvas, isNotNull);
        for (final p in repo.salvas!.where((p) => p.categoria != 'agenda')) {
          expect((p.app, p.email), (true, true), reason: p.categoria);
        }
        expect(repo.salvas!.last.email, isFalse);
        expect(t.takeException(), isNull);
      });

      testWidgets('9.2: o SOS mostra 190, 192 e 193 ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final ligados = <String>[];
        await t.pumpWidget(_app(Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarEmergencia(c, 'Atendimento Trato (#AB12)', ligar: (n) async {
                ligados.add(n);
                return n != '193';
              }),
              child: const Text('sos'),
            ),
          ),
        )));
        for (final numero in ['190', '192', '193']) {
          await t.tap(find.text('sos'));
          await t.pumpAndSettle();
          final botao = find.byKey(ValueKey('ligar-$numero'));
          await t.ensureVisible(botao);
          await t.pumpAndSettle();
          await t.tap(botao);
          await t.pumpAndSettle();
        }
        expect(ligados, ['190', '192', '193']);
        // Sem telefone no aparelho, a pessoa vê o número para discar.
        expect(find.textContaining('Disque 193'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('4.1: o cadastro exige a data e bloqueia menor de 18 ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final auth = ServicoAuthFake();
        await t.pumpWidget(_app(CriarContaTela(servico: auth)));
        await t.pumpAndSettle();
        Finder campo(int i) => find.byType(TextField).at(i);
        Future<void> digitar(int i, String valor) async {
          await t.ensureVisible(campo(i));
          await t.pumpAndSettle();
          await t.enterText(campo(i), valor);
          await t.pump();
        }

        await digitar(0, 'Ana Souza');
        await digitar(2, '31999998888');
        await digitar(3, 'ana@teste.com');
        await digitar(4, 'segredo123');
        await t.ensureVisible(find.byType(Checkbox).first);
        await t.pumpAndSettle();
        await t.tap(find.byType(Checkbox).first);
        await t.pump();
        Future<void> criar() async {
          await t.tap(find.text('Criar conta').last);
          await t.pumpAndSettle();
        }

        await criar();
        expect(find.text('Data incompleta. Use dd/mm/aaaa.', skipOffstage: false), findsOneWidget);
        expect(auth.sessaoAtual, isNull);

        final ano = DateTime.now().year - 10;
        await digitar(1, '0101$ano');
        await criar();
        expect(find.text('O cadastro é exclusivo para maiores de 18 anos.', skipOffstage: false),
            findsOneWidget);
        expect(auth.sessaoAtual, isNull);

        await digitar(1, '15031992');
        await criar();
        expect(auth.sessaoAtual?.email, 'ana@teste.com');
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('9.2: a barra do atendimento chama o SOS', (t) async {
    await _janela(t, _tamanhos.first, 1);
    var sos = 0;
    await t.pumpWidget(_app(Scaffold(
      body: BarraAtendimento(aoChat: () {}, aoAjuda: () {}, aoSos: () => sos++),
    )));
    await t.tap(find.byKey(const ValueKey('botao-sos-emergencia')));
    expect(sos, 1);
  });
}
