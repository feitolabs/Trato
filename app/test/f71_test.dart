import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/exemplos/telas/profissional_cadastro/cadastro_fake.dart';

const _tela = Size(320, 568);
const _teclado = 260.0;

/// Abre a tela em 320×568 com o teclado aberto (a área útil encolhe em [_teclado]).
Future<void> _abrirComTeclado(WidgetTester tester, Widget tela, {bool tecladoJa = true}) async {
  tester.view.physicalSize = _tela;
  tester.view.devicePixelRatio = 1;
  if (tecladoJa) tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

/// Rola até o fim e confere que o botão principal está inteiro acima do teclado, sem overflow.
Future<void> _botaoAcessivel(WidgetTester tester, Finder botao) async {
  final rolavel = find.byType(Scrollable);
  if (rolavel.evaluate().isNotEmpty) {
    await tester.drag(rolavel.first, const Offset(0, -6000));
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull, reason: 'overflow/erro com o teclado aberto');
  expect(botao, findsOneWidget);
  final r = tester.getRect(botao);
  expect(r.top, greaterThanOrEqualTo(0));
  expect(r.bottom, lessThanOrEqualTo(_tela.height - _teclado + 0.5),
      reason: 'botão ficou atrás do teclado');
  expect(botao.hitTestable(), findsOneWidget, reason: 'botão coberto por outro widget');
}

void main() {
  testWidgets('Criar conta: botão principal acessível com teclado em 320x568', (tester) async {
    await _abrirComTeclado(tester, CriarContaTela(servico: ServicoAuthFake()));
    await _botaoAcessivel(tester, find.widgetWithText(BotaoPrimario, 'Criar conta'));
  });

  testWidgets('Criar pedido: botão principal acessível com teclado em 320x568', (tester) async {
    await _abrirComTeclado(
      tester,
      NovoPedidoTela(
        formulario: formularioExemplo,
        aoTrocarCategoria: () {},
        aoMudarEndereco: () {},
        aoAdicionarFoto: () {},
      ),
    );
    await _botaoAcessivel(tester, find.widgetWithText(BotaoPrimario, 'Enviar pedido'));
  });

  testWidgets('Calculadora de orçamento: botão principal acessível com teclado em 320x568',
      (tester) async {
    await _abrirComTeclado(
      tester,
      CalculadoraOrcamentoTela(servico: ServicoOrcamentoFake(), tituloPedido: 'Tomadas'),
    );
    await _botaoAcessivel(tester, find.widgetWithText(BotaoPrimario, 'Enviar orçamento'));
  });

  testWidgets('Editar cadastro (profissional): seção aberta com botão acessível e teclado aberto',
      (tester) async {
    await _abrirComTeclado(
      tester,
      CadastroProfissionalTela(
        servico: ServicoCadastroProfissionalFake(
          atual: const DadosCadastroProfissional(
            nome: 'Carlos Almeida',
            sobre: 'Instalações elétricas',
            categorias: {'Eletricista'},
            cidade: 'Belo Horizonte',
            raioKm: 10,
            dias: {'Seg', 'Qua'},
            periodos: {'Manhã'},
            portfolio: ['foto-1'],
          ),
        ),
      ),
      tecladoJa: false,
    );
    // O teclado só abre depois de entrar numa seção para editar.
    await tester.tap(find.text('Dados básicos'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
    await tester.pumpAndSettle();
    await _botaoAcessivel(tester, find.widgetWithText(BotaoPrimario, 'Salvar alterações'));
  });
}
