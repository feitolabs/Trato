import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cache_leitura.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_indicacoes_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/indicacoes/indique_e_ganhe_tela.dart';
import 'package:trato/telas/indicacoes/modelos.dart';
import 'package:trato/telas/indicacoes/servico_fake.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';

final _meu = MeuCodigoIndicacao(
  codigo: 'TRATO2026',
  resumo: const ResumoIndicacoes(
    cadastradas: 4,
    aguardandoLiberacao: 2,
    liberadas: 1,
    limiteMensal: 5,
    limiteMensalRestante: 3,
  ),
  indicacoes: [
    const Indicacao(id: 'i1', status: 'cadastrado', nomeIndicado: 'Bia C.', bonusTratinhos: 50),
    Indicacao(
      id: 'i2',
      status: 'aguardando_liberacao',
      nomeIndicado: 'Caio D.',
      bonusTratinhos: 50,
      liberacaoPrevista: DateTime(2030, 12, 5, 12),
    ),
    const Indicacao(id: 'i3', status: 'liberado', nomeIndicado: 'Duda E.', bonusTratinhos: 50),
    const Indicacao(id: 'i4', status: 'cancelado', nomeIndicado: 'Edu F.', bonusTratinhos: 50),
  ],
);

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 2400),
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

http.Response _json(Object o, [int status = 200]) =>
    http.Response(jsonEncode(o), status, headers: {'content-type': 'application/json'});

void main() {
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('Contrato com o backend', () {
    late List<http.Request> pedidas;
    ServicoIndicacoesApi servico(http.Response Function(http.Request) responder, {bool logado = true}) {
      pedidas = [];
      final sessao = SessaoTrato();
      if (logado) sessao.entrar('t');
      return ServicoIndicacoesApi(
        ClienteApi(
          urlBase: 'https://api.teste/',
          sessao: sessao,
          intervaloBaseRetry: Duration.zero,
          cliente: MockClient((req) async {
            pedidas.add(req);
            return responder(req);
          }),
        ),
      );
    }

    test('GET /v1/indicacoes/meu-codigo lê código, resumo e lista', () async {
      final s = servico(
        (_) => _json({
          'codigo': 'AB12CD34',
          'resumo': {
            'cadastradas': 3,
            'aguardando_liberacao': 1,
            'liberadas': 2,
            'limite_mensal': 5,
            'limite_mensal_restante': 4,
          },
          'indicacoes': [
            {
              'id': 'x1',
              'indicado_nome': 'Ana S.',
              'status': 'aguardando_liberacao',
              'tipo': 'cliente',
              'bonus_indicador_tratinhos': 50,
              'liberacao_prevista_em': '2030-12-05T15:00:00Z',
              'liberado_em': null,
            },
            {'sem': 'id'},
          ],
        }),
      );
      final r = await s.meuCodigo();
      expect(pedidas.single.url.path, '/v1/indicacoes/meu-codigo');
      expect(pedidas.single.headers['Authorization'], 'Bearer t');
      expect(r.codigo, 'AB12CD34');
      expect(r.resumo.liberadas, 2);
      expect(r.resumo.limiteMensalRestante, 4);
      expect(r.indicacoes.map((i) => i.id), ['x1']); // item sem id é ignorado
      expect(r.indicacoes.single.bonusTratinhos, 50);
      expect(r.indicacoes.single.liberacaoPrevista, isNotNull);
    });

    test('backend antigo (campos ausentes) não quebra: valores padrão seguros', () async {
      final s = servico((_) => _json({'codigo': 'ZZ'}));
      final r = await s.meuCodigo();
      expect(r.codigo, 'ZZ');
      expect(r.resumo.cadastradas, 0);
      expect(r.indicacoes, isEmpty);
    });

    test('GET público /v1/indicacoes/codigo/{codigo}: maiúsculo, codificado e sem login', () async {
      final s = servico(
        (_) => _json({'valido': true, 'indicador_nome_curto': 'Ana S.', 'indicador_papel': 'cliente'}),
        logado: false,
      );
      final c = await s.validar('  ab 12/cd ');
      expect(pedidas.single.url.toString(), 'https://api.teste/v1/indicacoes/codigo/AB%2012%2FCD');
      expect(pedidas.single.headers.containsKey('Authorization'), isFalse);
      expect(c.valido, isTrue);
      expect(c.indicadorNomeCurto, 'Ana S.');
      expect(c.indicadorPapel, 'cliente');
    });

    test('POST /v1/indicacoes/aplicar manda só o código e devolve a mensagem do backend', () async {
      final s = servico(
        (_) => _json({
          'id': 'ind-1',
          'tipo': 'cliente',
          'status': 'cadastrado',
          'bonus_indicado_tratinhos': 50,
          'mensagem': 'Código aplicado! Seu bônus sai depois do 1º serviço.',
        }, 201),
      );
      final r = await s.aplicar(' amigo123 ');
      expect(pedidas.single.method, 'POST');
      expect(pedidas.single.url.path, '/v1/indicacoes/aplicar');
      expect(jsonDecode(pedidas.single.body), {'codigo': 'AMIGO123'});
      expect(r.mensagem, 'Código aplicado! Seu bônus sai depois do 1º serviço.');
      expect(r.bonusIndicadoTratinhos, 50);
    });

    test('erros 404, 409 e 422 chegam com o texto em português do backend', () async {
      for (final (status, texto) in [
        (404, 'Código de indicação não encontrado.'),
        (409, 'Você já utilizou um código de indicação.'),
        (422, 'Você não pode usar o seu próprio código.'),
      ]) {
        final s = servico((_) => _json({'detail': texto}, status));
        await expectLater(
          s.aplicar('ABC123'),
          throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', texto)),
        );
      }
    });

    test('o meu-codigo pode ficar no cache de leitura (offline), o código público não', () {
      expect(CacheLeitura.elegivel('/v1/indicacoes/meu-codigo'), isTrue);
      expect(CacheLeitura.elegivel('/v1/indicacoes/codigo/ABC123'), isFalse);
      expect(CacheLeitura.elegivel('/v1/indicacoes/aplicar'), isFalse);
    });
  });

  group('Status legível', () {
    test('mapeia os 4 status do backend', () {
      expect(const Indicacao(id: 'a', status: 'cadastrado').textoStatus, 'Aguardando 1º serviço');
      expect(
        Indicacao(id: 'b', status: 'aguardando_liberacao', liberacaoPrevista: DateTime(2030, 12, 5))
            .textoStatus,
        'Liberação em 05/12',
      );
      expect(
        const Indicacao(id: 'c', status: 'aguardando_liberacao').textoStatus,
        'Aguardando liberação',
      );
      expect(const Indicacao(id: 'd', status: 'liberado').textoStatus, 'Liberado');
      expect(const Indicacao(id: 'e', status: 'cancelado').textoStatus, 'Cancelado');
      expect(const Indicacao(id: 'f', status: 'novo_status').textoStatus, 'Em análise');
    });
  });

  group('Tela "Indique e ganhe"', () {
    testWidgets('mostra código, resumo e a lista com status e bônus em Tratinhos e reais',
        (tester) async {
      await _abrir(
        tester,
        IndiqueEGanheTela(servico: ServicoIndicacoesFake(meu: _meu), valorMoedaCentavos: 1),
      );
      expect(find.text('Indique e ganhe'), findsWidgets);
      expect(find.byKey(const ValueKey('codigo-indicacao')), findsOneWidget);
      expect(find.text('TRATO2026'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Neste mês ainda dá para ganhar com 3 de 5 indicações.'), findsOneWidget);

      expect(find.text('Bia C.'), findsOneWidget);
      expect(find.text('Aguardando 1º serviço'), findsOneWidget);
      expect(find.text('Liberação em 05/12'), findsOneWidget);
      expect(find.text('Liberado'), findsOneWidget);
      expect(find.text('Cancelado'), findsOneWidget);
      // Bônus sempre também em reais; cancelada não mostra bônus (3 de 4).
      expect(find.text('+50 Tratinhos = R\$ 0,50'), findsNWidgets(3));
    });

    testWidgets('sem indicações: texto vazio claro', (tester) async {
      await _abrir(tester, IndiqueEGanheTela(servico: ServicoIndicacoesFake()));
      expect(find.byKey(const ValueKey('indicacoes-vazio')), findsOneWidget);
    });

    testWidgets('erro ao carregar mostra o erro com "Tentar de novo" e recarrega', (tester) async {
      var falha = true;
      await _abrir(
        tester,
        IndiqueEGanheTela(servico: _Instavel(() => falha, ServicoIndicacoesFake(meu: _meu))),
      );
      expect(find.byKey(const ValueKey('codigo-indicacao')), findsNothing);
      falha = false;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('TRATO2026'), findsOneWidget);
    });

    testWidgets('copiar código copia só o código e avisa', (tester) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _abrir(tester, IndiqueEGanheTela(servico: ServicoIndicacoesFake(meu: _meu)));
      await tester.tap(find.byKey(const ValueKey('copiar-codigo')));
      await tester.pumpAndSettle();
      expect(copiado, 'TRATO2026');
      expect(find.text('Código copiado!'), findsOneWidget);
    });

    testWidgets('compartilhar manda texto com o código, sem id nem link', (tester) async {
      final enviados = <String>[];
      await _abrir(
        tester,
        IndiqueEGanheTela(
          servico: ServicoIndicacoesFake(meu: _meu),
          compartilhar: (t) async => enviados.add(t),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('compartilhar-codigo')));
      await tester.pumpAndSettle();
      expect(enviados.single, contains('TRATO2026'));
      expect(enviados.single, isNot(contains('http')));
      expect(enviados.single, isNot(contains('i1')));
    });

    testWidgets('sem compartilhamento no aparelho copia o texto e avisa', (tester) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _abrir(
        tester,
        IndiqueEGanheTela(
          servico: ServicoIndicacoesFake(meu: _meu),
          compartilhar: (_) async => throw StateError('indisponível'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('compartilhar-codigo')));
      await tester.pumpAndSettle();
      expect(copiado, contains('TRATO2026'));
      expect(find.text('Texto copiado! Cole no WhatsApp para convidar.'), findsOneWidget);
    });
  });

  group('Campo "Tenho um código de indicação"', () {
    Future<ServicoIndicacoesFake> abrirCampo(WidgetTester tester) async {
      final s = ServicoIndicacoesFake();
      await _abrir(tester, Scaffold(body: SingleChildScrollView(child: CampoCodigoIndicacao(servico: s))));
      return s;
    }

    testWidgets('valida, mostra "Indicado por X" e aplica; depois mostra a mensagem do backend',
        (tester) async {
      final s = ServicoIndicacoesFake();
      var aplicou = 0;
      await _abrir(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: CampoCodigoIndicacao(servico: s, aoAplicado: () => aplicou++),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('aplicar-codigo')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('campo-codigo-indicacao')), 'amigo123');
      await tester.tap(find.byKey(const ValueKey('validar-codigo')));
      await tester.pumpAndSettle();
      expect(s.validados, ['AMIGO123']);
      expect(find.text('Indicado por Ana S.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('aplicar-codigo')));
      await tester.pumpAndSettle();
      expect(s.aplicados, ['AMIGO123']);
      expect(aplicou, 1);
      expect(find.text('Código aplicado! Seu bônus sai depois do 1º serviço.'), findsOneWidget);
      expect(find.byKey(const ValueKey('campo-codigo-indicacao')), findsNothing);
    });

    testWidgets('código inexistente mostra o texto do backend como veio', (tester) async {
      await abrirCampo(tester);
      await tester.enterText(find.byKey(const ValueKey('campo-codigo-indicacao')), 'XXXX999');
      await tester.tap(find.byKey(const ValueKey('validar-codigo')));
      await tester.pumpAndSettle();
      expect(find.text('Código de indicação não encontrado.'), findsOneWidget);
      expect(find.byKey(const ValueKey('aplicar-codigo')), findsNothing);
    });

    testWidgets('campo vazio pede o código sem chamar o servidor', (tester) async {
      final s = await abrirCampo(tester);
      await tester.tap(find.byKey(const ValueKey('validar-codigo')));
      await tester.pumpAndSettle();
      expect(find.text('Digite o código de indicação.'), findsOneWidget);
      expect(s.validados, isEmpty);
    });

    testWidgets('erro 409/422 ao aplicar aparece como veio e dá para tentar de novo',
        (tester) async {
      final s = ServicoIndicacoesFake()
        ..erroAoAplicar = const ErroTrato(
          TipoErro.recusado,
          'Você já utilizou um código de indicação.',
          codigoHttp: 409,
        );
      await _abrir(tester, Scaffold(body: SingleChildScrollView(child: CampoCodigoIndicacao(servico: s))));
      await tester.enterText(find.byKey(const ValueKey('campo-codigo-indicacao')), 'AMIGO123');
      await tester.tap(find.byKey(const ValueKey('validar-codigo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('aplicar-codigo')));
      await tester.pumpAndSettle();
      expect(find.text('Você já utilizou um código de indicação.'), findsOneWidget);
      expect(find.byKey(const ValueKey('aplicar-codigo')), findsOneWidget);
    });

    testWidgets('mudar o código depois de validar volta ao passo de validar', (tester) async {
      await abrirCampo(tester);
      await tester.enterText(find.byKey(const ValueKey('campo-codigo-indicacao')), 'AMIGO123');
      await tester.tap(find.byKey(const ValueKey('validar-codigo')));
      await tester.pumpAndSettle();
      expect(find.text('Indicado por Ana S.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('campo-codigo-indicacao')), 'OUTRO11');
      await tester.pump();
      expect(find.text('Indicado por Ana S.'), findsNothing);
      expect(find.byKey(const ValueKey('aplicar-codigo')), findsNothing);
      expect(find.byKey(const ValueKey('validar-codigo')), findsOneWidget);
    });

    testWidgets('anti-duplo clique: toque repetido em Aplicar chama o servidor uma vez',
        (tester) async {
      final s = _AplicaLento();
      await _abrir(tester, Scaffold(body: SingleChildScrollView(child: CampoCodigoIndicacao(servico: s))));
      await tester.enterText(find.byKey(const ValueKey('campo-codigo-indicacao')), 'AMIGO123');
      await tester.tap(find.byKey(const ValueKey('validar-codigo')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('aplicar-codigo')));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario), warnIfMissed: false);
      await tester.pump();
      expect(s.chamadas, 1);
      s.pendente.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('codigo-aplicado')), findsOneWidget);
    });
  });

  group('Pontos de entrada', () {
    testWidgets('perfil do profissional: card "Indique e ganhe" só com o callback', (tester) async {
      var abriu = 0;
      await _abrir(
        tester,
        PerfilPublicoTela(servico: ServicoPerfilPublicoFake(), aoAbrirIndicacoes: () => abriu++),
      );
      await tester.ensureVisible(find.byKey(const Key('abrir-indique-e-ganhe')));
      await tester.tap(find.byKey(const Key('abrir-indique-e-ganhe')));
      expect(abriu, 1);

      await _abrir(tester, PerfilPublicoTela(servico: ServicoPerfilPublicoFake()));
      expect(find.byKey(const Key('abrir-indique-e-ganhe')), findsNothing);
    });

    test('perfil do cliente: o item "Indique e ganhe" fica no Perfil (não só nas configurações)', () {
      const perfil = PerfilCliente(
        nome: 'Ana',
        iniciais: 'A',
        resumo: '',
        grupos: [
          GrupoPerfil(
            titulo: 'CONTA',
            itens: [
              ItemPerfil(acao: AcaoPerfil.favoritos, titulo: 'Profissionais de confiança'),
              ItemPerfil(acao: AcaoPerfil.indiqueEGanhe, titulo: 'Indique e ganhe'),
              ItemPerfil(acao: AcaoPerfil.notificacoes, titulo: 'Notificações'),
            ],
          ),
        ],
      );
      final no = RotasTrato.soNoPerfilParaTeste(perfil);
      expect(
        no.grupos.single.itens.map((i) => i.acao),
        [AcaoPerfil.favoritos, AcaoPerfil.indiqueEGanhe],
      );
    });

    testWidgets('rota: abrirIndicacoes abre a tela com o código (demonstração)', (tester) async {
      await _abrir(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RotasTrato.abrirIndicacoes(context, valorMoedaCentavos: 1),
            child: const Text('abrir'),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(IndiqueEGanheTela), findsOneWidget);
      expect(find.text('TRATO2026'), findsOneWidget);
    });
  });
}

class _Instavel implements ServicoIndicacoes {
  _Instavel(this._falha, this._base);

  final bool Function() _falha;
  final ServicoIndicacoes _base;

  @override
  Future<MeuCodigoIndicacao> meuCodigo() async {
    if (_falha()) throw ErroTrato.semInternet;
    return _base.meuCodigo();
  }

  @override
  Future<ConviteIndicacao> validar(String codigo) => _base.validar(codigo);

  @override
  Future<ResultadoAplicacao> aplicar(String codigo) => _base.aplicar(codigo);
}

class _AplicaLento extends ServicoIndicacoesFake {
  final pendente = Completer<void>();
  var chamadas = 0;

  @override
  Future<ResultadoAplicacao> aplicar(String codigo) async {
    chamadas++;
    await pendente.future;
    return super.aplicar(codigo);
  }
}
