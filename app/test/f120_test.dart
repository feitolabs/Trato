// APP-69: contestação de nota de material pelo cliente (Termos 6.9).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/medidas/modelos.dart' show ProvaEscolhida;
import 'package:trato/telas/nota_material/ver_nota_tela.dart';

import 'apoio/exemplos/telas/nota_material/nota_material_fake.dart';
import 'apoio/fontes.dart';

Map<String, Object?> _nota({bool comIdDoItem = true}) => {
      'id': 'n1',
      'contrato_id': 'p1',
      'enviada_em': '2026-11-20T12:00:00Z',
      'total_centavos': 6400,
      'itens': [
        {
          if (comIdDoItem) 'id': 'i1',
          'descricao': 'Resistência',
          'quantidade': '1',
          'valor_unitario_centavos': 6400,
          'total_centavos': 6400,
        },
      ],
    };

const _decidida = {
  'id': 'c1',
  'protocolo': 'MAT-0001',
  'nota_id': 'n1',
  'item_id': 'i1',
  'motivo': 'nao_comprovado',
  'descricao': 'Não há comprovante desta peça.',
  'anexos': ['m9'],
  'valor_contestado_centavos': 6400,
  'aberta_em': '2026-11-21T12:00:00Z',
  'responder_ate': '2026-11-28T12:00:00Z',
  'status': 'parcial',
  'resposta': 'Parte do valor não foi comprovada.',
  'valor_reconhecido_centavos': 3000,
  'decidida_em': '2026-11-25T12:00:00Z',
  'efeito_financeiro': 'executado',
};

class _Upload implements ServicoUpload {
  final enviados = <(FinalidadeArquivo, String?)>[];

  @override
  Future<ArquivoEnviado> enviar(ArquivoCapturado arquivo, FinalidadeArquivo finalidade,
      {String? pedidoId}) async {
    enviados.add((finalidade, pedidoId));
    return ArquivoEnviado(arquivoId: 'midia-${enviados.length}');
  }
}

class _Servidor {
  _Servidor({this.contestacoes = const [], this.statusLista = 200, this.comIdDoItem = true});

  List<Object> contestacoes;
  int statusLista;
  bool comIdDoItem;
  (int, Object)? envio;
  final chamadas = <http.Request>[];

  Iterable<http.Request> get envios => chamadas.where((r) => r.method == 'POST');

  late final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      chamadas.add(r);
      var status = 200;
      Object corpo = <String, Object>{};
      if (r.url.path.endsWith('/notas-material')) {
        corpo = [_nota(comIdDoItem: comIdDoItem)];
      } else if (r.url.path.endsWith('/materiais/contestacoes')) {
        status = statusLista;
        corpo = status == 200
            ? {'itens': contestacoes, 'total': contestacoes.length}
            : {'detail': 'falhou'};
      } else if (r.method == 'POST') {
        (status, corpo) = envio ?? (201, {..._decidida, 'status': 'aberta'});
        if (status < 300) contestacoes = [corpo];
      }
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  );
}

Future<void> _abrir(WidgetTester t, _Servidor s,
    {ServicoUpload? upload, Future<ProvaEscolhida?> Function()? foto}) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: VerNotaTela(
      servico: ServicoNotaMaterialApi(s.api, upload: upload, nomeProfissional: 'Carlos'),
      pedidoId: 'p1',
      escolherFoto: foto,
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _ver(WidgetTester t, Finder alvo) async {
  await t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, String chave) async {
  final alvo = find.byKey(ValueKey(chave));
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Future<void> _irAoFormulario(WidgetTester t) async {
  await _ver(t, find.byKey(const ValueKey('botao-contestar-material')));
  await _tocar(t, 'botao-contestar-material');
}

Future<void> _preencher(WidgetTester t, String alvo) async {
  await _tocar(t, alvo);
  await _tocar(t, 'motivo-diferente_do_combinado');
  final valor = find.descendant(
      of: find.byKey(const ValueKey('valor-contestado')), matching: find.byType(TextField));
  await t.ensureVisible(valor);
  await t.enterText(valor, '25,50');
  final descricao = find.byKey(const ValueKey('descricao-contestacao-material'));
  await t.ensureVisible(descricao);
  await t.enterText(descricao, 'Veio uma peça de outra marca.');
}

const _enviar = 'botao-enviar-contestacao-material';

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('acompanha sem falar em devolução nem pagamento feito', (t) async {
    await _abrir(t, _Servidor(contestacoes: [_decidida]));
    await _ver(t, find.byKey(const ValueKey('botao-contestar-material')));
    for (final texto in [
      'Aceita em parte',
      'Nota inteira',
      'Nota · Resistência',
      'Valor contestado: R\$ 64,00',
      'Parte do valor não foi comprovada.',
      'Valor reconhecido na análise: R\$ 30,00',
      'É o resultado da análise, não um comprovante de pagamento.',
    ]) {
      expect(find.text(texto, skipOffstage: false),
          texto == 'Nota inteira' ? findsNothing : findsOneWidget,
          reason: texto);
    }
    for (final proibido in ['devol', 'reembols', 'estorn', 'executado', 'foi pago']) {
      expect(find.textContaining(RegExp(proibido, caseSensitive: false), skipOffstage: false),
          findsNothing,
          reason: proibido);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('valida e envia o contrato do item, com a foto reaproveitando o envio', (t) async {
    final s = _Servidor();
    final upload = _Upload();
    await _abrir(t, s,
        upload: upload,
        foto: () async =>
            ProvaEscolhida(nome: 'f.jpg', bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1])));
    await _irAoFormulario(t);
    await _tocar(t, _enviar);
    expect(find.text('Escolha a nota inteira ou um item.'), findsOneWidget);
    expect(s.envios, isEmpty);

    await _preencher(t, 'alvo-n1-i1');
    await _tocar(t, 'adicionar-foto-material');
    await _tocar(t, _enviar);

    expect(upload.enviados, [(FinalidadeArquivo.evidenciaDisputa, 'p1')]);
    expect(s.envios.single.url.path, '/v1/pedidos/p1/materiais/n1/contestar');
    expect(jsonDecode(s.envios.single.body), {
      'motivo': 'diferente_do_combinado',
      'descricao': 'Veio uma peça de outra marca.',
      'valor_contestado_centavos': 2550,
      'item_id': 'i1',
      'anexos': ['midia-1'],
    });
    expect(find.text('Contestação enviada. Protocolo MAT-0001.'), findsOneWidget);
    expect(find.text('Contestação enviada', skipOffstage: false), findsOneWidget);
  });

  testWidgets('item sem id (servidor antigo): só a nota inteira, sem item_id nem anexos',
      (t) async {
    final s = _Servidor(comIdDoItem: false);
    await _abrir(t, s);
    await _irAoFormulario(t);
    expect(find.byKey(const ValueKey('alvo-n1-i1')), findsNothing);
    expect(find.byKey(const ValueKey('adicionar-foto-material')), findsNothing);
    await _preencher(t, 'alvo-n1');
    await _tocar(t, _enviar);
    expect((jsonDecode(s.envios.single.body) as Map).keys,
        ['motivo', 'descricao', 'valor_contestado_centavos']);
  });

  for (final (status, detalhe) in [
    (409, 'Já há uma contestação em aberto (MAT-0001). Aguarde a resposta.'),
    (422, 'O valor contestado ultrapassa o valor do item.'),
    (403, 'Só o cliente do pedido pode contestar a nota de material.'),
  ]) {
    testWidgets('erro $status no envio mostra o detail e mantém o preenchido', (t) async {
      final s = _Servidor()..envio = (status, {'detail': detalhe});
      await _abrir(t, s);
      await _irAoFormulario(t);
      await _preencher(t, 'alvo-n1');
      await _tocar(t, _enviar);
      expect(find.text(detalhe), findsOneWidget);
      expect(find.text('Veio uma peça de outra marca.', skipOffstage: false), findsOneWidget);
      expect(find.text('25,50', skipOffstage: false), findsOneWidget);
    });
  }

  for (final status in [404, 503, 403]) {
    testWidgets('lista $status: a nota continua e não há botão de contestar', (t) async {
      await _abrir(t, _Servidor(statusLista: status));
      expect(find.text('Materiais do serviço'), findsOneWidget);
      await _ver(t, find.textContaining('ainda não está disponível'));
      expect(find.byKey(const ValueKey('botao-contestar-material')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('erro ao carregar a lista permite tentar de novo; depois, vazio', (t) async {
    final s = _Servidor(statusLista: 500);
    await _abrir(t, s);
    await _ver(t, find.byKey(const ValueKey('recarregar-contestacoes-material')));
    s.statusLista = 200;
    await _tocar(t, 'recarregar-contestacoes-material');
    await _ver(t, find.text('Nenhuma contestação neste pedido.'));
  });

  testWidgets('campos ausentes usam texto padrão', (t) async {
    await _abrir(t, _Servidor(contestacoes: [<String, Object>{}]));
    await _ver(t, find.byKey(const ValueKey('botao-contestar-material')));
    expect(find.text('Situação não informada', skipOffstage: false), findsOneWidget);
    expect(find.text('Motivo não informado', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('serviço sem a função: nota sem a seção de contestação', (t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: VerNotaTela(servico: ServicoNotaMaterialFake(), pedidoId: 'p')));
    await t.pumpAndSettle();
    expect(find.text('Contestação de material'), findsNothing);
  });
}
