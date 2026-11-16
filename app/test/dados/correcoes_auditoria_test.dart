// Correções da auditoria de 15/11/2026: o que o app manda ao servidor nas disputas, no
// retrabalho, no cancelamento, nas notificações e na avaliação do cliente; fila offline em disco;
// provedores de login e e-mail de suporte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/config_auth.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_supabase.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/config_publica.dart';
import 'package:trato/dados/fila_offline.dart';
import 'package:trato/dados/fila_offline_arquivo.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/disputa_profissional/disputa.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';

import '../apoio/exemplos/dados/servico_upload_fake.dart';

class _Chamada {
  _Chamada(this.metodo, this.caminho, this.corpo);
  final String metodo;
  final String caminho;
  final Map<String, dynamic>? corpo;
}

(ClienteApi, List<_Chamada>) _cliente([Object resposta = const <String, Object?>{}]) {
  final chamadas = <_Chamada>[];
  final sessao = SessaoTrato()..entrar('valor-de-teste');
  final api = ClienteApi(
    urlBase: 'https://api.teste/',
    sessao: sessao,
    cliente: MockClient((req) async {
      chamadas.add(_Chamada(
        req.method,
        req.url.path,
        req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>,
      ));
      return http.Response(
        jsonEncode(resposta),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return (api, chamadas);
}

File _foto(Directory pasta, String nome) =>
    File('${pasta.path}/$nome')..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

void main() {
  late Directory pasta;

  setUp(() => pasta = Directory.systemTemp.createTempSync('trato_teste_'));
  tearDown(() => pasta.deleteSync(recursive: true));

  group('disputa e retrabalho mandam as fotos', () {
    test('relato sobe as fotos e manda os ids; "não compareceu" tem código próprio', () async {
      final (api, chamadas) = _cliente();
      final upload = ServicoUploadFake();
      final repo = RepositorioPedidosApi(api, upload: upload);

      await repo.relatarProblema(
        'abcd1234',
        EnvioRelato(
          motivo: 'O profissional não compareceu',
          descricao: 'Esperei duas horas',
          solucao: 'Reembolso total',
          fotos: [_foto(pasta, 'a.jpg').path, 'fake://nao-existe'],
        ),
      );

      expect(upload.enviados, hasLength(1));
      final corpo = chamadas.single.corpo!;
      expect(corpo['motivo'], 'nao_compareceu');
      expect((corpo['fotos'] as List).single['arquivo_id'], 'arq-1');
    });

    test('"abandonou o serviço" vira abandono', () async {
      final (api, chamadas) = _cliente();
      await RepositorioPedidosApi(api).relatarProblema(
        'abcd1234',
        const EnvioRelato(
          motivo: 'O profissional abandonou o serviço',
          descricao: 'Sumiu',
          solucao: 'Reembolso total',
        ),
      );
      expect(chamadas.single.corpo!['motivo'], 'abandono');
    });

    test('pedido de retrabalho leva as fotos', () async {
      final (api, chamadas) = _cliente();
      final repo = RepositorioPedidosApi(api, upload: ServicoUploadFake());

      await repo.pedirRetrabalho('abcd1234', 'Tomada solta', fotos: [_foto(pasta, 'b.jpg').path]);

      expect(chamadas.single.corpo!['fotos'] as List, hasLength(1));
    });

    test('a resposta do profissional leva texto, proposta e fotos', () async {
      final (api, chamadas) = _cliente();
      final servico = ServicoDisputaProfissionalApi(api, upload: ServicoUploadFake());

      await servico.responder(RespostaDisputa(
        disputaId: 'abcd1234',
        tipo: TipoRespostaDisputa.proporReembolsoParcial,
        mensagem: 'Fiz como combinado',
        reembolsoParcialCentavos: 5000,
        evidencias: [_foto(pasta, 'c.jpg').path],
      ));

      expect(chamadas.single.caminho, '/v1/pedidos/abcd1234/disputa/resposta');
      final corpo = chamadas.single.corpo!;
      expect(corpo['mensagem'], 'Fiz como combinado');
      expect(corpo['solucao'], 'reembolso_parcial');
      expect(corpo['reembolso_parcial_centavos'], 5000);
      expect(corpo['fotos'] as List, hasLength(1));
    });
  });

  group('retrabalho anda até o fim', () {
    test('agendar aceita e avisa o cliente pelo chat', () async {
      final (api, chamadas) = _cliente();
      await ServicoDisputaProfissionalApi(api).agendarRetrabalho(
        const AgendamentoRetrabalho(disputaId: 'p1', horario: 'Manhã', mensagem: 'Levo a peça'),
      );

      expect(chamadas[0].caminho, '/v1/pedidos/p1/retrabalho/atender');
      expect(chamadas[0].corpo, {'etapa': 'aceitar'});
      expect(chamadas[1].caminho, '/v1/pedidos/p1/mensagens');
      expect(chamadas[1].corpo!['texto'], contains('Manhã'));
    });

    test('iniciar e resolver usam a rota de atender', () async {
      final (api, chamadas) = _cliente();
      final servico = ServicoDisputaProfissionalApi(api);
      await servico.avancarRetrabalho('p1', 'iniciar');
      await servico.avancarRetrabalho('p1', 'resolver');
      expect([for (final c in chamadas) c.corpo!['etapa']], ['iniciar', 'resolver']);
    });

    test('só mostra retrabalho que ainda pede ação e usa o prazo da configuração', () async {
      final (api, _) = _cliente([
        {'estado': 'resolvido', 'descricao': 'velho'},
        {'estado': 'em_execucao', 'descricao': 'Tomada solta'},
      ]);
      final dados = await ServicoDisputaProfissionalApi(api).carregarRetrabalho('p1');
      expect(dados!.estado, 'em_execucao');
      expect(dados.descricaoProblema, 'Tomada solta');
      expect(dados.prazoAtendimentoDias, ConfigPublica.atual.prazoRetrabalhoDias);
    });
  });

  test('cancelar manda o motivo como prova', () async {
    final (api, chamadas) = _cliente();
    await RepositorioPedidosApi(api).cancelar('abcd1234', 'Mudei de ideia');
    expect(chamadas.single.caminho, '/v1/pedidos/abcd1234/acoes/cancelar');
    expect(chamadas.single.corpo, {
      'prova': {'motivo': 'Mudei de ideia'},
    });
  });

  test('o profissional avalia o cliente pela rota de avaliação do pedido', () async {
    final (api, chamadas) = _cliente();
    await RepositorioProfissionalApi(api).avaliarCliente('abcd1234', 5, 'Tudo certo');
    expect(chamadas.single.caminho, '/v1/pedidos/abcd1234/avaliacao');
    expect(chamadas.single.corpo, {'nota_geral': 5, 'comentario': 'Tudo certo'});
  });

  group('notificações', () {
    final lista = [
      {'id': 'n1', 'titulo': 'A', 'corpo': '', 'criada_em': '2026-11-15T10:00:00Z', 'lida': false},
      {'id': 'n2', 'titulo': 'B', 'corpo': '', 'criada_em': '2026-11-15T10:00:00Z', 'lida': true},
      {'id': 'n3', 'titulo': 'C', 'corpo': '', 'criada_em': '2026-11-15T10:00:00Z', 'lida': false},
    ];

    test('marcar como lida grava no servidor', () async {
      final (api, chamadas) = _cliente(lista);
      final servico = ServicoNotificacoesRepositorio(RepositorioNotificacoesApi(api));
      await servico.listar();
      await servico.marcarLida('n1');
      expect(chamadas.last.metodo, 'POST');
      expect(chamadas.last.caminho, '/v1/notificacoes/n1/lida');
    });

    test('marcar todas grava só as que estavam sem ler', () async {
      final (api, chamadas) = _cliente(lista);
      final servico = ServicoNotificacoesRepositorio(RepositorioNotificacoesApi(api));
      await servico.listar();
      await servico.marcarTodasLidas();
      expect(
        [for (final c in chamadas.skip(1)) c.caminho],
        ['/v1/notificacoes/n1/lida', '/v1/notificacoes/n3/lida'],
      );
    });
  });

  group('fila offline em disco', () {
    AcaoOffline acao() => AcaoOffline(
          pedidoId: 'p1',
          tipo: TipoAcaoOffline.checkIn,
          codigo: '1234',
          foto: FotoCapturada(
            tiradaEm: DateTime.utc(2026, 11, 15, 12),
            local: ArquivoCapturado(
              bytes: Uint8List.fromList([9, 8, 7]),
              sha256: 'x',
              capturadaEm: DateTime.utc(2026, 11, 15, 12),
            ),
          ),
          posicao: const PosicaoCapturada(-19.9, -43.9, distanciaMetros: 40),
        );

    Iterable<File> fotos() =>
        pasta.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg'));

    test('o que ficou guardado volta quando o app abre de novo', () {
      FilaOfflineArquivo.abrirEm(pasta).guardar(acao());

      final reaberta = FilaOfflineArquivo.abrirEm(pasta);

      expect(reaberta.pendentes, hasLength(1));
      final a = reaberta.pendentes.single;
      expect(a.pedidoId, 'p1');
      expect(a.codigo, '1234');
      expect(a.foto.local!.bytes, [9, 8, 7]);
      expect(a.posicao!.distanciaMetros, 40);
    });

    test('remover apaga da lista e o arquivo da foto', () {
      FilaOfflineArquivo.abrirEm(pasta).guardar(acao());
      expect(fotos(), hasLength(1));

      final reaberta = FilaOfflineArquivo.abrirEm(pasta);
      reaberta.remover(reaberta.pendentes.single);

      expect(FilaOfflineArquivo.abrirEm(pasta).pendentes, isEmpty);
      expect(fotos(), isEmpty);
    });

    test('arquivo estragado vira fila vazia, não derruba o app', () {
      File('${pasta.path}/fila.json').writeAsStringSync('{ isto não é json');
      expect(FilaOfflineArquivo.abrirEm(pasta).pendentes, isEmpty);
    });
  });

  group('login com Google e Apple', () {
    const config = ConfigAuth(
      supabaseUrl: 'https://x.supabase.co',
      supabaseAnonKey: 'chave-publica-de-teste',
    );

    Future<Set<ProvedorAuth>?> consultar(Object corpo, [int status = 200]) =>
        ServicoAuthSupabase.provedoresLigadosNoServidor(
          config,
          cliente: MockClient((_) async => http.Response(jsonEncode(corpo), status)),
        );

    test('só entram os provedores que o Supabase tem ligados', () async {
      expect(
        await consultar({
          'external': {'google': false, 'apple': false, 'email': true},
        }),
        isEmpty,
      );
      expect(
        await consultar({
          'external': {'google': true, 'apple': false},
        }),
        {ProvedorAuth.google},
      );
    });

    test('sem resposta do servidor devolve nulo (vale só a configuração do app)', () async {
      expect(await consultar({}, 500), isNull);
      expect(await consultar({'sem': 'external'}), isNull);
    });
  });

  test('e-mail de suporte só vale se parecer e-mail', () {
    expect(ConfigPublica.deJson({}).suporteEmail, isNull);
    expect(ConfigPublica.deJson({'suporte_email': 'sem-arroba'}).suporteEmail, isNull);
    expect(
      ConfigPublica.deJson({'suporte_email': ' ajuda@exemplo.test '}).suporteEmail,
      'ajuda@exemplo.test',
    );
  });
}
