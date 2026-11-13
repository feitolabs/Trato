import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/aditivo/aditivo.dart';
import 'package:trato/telas/aditivo/responder_aditivo_tela.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/profissional_inicio/pedidos_profissional_tela.dart';
import 'package:trato/telas/servicos/detalhe_servico_tela.dart';
import 'package:trato/telas/servicos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Chamada {
  _Chamada(this.metodo, this.caminho, this.corpo);

  final String metodo;
  final String caminho;
  final Map<String, dynamic>? corpo;
}

(ClienteApi, List<_Chamada>) _cliente(http.Response Function(http.Request) responder) {
  final chamadas = <_Chamada>[];
  final sessao = SessaoTrato()..entrar('valor-de-teste');
  final api = ClienteApi(
    urlBase: 'https://api.teste/',
    sessao: sessao,
    cliente: MockClient((req) async {
      chamadas.add(
        _Chamada(
          req.method,
          req.url.path + (req.url.hasQuery ? '?${req.url.query}' : ''),
          req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>,
        ),
      );
      return responder(req);
    }),
  );
  return (api, chamadas);
}

Map<String, Object?> _pedidoJson(String id, String estado, {String modalidade = 'presencial'}) => {
      'id': id,
      'estado': estado,
      'estado_nome': estado,
      'cliente_id': 'c1',
      'profissional_id': 'me',
      'aberto_em': '2026-11-07T12:00:00Z',
      'janela': null,
      'concluido_em': null,
      'acoes_permitidas': <String>[],
      'codigo_inicio': null,
      'codigo_conclusao': null,
      'modalidade': modalidade,
    };

const _endereco = {
  'logradouro': 'Rua das Flores',
  'numero': '10',
  'complemento': 'apto 2',
  'bairro': 'Centro',
  'cep': '35500-000',
  'referencia': 'perto da praça',
};

Widget _app(Widget filho) => MaterialApp(theme: TemaTrato.claro, home: filho);

void main() {
  group('Criar pedido: modalidade e endereço', () {
    RascunhoPedido rascunho({Modalidade m = Modalidade.presencial, EnderecoRascunho? e}) =>
        RascunhoPedido(
          categoriaId: 'cat-1',
          cidadeId: 'cid-1',
          servicos: const ['Site'],
          quantidade: 1,
          voltagem: '',
          descricao: 'Preciso de um site',
          prazo: 'Sem pressa',
          faixa: const FaixaPreco(minimoCentavos: 10000, maximoCentavos: 20000),
          modalidade: m,
          endereco: e,
        );

    test('presencial manda o endereço completo e o bairro dele', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson('abcd1234', 'aberto')));
      await RepositorioPedidosApi(api).criar(
        rascunho(
          e: const EnderecoRascunho(
            logradouro: ' Rua das Flores ',
            numero: '10',
            bairro: 'Centro',
            cep: '35500-000',
            complemento: 'apto 2',
          ),
        ),
      );
      final corpo = chamadas.single.corpo!;
      expect(corpo['modalidade'], 'presencial');
      expect(corpo['bairro'], 'Centro');
      expect(corpo['endereco'], {
        'logradouro': 'Rua das Flores',
        'numero': '10',
        'bairro': 'Centro',
        'cep': '35500-000',
        'complemento': 'apto 2',
      });
    });

    test('remoto não manda endereço', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson('abcd1234', 'aberto')));
      await RepositorioPedidosApi(api).criar(rascunho(m: Modalidade.remoto));
      final corpo = chamadas.single.corpo!;
      expect(corpo['modalidade'], 'remoto');
      expect(corpo.containsKey('endereco'), isFalse);
    });
  });

  group('Catálogo e formulário', () {
    test('a categoria diz se aceita remoto e o formulário herda', () async {
      final (api, _) = _cliente((r) {
        if (r.url.path == '/v1/catalogo/categorias') {
          return _json([
            {'id': 'c1', 'nome': 'Eletricista', 'slug': 'eletricista'},
            {'id': 'c2', 'nome': 'Design', 'slug': 'design', 'aceita_remoto': true},
          ]);
        }
        if (r.url.path == '/v1/catalogo/cidades') {
          return _json([
            {'id': 'cid-1', 'nome': 'Divinopolis', 'uf': 'MG'},
          ]);
        }
        return _json({'detail': 'não'}, 404);
      });
      final repo = RepositorioCatalogoApi(api);
      final cats = await repo.categorias();
      expect(cats.map((c) => c.aceitaRemoto), [false, true]); // padrão: só presencial
      expect((await repo.formulario('c1')).aceitaRemoto, isFalse);
      expect((await repo.formulario('c2')).aceitaRemoto, isTrue);
    });
  });

  group('Profissional: pedidos contratados', () {
    http.Response responder(http.Request r) {
      switch (r.url.path) {
        case '/v1/me':
          return _json({'id': 'me', 'nome': 'Ana Souza'});
        case '/v1/profissional/pedidos-abertos':
          return _json([
            {
              'id': 'ab1',
              'titulo': 'Montar site',
              'descricao': 'x',
              'bairro': null,
              'categoria_id': 'c',
              'faixa_preco_min_centavos': null,
              'faixa_preco_max_centavos': null,
              'urgente': false,
              'prazo_desejado': null,
              'aberto_em': '2026-11-12T10:00:00Z',
              'modalidade': 'remoto',
            },
          ]);
        case '/v1/profissionais/me/saldo':
          return _json({'a_liberar_centavos': 0, 'liberado_centavos': 0});
        case '/v1/pedidos':
          return _json([
            _pedidoJson('pres1111', 'agendado'),
            _pedidoJson('remo2222', 'agendado', modalidade: 'remoto'),
          ]);
        case '/v1/pedidos/pres1111/dados':
          return _json({
            'titulo': 'Pintar',
            'descricao': 'x',
            'endereco': _endereco,
            'modalidade': 'presencial',
          });
      }
      return _json({'detail': 'não'}, 404);
    }

    test('presencial traz o endereço completo e o texto do mapa; remoto não busca endereço', () async {
      final (api, chamadas) = _cliente(responder);
      final inicio = await RepositorioProfissionalApi(api).inicio();

      final presencial = inicio.contratados.firstWhere((c) => c.pedidoId == 'pres1111');
      expect(presencial.remoto, isFalse);
      expect(
        presencial.endereco,
        'Rua das Flores, 10 · apto 2 · Centro · CEP 35500-000 · (perto da praça)',
      );
      expect(presencial.consultaMapa, 'Rua das Flores, 10, Centro, 35500-000');

      final remoto = inicio.contratados.firstWhere((c) => c.pedidoId == 'remo2222');
      expect(remoto.remoto, isTrue);
      expect(remoto.endereco, isNull);
      // o endereço só é buscado para o pedido presencial
      expect(chamadas.where((c) => c.caminho.endsWith('/dados')).map((c) => c.caminho),
          ['/v1/pedidos/pres1111/dados']);
      // pedido aberto remoto vem marcado
      expect(inicio.pedidos.single.remoto, isTrue);
      // o próximo atendimento acompanha o primeiro pedido pago
      expect(inicio.proximo?.pedidoId, 'pres1111');
      expect(inicio.proximo?.endereco, contains('Rua das Flores'));
    });

    test('a agenda mostra o endereço do presencial e "Atendimento remoto" no remoto', () async {
      final (api, _) = _cliente(responder);
      final agenda = await RepositorioAgendaApi(RepositorioProfissionalApi(api)).listar();
      final porPedido = {for (final a in agenda) a.pedidoId: a};
      expect(porPedido['pres1111']!.local, contains('Rua das Flores'));
      expect(porPedido['pres1111']!.remoto, isFalse);
      expect(porPedido['remo2222']!.local, 'Atendimento remoto');
      expect(porPedido['remo2222']!.remoto, isTrue);
    });
  });

  group('Check-in e check-out remotos', () {
    test('iniciar só com o código: nada de foto nem localização', () async {
      final (api, chamadas) = _cliente((_) => _json({'id': 'p'}));
      final servico = RepositorioProfissionalApi(api).servicoCheckIn('p1', remoto: true);
      final r = await servico.iniciarServico('4821');
      expect(r, ResultadoInicio.iniciado);
      expect(chamadas.single.caminho, '/v1/pedidos/p1/acoes/fazer_check_in');
      expect(chamadas.single.corpo, {
        'prova': {'codigo_inicio': '4821'},
      });
    });

    test('código errado no remoto vira "código incorreto" (quem decide é o backend)', () async {
      final (api, _) = _cliente((_) => _json({'detail': 'O código está errado.'}, 422));
      final r = await RepositorioProfissionalApi(api)
          .servicoCheckIn('p1', remoto: true)
          .iniciarServico('0000');
      expect(r, ResultadoInicio.codigoIncorreto);
    });

    test('concluir só com o código de conclusão', () async {
      final (api, chamadas) = _cliente((_) => _json({'id': 'p'}));
      final fim = await RepositorioProfissionalApi(api).servicoCheckOut('p1', remoto: true).finalizar('9876');
      expect(fim.name, 'concluido');
      expect(chamadas.single.caminho, '/v1/pedidos/p1/acoes/fazer_check_out');
      expect(chamadas.single.corpo, {
        'prova': {'codigo_conclusao': '9876'},
      });
    });

    testWidgets('a tela de check-in remoto não pede foto nem localização', (tester) async {
      final servico = ServicoCheckInFake();
      await tester.pumpWidget(
        _app(CheckInTela(servico: servico, tituloBarra: 'Pedido #AAAA', remoto: true)),
      );
      expect(find.text('Foto de chegada'), findsNothing);
      expect(find.text('Localização'), findsNothing);
      expect(find.text('Iniciar atendimento'), findsOneWidget);
      // com 4 dígitos já dá para iniciar (no presencial precisaria de foto e localização)
      await tester.enterText(find.byType(TextField).first, '4821');
      await tester.pump();
      await tester.tap(find.text('Iniciar serviço'));
      await tester.pumpAndSettle();
      expect(servico.codigosEnviados, ['4821']);
    });

    testWidgets('a tela de check-in presencial continua pedindo foto e localização', (tester) async {
      await tester.pumpWidget(
        _app(CheckInTela(servico: ServicoCheckInFake(), tituloBarra: 'Pedido #AAAA')),
      );
      expect(find.text('Foto de chegada'), findsOneWidget);
      expect(find.text('Localização'), findsOneWidget);
    });
  });

  group('Telas do profissional', () {
    testWidgets('cartão de pedido aberto remoto tem o selo Remoto e não mostra bairro', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CartaoPedidoAberto(
              pedido: const PedidoAberto(
                id: 'a',
                titulo: 'Montar site',
                bairro: 'Centro',
                prazo: 'sem data',
                modalidade: 'remoto',
              ),
              aoTocar: () {},
            ),
          ),
        ),
      );
      expect(find.text('Remoto'), findsOneWidget);
      expect(find.textContaining('Atendimento remoto'), findsOneWidget);
      expect(find.textContaining('Centro'), findsNothing);
    });

    testWidgets('Em andamento mostra o endereço, abre no mapa e marca o remoto', (tester) async {
      String? aberto;
      await tester.pumpWidget(
        _app(
          PedidosProfissionalTela(
            pedidos: const [],
            conversas: const SizedBox.shrink(),
            aoAbrirMapa: (q) => aberto = q,
            contratados: const [
              PedidoContratado(
                pedidoId: 'p1',
                titulo: 'Pedido #AAAA',
                situacao: 'Agendado',
                estadoApi: 'agendado',
                endereco: 'Rua das Flores, 10 · Centro · CEP 35500-000',
                consultaMapa: 'Rua das Flores, 10, Centro, 35500-000',
              ),
              PedidoContratado(
                pedidoId: 'p2',
                titulo: 'Pedido #BBBB',
                situacao: 'Agendado',
                estadoApi: 'agendado',
                remoto: true,
              ),
              PedidoContratado(
                pedidoId: 'p3',
                titulo: 'Pedido #CCCC',
                situacao: 'Agendado',
                estadoApi: 'agendado',
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Em andamento (3)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('endereco-do-pedido')), findsOneWidget);
      expect(find.textContaining('Rua das Flores, 10'), findsOneWidget);
      expect(find.byKey(const ValueKey('modalidade-remoto')), findsOneWidget);
      expect(find.textContaining('ainda não informou o endereço'), findsOneWidget);

      await tester.tap(find.text('Abrir no mapa'));
      expect(aberto, 'Rua das Flores, 10, Centro, 35500-000');
    });

    testWidgets('o check-out remoto também só pede o código', (tester) async {
      await tester.pumpWidget(
        _app(CheckOutTela(servico: _CheckOutFake(), tituloBarra: 'Pedido #AAAA', remoto: true)),
      );
      expect(find.text('Foto final'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '9876');
      await tester.pump();
      final botao = tester.widget<BotaoPrimario>(find.byType(BotaoPrimario));
      expect(botao.aoTocar, isNotNull);
      expect(find.text('Tirar foto'), findsNothing);
    });
  });

  group('Cliente: local do serviço no pedido', () {
    DetalheServico detalhe({bool remoto = false, String? local}) => DetalheServico(
          pedidoId: 'p1',
          numero: 'AAAA',
          titulo: 'Pedido #AAAA',
          estadoApi: 'pago_e_retido',
          statusTexto: 'Pago',
          statusTipo: TipoStatus.info,
          abertoEm: 'Aberto em 07/11',
          etapas: const [],
          remoto: remoto,
          local: local,
        );

    testWidgets('presencial mostra o endereço; remoto diz que é à distância', (tester) async {
      await tester.pumpWidget(
        _app(DetalheServicoTela(dados: detalhe(local: 'Rua das Flores, 10 · Centro'), aoAcao: (_) {})),
      );
      expect(find.text('Local do serviço'), findsOneWidget);
      expect(find.text('Atendimento presencial'), findsOneWidget);
      expect(find.text('Rua das Flores, 10 · Centro'), findsOneWidget);

      await tester.pumpWidget(_app(DetalheServicoTela(dados: detalhe(remoto: true), aoAcao: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('Atendimento remoto'), findsOneWidget);
      expect(find.textContaining('combina tudo'), findsOneWidget);
    });

    testWidgets('presencial sem endereço avisa que não foi informado', (tester) async {
      await tester.pumpWidget(_app(DetalheServicoTela(dados: detalhe(), aoAcao: (_) {})));
      expect(find.text('Endereço não informado neste pedido.'), findsOneWidget);
    });

    test('o detalhe busca o endereço do próprio cliente e marca o remoto', () async {
      final (api, _) = _cliente((r) {
        if (r.url.path == '/v1/pedidos/aaaa1111') {
          return _json(_pedidoJson('aaaa1111', 'pago_e_retido'));
        }
        if (r.url.path == '/v1/pedidos/aaaa1111/dados') {
          return _json({'titulo': 'x', 'descricao': 'y', 'endereco': _endereco});
        }
        if (r.url.path.endsWith('/eventos') || r.url.path.endsWith('/fotos')) {
          return _json(<Object>[]);
        }
        if (r.url.path.endsWith('/interlocutor')) {
          return _json({'id': 'me', 'nome': 'Ana S.', 'papel': 'profissional'});
        }
        return _json({'detail': 'não'}, 404);
      });
      final repo = RepositorioServicosClienteApi(api, RepositorioPedidosApi(api));
      final d = await repo.detalhe('aaaa1111');
      expect(d.remoto, isFalse);
      expect(d.local, contains('Rua das Flores, 10'));
    });
  });

  group('Mensagem rápida do check-in', () {
    test('sai como mensagem no chat do pedido', () async {
      final (api, chamadas) = _cliente((_) => _json({'id': 'm1'}, 201));
      final servico = RepositorioProfissionalApi(api).servicoCheckIn('p1');
      await servico.enviarMensagemRapida('Cheguei');
      expect(chamadas.single.metodo, 'POST');
      expect(chamadas.single.caminho, '/v1/pedidos/p1/mensagens');
      expect(chamadas.single.corpo, {'texto': 'Cheguei'});
    });

    test('cliente ausente também avisa pelo chat', () async {
      final (api, chamadas) = _cliente((_) => _json({'id': 'm1'}, 201));
      await RepositorioProfissionalApi(api).servicoCheckIn('p1').avisarClienteAusente();
      expect(chamadas.single.caminho, '/v1/pedidos/p1/mensagens');
      expect(chamadas.single.corpo!['texto'], contains('não encontrei'));
    });
  });

  group('Aditivo: resposta do cliente', () {
    http.Response responder(http.Request r) {
      if (r.method == 'GET' && r.url.path == '/v1/contratos/ped-1/aditivos') {
        return _json([
          {'id': 'adit-9', 'descricao': 'Horas extras', 'valor_centavos': 45000, 'estado': 'proposto'},
        ]);
      }
      if (r.url.path == '/v1/pedidos/ped-1/interlocutor') {
        return _json({'id': 'pro', 'nome': 'Gabriel L.'});
      }
      if (r.url.path == '/v1/contratos/ped-1/aditivos/adit-9/aprovar') {
        return _json({'aditivo': {'id': 'adit-9'}});
      }
      return _json({'detail': 'não'}, 404);
    }

    test('o detalhe traz o nome de quem pediu', () async {
      final (api, _) = _cliente(responder);
      final d = await ServicoAditivoApi(api).carregar('ped-1');
      expect(d!.profissional, 'Gabriel L.');
      expect(d.pedidoTitulo, startsWith('Pedido #'));
    });

    testWidgets('aprovar responde com o id do pedido (não o do aditivo) e cobra no cartão', (t) async {
      final (api, chamadas) = _cliente(responder);
      bool? aprovou;
      await t.pumpWidget(
        _app(
          ResponderAditivoTela(
            servico: ServicoAditivoApi(api),
            aditivoId: 'ped-1',
            aoResponder: (a) => aprovou = a,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Aprovar aditivo'));
      await t.pumpAndSettle();
      expect(aprovou, isTrue);
      final post = chamadas.firstWhere((c) => c.metodo == 'POST');
      expect(post.caminho, '/v1/contratos/ped-1/aditivos/adit-9/aprovar');
      expect(post.corpo, {'meio': 'cartao'});
    });
  });

  group('Cadastro do profissional: como atende', () {
    test('salvar envia presencial/remoto e carregar lê de volta', () async {
      final (api, chamadas) = _cliente((r) {
        if (r.url.path == '/v1/catalogo/categorias') {
          return _json([
            {'id': 'c1', 'nome': 'Design'},
          ]);
        }
        if (r.url.path == '/v1/catalogo/cidades') {
          return _json([
            {'id': 'cid-1', 'nome': 'Divinopolis', 'uf': 'MG'},
          ]);
        }
        if (r.url.path == '/v1/profissional/perfil') {
          return _json({
            'bio': 'x',
            'categorias': ['c1'],
            'regioes': [
              {'cidade_id': 'cid-1'},
            ],
            'disponibilidade': <Object>[],
            'portfolio': <Object>[],
            'atende_presencial': false,
            'atende_remoto': true,
          });
        }
        return _json({'id': 'u'}, 201);
      });
      final servico = ServicoCadastroProfissionalApi(api);
      await servico.carregarOpcoes();
      await servico.salvar(
        const DadosCadastroProfissional(
          nome: 'Ana Souza',
          sobre: '',
          categorias: {'Design'},
          cidade: 'Divinopolis',
          raioKm: 10,
          dias: {'Seg'},
          periodos: {'Manhã'},
          portfolio: [],
          atendePresencial: true,
          atendeRemoto: true,
        ),
      );
      final corpo = chamadas.firstWhere((c) => c.caminho == '/v1/profissional/cadastro').corpo!;
      expect(corpo['atende_presencial'], true);
      expect(corpo['atende_remoto'], true);

      final atual = await servico.carregarAtual();
      expect(atual!.atendePresencial, isFalse);
      expect(atual.atendeRemoto, isTrue);
    });
  });
}

class _CheckOutFake implements ServicoCheckOut {
  @override
  Future<FotoChegada?> tirarFotoFinal() async => const FotoChegada(hora: '10:00');

  @override
  Future<ResultadoFim> finalizar(String codigo) async => ResultadoFim.concluido;
}
