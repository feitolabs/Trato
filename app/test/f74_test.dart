import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/servico_conta_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/comuns/denuncia_folha.dart';
import 'package:trato/telas/conta/servico_fake.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/cliente/dados_exemplo.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

/// Botão que abre a folha e guarda o resultado.
Widget _comBotao(Future<void> Function(MotivoDenuncia, String) enviar, void Function(bool?) fim) =>
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => fim(await mostrarFolhaDenuncia(context, enviar: enviar)),
          child: const Text('abrir'),
        ),
      ),
    );

void main() {
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('Folha de denúncia', () {
    testWidgets('valida motivo e mínimo de 5 caracteres; envia motivo e detalhes', (tester) async {
      MotivoDenuncia? motivoEnviado;
      String? detalhesEnviados;
      bool? resultado = false;
      await _abrir(
        tester,
        _comBotao((m, d) async {
          motivoEnviado = m;
          detalhesEnviados = d;
        }, (r) => resultado = r),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Os 5 motivos pedidos.
      for (final rotulo in [
        'Assédio ou desrespeito',
        'Tentativa de golpe/fraude',
        'Cobrança fora do app',
        'Perfil falso',
        'Outro',
      ]) {
        expect(find.text(rotulo), findsOneWidget);
      }

      await tester.tap(find.text('Enviar denúncia'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha um motivo.'), findsOneWidget);

      await tester.tap(find.text('Tentativa de golpe/fraude'));
      await tester.enterText(find.byKey(const ValueKey('detalhes-denuncia')), 'abc');
      await tester.tap(find.text('Enviar denúncia'));
      await tester.pumpAndSettle();
      expect(find.textContaining('mínimo de 5 caracteres'), findsOneWidget);
      expect(motivoEnviado, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('detalhes-denuncia')),
        '  Pediu Pix fora do app  ',
      );
      await tester.tap(find.text('Enviar denúncia'));
      await tester.pumpAndSettle();
      expect(motivoEnviado, MotivoDenuncia.fraude);
      expect(detalhesEnviados, 'Pediu Pix fora do app');
      expect(resultado, isTrue);
      expect(find.text('Enviar denúncia'), findsNothing); // folha fechou
    });

    testWidgets('toque repetido no enviar chama a API uma vez só', (tester) async {
      var chamadas = 0;
      final pendente = Completer<void>();
      await _abrir(
        tester,
        _comBotao((m, d) {
          chamadas++;
          return pendente.future;
        }, (_) {}),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Perfil falso'));
      await tester.enterText(
        find.byKey(const ValueKey('detalhes-denuncia')),
        'Foto de outra pessoa',
      );
      await tester.tap(find.text('Enviar denúncia'));
      await tester.pump();
      // Enquanto envia, o botão mostra o indicador (sem texto) e ignora o toque.
      expect(find.text('Enviar denúncia'), findsNothing);
      await tester.tap(find.byType(BotaoPrimario), warnIfMissed: false);
      await tester.pump();
      expect(chamadas, 1);
      pendente.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('erro do servidor aparece na folha e dá para tentar de novo', (tester) async {
      var tentativas = 0;
      bool? resultado;
      await _abrir(
        tester,
        _comBotao((m, d) async {
          tentativas++;
          if (tentativas == 1) {
            throw const ErroTrato(TipoErro.recusado, 'Você não pode denunciar a si mesmo.');
          }
        }, (r) => resultado = r),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outro'));
      await tester.enterText(find.byKey(const ValueKey('detalhes-denuncia')), 'Algo estranho');
      await tester.tap(find.text('Enviar denúncia'));
      await tester.pumpAndSettle();
      expect(find.text('Você não pode denunciar a si mesmo.'), findsOneWidget);
      expect(resultado, isNull); // folha continua aberta

      await tester.tap(find.text('Enviar denúncia'));
      await tester.pumpAndSettle();
      expect(tentativas, 2);
      expect(resultado, isTrue);
    });
  });

  group('API: POST /v1/denuncias', () {
    test('manda alvo, denunciado, pedido, motivo e detalhes', () async {
      late http.Request pedida;
      final sessao = SessaoTrato()..entrar('t');
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: sessao,
        cliente: MockClient((req) async {
          pedida = req;
          return http.Response(
            jsonEncode({'id': 'a1', 'status': 'recebida'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await ServicoContaApi(api).enviarDenuncia(
        alvoTipo: 'chat',
        denunciadoId: 'usr-9',
        pedidoId: 'ped-3',
        motivo: 'cobranca_fora',
        detalhes: '  Quer receber por fora  ',
      );

      expect(pedida.method, 'POST');
      expect(pedida.url.path, '/v1/denuncias');
      expect(jsonDecode(pedida.body), {
        'alvo_tipo': 'chat',
        'denunciado_id': 'usr-9',
        'pedido_id': 'ped-3',
        'motivo': 'cobranca_fora',
        'detalhes': 'Quer receber por fora',
      });
    });
  });

  group('Pontos de entrada discretos', () {
    testWidgets('perfil do profissional: menu "Denunciar" chama o callback', (tester) async {
      var denunciou = 0;
      await _abrir(
        tester,
        PerfilProfissionalTela(
          profissional: profissionais.firstWhere((p) => p.detalhe != null),
          aoDenunciar: () => denunciou++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('menu-denunciar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Denunciar'));
      await tester.pumpAndSettle();
      expect(denunciou, 1);
    });

    testWidgets('perfil do profissional: sem callback (próprio perfil) não há menu',
        (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(profissional: profissionais.firstWhere((p) => p.detalhe != null)),
      );
      expect(find.byKey(const ValueKey('menu-denunciar')), findsNothing);
    });

    testWidgets('chat: menu "Denunciar" no topo chama o callback; sem callback não aparece',
        (tester) async {
      const conversa = ConversaPedido(
        nome: 'Carlos M.',
        iniciais: 'CM',
        numeroPedido: 'AB12',
        situacao: 'Agendado',
        mensagens: [],
        respostasRapidas: [],
      );
      var denunciou = 0;
      await _abrir(tester, ChatPedidoTela(conversa: conversa, aoDenunciar: () => denunciou++));
      await tester.tap(find.byKey(const ValueKey('menu-denunciar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Denunciar'));
      await tester.pumpAndSettle();
      expect(denunciou, 1);

      await _abrir(tester, const ChatPedidoTela(conversa: conversa));
      expect(find.byKey(const ValueKey('menu-denunciar')), findsNothing);
    });
  });

  testWidgets('rota: denunciar um chat envia o motivo ao serviço e avisa a pessoa',
      (tester) async {
    final conta = ServicoContaFake();
    final base = repositoriosDemo();
    RotasTrato.repos = RepositoriosTrato(
      pedidos: base.pedidos,
      orcamentos: base.orcamentos,
      pagamento: base.pagamento,
      chat: base.chat,
      notificacoes: base.notificacoes,
      perfil: base.perfil,
      profissional: base.profissional,
      catalogo: base.catalogo,
      servicos: base.servicos,
      agenda: base.agenda,
      conta: conta,
    );
    await _abrir(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => RotasTrato.denunciar(
              context,
              alvoTipo: 'chat',
              denunciadoId: 'usr-9',
              pedidoId: 'ped-3',
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assédio ou desrespeito'));
    await tester.enterText(find.byKey(const ValueKey('detalhes-denuncia')), 'Mensagens ofensivas');
    await tester.tap(find.text('Enviar denúncia'));
    await tester.pumpAndSettle();

    expect(conta.denuncias, [
      {
        'alvo_tipo': 'chat',
        'denunciado_id': 'usr-9',
        'pedido_id': 'ped-3',
        'motivo': 'assedio',
        'detalhes': 'Mensagens ofensivas',
      },
    ]);
    expect(find.text('Denúncia enviada para análise da nossa equipe.'), findsOneWidget);
  });
}
