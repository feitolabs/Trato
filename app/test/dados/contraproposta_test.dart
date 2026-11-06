import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/orcamentos/folha_contraproposta.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

ClienteApi _api(List<http.Request> pedidas) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((req) async {
        pedidas.add(req);
        return http.Response.bytes(
          utf8.encode(jsonEncode({'ok': true})),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

ConversaPedido _conversa(List<MensagemChat> mensagens) => ConversaPedido(
      nome: 'Cliente C.',
      iniciais: 'CC',
      numeroPedido: '#AB12',
      situacao: 'Aberto',
      mensagens: mensagens,
      respostasRapidas: const [],
    );

void main() {
  test('lê a marca da contraproposta e limpa o texto', () {
    final (c, texto) = ContrapropostaChat.ler(
        '[contraproposta:orc-1:25000] Contraproposta de R\$ 250,00 (o orçamento atual é R\$ 300,00).');
    expect(c!.orcamentoId, 'orc-1');
    expect(c.valorCentavos, 25000);
    expect(texto, startsWith('Contraproposta de R\$ 250,00'));
    final (nada, igual) = ContrapropostaChat.ler('Oi, tudo bem?');
    expect(nada, isNull);
    expect(igual, 'Oi, tudo bem?');
  });

  test('cliente propõe e profissional aceita: os dois pedidos certos ao backend', () async {
    final pedidas = <http.Request>[];
    final repo = RepositorioOrcamentosApi(_api(pedidas));
    await repo.contraproporValor('p1', 'o1', 25000, mensagem: ' Fecho hoje ');
    await repo.aceitarContraproposta('p1', 'o1', 25000);

    expect(pedidas[0].url.path, '/v1/pedidos/p1/orcamentos/o1/contraproposta');
    expect(jsonDecode(pedidas[0].body), {'valor_centavos': 25000, 'mensagem': 'Fecho hoje'});
    expect(pedidas[1].url.path, '/v1/pedidos/p1/orcamentos/o1/contraproposta/aceitar');
    expect(jsonDecode(pedidas[1].body), {'valor_centavos': 25000});
  });

  Future<void> abrirChat(WidgetTester t, ConversaPedido c,
      {Future<void> Function(ContrapropostaChat)? aceitar}) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: ChatPedidoTela(conversa: c, aoAceitarContraproposta: aceitar),
    ));
  }

  const proposta = MensagemChat(
    tipo: TipoMensagem.texto,
    hora: '10:00',
    texto: 'Contraproposta de R\$ 250,00.',
    contraproposta: ContrapropostaChat(orcamentoId: 'o1', valorCentavos: 25000),
  );

  testWidgets('profissional vê o botão de aceitar e ele chama o backend', (t) async {
    ContrapropostaChat? aceita;
    await abrirChat(t, _conversa(const [proposta]), aceitar: (c) async => aceita = c);
    expect(find.text('Contraproposta'), findsOneWidget);
    expect(find.text('Contraproposta de R\$ 250,00.'), findsOneWidget);
    await t.tap(find.text('Aceitar e atualizar orçamento'));
    await t.pump();
    expect(aceita!.orcamentoId, 'o1');
    expect(aceita!.valorCentavos, 25000);
  });

  testWidgets('quem fez a proposta não vê o botão de aceitar', (t) async {
    const minha = MensagemChat(
      tipo: TipoMensagem.texto,
      hora: '10:00',
      texto: 'Contraproposta de R\$ 250,00.',
      minha: true,
      contraproposta: ContrapropostaChat(orcamentoId: 'o1', valorCentavos: 25000),
    );
    await abrirChat(t, _conversa(const [minha]), aceitar: (c) async {});
    expect(find.text('Aceitar e atualizar orçamento'), findsNothing);
  });

  testWidgets('folha: valida antes de enviar e devolve valor e mensagem', (t) async {
    (int, String?)? resultado;
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => resultado = await pedirContraproposta(context, 30000),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();

    await t.tap(find.text('Enviar contraproposta'));
    await t.pump();
    expect(find.text('Digite o valor que você propõe.'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '300');
    await t.tap(find.text('Enviar contraproposta'));
    await t.pump();
    expect(find.textContaining('Proponha menos que'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '250,50');
    await t.enterText(find.byType(TextField).last, 'Fecho hoje');
    await t.tap(find.text('Enviar contraproposta'));
    await t.pumpAndSettle();
    expect(resultado, (25050, 'Fecho hoje'));
  });
}
