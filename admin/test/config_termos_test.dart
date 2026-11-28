import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/formato.dart';
import 'package:trato_admin/nucleo/parametros_config.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const _espera = ConfigDefinicao(
    chave: 'ausencia_espera_minutos',
    descricao: 'Espera antes da ausência (exemplo)',
    unidade: UnidadeConfig.minutos,
    minimo: 20,
    maximo: 120,
    exigeDuplaAprovacao: false);
const _chaveLigada = ConfigDefinicao(
    chave: 'chave_exemplo',
    descricao: 'Chave sem valor (exemplo)',
    unidade: UnidadeConfig.quantidade,
    minimo: 0,
    maximo: 1,
    exigeDuplaAprovacao: false);

class _Api extends ApiFake {
  final propostas = <Map<String, int>>[];

  @override
  Future<ConfigAtual> carregarConfig() async {
    final base = await super.carregarConfig();
    return ConfigAtual(definicoes: [...base.definicoes, _espera, _chaveLigada], versoes: base.versoes);
  }

  @override
  Future<void> proporConfig(Map<String, int> valores, String motivo) async => propostas.add(valores);
}

Finder _campo() => find.byKey(const ValueKey('campo-ausencia_espera_minutos'));

OutlinedButton _propor(WidgetTester tester) {
  // O último "Propor" da lista é o da chave liga/desliga; o penúltimo, o da espera.
  final botoes = find.widgetWithText(OutlinedButton, 'Propor');
  return tester.widget<OutlinedButton>(botoes.at(botoes.evaluate().length - 2));
}

void main() {
  test('minutos é unidade, não quantidade', () {
    expect(valorLegivel(20, _espera), '20 minutos');
    expect(formatarConfig(1, 'minutos'), '1 minuto');
    expect(faixaLegivel(_espera), '20 a 120 minutos');
  });

  test('chaves novas têm grupo conhecido e ajuda', () {
    const grupos = {
      'arrependimento_dias': 'Pedidos e propostas',
      'ausencia_espera_minutos': 'Pedidos e propostas',
      'ausencia_justificativa_horas': 'Pedidos e propostas',
      'ausencia_retencao_max_bps': 'Pedidos e propostas',
      'sac_resposta_dias_uteis': 'Atendimento e dados',
      'sac_dados_pessoais_dias': 'Atendimento e dados',
      'incidente_seguranca_cautela_horas': 'Risco',
      'disputa_contestacao_prazo_dias_uteis': 'Disputas',
      'disputa_contestacao_resposta_dias_uteis': 'Disputas',
      'avaliacao_revisao_resposta_dias_uteis': 'Atendimento e dados',
      'lgpd_pedido_resposta_dias': 'Atendimento e dados',
      'aviso_previo_encerramento_dias': 'Avisos',
      'aviso_previo_termos_dias': 'Avisos',
      'aviso_previo_tratinhos_dias': 'Avisos',
      'aviso_previo_inatividade_dias': 'Avisos',
      'tratinhos_aviso_vencimento_dias': 'Avisos',
    };
    for (final e in grupos.entries) {
      expect(infoDe(e.key).grupo, e.value, reason: e.key);
      expect(gruposConfig, contains(e.value));
      expect(infoDe(e.key).ajuda, isNotEmpty, reason: e.key);
    }
  });

  testWidgets('sem valor publicado não mostra nem propõe zero', (tester) async {
    final api = _Api();
    await abrirPainel(tester, papel: 'financeiro', api: api, secao: 'config');
    await tester.tap(find.text('Pedidos e propostas'));
    await tester.pumpAndSettle();
    await rolarListaAte(tester, _campo());
    expect(find.text(kSemValorPublicado), findsNWidgets(2));
    expect(tester.widget<TextField>(_campo()).controller!.text, '');
    expect(find.text('0 minutos'), findsNothing);
    expect(find.text('Desligada'), findsNothing);
    expect(find.text('Digite um número'), findsNothing);
    expect(_propor(tester).onPressed, isNull);

    await tester.enterText(_campo(), '30');
    await tester.pump();
    expect(_propor(tester).onPressed, isNotNull);
    await tester.enterText(_campo(), '');
    await tester.pump();
    expect(_propor(tester).onPressed, isNull);

    await tester.enterText(_campo(), '30');
    await tester.pump();
    final botoes = find.widgetWithText(OutlinedButton, 'Propor');
    final alvo = botoes.at(botoes.evaluate().length - 2);
    await tester.ensureVisible(alvo);
    await tester.pump();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Dialog), matching: find.text(kSemValorPublicado)), findsOneWidget);
    await confirmarMotivo(tester, 'Enviar para aprovação');
    expect(api.propostas.single, {'ausencia_espera_minutos': 30});
  });

  testWidgets('celular: sem valor publicado também aparece por extenso', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: _Api(), largura: 390);
    final direto = find.byKey(const ValueKey('menu-config'));
    if (direto.evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('menu-mais')));
      await tester.pumpAndSettle();
      await tocarNoMais(tester, 'config');
    } else {
      await tester.tap(direto.last);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Pedidos e propostas'));
    await tester.pump();
    await tester.tap(find.text('Pedidos e propostas'));
    await tester.pumpAndSettle();
    await rolarListaAte(tester, _campo());
    expect(find.byType(Linha), findsWidgets);
    expect(find.textContaining(kSemValorPublicado, findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
