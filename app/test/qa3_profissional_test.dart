// QA3-B: Testes adversariais das telas do Profissional (em memoria; sem tocar producao).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/telas/aditivo/aditivo.dart';
import 'package:trato/telas/aditivo/criar_aditivo_tela.dart';
import 'package:trato/telas/agenda/agenda_tela.dart';
import 'package:trato/telas/agenda/modelos.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/modelos.dart';
import 'package:trato/telas/carteira/avaliar_cliente_tela.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/conta_recebimento_tela.dart';
import 'package:trato/telas/carteira/modelos.dart' as mc;
import 'package:trato/telas/configuracoes/configuracoes_tela.dart';
import 'package:trato/telas/disputa_profissional/disputa.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart' as mp;
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/dinheiro.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_orcamento.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/verificacao/verificacao.dart';
import 'package:trato/telas/verificacao/verificacao_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/aditivo/aditivo_fake.dart';
import 'apoio/exemplos/telas/disputa_profissional/disputa_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/exemplos/telas/profissional_cadastro/cadastro_fake.dart';
import 'apoio/exemplos/telas/profissional_inicio/dados_exemplo.dart';
import 'apoio/exemplos/telas/verificacao/verificacao_fake.dart';

const _textoGigante =
    'Texto gigante de teste adversarial sem quebra para estressar layout e validacao '
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const _emojiRtl = '🔧🔥 \u202Etxet LTR\u202C مطرقه';
const _htmlSql = '<script>alert(1)</script> \'; DROP TABLE pedidos; --';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 844),
  double fonte = 1.0,
  bool assentar = true,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fonte)),
        child: EscalaFonteLimitada(child: filho!),
      ),
      home: KeyedSubtree(key: UniqueKey(), child: tela),
    ),
  );
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _OrcamentoFalhaResumo extends ServicoOrcamentoFake {
  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async =>
      throw const ErroTrato(TipoErro.semInternet, 'Sem internet');
}

class _CheckInTimeout extends ServicoCheckInFake {
  @override
  Future<FotoChegada?> tirarFoto() async => throw TimeoutException('camera timeout');

  @override
  Future<int?> localizar() async => throw TimeoutException('gps timeout');

  @override
  Future<void> avisarClienteAusente() async => throw TimeoutException('rede timeout');

  @override
  Future<ResultadoInicio> iniciarServico(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) async =>
      throw TimeoutException('iniciar timeout');
}

class _CheckInLento extends ServicoCheckInFake {
  int chamadas = 0;
  final completer = Completer<ResultadoInicio>();

  @override
  Future<ResultadoInicio> iniciarServico(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) {
    chamadas++;
    return completer.future;
  }
}

class _CadastroLento extends ServicoCadastroProfissionalFake {
  int envios = 0;
  final completer = Completer<void>();

  @override
  Future<void> salvar(DadosCadastroProfissional dados) {
    envios++;
    return completer.future;
  }
}

class _CadastroErro extends ServicoCadastroProfissionalFake {
  @override
  Future<OpcoesCadastro> carregarOpcoes() async =>
      throw const ErroTrato(TipoErro.semInternet, 'Sem conexão');
}

class _VerificacaoErro extends ServicoVerificacaoFake {
  @override
  Future<SituacaoVerificacao> carregarSituacao() async =>
      throw const ErroTrato(TipoErro.sessaoExpirada, 'Sessão expirada');
}

class _AditivoLento extends ServicoAditivoFake {
  int envios = 0;
  final completer = Completer<void>();

  @override
  Future<void> criar(NovoAditivo aditivo) {
    envios++;
    return completer.future;
  }
}

class _DisputaLenta extends ServicoDisputaProfissionalFake {
  _DisputaLenta()
      : super(
          disputa: const DetalheDisputa(
            id: 'disp-1',
            titulo: 'Vazamento na pia',
            cliente: 'Mariana',
            motivo: 'Vazamento',
            descricao: 'Segue pingando',
            solucaoPedida: 'Retrabalho',
            prazoRespostaHoras: 48,
            valorCongeladoCentavos: 25000,
          ),
        );

  int envios = 0;
  final completer = Completer<void>();

  @override
  Future<void> responder(RespostaDisputa resposta) {
    envios++;
    return completer.future;
  }
}

class _MensagensErro implements ServicoMensagens {
  @override
  Future<List<ConversaResumo>> listar() async =>
      throw const ErroTrato(TipoErro.semInternet, 'Sem internet');
}

class _Mensagens500 implements ServicoMensagens {
  @override
  Future<List<ConversaResumo>> listar() async => [
        for (var i = 0; i < 500; i++)
          ConversaResumo(
            pedidoId: 'ped-$i',
            tituloPedido: 'Serviço $i $_emojiRtl',
            interlocutor: 'Cliente $i',
            iniciais: 'C',
            ultimaMensagem: _htmlSql,
            quando: '10h',
            naoLidas: i % 3,
          ),
      ];
}

class _NotificacoesErro implements ServicoNotificacoes {
  @override
  Future<List<Notificacao>> listar() async => throw TimeoutException('timeout');

  @override
  Future<void> marcarLida(String id) async {}

  @override
  Future<void> marcarTodasLidas() async {}
}

class _Notificacoes500 implements ServicoNotificacoes {
  @override
  Future<List<Notificacao>> listar() async => [
        for (var i = 0; i < 500; i++)
          Notificacao(
            id: 'n-$i',
            tipo: TipoNotificacao.pedido,
            titulo: 'Aviso $i',
            texto: _textoGigante,
            quando: 'agora',
          ),
      ];

  @override
  Future<void> marcarLida(String id) async {}

  @override
  Future<void> marcarTodasLidas() async {}
}

class _Ajuda500 implements ServicoAjuda {
  @override
  Future<List<PerguntaFrequente>> perguntas() async => [
        for (var i = 0; i < 500; i++)
          PerguntaFrequente(pergunta: 'Pergunta $i $_htmlSql', resposta: 'Resposta $i $_emojiRtl'),
      ];
}

void main() {
  group('Dinheiro.lerCentavos / lerDecimosDeHora', () {
    test('0, negativo, enorme, NaN e lixo', () {
      expect(Dinheiro.lerCentavos('0'), 0);
      expect(Dinheiro.lerCentavos('-10'), isNull);
      expect(Dinheiro.lerCentavos('NaN'), isNull);
      expect(Dinheiro.lerCentavos('99999999999999999999'), isNull);
      expect(Dinheiro.lerCentavos('   '), isNull);
      expect(Dinheiro.lerCentavos(''), isNull);
      expect(Dinheiro.lerDecimosDeHora('-1'), isNull);
      expect(Dinheiro.lerDecimosDeHora('NaN'), isNull);
      expect(Dinheiro.lerDecimosDeHora('99999999'), isNull);
    });
  });

  group('CalculadoraOrcamentoTela', () {
    testWidgets('prazo 0 e Mesmo dia + valor 0 e maximo 500000,00', (tester) async {
      OrcamentoPronto? enviado;
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: ServicoOrcamentoFake(),
          tituloPedido: 'Trocar tomada',
          modoInicial: ModoOrcamento.valorFechado,
          valorFechadoInicial: '0',
          prazoExecucaoInicialDias: 0,
          aoEnviar: (p) => enviado = p,
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(enviado, isNull);
      expect(find.textContaining('mínimo 1 dia'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prazo-mesmo-dia')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '500000,00');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(enviado?.prazoExecucaoDias, 1);
      expect(enviado?.totalCentavos, 50000000);
    });

    testWidgets('duplo toque em Enviar orcamento dispara apenas 1 chamada', (tester) async {
      var envios = 0;
      final c = Completer<void>();
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: ServicoOrcamentoFake(),
          tituloPedido: 'Instalar chuveiro',
          modoInicial: ModoOrcamento.valorFechado,
          valorFechadoInicial: '200,00',
          aoEnviar: (_) {
            envios++;
            return c.future;
          },
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      expect(envios, 1);
      c.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('erro de rede ao resumir total na calculadora nao pode quebrar', (tester) async {
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: _OrcamentoFalhaResumo(),
          tituloPedido: 'Trocar tomada',
          modoInicial: ModoOrcamento.valorFechado,
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.enterText(find.byType(TextField).first, '150,00');
      await tester.pumpAndSettle();
    });

    testWidgets('celular pequeno 320x568 e tablet 1024x768 com fonte 1.3x sem overflow', (tester) async {
      for (final size in [const Size(320, 568), const Size(1024, 768)]) {
        await _abrir(
          tester,
          CalculadoraOrcamentoTela(
            servico: ServicoOrcamentoFake(),
            tituloPedido: _textoGigante,
            mostrarForaDoEscopo: true,
            foraDoEscopoInicial: '$_emojiRtl $_htmlSql',
          ),
          tamanho: size,
          fonte: 1.3,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('CheckInTela', () {
    testWidgets('duplo toque em Iniciar servico dispara apenas 1 chamada', (tester) async {
      final servico = _CheckInLento();
      await _abrir(
        tester,
        CheckInTela(
          servico: servico,
          tituloBarra: 'Mariana · hoje, 14h',
          fotoInicial: const FotoChegada(hora: '14h00'),
          distanciaInicialMetros: 20,
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      expect(servico.chamadas, 1);
      servico.completer.complete(ResultadoInicio.iniciado);
      await tester.pumpAndSettle();
    });

    testWidgets('timeout nao-ErroTrato ao iniciar servico nao trava tela nem explode', (tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInTimeout(),
          tituloBarra: 'Mariana · hoje, 14h',
          fotoInicial: const FotoChegada(hora: '14h00'),
          distanciaInicialMetros: 20,
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
    });

    testWidgets('timeout nao-ErroTrato ao tirar foto / localizar nao explode', (tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInTimeout(),
          tituloBarra: 'Mariana · hoje, 14h',
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();
    });
  });

  group('InicioProfissionalTela & DetalhePedidoTela (exclusividade)', () {
    testWidgets('Estou a caminho com toque duplo dispara 1 chamada', (tester) async {
      var chamadas = 0;
      final c = Completer<AvisoACaminho>();
      await _abrir(
        tester,
        InicioProfissionalTela(
          dados: const InicioProfissional(
            nome: 'Carlos',
            disponivelAgora: true,
            proximo: ProximoAtendimento(
              quando: 'Hoje · 14h',
              titulo: 'Troca de tomadas',
              endereco: 'Rua A, 10',
              pedidoId: 'ped-1',
              estadoApi: 'agendado',
            ),
            carteira: ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0),
            pedidos: [],
          ),
          aoAvisarACaminho: (_, __) {
            chamadas++;
            return c.future;
          },
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.text('Estou a caminho'));
      await tester.pump();
      await tester.tap(find.text('Avisando...'));
      await tester.pump();
      expect(chamadas, 1);
      c.complete(const AvisoACaminho(enviado: true, etaMinutos: 15));
      await tester.pumpAndSettle();
    });

    testWidgets('lista com 500 pedidos e celular 320px fonte 1.3x sem overflow', (tester) async {
      final pedidos500 = [
        for (var i = 0; i < 500; i++)
          PedidoAberto(
            id: 'p-$i',
            titulo: i == 0 ? '$_textoGigante $_emojiRtl' : 'Pedido $i',
            bairro: 'Savassi',
            prazo: 'hoje',
          ),
      ];
      await _abrir(
        tester,
        InicioProfissionalTela(
          dados: InicioProfissional(
            nome: 'Carlos $_emojiRtl',
            disponivelAgora: false,
            carteira: const ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0),
            pedidos: pedidos500,
          ),
        ),
        tamanho: const Size(320, 568),
        fonte: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('exclusividade com saldo 0, bloqueio passado e bloqueio futuro', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: DetalhePedido(
            pedido: pedidoTomadasExemplo,
            fechaEm: '30h',
            clienteResumo: 'Mariana',
            legendasFotos: const [],
            descricao: 'Desc',
            linhas: const [],
            exclusividades: const ResumoExclusividades(saldoProfissional: 0),
          ),
          aoPedirExclusividade: (_) async => const ExclusividadeProfissional(
            id: 'e1',
            pedidoId: 'ped-tomadas',
            status: 'aguardando_cliente',
          ),
        ),
        tamanho: const Size(390, 1400),
      );
      expect(find.textContaining('100 Tratinhos'), findsWidgets);

      var pediu = 0;
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: DetalhePedido(
            pedido: pedidoTomadasExemplo,
            fechaEm: '30h',
            clienteResumo: 'Mariana',
            legendasFotos: const [],
            descricao: 'Desc',
            linhas: const [],
            bloqueadoAte: DateTime.now().subtract(const Duration(hours: 2)),
            exclusividades: const ResumoExclusividades(saldoProfissional: 150),
          ),
          aoPedirExclusividade: (_) async {
            pediu++;
            return const ExclusividadeProfissional(
              id: 'e1',
              pedidoId: 'ped-tomadas',
              status: 'aguardando_cliente',
            );
          },
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.text('Pedir exclusividade de 48 horas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar por 100 Tratinhos'));
      await tester.pumpAndSettle();
      expect(pediu, 1);

      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: DetalhePedido(
            pedido: pedidoTomadasExemplo,
            fechaEm: '30h',
            clienteResumo: 'Mariana',
            legendasFotos: const [],
            descricao: 'Desc',
            linhas: const [],
            bloqueadoAte: DateTime.now().add(const Duration(hours: 12)),
            exclusividades: const ResumoExclusividades(saldoProfissional: 150),
          ),
          aoPedirExclusividade: (_) async => const ExclusividadeProfissional(
            id: 'e1',
            pedidoId: 'ped-tomadas',
            status: 'aguardando_cliente',
          ),
        ),
        tamanho: const Size(390, 1400),
      );
      expect(find.textContaining('poderá tentar de novo'), findsOneWidget);
    });

    testWidgets('toque duplo rapido na confirmacao de exclusividade nao fecha a tela anterior', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var pediu = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DetalhePedidoTela(
                      dados: const DetalhePedido(
                        pedido: pedidoTomadasExemplo,
                        fechaEm: '30h',
                        clienteResumo: 'Mariana',
                        legendasFotos: [],
                        descricao: 'Desc',
                        linhas: [],
                        exclusividades: ResumoExclusividades(saldoProfissional: 200),
                      ),
                      aoPedirExclusividade: (_) async {
                        pediu++;
                        return const ExclusividadeProfissional(
                          id: 'e1',
                          pedidoId: 'ped-tomadas',
                          status: 'aguardando_cliente',
                        );
                      },
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedir exclusividade de 48 horas'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar por 100 Tratinhos'));
      await tester.tap(find.text('Confirmar por 100 Tratinhos'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(pediu, 1);
      expect(find.byType(DetalhePedidoTela), findsOneWidget);
    });

    testWidgets('voltar no meio da folha de exclusividade nao chama aoPedirExclusividade', (tester) async {
      var pediu = 0;
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: const DetalhePedido(
            pedido: pedidoTomadasExemplo,
            fechaEm: '30h',
            clienteResumo: 'Mariana',
            legendasFotos: [],
            descricao: 'Desc',
            linhas: [],
            exclusividades: ResumoExclusividades(saldoProfissional: 200),
          ),
          aoPedirExclusividade: (_) async {
            pediu++;
            return const ExclusividadeProfissional(
              id: 'e1',
              pedidoId: 'ped-tomadas',
              status: 'aguardando_cliente',
            );
          },
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.text('Pedir exclusividade de 48 horas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(pediu, 0);
    });
  });

  group('Modelos API & Carregador', () {
    test('PedidoApi.deJson aceita status desconhecido e campos opcionais nulos/faltando', () {
      final p = PedidoApi.deJson({
        'id': 'p1',
        'estado': 'status_futuro_desconhecido',
        'estado_nome': 'Novo status',
        'cliente_id': 'c1',
        'profissional_id': null,
        'aberto_em': '2026-11-20T10:00:00Z',
        'concluido_em': null,
        'acoes_permitidas': <String>[],
        'codigo_inicio': null,
        'codigo_conclusao': null,
        'titulo': null,
      });
      expect(p.estado, 'status_futuro_desconhecido');
      expect(p.rotulo, startsWith('Pedido #'));
    });

    testWidgets('Carregador com erro de rede mostra Tentar de novo', (tester) async {
      var tentativas = 0;
      await _abrir(
        tester,
        Scaffold(
          body: Carregador<List<String>>(
            carregar: () async {
              tentativas++;
              if (tentativas == 1) {
                throw const ErroTrato(TipoErro.semInternet, 'Sem internet');
              }
              return ['ok'];
            },
            construir: (_, lista) => Text(lista.first),
          ),
        ),
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('ok'), findsOneWidget);
    });
  });

  group('Demais telas do profissional', () {
    testWidgets('CadastroProfissionalTela: so espacos no nome e erro de rede', (tester) async {
      await _abrir(tester, CadastroProfissionalTela(servico: _CadastroErro()));
      expect(find.text('Tentar de novo'), findsOneWidget);

      final lento = _CadastroLento();
      await _abrir(
        tester,
        CadastroProfissionalTela(servico: lento, nomeInicial: '   '),
        tamanho: const Size(390, 1800),
      );
      await tester.tap(find.text('Salvar e continuar'));
      await tester.pumpAndSettle();
      expect(lento.envios, 0);
      expect(find.textContaining('mínimo 3 letras'), findsOneWidget);
    });

    testWidgets('VerificacaoTela com erro sessao expirada mostra Tentar de novo', (tester) async {
      await _abrir(tester, VerificacaoTela(servico: _VerificacaoErro()));
      expect(find.text('Sessão expirada'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('AgendaTela com lista vazia e 500 itens sem overflow', (tester) async {
      await _abrir(tester, AgendaTela(carregar: () async => []));
      expect(find.text('Nada agendado'), findsOneWidget);

      await _abrir(
        tester,
        AgendaTela(
          carregar: () async => [
            for (var i = 0; i < 500; i++)
              Agendamento(
                id: 'a-$i',
                pedidoId: 'p-$i',
                dia: DateTime(2026, 11, 20),
                horario: '14h',
                titulo: i == 0 ? '$_textoGigante $_emojiRtl' : 'Atendimento $i',
                local: 'Savassi',
              ),
          ],
          hoje: DateTime(2026, 11, 20),
        ),
        tamanho: const Size(320, 568),
        fonte: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('CriarAditivoTela: valor 0, espacos e duplo toque', (tester) async {
      final lento = _AditivoLento();
      await _abrir(
        tester,
        CriarAditivoTela(
          servico: lento,
          servicoLiquido: ServicoOrcamentoFake(),
          pedidoId: 'ped-1',
          tituloPedido: 'Troca de tubo',
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.enterText(find.byType(TextField).last, '0');
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(lento.envios, 0);

      await tester.enterText(find.byType(TextField).first, 'Troca de peça $_htmlSql');
      await tester.enterText(find.byType(TextField).last, '120,00');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      expect(lento.envios, 1);
      lento.completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('ResponderDisputaTela: espacos e duplo toque dispara 1 chamada', (tester) async {
      final lento = _DisputaLenta();
      await _abrir(
        tester,
        ResponderDisputaTela(servico: lento, disputaId: 'disp-1'),
        tamanho: const Size(390, 1600),
      );
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(lento.envios, 0);

      await tester.enterText(find.byType(TextField).last, 'Resposta valida $_emojiRtl');
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      expect(lento.envios, 1);
      lento.completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('CarteiraTela, ContaRecebimentoTela e AvaliarClienteTela', (tester) async {
      await _abrir(
        tester,
        CarteiraTela(
          dados: mc.DadosCarteira(
            extrato: [
              for (var i = 0; i < 500; i++)
                mc.ItemExtrato(
                  titulo: 'Serviço $i',
                  detalheData: '20/11/2026',
                  brutoCentavos: 10000,
                  textoTaxa: 'Sem taxa',
                  liquidoCentavos: 10000,
                  status: mc.StatusExtrato.liberado,
                ),
            ],
          ),
        ),
        tamanho: const Size(320, 568),
        fonte: 1.3,
      );
      expect(tester.takeException(), isNull);

      var salvou = 0;
      final c = Completer<mc.ContaRecebimento>();
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ContaRecebimentoTela(
                      inicial: const mc.ContaRecebimento(cadastrada: false),
                      aoSalvar: ({
                        required String tipoPix,
                        required String chavePix,
                        String? bancoCodigo,
                        String? bancoNome,
                        String? agencia,
                        String? conta,
                        String? tipoConta,
                      }) {
                        salvou++;
                        return c.future;
                      },
                    ),
                  ),
                ),
                child: const Text('Abrir conta'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir conta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(salvou, 0);

      await tester.enterText(find.byType(TextField).first, '12345678909');
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      expect(salvou, 1);
      c.complete(const mc.ContaRecebimento(cadastrada: true, tipoPix: 'cpf', chavePix: '12345678909'));
      await tester.pumpAndSettle();

      var avaliou = 0;
      final cAv = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AvaliarClienteTela(
                      pedidoNumero: '#123',
                      aoEnviar: (_, __) {
                        avaliou++;
                        return cAv.future;
                      },
                    ),
                  ),
                ),
                child: const Text('Abrir avaliar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir avaliar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '$_textoGigante $_emojiRtl $_htmlSql');
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pump();
      expect(avaliou, 1);
      cAv.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Mensagens, Notificacoes, Configuracoes, Chat e Ajuda (500 itens, erro, 1.3x)', (tester) async {
      await _abrir(tester, MensagensTela(servico: _MensagensErro()));
      expect(find.text('Tentar de novo'), findsOneWidget);
      await _abrir(tester, MensagensTela(servico: _Mensagens500()), tamanho: const Size(320, 568), fonte: 1.3);
      expect(tester.takeException(), isNull);

      await _abrir(tester, NotificacoesTela(servico: _NotificacoesErro()));
      expect(find.text('Tentar de novo'), findsOneWidget);
      await _abrir(tester, NotificacoesTela(servico: _Notificacoes500()), tamanho: const Size(320, 568), fonte: 1.3);
      expect(tester.takeException(), isNull);

      await _abrir(
        tester,
        ConfiguracoesTela(
          grupos: [
            GrupoConfiguracao(
              titulo: 'CONTA',
              itens: [
                ItemContaPerfil(icone: Icons.person, titulo: '$_textoGigante $_emojiRtl', aoTocar: () {}),
              ],
            ),
          ],
          aoSair: () {},
        ),
        tamanho: const Size(320, 568),
        fonte: 1.3,
      );
      expect(tester.takeException(), isNull);

      await _abrir(tester, AjudaTela(servico: _Ajuda500()), tamanho: const Size(320, 568), fonte: 1.3);
      await tester.enterText(find.byType(TextField).first, _htmlSql);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _abrir(
        tester,
        ChatPedidoTela(
          conversa: mp.ConversaPedido(
            nome: 'Mariana $_emojiRtl',
            iniciais: 'M',
            numeroPedido: '#123',
            situacao: 'Em andamento',
            respostasRapidas: const [],
            souCliente: false,
            mensagens: [
              for (var i = 0; i < 500; i++)
                mp.MensagemChat(
                  id: i,
                  tipo: mp.TipoMensagem.texto,
                  minha: i.isEven,
                  texto: i == 0 ? '$_textoGigante $_htmlSql' : 'Mensagem $i',
                  hora: '10h',
                ),
            ],
          ),
          aoEnviar: (_) async {},
        ),
        tamanho: const Size(320, 568),
        fonte: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
