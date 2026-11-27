// TERMOS-APP15: tributos no preço (6.1), limite dos Tratinhos antes de usar e PDF na
// contestação de medida (20.5).
import 'dart:convert';
import 'dart:typed_data';

// O pacote vem junto do file_selector; aqui só para simular o seletor do sistema.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/seletor_pdf.dart';
import 'package:trato/telas/aditivo/responder_aditivo_tela.dart';
import 'package:trato/telas/comuns/textos_dos_termos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/medidas/medidas_tela.dart';
import 'package:trato/telas/medidas/modelos.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/orcamentos/dados_exemplo.dart' as exorc;
import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as expag;
import 'apoio/fontes.dart';
import 'apoio/exemplos/telas/aditivo/aditivo_fake.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

Future<void> _ver(WidgetTester t, Finder alvo) async {
  if (alvo.evaluate().isEmpty) {
    await t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);
  }
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await _ver(t, alvo);
  await t.tap(alvo);
  await t.pumpAndSettle();
}

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json'},
    );

Uint8List _pdf([int n = 2048]) => Uint8List(n)..setRange(0, 5, '%PDF-'.codeUnits);

class _Seletor extends FileSelectorPlatform {
  _Seletor(this.arquivo);
  XFile? arquivo;
  List<XTypeGroup>? tipos;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    tipos = acceptedTypeGroups;
    return arquivo;
  }
}

class _Medidas implements ServicoMedidas {
  @override
  Future<List<MedidaDeConta>?> listar() async => const [];

  @override
  Object? noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _medida = MedidaDeConta(
  id: 'm1',
  tipo: 'aviso',
  contestavelAte: DateTime.now().add(const Duration(days: 10)),
);

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  group('1. Tributos incluídos (6.1)', () {
    test('o texto é o do termo', () {
      expect(textoPrecoComTributos, contains('já inclui os tributos que incidam sobre ele'));
      expect(textoPrecoComTributos, contains('todas as despesas conhecidas'));
      expect(textoPrecoComTributos,
          contains('(materiais, deslocamento, taxa de parcelamento) é informado antes'));
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        for (final (nome, tela) in <(String, Widget Function())>[
          (
            'orçamentos recebidos',
            () => OrcamentosRecebidosTela(
                pedido: exorc.resumoPedidoExemplo, orcamentos: exorc.orcamentosExemplo),
          ),
          (
            'detalhe do orçamento',
            () => DetalheOrcamentoTela(
                orcamento: exorc.orcamentosExemplo.firstWhere((o) => o.detalhe != null)),
          ),
          (
            'aditivo',
            () => ResponderAditivoTela(
                servico: ServicoAditivoFake(detalhe: aditivoExemplo), aditivoId: 'a'),
          ),
          ('pagamento', () => const PagamentoTela(dados: expag.DadosExemplo.pagamento)),
        ]) {
          testWidgets('$nome ${tamanho.width.toInt()} fonte $fonte', (t) async {
            await _janela(t, tamanho, fonte);
            await t.pumpWidget(_app(tela()));
            await t.pumpAndSettle();
            await _ver(t, find.byKey(const Key('nota-tributos')));
            expect(find.text(textoPrecoComTributos), findsOneWidget);
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });

  group('2. Limite dos Tratinhos antes de usar', () {
    RepositorioPagamentoApi repo(
      List<String> caminhos, {
      int saldo = 500,
      Map<String, Object?>? moedas,
      int statusDasMoedas = 200,
    }) =>
        RepositorioPagamentoApi(ClienteApi(
          urlBase: 'https://api.teste',
          sessao: SessaoTrato()..entrar('t'),
          cliente: MockClient((r) async {
            caminhos.add(r.url.path);
            if (r.url.path.endsWith('/pagamento')) {
              return _json({
                'valor_centavos': 20000,
                'meios_disponiveis': ['pix'],
                'moedas_saldo': saldo,
              });
            }
            if (r.url.path == '/v1/me/moedas') {
              return _json(moedas ?? {'detail': 'x'}, statusDasMoedas);
            }
            return _json({'cpf_cadastrado': true});
          }),
        ));

    test('lê o teto e o usado no mês do servidor', () async {
      final d = await repo([], moedas: {
        'teto_desconto_mes_centavos': 3210,
        'desconto_usado_mes_centavos': 45,
      }).dados('p1');
      expect((d.tetoDescontoMesCentavos, d.descontoUsadoMesCentavos), (3210, 45));
    });

    test('servidor sem o campo, ou com erro: sem número, e o pagamento abre', () async {
      for (final r in [repo([], moedas: {'saldo': 1}), repo([], statusDasMoedas: 500)]) {
        final d = await r.dados('p1');
        expect(d.valorAgoraCentavos, 20000);
        expect(d.tetoDescontoMesCentavos, isNull);
      }
    });

    test('sem Tratinhos, nem pergunta', () async {
      final caminhos = <String>[];
      await repo(caminhos, saldo: 0).dados('p1');
      expect(caminhos, isNot(contains('/v1/me/moedas')));
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        testWidgets('aparece antes do interruptor e segue após ligar '
            '(${tamanho.width.toInt()} fonte $fonte)', (t) async {
          await _janela(t, tamanho, fonte);
          final base = expag.DadosExemplo.pagamento.copiarCom(
              moedasSaldo: 500,
              tetoDescontoMesCentavos: 3210,
              descontoUsadoMesCentavos: 45);
          // O recálculo não traz o limite: a tela continua com o que já leu.
          await t.pumpWidget(_app(PagamentoTela(
            dados: base,
            aoAlternarMoedas: (usar, _) async =>
                expag.DadosExemplo.pagamento.copiarCom(moedasSaldo: 500, moedasUsadas: 100),
          )));
          await t.pumpAndSettle();
          const texto = 'Limite de desconto com Tratinhos: R\$ 32,10 por mês. '
              'Você já usou R\$ 0,45 neste mês.';
          final limite = find.text(texto, skipOffstage: false);
          final interruptor = find.byKey(const Key('interruptor-moedas'));
          await _ver(t, interruptor);
          expect(limite, findsOneWidget);
          expect(t.getTopLeft(limite).dy, lessThan(t.getTopLeft(interruptor).dy));
          await _tocar(t, interruptor);
          expect(find.text(texto, skipOffstage: false), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('sem o teto, a tela diz que não foi informado', (t) async {
      await _janela(t, const Size(390, 844), 1);
      await t.pumpWidget(_app(PagamentoTela(
        dados: expag.DadosExemplo.pagamento.copiarCom(moedasSaldo: 500),
        aoAlternarMoedas: (_, __) async => expag.DadosExemplo.pagamento,
      )));
      await t.pumpAndSettle();
      await _ver(t, find.byKey(const Key('limite-tratinhos')));
      expect(find.text('O limite mensal do desconto com Tratinhos não foi informado agora.'),
          findsOneWidget);
    });
  });

  group('3. PDF na contestação de medida (20.5)', () {
    test('o seletor pede só PDF (Android e iOS) e devolve o arquivo', () async {
      final anterior = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = anterior);
      final s = _Seletor(XFile.fromData(_pdf(), name: 'nota.pdf', path: 'nota.pdf'));
      FileSelectorPlatform.instance = s;
      final p = (await escolherPdfDoAparelho())!;
      expect(tipoDaProva(p.bytes), 'application/pdf');
      expect(p.bytes.length, 2048);
      final tipo = s.tipos!.single;
      expect(tipo.mimeTypes, ['application/pdf']);
      expect(tipo.uniformTypeIdentifiers, ['com.adobe.pdf']);

      s.arquivo = null;
      expect(await escolherPdfDoAparelho(), isNull);
      s.arquivo = XFile.fromData(_pdf(tamanhoMaximoDaProva + 1), path: 'grande.pdf');
      await expectLater(escolherPdfDoAparelho(), throwsA(isA<PdfGrandeDemais>()));
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        testWidgets('anexa o PDF e mostra os erros (${tamanho.width.toInt()} fonte $fonte)',
            (t) async {
          await _janela(t, tamanho, fonte);
          Future<ProvaEscolhida?> Function() proximo =
              () async => ProvaEscolhida(nome: 'nota.pdf', bytes: _pdf());
          await t.pumpWidget(_app(ContestarMedidaTela(
            servico: _Medidas(),
            medida: _medida,
            escolherPdf: () => proximo(),
          )));
          await t.pumpAndSettle();
          final botao = find.byKey(const Key('adicionar-pdf'));
          expect(find.byKey(const Key('adicionar-prova')), findsNothing);
          await _tocar(t, botao);
          expect(find.textContaining('nota.pdf · 2 KB', skipOffstage: false), findsOneWidget);

          proximo = () async => throw const PdfGrandeDemais('grande.pdf');
          await _tocar(t, botao);
          expect(find.text('O arquivo "grande.pdf" passa de 10 MB.', skipOffstage: false),
              findsOneWidget);
          proximo = () async => ProvaEscolhida(nome: 'x.pdf', bytes: Uint8List(10));
          await _tocar(t, botao);
          expect(find.text(textoProvaRecusada, skipOffstage: false), findsOneWidget);
          expect(find.textContaining('nota.pdf · 2 KB', skipOffstage: false), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('o app liga foto e PDF na contestação', (t) async {
      await _janela(t, const Size(390, 2400), 1);
      RotasTrato.repos = repositoriosDemo(medidas: _Medidas());
      await t.pumpWidget(_app(Builder(
        builder: (c) => TextButton(
          onPressed: () => RotasTrato.abrirMedidas(c),
          child: const Text('abrir'),
        ),
      )));
      await _tocar(t, find.text('abrir'));
      final tela = t.widget<MedidasTela>(find.byType(MedidasTela));
      expect(tela.escolherProva, isNotNull);
      expect(tela.escolherPdf, escolherPdfDoAparelho);
    });
  });
}
