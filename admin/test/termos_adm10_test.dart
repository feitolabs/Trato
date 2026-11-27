// Dinheiro digitado nas telas: "12.50" nunca vira R$ 1.250,00 nem zero. A função em si está em
// formato_test.dart; compensações, em termos_adm9_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/formato.dart';
import 'package:trato_admin/nucleo/parametros_config.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Guarda o que as telas de cupom e equipe mandam.
class _Anota extends ApiFake {
  final cupons = <({int valor, int minimo})>[];
  final alcadas = <int>[];

  @override
  Future<CupomAdmin> criarCupom({
    required String codigo,
    required String tipo,
    required int valor,
    int valorMinimoCentavos = 0,
    int? limiteUsos,
    int? limitePorUsuario,
    String? validoDesde,
    String? validoAte,
    String? campanha,
    required String motivo,
  }) {
    cupons.add((valor: valor, minimo: valorMinimoCentavos));
    return super.criarCupom(
        codigo: codigo, tipo: tipo, valor: valor, valorMinimoCentavos: valorMinimoCentavos, motivo: motivo);
  }

  @override
  Future<MembroEquipeAdmin> adicionarMembroEquipe({
    required String nome,
    required String email,
    required String papel,
    int alcadaCentavos = 0,
    required String motivo,
  }) {
    alcadas.add(alcadaCentavos);
    return super.adicionarMembroEquipe(
        nome: nome, email: email, papel: papel, alcadaCentavos: alcadaCentavos, motivo: motivo);
  }
}

Finder campo(String rotulo) => find.widgetWithText(TextField, rotulo);

Future<void> digitar(WidgetTester tester, Finder alvo, String texto) async {
  await tester.ensureVisible(alvo);
  await tester.enterText(alvo, texto);
  await tester.pumpAndSettle();
}

bool habilitado(WidgetTester tester, String botao) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, botao).last).onPressed != null;

Finder get aviso => find.text(kErroReais);

void main() {
  testWidgets('cupom: valor fixo e pedido mínimo recusam "12.50" e não viram zero', (tester) async {
    final api = _Anota();
    await abrirPainel(tester, api: api, secao: 'cupons');
    await tester.tap(find.text('Novo cupom'));
    await tester.pumpAndSettle();
    await digitar(tester, campo('Código'), 'TESTE10');
    await tester.tap(find.text('Valor fixo'));
    await tester.pumpAndSettle();
    await digitar(tester, campo('Motivo'), 'Campanha de teste do mês');

    await digitar(tester, campo('Valor'), '12.50');
    expect(aviso, findsOneWidget);
    expect(habilitado(tester, 'Criar cupom'), isFalse);

    await digitar(tester, campo('Valor'), '12,50');
    expect(aviso, findsNothing);
    for (final ruim in ['30.00', 'abc', '1,234']) {
      await digitar(tester, campo('Pedido mínimo'), ruim);
      expect(aviso, findsOneWidget, reason: ruim);
      expect(habilitado(tester, 'Criar cupom'), isFalse, reason: ruim);
    }
    await digitar(tester, campo('Pedido mínimo'), '1.234,56');
    expect(habilitado(tester, 'Criar cupom'), isTrue);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar cupom'));
    await tester.tap(find.widgetWithText(FilledButton, 'Criar cupom'));
    await tester.pumpAndSettle();
    expect(api.cupons.single, (valor: 1250, minimo: 123456));
  });

  testWidgets('cupom: percentual continua inteiro de 1 a 100; mínimo vazio é zero', (tester) async {
    final api = _Anota();
    await abrirPainel(tester, api: api, secao: 'cupons');
    await tester.tap(find.text('Novo cupom'));
    await tester.pumpAndSettle();
    await digitar(tester, campo('Código'), 'TESTE20');
    await digitar(tester, campo('Motivo'), 'Campanha de teste do mês');
    await digitar(tester, campo('Valor'), '12,5');
    expect(find.text('Entre 1 e 100'), findsWidgets);
    expect(aviso, findsNothing);
    await digitar(tester, campo('Valor'), '12');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar cupom'));
    await tester.tap(find.widgetWithText(FilledButton, 'Criar cupom'));
    await tester.pumpAndSettle();
    expect(api.cupons.single, (valor: 12, minimo: 0));
  });

  testWidgets('equipe: alçada recusa "12.50" ao conceder e ao editar', (tester) async {
    final api = _Anota();
    await abrirPainel(tester, api: api, secao: 'equipe');
    await tester.tap(find.text('Conceder acesso'));
    await tester.pumpAndSettle();
    await digitar(tester, campo('Nome'), 'Maria (exemplo)');
    await digitar(tester, campo('E-mail corporativo'), 'maria@feitolabs.com.br');
    await digitar(tester, campo('Motivo'), 'Entrada na equipe');
    await digitar(tester, campo('Alçada'), '12.50');
    expect(aviso, findsOneWidget);
    expect(habilitado(tester, 'Conceder acesso'), isFalse);
    await digitar(tester, campo('Alçada'), '0,00');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Conceder acesso').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Conceder acesso').last);
    await tester.pumpAndSettle();
    expect(api.alcadas, [0]);

    final editar = find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Editar '));
    await tester.ensureVisible(editar.first);
    await tester.tap(editar.first);
    await tester.pumpAndSettle();
    await digitar(tester, campo('Alçada'), '10.5');
    expect(aviso, findsOneWidget);
    await digitar(tester, campo('Motivo'), 'Ajuste de alçada');
    expect(habilitado(tester, 'Salvar alterações'), isFalse);
  });

  testWidgets('disputa: reembolso parcial recusa "12.50" junto do campo', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    await rolarListaAte(tester, find.text('Reembolso parcial'));
    await tester.tap(find.text('Reembolso parcial'));
    await tester.pumpAndSettle();
    final valor = campo('Valor do reembolso (R\$)');
    await rolarListaAte(tester, valor);
    await digitar(tester, valor, '12.50');
    expect(aviso, findsOneWidget); // antes mesmo de tentar registrar
    await digitar(tester, valor, '12,50');
    expect(aviso, findsNothing);
  });

  testWidgets('cliente ausente: retenção e nova retenção recusam "12.50" sem enviar', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'ausencias');
    await tester.tap(find.text('PED-AUSANALI').first);
    await tester.pumpAndSettle();
    await rolarListaAte(tester, find.text('Recusar'));
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    await rolarListaAte(tester, campo('Motivo'));
    await digitar(tester, campo('Motivo'), 'Justificativa sem comprovação');
    final retencao = campo('Retenção por custos comprovados (opcional)');
    await rolarListaAte(tester, retencao);
    await digitar(tester, retencao, '12.50');
    expect(aviso, findsOneWidget);
    await rolarListaAte(tester, find.text('Revisar decisão'));
    await tester.tap(find.text('Revisar decisão'));
    await tester.pumpAndSettle();
    expect(find.byType(CorpoModal), findsNothing); // não vira "sem retenção"
    expect(api.ultimaDecisaoAusencia, isNull);
  });

  testWidgets('cliente ausente: contestação, nova retenção recusa "12.50"', (tester) async {
    final api = ApiFake()
      ..ausencias = [
        CasoAusencia(
          pedidoId: 'aus-contest',
          status: CasoAusencia.recusada,
          chegadaEm: DateTime(2026, 11, 1),
          retencaoCentavos: 4500,
          cancelamentoStatus: CasoAusencia.propostaRetencao,
          contestacao: ContestacaoAusencia(
              status: 'aberta', texto: 't', abertaEm: DateTime(2026, 11, 3), responderAte: DateTime(2026, 11, 17)),
        ),
      ];
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'ausencias');
    await rolarListaAte(tester, find.text('Reduzir retenção'));
    await tester.tap(find.text('Reduzir retenção'));
    await tester.pumpAndSettle();
    await rolarListaAte(tester, campo('Nova retenção'));
    await digitar(tester, campo('Nova retenção'), '20.50');
    expect(aviso, findsOneWidget);
    expect(api.ultimaRevisao, isNull);
  });

  testWidgets('Tratinhos: campo em reais recusa "0.25"; campo de quantidade não muda de regra', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'moedas');
    final valor = find.byKey(const ValueKey('moedas-campo-valor_moeda_centavos'));
    await rolarListaAte(tester, find.text('Salvar configuração')).catchError((_) {});
    await digitar(tester, valor, '0.25');
    expect(aviso, findsOneWidget);
    expect(habilitado(tester, 'Salvar configuração'), isFalse);
    await digitar(tester, valor, '0,25');
    expect(aviso, findsNothing);
    await digitar(tester, find.byKey(const ValueKey('moedas-campo-teto_mensal_moedas')), '1.000');
    expect(find.text('Informe um número inteiro'), findsOneWidget);
    expect(aviso, findsNothing);
  });

  test('configurações: parâmetro em centavos usa a mesma leitura e preenche sem double', () {
    const dinheiro = ConfigDefinicao(
        chave: 'valor_minimo_servico_centavos',
        descricao: 'Valor mínimo',
        unidade: UnidadeConfig.centavos,
        minimo: 0,
        maximo: 100000000,
        exigeDuplaAprovacao: false);
    expect(campoParaValor('1.234,56', dinheiro), 123456);
    for (final ruim in ['12.50', '1,234', 'abc', '']) {
      expect(campoParaValor(ruim, dinheiro), isNull, reason: ruim);
    }
    expect(valorParaCampo(123456, dinheiro), '1234,56');
    expect(campoParaValor(valorParaCampo(29, dinheiro), dinheiro), 29);
  });
}
