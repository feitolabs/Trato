// TERMOS-APP5: versão do texto nos consentimentos e "Guardar uma cópia" (Termos 1.5 e 24.3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/comuns/textos_dos_termos.dart';
import 'package:trato/telas/legal/texto_legal_tela.dart';
import 'package:trato/tema/tema.dart';

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

void main() {
  setUpAll(carregarFontesTrato);

  test('1. cada consentimento leva a versão do documento mostrado', () async {
    final enviados = <Map<String, dynamic>>[];
    final servico = ServicoPrivacidadeApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        enviados.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{}', 201, headers: const {'content-type': 'application/json'});
      }),
    ));
    for (final id in ['dados_pedido', 'localizacao', 'avisos', 'politica_privacidade']) {
      await servico.alterarConsentimento(id, ativo: true);
    }
    expect({for (final c in enviados) c['finalidade']: c['versao_texto']}, {
      'termos_de_uso': versaoDosTermos,
      'localizacao_no_servico': versaoDaPrivacidade,
      'comunicacoes_marketing': versaoDaPrivacidade,
      'politica_privacidade': versaoDaPrivacidade,
    });
    expect(File('lib/dados/servicos_api.dart').readAsStringSync(), isNot(contains("'1.0'")));
  });

  test('1. as versões batem com o texto de cada documento', () {
    for (final t in TextoLegal.values) {
      expect(File(t.arquivo).readAsStringSync(), contains('**Versão ${t.versao} —'),
          reason: t.arquivo);
    }
  });

  for (final texto in TextoLegal.values) {
    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${texto.name} ${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets('2. guardar uma cópia entrega o texto mostrado ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final guardados = <(String, String)>[];
          final conteudo = File(texto.arquivo).readAsStringSync();
          await t.pumpWidget(MaterialApp(
            theme: TemaTrato.claro,
            home: TextoLegalTela(
              titulo: texto.titulo,
              nomeDaCopia: texto.nomeDaCopia,
              carregar: () async => conteudo,
              guardar: (nome, c) async => guardados.add((nome, c)),
            ),
          ));
          await t.pumpAndSettle();
          final botao = find.byKey(const Key('guardar-texto-legal'));
          await t.ensureVisible(botao);
          await t.pumpAndSettle();
          await t.tap(botao);
          await t.pumpAndSettle();
          final (nome, copia) = guardados.single;
          expect(nome, endsWith('-v${texto.versao}.txt'));
          expect(copia, startsWith('${texto.titulo}\n'));
          expect(copia, contains('Versão ${texto.versao}'));
          expect(copia, isNot(contains('**')));
          expect(copia.length, greaterThan(2000));
          expect(t.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('2. sem compartilhamento: erro junto do botão e "Copiar texto"', (t) async {
    await _janela(t, _tamanhos.last, 1.3);
    String? copiado;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copiado = (c.arguments as Map)['text'] as String?;
      return null;
    });
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: TextoLegalTela(
        titulo: 'Termos de uso',
        carregar: () async => '## 1. Quem somos\n\nTexto **do** app.',
        guardar: (_, __) async => throw StateError('sem compartilhamento'),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('guardar-texto-legal')));
    await t.pumpAndSettle();
    expect(find.textContaining('Não foi possível abrir o compartilhamento'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('copiar-texto-legal')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('copiar-texto-legal')));
    await t.pumpAndSettle();
    expect(copiado, 'Termos de uso\n\n1. Quem somos\nTexto do app.\n');
    expect(find.text('Texto copiado'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
