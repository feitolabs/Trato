import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_push.dart';
import 'package:trato/telas/conta/seguranca_conta_tela.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/preferencias_notificacoes_tela.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart' as expn;

Widget _app(Widget home) => MaterialApp(
      theme: TemaTrato.claro,
      home: home,
    );

ClienteApi _apiSimulado(
  Future<http.Response> Function(http.Request req) handler,
) =>
    ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient(handler),
    );

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Fotos do pedido aberto', () {
    test('API lê fotos em dados(), fotosDoPedidoAberto() e detalhe() do profissional', () async {
      final api = _apiSimulado((req) async {
        switch (req.url.path) {
          case '/v1/pedidos/p1/dados':
            return _json({
              'titulo': 'Troca de disjuntor',
              'descricao': 'Quadro desarmando',
              'modalidade': 'presencial',
              'fotos_urls': ['https://cdn.teste/quadro.jpg'],
            });
          case '/v1/pedidos/p1/fotos':
            expect(req.url.queryParameters['finalidade'], 'pedido');
            return _json([
              {
                'id': 'f1',
                'finalidade': 'pedido',
                'url': 'https://cdn.teste/quadro.jpg',
                'expira_em_segundos': 60,
                'criada_em': '2026-11-17T10:00:00Z',
              },
            ]);
          case '/v1/profissional/pedidos-abertos/p1':
            return _json({
              'id': 'p1',
              'titulo': 'Troca de disjuntor',
              'descricao': 'Quadro desarmando',
              'bairro': 'Centro',
              'aberto_em': '2026-11-17T09:00:00Z',
              'modalidade': 'presencial',
              'convidado': true,
              'fotos_urls': ['https://cdn.teste/quadro.jpg'],
              'respostas': <Object>[],
            });
          default:
            return _json({}, 404);
        }
      });

      final repoPedidos = RepositorioPedidosApi(api);
      final dados = await repoPedidos.dados('p1');
      expect(dados.fotos, ['https://cdn.teste/quadro.jpg']);
      expect(await repoPedidos.fotosDoPedidoAberto('p1'), ['https://cdn.teste/quadro.jpg']);

      final repoPro = RepositorioProfissionalApi(api);
      final detalhe = await repoPro.detalhe('p1');
      expect(detalhe.legendasFotos, ['https://cdn.teste/quadro.jpg']);
      expect(detalhe.pedido.convidado, isTrue);
    });

    testWidgets('PedidoAbertoTela exibe seção Fotos anexadas quando há fotos', (t) async {
      await t.pumpWidget(
        _app(
          PedidoAbertoTela(
            numero: '#AB12',
            dados: const DadosDoPedido(
              titulo: 'Pintura sala',
              descricao: 'Duas paredes',
              fotos: ['https://cdn.teste/parede.jpg'],
            ),
            aoSalvar: ({
              String? descricao,
              int? faixaMinCentavos,
              int? faixaMaxCentavos,
              String? cep,
              String? logradouro,
              String? numero,
              String? bairro,
              String? complemento,
            }) async =>
                const DadosDoPedido(titulo: 'Pintura sala', descricao: 'Duas paredes'),
            aoVerOrcamentos: () {},
          ),
        ),
      );
      expect(find.text('Fotos anexadas'), findsOneWidget);
    });
  });

  group('2. Parcelamento no cartão e cupom no checkout', () {
    test('RepositorioPagamentoApi aplica cupom e envia parcelas/cupom na cobrança', () async {
      final requisicoes = <http.Request>[];
      final api = _apiSimulado((req) async {
        requisicoes.add(req);
        if (req.url.path == '/v1/contratos/p1/cupom') {
          return _json({
            'valor_centavos': 100000,
            'desconto_centavos': 10000,
            'total_a_pagar_centavos': 90000,
            'cupom_codigo': 'TRATO10',
            'meios_disponiveis': ['pix', 'cartao'],
            'opcoes_parcelamento': [
              {
                'parcelas': 2,
                'custo_centavos': 2700,
                'total_centavos': 92700,
                'valor_parcela_centavos': 46350,
              },
            ],
          });
        }
        return _json({
          'cobranca_id': 'cob-1',
          'tipo_instrucao': 'cartao_segredo_do_cliente',
          'instrucao': 'secret-1',
          'parcelas': 2,
          'valor_centavos': 92700,
        }, 201);
      });

      final repo = RepositorioPagamentoApi(api);
      final comCupom = await repo.aplicarCupom('p1', ' trato10 ');
      expect(comCupom.descontoCentavos, 10000);
      expect(comCupom.cupomCodigo, 'TRATO10');
      expect(comCupom.valorAgoraCentavos, 90000);
      expect(comCupom.parcelamento.single.parcelas, 2);

      await repo.criarCobranca('p1', MetodoPagamento.cartao, parcelas: 2, cupom: 'TRATO10');
      final corpoCobranca = jsonDecode(requisicoes.last.body) as Map<String, dynamic>;
      expect(corpoCobranca, {'meio': 'cartao', 'parcelas': 2, 'cupom': 'TRATO10'});
    });

    testWidgets('PagamentoTela seleciona parcela 2x, aplica cupom e envia detalhado', (t) async {
      t.view.physicalSize = const Size(420, 960);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      MetodoPagamento? metodoEnvio;
      int? parcelasEnvio;
      String? cupomEnvio;

      const dadosBase = DadosPagamento(
        subtitulo: 'Pedido #1234',
        valorAgoraCentavos: 100000,
        opcoes: [
          OpcaoPagamento(metodo: MetodoPagamento.pix, titulo: 'Pix', descricao: 'No seu banco'),
          OpcaoPagamento(metodo: MetodoPagamento.cartao, titulo: 'Cartão', descricao: 'Parcelado'),
        ],
        parcelamento: [
          OpcaoParcelamento(
            parcelas: 2,
            custoCentavos: 3000,
            totalCentavos: 103000,
            valorParcelaCentavos: 51500,
          ),
        ],
      );

      await t.pumpWidget(
        _app(
          PagamentoTela(
            dados: dadosBase,
            aoAplicarCupom: (codigo) async => dadosBase.copiarCom(
              valorAgoraCentavos: 90000,
              descontoCentavos: 10000,
              descontoCupomCentavos: 10000,
              cupomCodigo: codigo.trim().toUpperCase(),
              parcelamento: const [
                OpcaoParcelamento(
                  parcelas: 2,
                  custoCentavos: 2700,
                  totalCentavos: 92700,
                  valorParcelaCentavos: 46350,
                ),
              ],
            ),
            aoPagarDetalhado: (m, p, c) async {
              metodoEnvio = m;
              parcelasEnvio = p;
              cupomEnvio = c;
            },
          ),
        ),
      );

      await t.ensureVisible(find.byKey(const Key('campo-cupom')));
      await t.enterText(find.byKey(const Key('campo-cupom')), 'trato10');
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('botao-aplicar-cupom')));
      await t.tap(find.byKey(const Key('botao-aplicar-cupom')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('botao-remover-cupom')), findsOneWidget);
      await t.drag(find.byType(ListView), const Offset(0, 400));
      await t.pumpAndSettle();
      expect(find.textContaining('Cupom TRATO10 aplicado'), findsOneWidget);

      await t.ensureVisible(find.text('Cartão'));
      await t.tap(find.text('Cartão'));
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('parcela-2')));
      await t.tap(find.byKey(const Key('parcela-2')));
      await t.pumpAndSettle();

      await t.tap(find.textContaining('em 2x no cartão'));
      await t.pumpAndSettle();

      expect(metodoEnvio, MetodoPagamento.cartao);
      expect(parcelasEnvio, 2);
      expect(cupomEnvio, 'TRATO10');
    });
  });

  group('3. Pedido direcionado ao profissional', () {
    testWidgets('NovoPedidoTela exibe banner do profissional convidado e preenche RascunhoPedido',
        (t) async {
      t.view.physicalSize = const Size(420, 960);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      RascunhoPedido? enviado;
      const formulario = FormularioPedido(
        categoria: 'Elétrica',
        servicos: ['Trocar tomada'],
        servicosIniciais: {'Trocar tomada'},
        perguntaQuantidade: 'Quantas?',
        dicaQuantidade: 'Qtd',
        quantidadeInicial: 1,
        perguntaVoltagem: 'Voltagem',
        voltagens: ['220 V'],
        voltagemInicial: '220 V',
        descricaoInicial: 'Instalação na sala',
        fotos: [],
        prazos: ['Esta semana'],
        faixas: [FaixaPreco(minimoCentavos: 10000, maximoCentavos: 20000)],
        endereco: 'Centro',
        avisoEndereco: '',
        avisoPrazo: '',
        categoriaId: 'cat-1',
        cidades: [CidadeOpcao(id: 'cid-1', nome: 'BH', uf: 'MG')],
        aceitaRemoto: true,
      );

      await t.pumpWidget(
        _app(
          NovoPedidoTela(
            formulario: formulario,
            agora: () => DateTime(2026, 11, 17, 10),
            profissionalConvidadoId: 'pro-1',
            profissionalConvidadoNome: 'Carlos Mendes',
            aoEnviar: (r) => enviado = r,
          ),
        ),
      );

      expect(find.byKey(const Key('banner-profissional-convidado')), findsOneWidget);
      expect(find.text('Pedido direto para Carlos Mendes. Ele será avisado primeiro.'), findsOneWidget);

      await t.ensureVisible(find.text(Modalidade.remoto.rotulo));
      await t.tap(find.text(Modalidade.remoto.rotulo));
      await t.pump();

      await t.tap(find.text('Enviar pedido'));
      await t.pumpAndSettle();

      expect(enviado?.profissionalConvidadoId, 'pro-1');
      expect(enviado?.profissionalConvidadoNome, 'Carlos Mendes');
    });

    testWidgets('CartaoPedidoAberto mostra selo "Para você" quando convidado == true', (t) async {
      await t.pumpWidget(
        _app(
          const Scaffold(
            body: CartaoPedidoAberto(
              pedido: PedidoAberto(
                id: 'p1',
                titulo: 'Pintar quarto',
                bairro: 'Savassi',
                prazo: 'Esta semana',
                convidado: true,
              ),
              aoTocar: null,
            ),
          ),
        ),
      );
      expect(find.text('Para você'), findsOneWidget);
    });

    test('RepositorioPedidosApi.criar envia profissional_convidado_id', () async {
      Map<String, dynamic>? bodyEnviado;
      final api = _apiSimulado((req) async {
        bodyEnviado = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'id': 'ped-novo',
          'estado': 'aberto',
          'estado_nome': 'Aberto',
          'cliente_id': 'cli-1',
          'aberto_em': '2026-11-17T10:00:00Z',
          'acoes_permitidas': <String>[],
        }, 201);
      });

      final repo = RepositorioPedidosApi(api);
      final id = await repo.criar(
        RascunhoPedido(
          servicos: const ['Pintura'],
          quantidade: 1,
          voltagem: '',
          descricao: 'Sala',
          prazo: 'Hoje',
          prazoDesejado: DateTime(2026, 11, 20),
          urgente: false,
          faixa: expn.formularioExemplo.faixas.first,
          fotos: const [],
          categoriaId: 'cat-1',
          cidadeId: 'cid-1',
          modalidade: Modalidade.remoto,
          profissionalConvidadoId: 'pro-1',
          profissionalConvidadoNome: 'Carlos',
        ),
      );
      expect(id, 'ped-novo');
      expect(bodyEnviado?['profissional_convidado_id'], 'pro-1');
    });
  });

  group('4. Remarcação de visita e aprovação de horário pelo cliente', () {
    test('PropostaAgendaChat.ler extrai janela e preserva texto', () {
      final (agenda, texto) = PropostaAgendaChat.ler(
        '[agenda:2026-11-20T12:00:00Z|2026-11-20T14:00:00Z] Sugestão de visita.',
      );
      expect(agenda, isNotNull);
      expect(agenda!.fim.difference(agenda.inicio), const Duration(hours: 2));
      expect(texto, 'Sugestão de visita.');
    });

    test('API chama remarcar, agenda/propor e agenda/aceitar', () async {
      final caminhos = <String>[];
      final api = _apiSimulado((req) async {
        caminhos.add(req.url.path);
        return _json({'ok': true});
      });

      final pedidosApi = RepositorioPedidosApi(api);
      final chatApi = RepositorioChatApi(api);
      final inicio = DateTime.utc(2026, 11, 20, 12);
      final fim = DateTime.utc(2026, 11, 20, 14);

      await pedidosApi.remarcarAgenda('p1', inicio, fim);
      await chatApi.proporAgenda('p1', inicio, fim, justificativa: 'Tarde');
      await chatApi.aceitarAgenda('p1', mensagemId: 7, inicio: inicio, fim: fim);

      expect(caminhos, [
        '/v1/pedidos/p1/acoes/remarcar',
        '/v1/pedidos/p1/agenda/propor',
        '/v1/pedidos/p1/agenda/aceitar',
      ]);
    });

    testWidgets('ChatPedidoTela mostra botão Confirmar este horário e chama callback', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      MensagemChat? aceita;
      final inicio = DateTime(2026, 11, 20, 9);
      final fim = DateTime(2026, 11, 20, 11);

      await t.pumpWidget(
        _app(
          ChatPedidoTela(
            conversa: ConversaPedido(
              nome: 'Carlos',
              iniciais: 'CM',
              numeroPedido: '#AB12',
              situacao: 'Pago e retido',
              pedidoAberto: false,
              respostasRapidas: const [],
              mensagens: [
                MensagemChat(
                  id: 10,
                  tipo: TipoMensagem.texto,
                  hora: '09h00',
                  texto: 'Posso ir nesse horário.',
                  minha: false,
                  propostaAgenda: PropostaAgendaChat(inicio: inicio, fim: fim),
                ),
              ],
            ),
            aoSugerirAgenda: () async {},
            aoAceitarAgenda: (m) async => aceita = m,
          ),
        ),
      );

      expect(find.byKey(const Key('botao-sugerir-agenda')), findsOneWidget);
      expect(find.text('Confirmar este horário'), findsOneWidget);
      await t.tap(find.text('Confirmar este horário'));
      await t.pumpAndSettle();

      expect(aceita?.id, 10);
    });

    testWidgets('PedidoExecucaoTela exibe Remarcar visita quando estadoApi == agendado', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      await t.pumpWidget(
        _app(
          PedidoExecucaoTela(
            pedido: const PedidoEmExecucao(
              numero: '#AB12',
              titulo: 'Visita marcada',
              estadoApi: 'agendado',
              etapas: [
                EtapaLinhaDoTempo(titulo: 'Visita', detalhe: 'Amanhã', estado: EstadoEtapa.atual),
              ],
              fotos: [],
            ),
            aoRemarcarVisita: () {},
          ),
        ),
      );
      expect(find.text('Remarcar visita'), findsOneWidget);
    });
  });

  group('5. Preferências de notificação e push nativo', () {
    test('tipoDaNotificacao reconhece pedido.direcionado e ServicoPushNativo lê canal', () async {
      expect(tipoDaNotificacao('pedido.direcionado'), TipoNotificacao.pedido);

      const canal = MethodChannel('br.com.feitolabs.trato/push_teste');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        canal,
        (call) async => call.method == 'obterTokenPush' ? 'token-fcm-valido-123' : null,
      );
      final push = ServicoPushNativo(canal: canal, plataformaAtual: () => 'android');
      final token = await push.obterToken();
      expect(token?.token, 'token-fcm-valido-123');
      expect(token?.plataforma, 'android');
    });

    testWidgets('PreferenciasNotificacoesTela altera e salva preferências', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      final repo = RepositorioNotificacoesFake();
      await t.pumpWidget(_app(PreferenciasNotificacoesTela(repositorio: repo)));
      await t.pumpAndSettle();

      expect(find.text('Orçamentos e convites'), findsOneWidget);
      await t.tap(find.byKey(const Key('switch-push-orcamentos')));
      await t.pump();

      await t.scrollUntilVisible(
        find.byKey(const Key('botao-salvar-preferencias')),
        200,
      );
      await t.tap(find.byKey(const Key('botao-salvar-preferencias')));
      await t.pumpAndSettle();

      expect(find.text('Preferências salvas.'), findsOneWidget);
      expect(repo.preferenciasSalvas.first.push, isFalse);
    });
  });

  group('6. Alteração de e-mail e senha logado', () {
    testWidgets('SegurancaContaTela atualiza e-mail e senha com sessão aberta', (t) async {
      t.view.physicalSize = const Size(420, 960);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      final auth = ServicoAuthFake();
      const chaveEntrada = 'Trato2026!'; // verificar: ignorar
      await auth.entrarComEmail(email: 'cli@exemplo.com', senha: chaveEntrada);

      await t.pumpWidget(_app(SegurancaContaTela(auth: auth)));

      await t.enterText(find.byKey(const Key('campo-novo-email')), 'novo@exemplo.com');
      await t.tap(find.byKey(const Key('botao-atualizar-email')));
      await t.pumpAndSettle();

      expect(auth.emailsAlterados, ['novo@exemplo.com']);
      expect(auth.sessaoAtual?.email, 'novo@exemplo.com');

      const novaChave = 'NovaTrato2027!'; // verificar: ignorar
      await t.enterText(find.byKey(const Key('campo-nova-senha')), novaChave);
      await t.enterText(find.byKey(const Key('campo-confirmar-senha')), novaChave);
      await t.ensureVisible(find.byKey(const Key('botao-atualizar-senha')));
      await t.tap(find.byKey(const Key('botao-atualizar-senha')));
      await t.pumpAndSettle();

      expect(auth.senhasDefinidas, [novaChave]);
      expect(find.text('Senha atualizada com sucesso.'), findsOneWidget);
    });
  });
}
