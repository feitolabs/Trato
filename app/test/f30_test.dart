import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dados/sessao_expirada.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

FormularioPedido _formulario({bool remoto = true}) => FormularioPedido(
      categoria: formularioExemplo.categoria,
      categoriaId: formularioExemplo.categoriaId,
      servicos: formularioExemplo.servicos,
      servicosIniciais: formularioExemplo.servicosIniciais,
      perguntaQuantidade: formularioExemplo.perguntaQuantidade,
      dicaQuantidade: formularioExemplo.dicaQuantidade,
      quantidadeInicial: formularioExemplo.quantidadeInicial,
      perguntaVoltagem: formularioExemplo.perguntaVoltagem,
      voltagens: formularioExemplo.voltagens,
      voltagemInicial: formularioExemplo.voltagemInicial,
      descricaoInicial: formularioExemplo.descricaoInicial,
      fotos: formularioExemplo.fotos,
      prazos: formularioExemplo.prazos,
      faixas: formularioExemplo.faixas,
      endereco: 'Seu endereço atual',
      avisoEndereco: 'O endereço completo só aparece para o profissional contratado.',
      avisoPrazo: formularioExemplo.avisoPrazo,
      aceitaRemoto: remoto,
      cidades: const [CidadeOpcao(id: 'bh', nome: 'Belo Horizonte', uf: 'MG')],
    );

PedidoAbertoTela _pedidoAberto({String? categoria, bool remoto = false, int orcamentos = 0}) =>
    PedidoAbertoTela(
      numero: 'AB12',
      dados: DadosDoPedido(
        titulo: 'Orçamento geral',
        descricao: 'Preciso de ajuda com a planilha',
        categoriaNome: categoria,
        modalidade: remoto ? 'remoto' : 'presencial',
        orcamentosRecebidos: orcamentos,
      ),
      aoSalvar: ({
        required String descricao,
        required int faixaMaxCentavos,
        required String logradouro,
        required String numero,
        required String bairro,
        String? cep,
      }) async =>
          null,
      aoVerOrcamentos: () {},
      aoCancelar: () {},
    );

void main() {
  group('T1: sem pedido remoto no formulário (Termos 3.7)', () {
    testWidgets('categoria que aceita remoto mostra só o endereço', (tester) async {
      await _abrir(tester, NovoPedidoTela(formulario: _formulario()));
      expect(find.text('Remoto'), findsNothing);
      expect(find.text('Belo Horizonte · MG'), findsOneWidget);
      expect(find.textContaining('só aparece para o profissional contratado'), findsOneWidget);
    });
  });

  group('T2: tela do pedido aguardando orçamentos', () {
    testWidgets('remoto: categoria, descrição, selo, linha do tempo e banner de qualquer região',
        (tester) async {
      await _abrir(tester, _pedidoAberto(categoria: 'Planilhas', remoto: true));
      expect(find.byKey(const ValueKey('titulo-pedido')), findsOneWidget);
      expect(find.text('Planilhas'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('subtitulo-pedido'))).data,
        'Preciso de ajuda com a planilha',
      );
      expect(find.byKey(const ValueKey('selo-remoto')), findsOneWidget);
      expect(find.text('Pedido enviado'), findsOneWidget);
      expect(find.byType(LinhaDoTempo), findsOneWidget);
      expect(find.textContaining('profissionais de qualquer região'), findsOneWidget);
      // O que já existia continua.
      expect(find.text('Ver orçamentos'), findsOneWidget);
      expect(find.text('Editar pedido'), findsOneWidget);
      expect(find.text('Cancelar pedido'), findsOneWidget);
    });

    testWidgets('presencial sem categoria: título de antes, banner da região, sem selo',
        (tester) async {
      await _abrir(tester, _pedidoAberto());
      expect(find.text('Seu pedido'), findsOneWidget);
      expect(find.text('Orçamento geral'), findsOneWidget);
      expect(find.textContaining('profissionais da região'), findsOneWidget);
      expect(find.byKey(const ValueKey('selo-remoto')), findsNothing);
    });

    testWidgets('com orçamentos já recebidos, o banner some', (tester) async {
      await _abrir(tester, _pedidoAberto(orcamentos: 2));
      expect(find.textContaining('Pedido enviado aos profissionais'), findsNothing);
    });
  });

  group('T3: sem localização no envio (Termos 14.12)', () {
    (RepositorioPedidosApi, List<String>) repo() {
      final corpos = <String>[];
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((req) async {
          corpos.add(req.body);
          return http.Response(
            jsonEncode({
              'id': 'ab12cd34',
              'estado': 'aberto',
              'estado_nome': 'Aberto',
              'cliente_id': 'c1',
              'aberto_em': '2026-11-20T10:00:00Z',
              'acoes_permitidas': <String>[],
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      return (RepositorioPedidosApi(api), corpos);
    }

    RascunhoPedido rascunho(Modalidade m) => RascunhoPedido(
          servicos: const ['Aula'],
          quantidade: 1,
          voltagem: '',
          descricao: 'd',
          prazo: 'Esta semana',
          faixa: const FaixaPreco(minimoCentavos: 0, maximoCentavos: 0),
          categoriaId: 'cat',
          cidadeId: 'bh',
          modalidade: m,
          bairro: 'Savassi',
        );

    test('nem o pedido presencial nem o remoto mandam posição', () async {
      final (r, corpos) = repo();
      await r.criar(rascunho(Modalidade.remoto));
      await r.criar(rascunho(Modalidade.presencial));
      expect(corpos, hasLength(2));
      for (final corpo in corpos) {
        expect(corpo, isNot(contains('local_aprox')));
      }
    });

    testWidgets('o formulário presencial não fala em localização', (tester) async {
      await _abrir(tester, NovoPedidoTela(formulario: _formulario(remoto: false)));
      expect(find.textContaining('localização', skipOffstage: false), findsNothing);
    });
  });

  group('T4: sessão expirada', () {
    tearDown(() => abrirLoginPorSessaoExpiradaHook = null);

    testWidgets('"Tentar de novo" leva ao login em vez de recarregar em laço', (tester) async {
      var logins = 0;
      var cargas = 0;
      abrirLoginPorSessaoExpiradaHook = () => logins++;
      await _abrir(
        tester,
        Scaffold(
          body: Carregador<int>(
            carregar: () async {
              cargas++;
              throw ErroTrato.sessaoExpirada;
            },
            construir: (_, __) => const SizedBox(),
          ),
        ),
      );
      expect(find.text(ErroTrato.sessaoExpirada.mensagem), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(logins, 1);
      expect(cargas, 1); // não recarregou
    });

    testWidgets('outro erro continua recarregando', (tester) async {
      var cargas = 0;
      abrirLoginPorSessaoExpiradaHook = () => fail('não deveria abrir o login');
      await _abrir(
        tester,
        Scaffold(
          body: Carregador<int>(
            carregar: () async {
              cargas++;
              throw ErroTrato.semInternet;
            },
            construir: (_, __) => const SizedBox(),
          ),
        ),
      );
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(cargas, 2);
    });
  });

  testWidgets('lista de pedidos mostra a descrição como subtítulo', (tester) async {
    await _abrir(
      tester,
      const SeusPedidosTela(
        emAndamento: [
          PedidoResumo(
            titulo: 'Planilhas',
            subtitulo: 'Pedido #5577 · aberto em 21/11',
            statusTexto: 'Aguardando orçamentos',
            statusTipo: TipoStatus.info,
            descricao: 'Preciso de ajuda com a planilha',
          ),
          PedidoResumo(
            titulo: 'Reparo',
            subtitulo: 'Pedido #1 · aberto em 20/11',
            statusTexto: 'Agendado',
            statusTipo: TipoStatus.info,
          ),
        ],
        finalizados: [],
      ),
    );
    expect(find.text('Preciso de ajuda com a planilha'), findsOneWidget);
    expect(find.text('Pedido #5577 · aberto em 21/11'), findsOneWidget);
  });
}
