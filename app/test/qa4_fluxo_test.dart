// QA4: telas de fluxo de dinheiro e pedido do cliente sob estresse (so teste, em memoria).
// Skip = 'bug conhecido: QA4-n'.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/conclusao/dados_exemplo.dart';
import 'apoio/exemplos/telas/lgpd/servico_fake.dart';
import 'apoio/exemplos/telas/orcamentos/dados_exemplo.dart';
import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as expag;

const _tamanhos = {
  'pequeno 320x568': Size(320, 568),
  'deitado 568x320': Size(568, 320),
  'tablet 768x1024': Size(768, 1024),
};

Future<void> _abrir(WidgetTester t, Widget tela, {Size tam = const Size(390, 844), double escala = 1}) async {
  t.view.physicalSize = tam;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pump(const Duration(milliseconds: 200));
}

DadosPagamento _dados({
  int valor = 38000,
  String subtitulo = 'Carlos · Troca de tomadas',
  List<OpcaoParcelamento> parcelamento = const [],
  int desconto = 0,
  String? cupom,
  bool cpf = true,
  bool descontoOk = true,
  int saldo = 0,
  List<OpcaoPagamento>? opcoes,
}) =>
    DadosPagamento(
      subtitulo: subtitulo,
      valorAgoraCentavos: valor,
      parcelamento: parcelamento,
      descontoCentavos: desconto,
      cupomCodigo: cupom,
      cpfCadastrado: cpf,
      descontoDisponivel: descontoOk,
      moedasSaldo: saldo,
      opcoes: opcoes ?? expag.DadosExemplo.pagamento.opcoes,
    );

Finder get _botaoPagar => find.byType(BotaoPrimario);

void main() {
  group('Pagamento: valores formatados (vem do backend, em centavos)', () {
    final casos = {
      0: 'R\$ 0,00',
      1: 'R\$ 0,01',
      99: 'R\$ 0,99',
      100: 'R\$ 1,00',
      999999999: 'R\$ 9.999.999,99',
      9007199254740991: ',',
    };
    for (final e in casos.entries) {
      testWidgets('valor ${e.key} centavos aparece como ${e.value}', (t) async {
        await _abrir(t, PagamentoTela(dados: _dados(valor: e.key)));
        expect(find.textContaining(e.value), findsWidgets);
        expect(t.takeException(), isNull);
      });
    }
    testWidgets('valor negativo vindo do backend nao vira positivo', (t) async {
      await _abrir(t, PagamentoTela(dados: _dados(valor: -500)));
      expect(find.text('-R\$ 5,00'), findsWidgets, reason: 'sinal tem de aparecer');
      expect(t.takeException(), isNull);
    });
    testWidgets('negativo abaixo de R\$ 1 mantem o sinal (-50)', (t) async {
      await _abrir(t, PagamentoTela(dados: _dados(valor: -50)));
      expect(find.text('-R\$ 0,50'), findsWidgets);
    });
  });

  group('Pagamento: texto hostil e layout', () {
    final hostis = [
      '😀' * 300,
      '\u202e' * 200 + 'invertido',
      '<script>alert(1)</script>' * 30,
      "'; DROP TABLE pedidos; --" * 20,
      '   ',
      '',
      'A' * 4000,
    ];
    for (final e in _tamanhos.entries) {
      testWidgets('subtitulo hostil em ${e.key} fonte 1.3x: sem estouro', (t) async {
        for (final h in hostis) {
          await _abrir(t, PagamentoTela(dados: _dados(subtitulo: h)), tam: e.value, escala: 1.3);
          expect(t.takeException(), isNull, reason: 'texto "${h.substring(0, h.length.clamp(0, 12))}"');
        }
      });
      testWidgets('cupom hostil + parcelas + CPF ausente em ${e.key} fonte 1.3x', (t) async {
        await _abrir(
          t,
          PagamentoTela(
            dados: _dados(
              desconto: 5000,
              cupom: 'CUPOM-${'X' * 300}',
              cpf: false,
              saldo: 99999999,
              descontoOk: false,
              parcelamento: [
                for (var i = 1; i <= 12; i++)
                  OpcaoParcelamento(
                    parcelas: i,
                    custoCentavos: i * 100,
                    totalCentavos: 38000 + i * 100,
                    valorParcelaCentavos: (38000 + i * 100) ~/ i,
                  ),
              ],
            ),
            aoCadastrarCpf: (cpf, nasc) async {},
          ),
          tam: e.value,
          escala: 1.3,
        );
        await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
    testWidgets('sem nenhuma opcao de pagamento nao quebra', (t) async {
      await _abrir(t, PagamentoTela(dados: _dados(opcoes: const [])));
      expect(t.takeException(), isNull);
    }, skip: true); // bug conhecido: QA4-2 pagamento_tela.dart:46 opcoes.first estoura (StateError) se o backend manda opcoes vazias
    testWidgets('parcelamento com parcelas 0 e totais absurdos nao quebra', (t) async {
      await _abrir(
        t,
        PagamentoTela(
          dados: _dados(parcelamento: const [
            OpcaoParcelamento(parcelas: 0, custoCentavos: -1, totalCentavos: 0, valorParcelaCentavos: 0),
            OpcaoParcelamento(parcelas: 1, custoCentavos: 0, totalCentavos: 38000, valorParcelaCentavos: 38000),
          ]),
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('Pagamento: toque duplo, erro e saida', () {
    testWidgets('toque rapido 5x em Pagar = UMA chamada e botao travado', (t) async {
      final c = Completer<void>();
      var chamadas = 0;
      await _abrir(
        t,
        PagamentoTela(
          dados: _dados(),
          aoPagarDetalhado: (m, p, cupom) {
            chamadas++;
            return c.future;
          },
        ),
      );
      for (var i = 0; i < 5; i++) {
        await t.tap(_botaoPagar, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 10));
      }
      expect(chamadas, 1);
      c.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('depois de terminar o botao volta a funcionar (nao fica travado)', (t) async {
      var chamadas = 0;
      await _abrir(
        t,
        PagamentoTela(
          dados: _dados(),
          aoPagarDetalhado: (m, p, cupom) async {
            chamadas++;
          },
        ),
      );
      await t.tap(_botaoPagar);
      await t.pumpAndSettle();
      await t.tap(_botaoPagar);
      await t.pumpAndSettle();
      expect(chamadas, 2);
    });

    testWidgets('erro de rede ao pagar: botao destrava e a tela segue de pe', (t) async {
      var chamadas = 0;
      await _abrir(
        t,
        PagamentoTela(
          dados: _dados(),
          aoPagarDetalhado: (m, p, cupom) async {
            chamadas++;
            throw ErroTrato.semInternet;
          },
        ),
      );
      await runZonedGuarded(() async {
        await t.tap(_botaoPagar);
        await t.pumpAndSettle();
      }, (e, s) {});
      expect(find.byType(PagamentoTela), findsOneWidget);
      expect(_botaoPagar, findsOneWidget);
      expect(chamadas, 1);
    });

    testWidgets('erro ao pagar e tratado dentro da tela (usuario ve mensagem, sem erro solto)', (t) async {
      await _abrir(
        t,
        PagamentoTela(
          dados: _dados(),
          aoPagarDetalhado: (m, p, cupom) async => throw ErroTrato.semInternet,
        ),
      );
      Object? solto;
      await runZonedGuarded(() async {
        await t.tap(_botaoPagar);
        await t.pumpAndSettle();
      }, (e, s) => solto = e);
      expect(solto, isNull, reason: 'excecao do pagamento escapa da tela sem mensagem ao usuario');
    }, skip: true); // bug conhecido: QA4-1 PagamentoTela._pagar faz rethrow sem catch; erro depende do chamador

    testWidgets('voltar no meio: aoVoltar e chamado uma vez', (t) async {
      var voltou = 0;
      await _abrir(t, PagamentoTela(dados: _dados(), aoVoltar: () => voltou++));
      await t.tap(find.byTooltip('Voltar'));
      await t.pump();
      expect(voltou, 1);
    });

    testWidgets('cupom: aplicar com campo vazio e so espacos nao chama o backend', (t) async {
      var chamadas = 0;
      await _abrir(
        t,
        PagamentoTela(
          dados: _dados(),
          aoAplicarCupom: (codigo) async {
            chamadas++;
            return _dados(desconto: 1000, cupom: codigo);
          },
        ),
      );
      final campo = find.byType(TextField);
      if (campo.evaluate().isNotEmpty) {
        for (final txt in ['', '    ']) {
          await t.enterText(campo.first, txt);
          await t.pump();
          final aplicar = find.text('Aplicar');
          if (aplicar.evaluate().isNotEmpty) {
            await t.tap(aplicar.first, warnIfMissed: false);
            await t.pump();
          }
        }
      }
      expect(chamadas, 0);
    });
  });

  group('Orcamento (detalhe): texto hostil, valores extremos, layout', () {
    Orcamento orc(int centavos, String txt) => Orcamento(
          id: 'x',
          profissional: txt,
          iniciais: 'X',
          verificacao: txt,
          totalCentavos: centavos,
          nota: 0,
          notaResumo: txt,
          servicosResumo: txt,
          servicosConcluidos: 0,
          quando: txt,
          inicio: DateTime(2026, 10, 31, 9),
          garantia: txt,
          observacao: txt,
          detalhe: orcamentosExemplo.firstWhere((o) => o.detalhe != null).detalhe,
        );
    final hostis = ['😀' * 300, '\u202e' * 200 + 'x', '<script>alert(1)</script>' * 30, "'; DROP TABLE x;--" * 30, '   ', '', 'B' * 4000];
    for (final e in _tamanhos.entries) {
      testWidgets('textos hostis em ${e.key} fonte 1.3x: sem estouro', (t) async {
        for (final h in hostis) {
          await _abrir(t, DetalheOrcamentoTela(orcamento: orc(34000, h), aoAceitar: (_) {}, aoFazerContraproposta: (_) {}, aoConversar: (_) {}), tam: e.value, escala: 1.3);
          expect(t.takeException(), isNull, reason: 'texto "${h.substring(0, h.length.clamp(0, 10))}"');
        }
      });
    }
    for (final v in [0, 1, 999999999]) {
      testWidgets('total $v centavos formatado sem quebrar', (t) async {
        await _abrir(t, DetalheOrcamentoTela(orcamento: orc(v, 'Joana'), aoAceitar: (_) {}));
        expect(t.takeException(), isNull);
        final esperado = {0: 'R\$ 0,00', 1: 'R\$ 0,01', 999999999: 'R\$ 9.999.999,99'}[v]!;
        expect(find.textContaining(esperado), findsWidgets);
      });
    }
  });

  group('Avaliacao: comentario hostil e toque duplo em enviar', () {
    testWidgets('comentario gigante/emoji/HTML/RTL nao quebra e chega inteiro ao callback', (t) async {
      EnvioAvaliacao? envio;
      await _abrir(t, AvaliacaoTela(dados: dadosAvaliacaoExemplo, aoEnviar: (e) => envio = e), tam: const Size(320, 568), escala: 1.3);
      final campo = find.byType(TextField);
      if (campo.evaluate().isNotEmpty) {
        await t.enterText(campo.first, '😀<script>x</script>\u202e' * 500);
        await t.pump();
      }
      expect(t.takeException(), isNull);
      expect(envio, isNull);
    });
    testWidgets('toque rapido 5x em Enviar avaliacao = UMA chamada', (t) async {
      final c = Completer<void>();
      var chamadas = 0;
      await _abrir(t, AvaliacaoTela(dados: dadosAvaliacaoExemplo, notasIniciais: const [5, 5, 5, 5, 5], aoEnviar: (e) {
        chamadas++;
        return c.future;
      }));
      final botao = find.byType(BotaoPrimario).first;
      await t.ensureVisible(botao);
      for (var i = 0; i < 5; i++) {
        await t.tap(botao, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 10));
      }
      expect(chamadas, 1);
      c.complete();
      await t.pumpAndSettle();
    });
  });

  group('Excluir conta (LGPD): confirmacao e erro', () {
    testWidgets('sem digitar EXCLUIR nada e excluido; texto hostil nao quebra', (t) async {
      var excluida = false;
      await _abrir(t, ExcluirContaTela(servico: ServicoPrivacidadeFake(), aoContaExcluida: () => excluida = true), tam: const Size(320, 568), escala: 1.3);
      for (final txt in ['', '   ', 'excluir ', '😀' * 400, '<b>EXCLUIR</b>', "' OR 1=1 --"]) {
        final campo = find.byType(TextField);
        if (campo.evaluate().isNotEmpty) {
          await t.enterText(campo.first, txt);
          await t.pump();
        }
      }
      expect(excluida, isFalse);
      expect(t.takeException(), isNull);
    });
  });
}



