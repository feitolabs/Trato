import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpException, SocketException, TlsException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/estado_conexao.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

const _conversa = ConversaPedido(
  nome: 'Carlos Lima',
  iniciais: 'CL',
  numeroPedido: '#4821',
  situacao: 'pago e retido',
  respostasRapidas: [],
  mensagens: [MensagemChat(tipo: TipoMensagem.texto, texto: 'Bom dia!', hora: '09:00')],
);

/// Erros que o http de um aparelho sem rede realmente solta.
final _errosDoAparelho = <String, Object Function()>{
  'SocketException': () => const SocketException('Network is unreachable'),
  'ClientException': () => http.ClientException('Connection closed before full header'),
  'HandshakeException': () => const HandshakeException('Connection terminated during handshake'),
  'TlsException': () => const TlsException('falha de TLS'),
  'HttpException': () => const HttpException('Software caused connection abort'),
};

void main() {
  setUpAll(carregarFontesTrato);
  setUp(EstadoConexao.marcarOnline);
  tearDown(EstadoConexao.marcarOnline);

  for (final MapEntry(key: nome, value: erro) in _errosDoAparelho.entries) {
    test('$nome vira "sem internet" e liga o aviso', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('t'),
        intervaloBaseRetry: Duration.zero,
        cliente: MockClient((_) async => throw erro()),
      );
      await expectLater(
        api.post('/v1/pedidos/p1/mensagens', corpo: {'texto': 'oi'}, chaveIdempotencia: 'k'),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.semInternet)),
      );
      expect(EstadoConexao.online.value, isFalse);
    });
  }

  for (final nome in ['SocketException', 'ClientException', 'HandshakeException']) {
    testWidgets(
        'offline com $nome: aviso visível, "Atualizar conversa" não apaga e reenvia 1 vez',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var offline = true;
      final saiu = <String?>[];
      // Segura a primeira tentativa de envio: é a janela em que o QA tocou em "Atualizar".
      final trava = Completer<void>();
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('t'),
        intervaloBaseRetry: Duration.zero,
        cliente: MockClient((req) async {
          if (!trava.isCompleted) await trava.future;
          if (offline) throw _errosDoAparelho[nome]!();
          saiu.add(req.headers['Idempotency-Key']);
          return http.Response(jsonEncode({}), 200);
        }),
      );
      var leituras = 0;
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        builder: (c, filho) => MoldeConexao(child: filho!),
        home: ChatPedidoTela(
          conversa: _conversa,
          // Sem internet a leitura volta do cache: a conversa antiga, sem a mensagem nova.
          aoRecarregar: () async {
            leituras++;
            return _conversa.comContexto(categoriaNome: 'c$leituras');
          },
          aoEnviarIdempotente: (texto, chave) => api.post('/v1/pedidos/p1/mensagens',
              corpo: {'texto': texto}, chaveIdempotencia: chave),
          intervaloAtualizacao: const Duration(hours: 1),
        ),
      ));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Teste_offline_QA');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      expect(find.text('Teste_offline_QA'), findsOneWidget);

      // Ainda em envio: atualizar a conversa não pode apagar a mensagem.
      await t.tap(find.byIcon(Icons.refresh));
      await t.pump();
      expect(find.text('Teste_offline_QA'), findsOneWidget);

      trava.complete();
      await t.pumpAndSettle();
      expect(find.text('Sem internet'), findsOneWidget);
      expect(find.text('Teste_offline_QA'), findsOneWidget);
      expect(find.text('Aguardando conexão'), findsOneWidget);

      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(find.text('Teste_offline_QA'), findsOneWidget);
      expect(find.text('Aguardando conexão'), findsOneWidget);
      expect(saiu, isEmpty);

      offline = false;
      EstadoConexao.marcarOnline();
      await t.pumpAndSettle();
      EstadoConexao.marcarOffline();
      EstadoConexao.marcarOnline();
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(saiu, hasLength(1), reason: 'reenviada exatamente uma vez');
      expect(find.text('Aguardando conexão'), findsNothing);
      expect(find.text('Sem internet'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  }
}
