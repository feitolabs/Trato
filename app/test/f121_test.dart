// APP-53: comprovante e cópia dos Termos da contratação (Termos 5.3).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/documentos_contratacao.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

class _Servidor {
  _Servidor({this.status = 200, this.resposta = _completa});

  static const _completa = <String, Object>{
    'pedido_id': 'p1',
    'confirmada_em': '2026-11-20T12:00:00Z',
    'comprovante_url': 'https://outro.site/x.pdf',
    'termos_disponiveis': true,
    'termos_versao': '1.2',
  };

  int status;
  Map<String, Object> resposta;
  (int, String)? erroDoPdf;
  final chamadas = <http.Request>[];

  late final api = RepositorioPedidosApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('tok'),
    cliente: MockClient((r) async {
      chamadas.add(r);
      var codigo = status;
      Object corpo = codigo == 200 ? resposta : {'detail': 'recusado'};
      if (r.url.path.endsWith('.pdf')) {
        final erro = erroDoPdf;
        if (erro == null) return http.Response.bytes(utf8.encode('%PDF-1.4'), 200);
        codigo = erro.$1;
        corpo = {'detail': erro.$2};
      }
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), codigo,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

Future<void> _secao(WidgetTester t, _Servidor s,
    [Future<void> Function(DocumentoContratacao)? baixar]) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SecaoDocumentosContratacao(
          carregar: () => s.api.contratacao('p1'),
          baixar: baixar ??
              (d) async {
                await s.api.baixarDocumentoContratacao('p1', d);
              },
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

final _comprovante = find.byKey(const ValueKey('contratacao-comprovante'));
final _termos = find.byKey(const ValueKey('contratacao-termos'));

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('baixa os dois pelo caminho fixo da API, com o token, sem citar e-mail', (t) async {
    final s = _Servidor();
    await _secao(t, s);
    for (final botao in [_comprovante, _termos]) {
      await t.tap(botao);
      await t.pumpAndSettle();
    }
    expect(s.chamadas.map((r) => '${r.url.host}${r.url.path}'), [
      'api.teste/v1/pedidos/p1/contratacao',
      'api.teste/v1/pedidos/p1/contratacao/comprovante.pdf',
      'api.teste/v1/pedidos/p1/contratacao/termos.pdf',
    ]);
    expect(s.chamadas.every((r) => r.headers['Authorization'] == 'Bearer tok'), isTrue);
    expect(find.textContaining(RegExp('e-?mail', caseSensitive: false)), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final (nome, resposta) in [
    ('false', {..._Servidor._completa, 'termos_disponiveis': false}),
    ('ausente', <String, Object>{'confirmada_em': '2026-11-20T12:00:00Z'}),
  ]) {
    testWidgets('termos_disponiveis $nome: só o comprovante e a explicação', (t) async {
      await _secao(t, _Servidor(resposta: resposta));
      expect(_comprovante, findsOneWidget);
      expect(_termos, findsNothing);
      expect(find.text(textoSemCopiaDosTermos), findsOneWidget);
    });
  }

  for (final status in [409, 403, 404, 503]) {
    testWidgets('consulta $status: a seção some', (t) async {
      await _secao(t, _Servidor(status: status));
      expect(find.text('Documentos da contratação'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('resposta vazia: a seção some', (t) async {
    await _secao(t, _Servidor(resposta: const {}));
    expect(find.text('Documentos da contratação'), findsNothing);
  });

  testWidgets('erro na consulta permite tentar de novo', (t) async {
    final s = _Servidor(status: 500);
    await _secao(t, s);
    s.status = 200;
    await t.tap(find.byKey(const ValueKey('recarregar-contratacao')));
    await t.pumpAndSettle();
    expect(_comprovante, findsOneWidget);
  });

  testWidgets('erro no download mostra o detail junto do botão e some ao dar certo', (t) async {
    const detalhe = 'A cópia dos Termos da época não está no aplicativo. Peça ao atendimento.';
    final s = _Servidor()..erroDoPdf = (404, detalhe);
    await _secao(t, s);
    await t.tap(_termos);
    await t.pumpAndSettle();
    expect(find.text(detalhe), findsOneWidget);
    expect(t.getTopLeft(find.text(detalhe)).dy, greaterThan(t.getTopLeft(_termos).dy));
    s.erroDoPdf = null;
    await t.tap(_termos);
    await t.pumpAndSettle();
    expect(find.text(detalhe), findsNothing);
  });

  testWidgets('no pedido do cliente: salva o PDF, avisa e compartilha', (t) async {
    final anterior = RotasTrato.repos;
    final compartilharAntes = RotasTrato.compartilharArquivo;
    addTearDown(() {
      RotasTrato.repos = anterior;
      RotasTrato.salvarPdfParaTeste = null;
      RotasTrato.compartilharArquivo = compartilharAntes;
    });
    final pedidos = _PedidosComContratacao();
    RotasTrato.repos = repositoriosDemo(pedidos: pedidos);
    final salvos = <String>[];
    String? compartilhado;
    RotasTrato.salvarPdfParaTeste = (bytes, arquivo) async {
      salvos.add(arquivo);
      return '/tmp/$arquivo';
    };
    RotasTrato.compartilharArquivo = (c) async => compartilhado = c;
    t.view.physicalSize = const Size(390, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        MaterialApp(theme: TemaTrato.claro, home: RotasTrato.pedidoDoClienteParaTeste('ped-1')));
    await t.pumpAndSettle();

    await t.ensureVisible(_termos);
    await t.tap(_termos);
    await t.pumpAndSettle();
    expect(pedidos.baixados, [DocumentoContratacao.termos]);
    expect(salvos, ['trato_contratacao_termos_ped-1.pdf']);
    expect(find.text('Cópia dos Termos em PDF salva.'), findsOneWidget);
    await t.tap(find.text('Compartilhar'));
    await t.pumpAndSettle();
    expect(compartilhado, '/tmp/trato_contratacao_termos_ped-1.pdf');
  });
}

class _PedidosComContratacao extends RepositorioPedidosFake implements ServicoContratacao {
  final baixados = <DocumentoContratacao>[];

  @override
  Future<ContratacaoDoPedido?> contratacao(String pedidoId) async =>
      const ContratacaoDoPedido(termosDisponiveis: true);

  @override
  Future<List<int>> baixarDocumentoContratacao(
      String pedidoId, DocumentoContratacao documento) async {
    baixados.add(documento);
    return utf8.encode('%PDF-1.4');
  }
}
