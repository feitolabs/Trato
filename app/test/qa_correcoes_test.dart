import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo.dart' show FiltroProfissionais;
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/cliente/modelos.dart' show CategoriaServico;
import 'package:trato/telas/comuns/sucesso_acao_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/filtros_pedidos_tela.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/endereco_pedido.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/profissional_cadastro/cadastro_fake.dart';
import 'apoio/fontes.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

http.Response _jsonResp(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _AuthComSessao extends ServicoAuthFake {
  _AuthComSessao(SessaoAuth sessao) : _sessao = sessao;
  final SessaoAuth _sessao;

  @override
  SessaoAuth? get sessaoAtual => _sessao;
}

void main() {
  setUpAll(carregarFontesTrato);

  group('SucessoAcaoTela após pushReplacement', () {
    tearDown(() => RotasTrato.repos = repositoriosDemo());

    testWidgets('Ver pedidos no fluxo de Novo Pedido vai para a aba Pedidos',
        (tester) async {
      ligarDemoNosTestes();
      // Enviar pedido exige sessão (sem ela o app pede para criar conta; ver F6).
      final auth = ServicoAuthFake();
      await auth.entrarComEmail(email: 'ana@teste.com', senha: 'senha-forte-1');
      ServicoAuthPadrao.atual = auth;
      await _abrir(tester, const CascaClienteTela(abaInicial: 0));

      await tester.tap(find.text('Pedir orçamento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elétrica'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).first, 'Trocar tomada da sala');
      await preencherEnderecoDoPedido(tester);
      final enviar = find.text('Enviar pedido');
      await tester.ensureVisible(enviar.last);
      await tester.tap(enviar.last);
      await tester.pumpAndSettle();

      expect(find.text('Pedido enviado!'), findsOneWidget);
      await tester.tap(find.text('Ver pedidos'));
      await tester.pumpAndSettle();

      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(find.byType(SeusPedidosTela), findsOneWidget);
      expect(find.byType(SucessoAcaoTela), findsNothing);
    });

    testWidgets('Voltar ao perfil após editar cadastro profissional retorna ao perfil',
        (tester) async {
      ligarDemoNosTestes();
      await _abrir(tester, RotasTrato.cascaProfissionalParaTeste(abaInicial: 4));

      await tester.tap(find.text('Editar cadastro'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dados básicos'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Carlos Almeida');
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Categorias'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eletricista').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Área e horários'));
      await tester.pumpAndSettle();
      for (final texto in ['Belo Horizonte', 'Seg', 'Manhã']) {
        final finder = find.text(texto).last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      final salvar = find.text('Salvar alterações');
      await tester.ensureVisible(salvar);
      await tester.tap(salvar);
      await tester.pumpAndSettle();

      expect(find.text('Cadastro atualizado!'), findsOneWidget);
      await tester.tap(find.text('Voltar ao perfil'));
      await tester.pumpAndSettle();

      expect(find.byType(PerfilPublicoTela), findsOneWidget);
      expect(find.byType(SucessoAcaoTela), findsNothing);
    });
  });

  group('Home do profissional, filtros e trava de categorias', () {
    testWidgets('InicioProfissionalTela oculta botão de troca de perfil e mostra aviso em_analise',
        (tester) async {
      const dados = InicioProfissional(
        nome: 'Gabriel',
        disponivelAgora: true,
        emAnalise: true,
        carteira: ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0),
        pedidos: [],
        proximo: ProximoAtendimento(
          quando: 'Data da visita ainda não marcada',
          titulo: 'Instalar chuveiro',
          endereco: 'Rua A, 10',
          estadoApi: 'pago_e_retido',
        ),
      );
      await _abrir(
        tester,
        InicioProfissionalTela(
          dados: dados,
          aoUsarComoCliente: () {},
          aoFazerCheckIn: () {},
        ),
      );

      expect(find.bySemanticsLabel('Trocar para modo cliente'), findsNothing);
      expect(find.textContaining('Seu cadastro está em análise'), findsOneWidget);
      expect(find.text('Marcar data da visita'), findsOneWidget);
    });

    testWidgets('FiltrosPedidosAbertosTela esconde categoria quando há <= 1 categoria',
        (tester) async {
      await _abrir(
        tester,
        const FiltrosPedidosAbertosTela(
          categorias: [CategoriaServico('Eletricista', Icons.bolt, id: 'c1')],
        ),
      );
      expect(find.text('Categoria'), findsNothing);
      expect(find.text('Todas'), findsNothing);

      await _abrir(
        tester,
        const FiltrosPedidosAbertosTela(
          categorias: [
            CategoriaServico('Eletricista', Icons.bolt, id: 'c1'),
            CategoriaServico('Encanador', Icons.water_drop_outlined, id: 'c2'),
          ],
        ),
      );
      expect(find.text('Categoria'), findsOneWidget);
      expect(find.text('Todas'), findsOneWidget);
    });

    testWidgets('CadastroProfissionalTela trava categorias vinculadas à verificação na edição',
        (tester) async {
      final servico = ServicoCadastroProfissionalFake(
        atual: const DadosCadastroProfissional(
          nome: 'Carlos',
          sobre: 'Instalações residenciais',
          categorias: {'Eletricista'},
          cidade: 'Belo Horizonte',
          raioKm: 10,
          dias: {'Seg'},
          periodos: {'Manhã'},
          portfolio: [],
          categoriasTravadas: true,
        ),
      );
      await _abrir(
        tester,
        CadastroProfissionalTela(edicao: true, servico: servico),
      );

      await tester.tap(find.text('Categorias'));
      await tester.pumpAndSettle();

      expect(find.text('Eletricista'), findsOneWidget);
      expect(find.text('Encanador'), findsNothing);
      expect(
        find.textContaining('Categorias vinculadas à sua verificação'),
        findsOneWidget,
      );
      // Tocar na categoria travada não a desmarca.
      await tester.tap(find.text('Eletricista'));
      await tester.pumpAndSettle();
      expect(find.text('Eletricista'), findsOneWidget);
    });
  });

  group('Acompanhamento de notas e aditivos + isolamento + retry 429', () {
    testWidgets('PedidoExecucaoTela exibe resumo atualizado com aditivos e notas',
        (tester) async {
      final pedido = PedidoEmExecucao(
        numero: '#AB12',
        titulo: 'Serviço em execução',
        etapas: const [
          EtapaLinhaDoTempo(
            titulo: 'Em execução',
            detalhe: 'Hoje',
            estado: EstadoEtapa.atual,
          ),
        ],
        fotos: const [],
        orcamentoCentavos: 20000,
        totalAtualizadoCentavos: 24500,
        totalNotasCentavos: 5000,
        aditivos: const [
          ItemResumoAditivo(
            id: 'ad-1',
            descricao: 'Disjuntor bipolar 40A',
            valorCentavos: 4500,
            estadoTexto: 'Aprovado',
            estado: 'aprovado',
          ),
        ],
        notas: [
          ItemResumoNota(
            numero: 1,
            totalCentavos: 3500,
            itensResumo: 'Cabo 4mm, disjuntor',
            enviadaEm: DateTime(2026, 11, 17, 10),
          ),
          ItemResumoNota(
            numero: 2,
            totalCentavos: 1500,
            itensResumo: 'Fita isolante',
            enviadaEm: DateTime(2026, 11, 17, 11),
          ),
        ],
      );

      await _abrir(tester, PedidoExecucaoTela(pedido: pedido));

      expect(find.text('Valores, aditivos e notas'), findsOneWidget);
      expect(find.text('R\$ 200,00'), findsOneWidget);
      expect(find.text('R\$ 245,00'), findsOneWidget);
      expect(find.text('Disjuntor bipolar 40A'), findsOneWidget);
      expect(find.text('Aprovado'), findsOneWidget);
      expect(find.text('Nota 1'), findsOneWidget);
      expect(find.text('R\$ 35,00'), findsOneWidget);
      expect(find.text('Nota 2'), findsOneWidget);
      expect(find.text('R\$ 15,00'), findsOneWidget);
      expect(find.text('Total em materiais'), findsOneWidget);
      expect(find.text('R\$ 50,00'), findsOneWidget);
    });

    test('isolamento na API do app e retry automático no 429', () async {
      final anterior = ServicoAuthPadrao.atual;
      addTearDown(() => ServicoAuthPadrao.atual = anterior);
      ServicoAuthPadrao.atual = _AuthComSessao(
        const SessaoAuth(id: 'u-eu', email: 'eu@exemplo.com', perfil: 'profissional'),
      );

      var tentativas = 0;
      final sessao = SessaoTrato()..entrar('tk');
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: sessao,
        intervaloBaseRetry: Duration.zero,
        cliente: MockClient((req) async {
          tentativas++;
          if (req.url.path == '/v1/ping') {
            return tentativas == 1
                ? _jsonResp({'detail': 'Muitas tentativas.'}, 429)
                : _jsonResp({'ok': true});
          }
          if (req.url.path == '/v1/catalogo/categorias') {
            return _jsonResp([]);
          }
          if (req.url.path == '/v1/profissionais') {
            return _jsonResp({
              'itens': [
                {'id': 'u-eu', 'nome': 'Eu M.', 'categorias': []},
                {'id': 'u-outro', 'nome': 'Outro P.', 'categorias': []},
              ],
            });
          }
          if (req.url.path == '/v1/profissional/pedidos-abertos') {
            return _jsonResp([
              {
                'id': 'ped-meu',
                'titulo': 'Meu proprio pedido',
                'cliente_id': 'u-eu',
              },
              {
                'id': 'ped-terceiro',
                'titulo': 'Pedido de cliente',
                'cliente_id': 'u-cliente',
              },
            ]);
          }
          return _jsonResp({});
        }),
      );

      final ping = await api.get('/v1/ping') as Map;
      expect(ping['ok'], isTrue);
      expect(tentativas, 2);

      final pros = await RepositorioCatalogoApi(api)
          .profissionais('cat-1', const FiltroProfissionais());
      expect(pros.map((p) => p.id), ['u-outro']);

      final abertos = await RepositorioProfissionalApi(api)
          .pedidosAbertos(const FiltroPedidosAbertos());
      expect(abertos.map((p) => p.id), ['ped-terceiro']);
    });
  });
}
