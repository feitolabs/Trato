import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_check_out_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

class _CheckInOfflineReenvio extends ServicoCheckInFake implements ReenvioOffline {
  bool online = false;
  int chamadasReenvio = 0;

  @override
  Future<ResultadoInicio> iniciarServico(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) async {
    return online ? ResultadoInicio.iniciado : ResultadoInicio.guardadoOffline;
  }

  @override
  Future<int> reenviarPendentes() async {
    chamadasReenvio++;
    return online ? 1 : 0;
  }
}

class _CheckOutOfflineReenvio extends ServicoCheckOutFake implements ReenvioOffline {
  bool online = false;
  int chamadasReenvio = 0;

  @override
  Future<ResultadoFim> finalizar(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) async {
    return online ? ResultadoFim.concluido : ResultadoFim.guardadoOffline;
  }

  @override
  Future<int> reenviarPendentes() async {
    chamadasReenvio++;
    return online ? 1 : 0;
  }
}

void main() {
  group('F31', () {
    testWidgets('1. Cupom recalcula via GET /pagamento, atualiza total e envia cupom na cobrança',
        (tester) async {
      final anteriores = RotasTrato.repos;
      addTearDown(() => RotasTrato.repos = anteriores);

      final chamadas = <String>[];
      Map<String, dynamic>? corpoCobranca;
      final sessao = SessaoTrato()..entrar('tok');
      final cliente = ClienteApi(
        urlBase: 'https://api.trato.teste',
        sessao: sessao,
        cliente: MockClient((req) async {
          chamadas.add('${req.method} ${req.url.path}?${req.url.query}');
          if (req.url.path == '/v1/me') {
            return http.Response(jsonEncode({'id': 'u1', 'cpf_cadastrado': true}), 200);
          }
          if (req.url.path == '/v1/pedidos/p1/pagamento') {
            final cupom = req.url.queryParameters['cupom'];
            if (cupom == 'INVALIDO') {
              return http.Response(jsonEncode({'detail': 'Cupom expirado.'}), 400);
            }
            if (cupom == 'TESTE5') {
              return http.Response(
                jsonEncode({
                  'valor_centavos': 13400,
                  'total_a_pagar_centavos': 12900,
                  'desconto_centavos': 500,
                  'desconto_cupom_centavos': 500,
                  'cupom_codigo': 'TESTE5',
                  'meios_disponiveis': ['cartao', 'pix'],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'valor_centavos': 13400,
                'total_a_pagar_centavos': 13400,
                'desconto_centavos': 0,
                'meios_disponiveis': ['cartao', 'pix'],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/contratos/p1/cobranca') {
            corpoCobranca = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'cobranca_id': 'cob1',
                'tipo_instrucao': 'pix_copia_e_cola',
                'instrucao': '000201...',
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      RotasTrato.repos = RepositoriosTrato.api(cliente);

      await _abrir(tester, RotasTrato.pagamentoParaTeste('p1'));
      expect(find.text('R\$ 134,00'), findsWidgets);

      // Erro no cupom não marca como aplicado
      await tester.enterText(find.byKey(const Key('campo-cupom')), 'INVALIDO');
      await tester.tap(find.byKey(const Key('botao-aplicar-cupom')));
      await tester.pumpAndSettle();
      expect(find.text('Cupom expirado.'), findsOneWidget);
      expect(find.byKey(const Key('botao-aplicar-cupom')), findsOneWidget);
      expect(find.byKey(const Key('botao-remover-cupom')), findsNothing);

      // Cupom válido recalcula via GET /pagamento e atualiza total e linha de desconto
      await tester.enterText(find.byKey(const Key('campo-cupom')), 'TESTE5');
      await tester.tap(find.byKey(const Key('botao-aplicar-cupom')));
      await tester.pumpAndSettle();

      expect(
          chamadas.any((c) => c.startsWith('GET /v1/pedidos/p1/pagamento?cupom=TESTE5')), isTrue);
      expect(find.text('R\$ 129,00'), findsWidgets);
      expect(find.textContaining('Cupom TESTE5 aplicado'), findsOneWidget);
      expect(find.byKey(const Key('botao-remover-cupom')), findsOneWidget);

      // Pagar com Pix envia o cupom na cobrança
      await tester.tap(find.text('Pix'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pagar R\$ 129,00'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(corpoCobranca?['cupom'], 'TESTE5');
    });

    testWidgets('2. Selo Urgente aparece na lista e nos detalhes do pedido do cliente',
        (tester) async {
      final apiPedido = PedidoApi.deJson({
        'id': 'ped-1',
        'estado': 'aberto',
        'estado_nome': 'Aberto',
        'cliente_id': 'c1',
        'profissional_id': null,
        'aberto_em': '2026-11-21T12:00:00Z',
        'concluido_em': null,
        'acoes_permitidas': <String>[],
        'codigo_inicio': null,
        'codigo_conclusao': null,
        'urgente': true,
      });
      expect(apiPedido.urgente, isTrue);

      await _abrir(
        tester,
        const SeusPedidosTela(
          emAndamento: [
            PedidoResumo(
              id: 'ped-1',
              titulo: 'Eletricista',
              subtitulo: 'Aberto em 21/11',
              statusTexto: 'Aguardando orçamentos',
              statusTipo: TipoStatus.info,
              urgente: true,
            ),
          ],
          finalizados: [],
        ),
      );
      expect(find.byKey(const ValueKey('selo-urgente')), findsOneWidget);
      expect(find.text('Urgente'), findsOneWidget);

      await _abrir(
        tester,
        PedidoAbertoTela(
          numero: 'PED1',
          dados: const DadosDoPedido(
            categoriaNome: 'Eletricista',
            titulo: 'Orçamento geral',
            descricao: 'Tomada em curto',
            urgente: true,
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
        ),
      );
      expect(find.byKey(const ValueKey('selo-urgente')), findsOneWidget);

      await _abrir(
        tester,
        const PedidoExecucaoTela(
          pedido: PedidoEmExecucao(
            numero: '#PED1',
            titulo: 'Em execução',
            categoriaNome: 'Eletricista',
            urgente: true,
            estadoApi: 'em_andamento',
            etapas: [],
            fotos: [],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('selo-urgente')), findsOneWidget);
    });

    testWidgets('3. Perfil exibe aviso quando exclusao_agendada_em está presente', (tester) async {
      await _abrir(
        tester,
        PerfilClienteTela(
          perfil: PerfilCliente(
            nome: 'João',
            iniciais: 'J',
            resumo: 'Nota 5,0',
            grupos: const [],
            exclusaoAgendadaEm: DateTime(2026, 11, 28),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('aviso-exclusao-agendada')), findsOneWidget);
      expect(find.textContaining('28/11'), findsOneWidget);
    });

    testWidgets('4. Check-in e check-out drenam fila offline automaticamente quando sinal volta',
        (tester) async {
      final checkIn = _CheckInOfflineReenvio();
      var iniciou = false;
      await _abrir(
        tester,
        CheckInTela(
          servico: checkIn,
          tituloBarra: 'Pedido #1',
          remoto: false,
          fotoInicial: const FotoChegada(hora: '10:00'),
          distanciaInicialMetros: 20,
          aoIniciar: () => iniciou = true,
        ),
      );
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pump();
      await tester.tap(find.text('Iniciar serviço'));
      await tester.pump();

      expect(find.textContaining('Sem internet. Guardamos'), findsOneWidget);
      expect(iniciou, isFalse);

      // Sinal volta e o timer de 6s drena sozinho sem tocar de novo
      checkIn.online = true;
      await tester.pump(const Duration(seconds: 7));
      expect(checkIn.chamadasReenvio, greaterThanOrEqualTo(1));
      expect(iniciou, isTrue);

      final checkOut = _CheckOutOfflineReenvio();
      var concluiu = false;
      await _abrir(
        tester,
        CheckOutTela(
          servico: checkOut,
          tituloBarra: 'Pedido #1',
          remoto: true,
          aoConcluir: () => concluiu = true,
        ),
      );
      await tester.enterText(find.byType(TextField).first, '4321');
      await tester.pump();
      await tester.tap(find.text('Concluir serviço'));
      await tester.pump();

      expect(find.textContaining('Sem internet. Guardamos'), findsOneWidget);
      expect(concluiu, isFalse);

      checkOut.online = true;
      await tester.pump(const Duration(seconds: 7));
      expect(checkOut.chamadasReenvio, greaterThanOrEqualTo(1));
      expect(concluiu, isTrue);
    });

    testWidgets('5. Compartilhar atendimento e SOS / Emergência no presencial em execução',
        (tester) async {
      await _abrir(
        tester,
        const PedidoExecucaoTela(
          pedido: PedidoEmExecucao(
            numero: '#1234',
            titulo: 'Em execução',
            remoto: false,
            estadoApi: 'em_andamento',
            profissionalNome: 'Carlos M.',
            visita: '21/11 · 14:00',
            enderecoResumo: 'Rua das Flores, 10',
            etapas: [],
            fotos: [],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('botao-compartilhar-atendimento')), findsOneWidget);
      expect(find.byKey(const ValueKey('botao-sos-emergencia')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('botao-sos-emergencia')));
      await tester.pumpAndSettle();
      expect(find.text('SOS / Emergência'), findsWidgets);
      expect(find.textContaining('190'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      // Remoto: sem compartilhar, com SOS
      await _abrir(
        tester,
        const PedidoExecucaoTela(
          pedido: PedidoEmExecucao(
            numero: '#1234',
            titulo: 'Em execução',
            remoto: true,
            estadoApi: 'em_andamento',
            etapas: [],
            fotos: [],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('botao-compartilhar-atendimento')), findsNothing);
      // Termos 9.2: a emergência vale também no serviço remoto.
      expect(find.byKey(const ValueKey('botao-sos-emergencia')), findsOneWidget);
    });

    testWidgets('6. EventoApi converte para horário local e ConclusaoTela remota oculta fotos',
        (tester) async {
      final evento = EventoApi.deJson({
        'acao': 'fazer_check_in',
        'para': 'em_andamento',
        'em': '2026-11-21T15:00:00Z',
      });
      expect(evento.em.isUtc, isFalse);

      await _abrir(
        tester,
        const ConclusaoTela(
          resumo: ResumoConclusao(
            remoto: true,
            numeroPedido: '#9999',
            nomeProfissional: 'Ana',
            legendaFotoAntes: 'Antes',
            legendaFotoDepois: 'Depois',
            orcamentoCentavos: 10000,
            aditivoCentavos: 0,
            codigo: '1234',
            avisoLiberacao: 'Liberado após confirmação.',
          ),
        ),
      );
      expect(find.text('Confira o resultado antes de confirmar.'), findsOneWidget);
      expect(find.textContaining('Confira as fotos'), findsNothing);
      expect(find.text('Antes'), findsNothing);
      expect(find.text('Depois'), findsNothing);
    });
  });
}
