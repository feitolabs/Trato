import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dispositivo/abrir_link.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/profissional_mei/mei.dart';
import 'package:trato/telas/profissional_mei/meu_cnpj_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _valido = '11.444.777/0001-61';

class _Fake implements ServicoMei {
  _Fake(this.atual, {this.erroAoValidar, this.erroAoCarregar});

  DadosMei atual;
  final ErroTrato? erroAoValidar;
  final ErroTrato? erroAoCarregar;
  final enviados = <String>[];

  @override
  Future<DadosMei> carregar() async {
    if (erroAoCarregar != null) throw erroAoCarregar!;
    return atual;
  }

  @override
  Future<DadosMei> validar(String cnpjSoDigitos) async {
    enviados.add(cnpjSoDigitos);
    if (erroAoValidar != null) throw erroAoValidar!;
    return atual = const DadosMei(
      cnpj: '11444777000161',
      status: StatusMei.valido,
      razaoSocial: 'Carlos Lima Eletricista ME',
      podeOrcarEReceber: true,
    );
  }
}

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

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() {
    RotasTrato.repos = repositoriosDemo();
    abrirLink = (u) async => false;
  });

  group('regras locais do CNPJ', () {
    test('máscara e dígito verificador', () {
      expect(formatarCnpj('11444777000161'), _valido);
      expect(formatarCnpj('114447'), '11.444.7');
      expect(soDigitosCnpj('11.444.777/0001-61xx99'), '11444777000161');
      expect(cnpjParecidoValido(_valido), isTrue);
      expect(cnpjParecidoValido('11.444.777/0001-62'), isFalse);
      expect(cnpjParecidoValido('11111111111111'), isFalse);
      expect(cnpjParecidoValido('123'), isFalse);
    });

    test(
        'resposta com campo ausente usa valor seguro; tipo_cnpj ausente é ignorado',
        () {
      final d = DadosMei.deJson(const {});
      expect(d.status, StatusMei.naoInformado);
      expect(d.podeOrcarEReceber, isFalse);
      expect(d.tipoCnpj, isNull);
      final v = DadosMei.deJson(const {
        'cnpj': '11444777000161',
        'mei_status': 'valido',
        'razao_social': 'X',
        'pode_orcar_e_receber': true,
        'tipo_cnpj': 'mei',
      });
      expect(v.status, StatusMei.valido);
      expect(v.tipoCnpj, 'mei');
      expect(DadosMei.deJson(const {'mei_status': '???'}).status,
          StatusMei.naoInformado);
    });

    test('mensagem de CNPJ/MEI é reconhecida', () {
      expect(mensagemDeCnpj('Informe um CNPJ ativo para enviar orçamentos.'),
          isTrue);
      expect(mensagemDeCnpj('É preciso ser MEI.'), isTrue);
      expect(mensagemDeCnpj('Garantia mínima de 30 dias.'), isFalse);
    });
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final rotulo =
          '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('sem CNPJ: explica o MEI e abre o gov.br ($rotulo)',
          (t) async {
        await _janela(t, tamanho, fonte);
        Uri? aberto;
        abrirLink = (u) async {
          aberto = u;
          return true;
        };
        await t.pumpWidget(_app(MeuCnpjTela(servico: _Fake(const DadosMei()))));
        await t.pumpAndSettle();
        expect(find.text('Meu CNPJ'), findsOneWidget);
        expect(find.text('CNPJ não informado'), findsOneWidget);
        expect(find.text('Sem CNPJ você não consegue enviar orçamentos.'),
            findsWidgets);
        await t.scrollUntilVisible(
            find.byKey(const Key('botao-abrir-mei')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Abrir o MEI é grátis e leva cerca de 10 minutos.'),
            findsOneWidget);
        expect(find.text('Volte aqui para informar o número.'), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('botao-abrir-mei')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('botao-abrir-mei')));
        await t.pumpAndSettle();
        expect(aberto.toString(),
            'https://www.gov.br/empresas-e-negocios/pt-br/empreendedor');
        expect(t.takeException(), isNull);
      });

      testWidgets('digita com máscara e valida; mostra o selo ($rotulo)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final f = _Fake(const DadosMei());
        await t.pumpWidget(_app(MeuCnpjTela(servico: f)));
        await t.pumpAndSettle();
        await t.enterText(
            find.byKey(const Key('campo-cnpj')), '11444777000161');
        await t.pumpAndSettle();
        expect(find.text(_valido), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('botao-validar-cnpj')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('botao-validar-cnpj')));
        await t.pumpAndSettle();
        expect(f.enviados, ['11444777000161']);
        expect(find.text('CNPJ verificado'), findsOneWidget);
        expect(find.text('Carlos Lima Eletricista ME'), findsOneWidget);
        expect(find.byKey(const Key('botao-abrir-mei')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('422: o texto do servidor aparece junto do campo ($rotulo)',
          (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(MeuCnpjTela(
          servico: _Fake(const DadosMei(),
              erroAoValidar: const ErroTrato(
                  TipoErro.recusado, 'Este CNPJ não está ativo.',
                  codigoHttp: 422)),
        )));
        await t.pumpAndSettle();
        await t.enterText(
            find.byKey(const Key('campo-cnpj')), '11444777000161');
        await t.ensureVisible(find.byKey(const Key('botao-validar-cnpj')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('botao-validar-cnpj')));
        await t.pumpAndSettle();
        expect(find.text('Este CNPJ não está ativo.'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('pendente e inválido mostram o motivo ($rotulo)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(MeuCnpjTela(
          servico: _Fake(const DadosMei(
              cnpj: '11444777000161',
              status: StatusMei.pendente,
              motivo: 'Receita fora do ar.')),
        )));
        await t.pumpAndSettle();
        expect(find.text('Em conferência'), findsOneWidget);
        expect(find.text('Motivo: Receita fora do ar.'), findsOneWidget);

        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(MeuCnpjTela(
          servico: _Fake(const DadosMei(
              cnpj: '11444777000161',
              status: StatusMei.invalido,
              motivo: 'CNPJ baixado.')),
        )));
        await t.pumpAndSettle();
        expect(find.text('CNPJ não validado'), findsOneWidget);
        expect(find.text('Motivo: CNPJ baixado.'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('erro ao carregar: mostra o erro com nova tentativa', (t) async {
    await _janela(t, _tamanhos.first, 1);
    await t.pumpWidget(_app(MeuCnpjTela(
      servico: _Fake(const DadosMei(),
          erroAoCarregar:
              const ErroTrato(TipoErro.semInternet, 'Sem internet.')),
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('campo-cnpj')), findsNothing);
    expect(find.textContaining('Tentar'), findsWidgets);
  });

  testWidgets('CNPJ com dígito errado: só uma dica, o servidor decide',
      (t) async {
    await _janela(t, _tamanhos.first, 1);
    final f = _Fake(const DadosMei());
    await t.pumpWidget(_app(MeuCnpjTela(servico: f)));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('campo-cnpj')), '11444777000162');
    await t.pumpAndSettle();
    expect(find.textContaining('parece estar incorreto'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('botao-validar-cnpj')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('botao-validar-cnpj')));
    await t.pumpAndSettle();
    expect(f.enviados, ['11444777000162']);
  });

  group('orçamento barrado por falta de CNPJ', () {
    for (final fonte in _fontes) {
      testWidgets(
          '422 de CNPJ: texto do servidor e botão "Informar meu CNPJ" (x$fonte)',
          (t) async {
        await _janela(t, _tamanhos.first, fonte);
        RotasTrato.repos = repositoriosDemo(mei: _Fake(const DadosMei()));
        late BuildContext ctx;
        await t.pumpWidget(_app(Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })));
        final ok = RotasTrato.tentarOrcamento(
            ctx,
            () async => throw const ErroTrato(TipoErro.recusado,
                'Informe um CNPJ ativo para enviar orçamentos.',
                codigoHttp: 422));
        await t.pumpAndSettle();
        expect(
            find.byKey(const Key('dialogo-cnpj-necessario')), findsOneWidget);
        expect(find.text('Informe um CNPJ ativo para enviar orçamentos.'),
            findsOneWidget);
        await t.tap(find.byKey(const Key('botao-informar-cnpj')));
        await t.pumpAndSettle();
        expect(find.byType(MeuCnpjTela), findsOneWidget);
        expect(await ok, isFalse);
      });
    }

    testWidgets('422 de outro assunto não mostra o botão de CNPJ', (t) async {
      await _janela(t, _tamanhos.first, 1);
      RotasTrato.repos = repositoriosDemo(mei: _Fake(const DadosMei()));
      late BuildContext ctx;
      await t.pumpWidget(_app(Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))));
      final ok = RotasTrato.tentarOrcamento(
          ctx,
          () async => throw const ErroTrato(
              TipoErro.recusado, 'Garantia mínima de 30 dias.',
              codigoHttp: 422));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dialogo-cnpj-necessario')), findsNothing);
      expect(await ok, isFalse);
    });
  });

  testWidgets('Configurações do profissional tem "Meu CNPJ"; a do cliente não',
      (t) async {
    await _janela(t, _tamanhos.first, 1);
    RotasTrato.repos = repositoriosDemo(mei: _Fake(const DadosMei()));
    for (final profissional in [true, false]) {
      late BuildContext ctx;
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      RotasTrato.abrirConfiguracoes(ctx, profissional: profissional);
      await t.pumpAndSettle();
      expect(
          find.text('Meu CNPJ'), profissional ? findsOneWidget : findsNothing);
      if (profissional) {
        await t.tap(find.text('Meu CNPJ'));
        await t.pumpAndSettle();
        expect(find.byType(MeuCnpjTela), findsOneWidget);
      }
    }
  });
}
