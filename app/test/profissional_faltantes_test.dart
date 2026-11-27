import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/imagem_trato.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/conta_recebimento_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/detalhe_orcamento_enviado_tela.dart';
import 'package:trato/telas/profissional_inicio/casca_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/exemplos/telas/profissional_inicio/dados_exemplo.dart';
import 'apoio/fontes.dart';
import 'apoio/orcamento.dart';

final _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

ClienteApi _apiFake(
  Future<http.Response> Function(http.Request req) handler, {
  List<(String metodo, String caminho, Object? corpo, Map<String, String> consulta)>? log,
}) {
  final sessao = SessaoTrato()..entrar('tok-prof');
  return ClienteApi(
    urlBase: 'https://api.trato.teste',
    sessao: sessao,
    intervaloBaseRetry: Duration.zero,
    cliente: MockClient((req) async {
      Object? corpo;
      if (req.body.isNotEmpty) {
        corpo = jsonDecode(req.body);
      }
      log?.add((req.method, req.url.path, corpo, req.url.queryParameters));
      return handler(req);
    }),
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _CapturaComProva implements CapturaCheckIn {
  @override
  Future<FotoCapturada?> foto() async => FotoCapturada(
        arquivoId: 'midia-local-1',
        tiradaEm: DateTime.utc(2026, 10, 29, 14, 0),
      );

  @override
  Future<PosicaoCapturada?> posicao() async =>
      const PosicaoCapturada(-19.919, -43.938, distanciaMetros: 20);
}

class _ServicoCheckInAusenteErro extends ServicoCheckInFake {
  @override
  Future<void> avisarClienteAusente() async {
    throw const ErroTrato(
      TipoErro.recusado,
      'O registro de cliente ausente precisa de foto do local e localização.',
    );
  }
}

Future<void> _bombearTela(WidgetTester tester, Widget widget,
    {Size tamanho = const Size(390, 900)}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: widget));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);
  tearDown(() {
    RotasTrato.repos = repositoriosDemo();
    RotasTrato.salvarPdfParaTeste = null;
  });

  group('1. Conta de recebimento / Pix (API + UI)', () {
    test('obter e salvar conta de recebimento via API', () async {
      final log = <(String, String, Object?, Map<String, String>)>[];
      final api = _apiFake((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/profissional/conta-recebimento') {
          return _json({'cadastrada': false});
        }
        if (req.method == 'PUT' && req.url.path == '/v1/profissional/conta-recebimento') {
          return _json({
            'cadastrada': true,
            'tipo_pix': 'cpf',
            'chave_pix': '52998224725',
            'chave_pix_mascarada': '***.982.247-**',
            'banco_nome': 'Itaú',
            'resumo_exibicao': 'Pix (CPF): ***.982.247-** · Itaú',
          });
        }
        return _json({'detail': 'não encontrado'}, 404);
      }, log: log);

      final repo = RepositorioProfissionalApi(api);
      final vazia = await repo.obterContaRecebimento();
      expect(vazia.cadastrada, isFalse);

      final salva = await repo.salvarContaRecebimento(
        tipoPix: 'cpf',
        chavePix: '529.982.247-25',
        bancoNome: 'Itaú',
        bancoCodigo: '341',
        agencia: '1234',
        conta: '56789-0',
        tipoConta: 'corrente',
      );
      expect(salva.cadastrada, isTrue);
      expect(salva.chavePixMascarada, '***.982.247-**');
      expect(log.last.$3, {
        'tipo_pix': 'cpf',
        'chave_pix': '529.982.247-25',
        'banco_codigo': '341',
        'banco_nome': 'Itaú',
        'agencia': '1234',
        'conta': '56789-0',
        'tipo_conta': 'corrente',
      });
    });

    testWidgets('Carteira exibe atalho e ContaRecebimentoTela valida e salva', (tester) async {
      var abriuConfig = false;
      final extratoExemplo = await RepositorioProfissionalFake().extrato();
      await _bombearTela(
        tester,
        CarteiraTela(
          soExtrato: false,
          dados: DadosCarteira(
            resumo: resumoCarteiraDoSaldo(
              liberadoCentavos: 0,
              retidoCentavos: 0,
              aLiberarCentavos: 0,
            ),
            extrato: extratoExemplo,
          ),
          aoConfigurarRecebimento: () => abriuConfig = true,
        ),
      );
      expect(find.text('Cadastre sua conta Pix'), findsNothing);
      await tester.tap(find.text('Cadastrar conta de recebimento'));
      await tester.pumpAndSettle();
      expect(abriuConfig, isTrue);

      ContaRecebimento? salva;
      await _bombearTela(
        tester,
        Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                salva = await Navigator.of(ctx).push<ContaRecebimento>(
                  MaterialPageRoute(
                    builder: (_) => ContaRecebimentoTela(
                      inicial: const ContaRecebimento(cadastrada: false),
                      aoSalvar: ({
                        required tipoPix,
                        required chavePix,
                        bancoCodigo,
                        bancoNome,
                        agencia,
                        conta,
                        tipoConta,
                      }) async =>
                          ContaRecebimento(
                        cadastrada: true,
                        tipoPix: tipoPix,
                        chavePix: chavePix,
                        chavePixMascarada: chavePix,
                        resumoExibicao: 'Pix ($tipoPix): $chavePix',
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '52998224725');
      await tester.tap(find.text('Salvar conta de recebimento'));
      await tester.pumpAndSettle();
      expect(salva?.cadastrada, isTrue);
      expect(salva?.chavePix, '52998224725');
    });
  });

  group('2. Fotos do cliente no Detalhe do Pedido Aberto', () {
    test('detalhe carrega fotos_urls da API para legendasFotos', () async {
      final api = _apiFake((req) async {
        if (req.url.path == '/v1/profissional/pedidos-abertos/ped-1') {
          return _json({
            'id': 'ped-1',
            'titulo': 'Instalar tomada',
            'descricao': 'Tomada queimada na cozinha',
            'bairro': 'Centro',
            'aberto_em': '2026-10-29T10:00:00Z',
            'fotos_urls': [
              'https://cdn.trato.teste/foto1.png',
              'https://cdn.trato.teste/foto2.png',
            ],
            'respostas': <Object>[],
          });
        }
        return _json({'detail': 'não encontrado'}, 404);
      });
      final det = await RepositorioProfissionalApi(api).detalhe('ped-1');
      expect(det.legendasFotos, hasLength(2));
      expect(det.legendasFotos.first, contains('foto1.png'));
    });

    testWidgets('DetalhePedidoTela renderiza URLs reais com rótulo Foto 1..4 em múltiplas linhas',
        (tester) async {
      final urls = [
        for (var i = 1; i <= 4; i++) 'https://cdn.trato.teste/pedido-foto-$i.png',
      ];
      for (final u in urls) {
        registrarImagemEmMemoria(u, bytes: _png1x1);
      }
      await _bombearTela(
        tester,
        DetalhePedidoTela(
          dados: DetalhePedido(
            pedido: pedidoTomadasExemplo,
            fechaEm: 'Publicado há 1 h',
            clienteResumo: 'Para até 30/10',
            legendasFotos: urls,
            descricao: 'Veja as fotos da instalação.',
            linhas: const [LinhaDetalhe('Modalidade', 'Presencial')],
          ),
        ),
      );
      expect(find.text('Foto 1'), findsOneWidget);
      expect(find.text('Foto 4'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(4));
    });
  });

  group('3. Ver e editar próprio orçamento enviado antes do aceite', () {
    test('meuOrcamento e ServicoOrcamentoApi.enviar incluem fora_do_escopo e observacoes',
        () async {
      final log = <(String, String, Object?, Map<String, String>)>[];
      final api = _apiFake((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/orcamentos/orc-1') {
          return _json({
            'id': 'orc-1',
            'pedido_id': 'ped-1',
            'profissional_id': 'pro-1',
            'versao': 1,
            'status': 'enviado',
            'valor_centavos': 60000,
            'prazo_execucao_dias': 2,
            'garantia_dias': 90,
            'fora_do_escopo': 'Massa corrida',
            'observacoes': 'Horário comercial',
            'horas_deslocamento': '1',
            'horas_trabalhadas': '3',
            'aceito': false,
            'itens': [
              {
                'tipo': 'deslocamento',
                'descricao': 'Deslocamento',
                'quantidade': '1',
                'valor_unitario_centavos': 10000,
                'total_centavos': 10000,
              },
              {
                'tipo': 'horas',
                'descricao': 'Mão de obra',
                'quantidade': '3',
                'valor_unitario_centavos': 10000,
                'total_centavos': 30000,
              },
              {
                'tipo': 'material',
                'descricao': 'Cabo 2.5mm',
                'quantidade': '1',
                'valor_unitario_centavos': 20000,
                'total_centavos': 20000,
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path == '/v1/pedidos/ped-1/orcamentos') {
          return _json({'id': 'orc-2', 'versao': 2}, 201);
        }
        return _json({'detail': 'não'}, 404);
      }, log: log);

      final det = await RepositorioProfissionalApi(api).meuOrcamento('orc-1');
      expect(det.valorCentavos, 60000);
      expect(det.foraDoEscopo, 'Massa corrida');
      expect(det.decimosDeslocamento, 10);
      expect(det.decimosTrabalhadas, 30);
      expect(det.valorHoraCentavos, 10000);
      expect(det.materiais.single.nome, 'Cabo 2.5mm');

      await ServicoOrcamentoApi(api, pedidoId: 'ped-1').enviar(
        const OrcamentoPronto(
          decimosDeslocamento: 10,
          decimosDeHora: 40,
          valorHoraCentavos: 12000,
          garantiaDias: 90,
          validadeDias: 3,
          prazoExecucaoDias: 3,
          itens: [],
          materialPorMim: true,
          pedirSinalMaterial: false,
          totalCentavos: 60000,
          foraDoEscopo: 'Alvenaria',
          observacoes: 'Levar escada',
        ),
      );
      final enviado = log.last.$3! as Map<String, dynamic>;
      expect(enviado['fora_do_escopo'], 'Alvenaria');
      expect(enviado['observacoes'], 'Levar escada');
    });

    testWidgets('DetalheOrcamentoEnviadoTela abre edição pré-preenchida e envia nova versão',
        (tester) async {
      final det = await RepositorioProfissionalFake().meuOrcamento('orc-1');
      OrcamentoPronto? reenviado;

      await _bombearTela(
        tester,
        Builder(
          builder: (ctx) => DetalheOrcamentoEnviadoTela(
            detalhe: det,
            aoAbrirChat: () {},
            aoEditar: () {
              Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => CalculadoraOrcamentoTela(
                    servico: ServicoOrcamentoFake(),
                    tituloPedido: det.tituloPedido,
                    edicao: true,
                    deslocamentoInicial: '1',
                    horasInicial: '2,5',
                    valorHoraInicial: '100',
                    garantiaInicialDias: det.garantiaDias ?? 90,
                    prazoExecucaoInicialDias: det.prazoExecucaoDias ?? 2,
                    foraDoEscopoInicial: det.foraDoEscopo,
                    observacoesInicial: det.observacoes,
                    aoEnviar: (p) => reenviado = p,
                  ),
                ),
              );
            },
          ),
        ),
        tamanho: const Size(390, 1200),
      );

      expect(find.text('Aguardando cliente'), findsOneWidget);
      expect(find.text('Fornecimento de disjuntor geral'), findsOneWidget);
      await tester.tap(find.text('Editar orçamento'));
      await tester.pumpAndSettle();

      expect(find.text('Editar orçamento'), findsOneWidget);
      expect(find.text('Enviar nova versão'), findsOneWidget);
      expect(find.text('Fornecimento de disjuntor geral'), findsOneWidget);

      await completarOrcamento(tester, naoIncluido: null);
      await tester.tap(find.text('Enviar nova versão'));
      await tester.pumpAndSettle();
      expect(reenviado, isNotNull);
      expect(reenviado!.foraDoEscopo, 'Fornecimento de disjuntor geral');
      expect(reenviado!.decimosDeHora, 25);
    });
  });

  group('4. Baixar extrato em PDF no App', () {
    test('baixarExtratoPdf chama endpoint PDF com query mes', () async {
      final log = <(String, String, Object?, Map<String, String>)>[];
      final api = _apiFake((req) async {
        expect(req.headers['Accept'], 'application/pdf, */*');
        return http.Response.bytes(
          utf8.encode('%PDF-1.4\n%%EOF'),
          200,
          headers: const {'content-type': 'application/pdf'},
        );
      }, log: log);

      final bytes = await RepositorioProfissionalApi(api).baixarExtratoPdf(mes: '2026-10');
      expect(utf8.decode(bytes), startsWith('%PDF-1.4'));
      expect(log.single.$2, '/v1/profissionais/me/extrato.pdf');
      expect(log.single.$4, {'mes': '2026-10'});
    });

    testWidgets('Carteira na CascaProfissional baixa PDF mensal via RotasTrato', (tester) async {
      RotasTrato.repos = repositoriosDemo();
      String? arquivoSalvo;
      List<int>? bytesSalvos;
      RotasTrato.salvarPdfParaTeste = (bytes, arquivo) async {
        bytesSalvos = bytes;
        arquivoSalvo = arquivo;
        return '/tmp/$arquivo';
      };

      await _bombearTela(
        tester,
        RotasTrato.cascaProfissionalParaTeste(abaInicial: 3),
      );

      expect(find.text('PDF mensal'), findsOneWidget);
      await tester.tap(find.text('PDF mensal'));
      await tester.pumpAndSettle();

      expect(find.text('Extrato mensal em PDF'), findsOneWidget);
      await tester.tap(find.text('Baixar PDF'));
      await tester.pumpAndSettle();

      expect(arquivoSalvo, matches(RegExp(r'^trato_extrato_\d{4}_\d{2}\.pdf$')));
      expect(utf8.decode(bytesSalvos!), startsWith('%PDF-1.4'));
      expect(find.textContaining('Extrato em PDF salvo.'), findsOneWidget);
    });
  });

  group('5. Switch "Disponível agora"', () {
    test('inicio() lê disponivel_agora de /v1/me e alterarDisponivelAgora envia PATCH', () async {
      final log = <(String, String, Object?, Map<String, String>)>[];
      final api = _apiFake((req) async {
        if (req.method == 'GET' && req.url.path == '/v1/me') {
          return _json({'id': 'p1', 'nome': 'Carlos', 'disponivel_agora': false});
        }
        if (req.method == 'PATCH' && req.url.path == '/v1/profissional/perfil') {
          return _json({'disponivel_agora': true});
        }
        return _json(<Object>[]);
      }, log: log);

      final repo = RepositorioProfissionalApi(api);
      final inicio = await repo.inicio();
      expect(inicio.disponivelAgora, isFalse);

      final novo = await repo.alterarDisponivelAgora(true);
      expect(novo, isTrue);
      expect(log.last.$1, 'PATCH');
      expect(log.last.$2, '/v1/profissional/perfil');
      expect(log.last.$3, {'disponivel_agora': true});
    });

    testWidgets('CascaProfissionalTela liga o switch Disponível agora e recarrega início',
        (tester) async {
      var alteradoPara = <bool>[];
      var inicioAtual = inicioProfissionalExemplo.comDisponivel(false);
      await _bombearTela(
        tester,
        CascaProfissionalTela(
          inicio: inicioAtual,
          detalhe: detalhePedidoExemplo,
          aoAlterarDisponivel: (v) async {
            alteradoPara.add(v);
            inicioAtual = inicioAtual.comDisponivel(v);
            return v;
          },
          recarregarInicio: () async => inicioAtual,
        ),
      );

      expect(find.text('Disponível agora'), findsOneWidget);
      final swAntes = tester.widget<Switch>(find.byType(Switch));
      expect(swAntes.value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(alteradoPara, [true]);
      final swDepois = tester.widget<Switch>(find.byType(Switch));
      expect(swDepois.value, isTrue);
    });
  });

  group('6. Fluxo formal "Cliente Ausente" no Check-in', () {
    test('ServicoCheckInApi envia registrar_cliente_ausente com foto e localização', () async {
      final log = <(String, String, Object?, Map<String, String>)>[];
      final api = _apiFake((req) async => _json({'estado': 'agendado'}), log: log);

      final servico = ServicoCheckInApi(
        api,
        pedidoId: 'ped-1',
        captura: _CapturaComProva(),
      );

      await expectLater(servico.avisarClienteAusente, throwsA(isA<ErroTrato>()));
      await servico.tirarFoto();
      await servico.localizar();
      await servico.avisarClienteAusente();

      expect(log.single.$1, 'POST');
      expect(log.single.$2, '/v1/pedidos/ped-1/acoes/registrar_cliente_ausente');
      final prova = (log.single.$3 as Map<String, dynamic>)['prova'] as Map<String, dynamic>;
      expect((prova['foto'] as Map<String, dynamic>)['arquivo_id'], 'midia-local-1');
      expect((prova['localizacao'] as Map<String, dynamic>)['latitude'], -19.919);
    });

    testWidgets('CheckInTela exibe erro quando falta prova e confirma após registro válido',
        (tester) async {
      await _bombearTela(
        tester,
        CheckInTela(
          servico: _ServicoCheckInAusenteErro(),
          tituloBarra: 'Mariana · hoje, 14h',
        ),
      );
      await tester.tap(find.text('Cliente não está no local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar ausência'));
      await tester.pumpAndSettle();
      expect(
        find.text('O registro de cliente ausente precisa de foto do local e localização.'),
        findsOneWidget,
      );

      final fake = ServicoCheckInFake();
      await _bombearTela(
        tester,
        CheckInTela(
          servico: fake,
          tituloBarra: 'Mariana · hoje, 14h',
        ),
      );
      await tester.ensureVisible(find.text('Cliente não está no local'));
      await tester.tap(find.text('Cliente não está no local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(fake.clienteAusenteAvisado, isFalse);

      await tester.ensureVisible(find.text('Cliente não está no local'));
      await tester.tap(find.text('Cliente não está no local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar ausência'));
      await tester.pumpAndSettle();
      expect(fake.clienteAusenteAvisado, isTrue);
      expect(
        find.text('Ocorrência de cliente ausente registrada com comprovação e aviso ao cliente.'),
        findsOneWidget,
      );
    });
  });
}
