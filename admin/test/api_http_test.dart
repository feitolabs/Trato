import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_fake.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/config_painel.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';

/// Servidor simulado: guarda as chamadas e responde pelo "METODO caminho".
class Servidor {
  final chamadas = <http.Request>[];
  final respostas = <String, (int, Object?)>{};

  MockClient get cliente => MockClient((req) async {
        chamadas.add(req);
        final chave = '${req.method} ${req.url.path}';
        final r = respostas[chave];
        if (r == null) return http.Response(jsonEncode({'detail': 'sem rota $chave'}), 404);
        return http.Response.bytes(utf8.encode(jsonEncode(r.$2)), r.$1, headers: {'content-type': 'application/json'});
      });

  http.Request chamada(String metodo, String caminho) =>
      chamadas.lastWhere((c) => c.method == metodo && c.url.path == caminho);
}

const _tokenDeTeste = 'token-so-de-teste';

ApiAdminHttp criar(Servidor s) => ApiAdminHttp(
      urlApi: 'https://api.teste/',
      urlSupabase: 'https://sb.teste',
      chaveAnonSupabase: 'chave-publica-de-teste',
      cliente: s.cliente,
    );

Servidor servidorLogavel({String papel = 'mediador'}) {
  final s = Servidor();
  s.respostas['POST /auth/v1/token'] = (200, {'access_token': _tokenDeTeste});
  s.respostas['GET /v1/admin/eu'] = (
    200,
    {'id': 'u-1', 'nome': 'Maria', 'email': 'maria@teste.local', 'papel': papel, 'alcada_centavos': 50000},
  );
  return s;
}

void main() {
  group('escolha da API', () {
    test('sem configuração usa os dados de exemplo', () {
      expect(criarApi(const ConfigPainel()), isA<ApiFake>());
      expect(criarApi(const ConfigPainel(modo: 'api')), isA<ApiFake>()); // faltam as URLs
    });

    test('com modo api e todos os valores usa HTTP', () {
      const c = ConfigPainel(modo: 'api', urlApi: 'https://a', urlSupabase: 'https://s', chaveAnon: 'k');
      expect(c.usaApi, isTrue);
      expect(criarApi(c), isA<ApiAdminHttp>());
    });
  });

  group('sessão', () {
    test('entra pelo Supabase, lê o papel e manda o token só no cabeçalho', () async {
      final s = servidorLogavel();
      final api = criar(s);
      final eu = await api.entrar('maria@teste.local', 'senha-de-teste');
      expect(eu.papel, Papel.mediador);
      expect(eu.alcadaCentavos, 50000);

      final login = s.chamada('POST', '/auth/v1/token');
      expect(login.url.queryParameters, {'grant_type': 'password'});
      expect(login.headers['apikey'], 'chave-publica-de-teste');

      final perfil = s.chamada('GET', '/v1/admin/eu');
      expect(perfil.headers['Authorization'], 'Bearer $_tokenDeTeste');
      for (final c in s.chamadas) {
        expect(c.url.toString().contains(_tokenDeTeste), isFalse, reason: 'token fora da URL');
      }
    });

    test('senha errada vira mensagem simples', () async {
      final s = Servidor();
      s.respostas['POST /auth/v1/token'] = (400, {'error': 'invalid_grant'});
      expect(() => criar(s).entrar('a@b.c', 'x'), throwsA(isA<ErroApi>()));
    });

    test('conta fora da equipe (403 em /eu) não fica logada', () async {
      final s = servidorLogavel();
      s.respostas['GET /v1/admin/eu'] = (403, {'detail': 'Sem papel na equipe.'});
      final api = criar(s);
      await expectLater(api.entrar('a@b.c', 'senha-de-teste'), throwsA(isA<ErroApi>()));
      expect(() => api.listarVerificacoes(), throwsA(isA<ErroApi>().having((e) => e.sessao, 'sessao', isTrue)));
    });

    test('sair apaga o token', () async {
      final s = servidorLogavel();
      final api = criar(s);
      await api.entrar('maria@teste.local', 'senha-de-teste');
      await api.sair();
      expect(() => api.listarDisputas(), throwsA(isA<ErroApi>().having((e) => e.sessao, 'sessao', isTrue)));
    });

    test('401 e 403 do backend viram erros marcados', () async {
      final s = servidorLogavel();
      final api = criar(s);
      await api.entrar('maria@teste.local', 'senha-de-teste');
      s.respostas['GET /v1/admin/pagamentos/resumo'] = (403, {'detail': 'Seu papel não vê pagamentos.'});
      await expectLater(
        api.resumoConciliacao(),
        throwsA(isA<ErroApi>().having((e) => e.proibido, 'proibido', isTrue).having((e) => e.mensagem, 'm', contains('pagamentos'))),
      );
      s.respostas['GET /v1/admin/pagamentos'] = (401, {'detail': 'x'});
      await expectLater(api.extrato(), throwsA(isA<ErroApi>().having((e) => e.sessao, 'sessao', isTrue)));
    });
  });

  group('telas ligadas à API', () {
    late Servidor s;
    late ApiAdminHttp api;

    setUp(() async {
      s = servidorLogavel(papel: 'administrador');
      api = criar(s);
      await api.entrar('maria@teste.local', 'senha-de-teste');
    });

    test('verificações: lista e URL assinada do documento', () async {
      s.respostas['GET /v1/admin/verificacoes'] = (
        200,
        {
          'itens': [
            {
              'id': 'v-1',
              'profissional_id': 'p-1',
              'profissional_nome': 'Carlos',
              'nivel_solicitado': 'basico',
              'status': 'em_analise',
              'enviada_em': '2026-10-29T12:00:00Z',
              'cpf_mascarado': '***.***.***-09',
              'documentos': [
                {'id': 'doc-1', 'tipo': 'documento_frente', 'mascarado': true},
                {'id': 'doc-2', 'tipo': 'selfie', 'mascarado': true},
              ],
            },
          ],
          'total': 1,
          'limite': 100,
          'deslocamento': 0,
        },
      );
      s.respostas['POST /v1/admin/verificacoes/v-1/documentos/doc-2/url'] = (
        200,
        {'url': 'https://storage.teste/arquivo?assinatura=1', 'expira_em_segundos': 60},
      );
      final lista = await api.listarVerificacoes();
      expect(lista.single.profissional, 'Carlos');
      expect(lista.single.status, StatusVerificacao.emAnalise);
      expect(lista.single.documentos, ['Documento frente', 'Selfie']);

      final url = await api.revelarDocumento('v-1', 'Selfie', 'Conferir a foto do cadastro');
      expect(url, contains('storage.teste'));
      expect(jsonDecode(s.chamada('POST', '/v1/admin/verificacoes/v-1/documentos/doc-2/url').body), {
        'motivo': 'Conferir a foto do cadastro',
      });

      s.respostas['POST /v1/admin/verificacoes/v-1/decisao'] = (200, {});
      await api.decidirVerificacao('v-1', aprovar: false, motivo: 'Foto ilegível');
      expect(jsonDecode(s.chamada('POST', '/v1/admin/verificacoes/v-1/decisao').body), {
        'aprovar': false,
        'motivo': 'Foto ilegível',
      });
    });

    test('disputas: mapeia detalhe, decide e aprova', () async {
      s.respostas['GET /v1/admin/disputas'] = (
        200,
        {
          'itens': [
            {'pedido_id': 'ped-1'},
          ],
        },
      );
      s.respostas['GET /v1/admin/disputas/ped-1'] = (
        200,
        {
          'pedido_id': 'ped-1',
          'estado': 'aguardando_aprovacao',
          'motivo': 'mal_feito',
          'valor_congelado_centavos': 240000,
          'decisao_ate': '2026-11-02T12:00:00Z',
          'cliente': {'id': 'c', 'nome': 'Marina'},
          'profissional': {'id': 'p', 'nome': 'Carlos'},
          'decisao': 'reembolso_total',
          'decidido_por': 'u-9',
          'divisao': {'para_profissional_centavos': 0, 'para_cliente_centavos': 240000, 'retido_centavos': 0},
          'evidencias': [
            {'origem': 'foto', 'em': '2026-10-28T10:00:00Z', 'ator_papel': 'cliente', 'dados': {'descricao': 'mancha'}},
          ],
          'linha_do_tempo': [
            {'em': '2026-10-28T10:00:00Z', 'tipo': 'disputa', 'acao': 'aberta', 'de': null, 'para': null, 'ator_papel': 'cliente'},
          ],
        },
      );
      final d = (await api.listarDisputas()).single;
      expect(d.cliente, 'Marina');
      expect(d.status, StatusDisputa.aguardandoSegundaPessoa);
      expect(d.decisao, DecisaoDisputa.reembolsoTotal);
      expect(d.valorReembolsoCentavos, 240000);
      expect(d.decididoPor, 'u-9');
      expect(d.evidencias.single.texto, 'descricao: mancha');

      s.respostas['POST /v1/admin/disputas/ped-1/decisao'] = (200, {'estado': 'aguardando_aprovacao'});
      final r = await api.decidirDisputa(
        'ped-1',
        decisao: DecisaoDisputa.reembolsoParcial,
        valorReembolsoCentavos: 5000,
        justificativa: 'Parte do serviço foi feita',
      );
      expect(r.status, StatusDisputa.aguardandoSegundaPessoa);
      expect(jsonDecode(s.chamada('POST', '/v1/admin/disputas/ped-1/decisao').body), {
        'resultado': 'reembolso_parcial',
        'justificativa': 'Parte do serviço foi feita',
        'valor_cliente_centavos': 5000,
      });

      await api.decidirDisputa('ped-1', decisao: DecisaoDisputa.novaVisita, justificativa: 'Voltar e refazer');
      expect(jsonDecode(s.chamada('POST', '/v1/admin/disputas/ped-1/decisao').body).containsKey('valor_cliente_centavos'), isFalse);

      s.respostas['POST /v1/admin/disputas/ped-1/aprovacao'] = (200, {'estado': 'decidida'});
      expect((await api.aprovarDisputa('ped-1', justificativa: 'De acordo')).status, StatusDisputa.decidida);
    });

    test('pagamentos: somente leitura, só chamadas GET', () async {
      s.respostas['GET /v1/admin/pagamentos/resumo'] = (
        200,
        {
          'confirmado_centavos': 100000,
          'estornado_centavos': 5000,
          'retido_centavos': 20000,
          'taxa_trato_centavos': 7500,
          'divergencias': 2,
          'atualizado_em': '2026-10-29T12:00:00Z',
        },
      );
      s.respostas['GET /v1/admin/pagamentos'] = (
        200,
        {
          'itens': [
            {
              'lancamento_id': 7,
              'pedido_id': 'ped-1',
              'valor_centavos': 36000,
              'estornado_centavos': 0,
              'status': 'estornado_parcial',
              'data': '2026-10-29T12:00:00Z',
              'referencia_provedor': null,
              'divergente': true,
            },
          ],
        },
      );
      final r = await api.resumoConciliacao();
      expect((r.confirmadoCentavos, r.estornadoCentavos, r.emAndamentoCentavos, r.divergencias), (100000, 5000, 20000, 2));
      final e = (await api.extrato()).single;
      expect(e.status, StatusProvedor.reembolsadoParcial);
      expect(e.divergente, isTrue);
      expect(e.refProvedor, '—');
      expect(s.chamadas.where((c) => c.url.path.contains('/pagamentos')).every((c) => c.method == 'GET'), isTrue);
    });

    test('usuários, dados pessoais e pedidos', () async {
      s.respostas['GET /v1/admin/usuarios'] = (
        200,
        {
          'itens': [
            {'id': 'u-1', 'nome': 'Marina', 'status': 'ativo', 'tipo': 'cliente'},
          ],
        },
      );
      s.respostas['POST /v1/admin/usuarios/u-1/dados-pessoais'] = (
        200,
        {'cpf': '000.000.000-00', 'telefone': '(31) 90000-0000', 'data_nascimento': '1990-01-01'},
      );
      s.respostas['GET /v1/admin/pedidos'] = (
        200,
        {
          'itens': [
            {'id': 'ped-1', 'titulo': 'Pintura', 'estado': 'em_execucao', 'cliente_nome': 'Marina', 'valor_centavos': 120000},
          ],
        },
      );
      final u = (await api.buscarUsuarios(' marina ')).single;
      expect(u.tipo, 'Cliente');
      expect(u.emailMascarado, isNull);
      expect(s.chamada('GET', '/v1/admin/usuarios').url.queryParameters['q'], 'marina');
      final d = await api.revelarDadosPessoais('u-1', 'Confirmar o contato do cliente');
      expect(d.cpf, '000.000.000-00');
      expect(d.email, isNull);
      expect(d.nascimento, '1990-01-01');
      expect((await api.buscarPedidos('')).single.status, 'em execucao');
      expect(s.chamada('GET', '/v1/admin/pedidos').url.queryParameters.containsKey('q'), isFalse);
    });

    test('categorias e chamados ainda não existem no servidor', () async {
      expect(api.listarCategorias(), throwsA(isA<ErroApi>()));
      expect(api.listarChamados(), throwsA(isA<ErroApi>()));
      expect(api.alterarCategoria('c', ativa: false, motivo: 'motivo qualquer'), throwsA(isA<ErroApi>()));
    });

    test('configuração: carrega, propõe (criar + enviar), aprova (aprovar + publicar)', () async {
      s.respostas['GET /v1/admin/config/definicoes'] = (
        200,
        [
          {'chave': 'taxa_base_bps', 'descricao': 'Taxa base', 'unidade': 'bps', 'minimo': 100, 'maximo': 2000, 'exige_dupla_aprovacao': true},
          {'chave': 'prazo', 'descricao': 'Prazo', 'unidade': 'dias_uteis', 'minimo': 1, 'maximo': 30, 'exige_dupla_aprovacao': false},
        ],
      );
      s.respostas['GET /v1/admin/config/versoes'] = (
        200,
        {
          'itens': [
            {'id': 'v2'},
          ],
        },
      );
      s.respostas['GET /v1/admin/config/versoes/v2'] = (
        200,
        {
          'id': 'v2',
          'numero': 2,
          'status': 'aguardando_aprovacao',
          'motivo': 'Ajuste',
          'criada_por': 'u-3',
          'criado_em': '2026-10-29T10:00:00Z',
          'parametros': [
            {'chave': 'taxa_base_bps', 'valor': 750, 'escopo_tipo': 'global'},
            {'chave': 'taxa_base_bps', 'valor': 900, 'escopo_tipo': 'cidade'},
          ],
        },
      );
      final c = await api.carregarConfig();
      expect(c.definicoes.last.unidade, UnidadeConfig.dias);
      expect(c.versoes.single.status, StatusVersao.aguardandoAprovacao);
      expect(c.versoes.single.valores, {'taxa_base_bps': 750});
      expect(c.versoes.single.criadaPor, 'u-3');

      s.respostas['POST /v1/admin/config/versoes'] = (201, {'id': 'v3'});
      s.respostas['POST /v1/admin/config/versoes/v3/enviar'] = (200, {});
      await api.proporConfig({'taxa_base_bps': 800}, 'Subir a taxa base');
      expect(jsonDecode(s.chamada('POST', '/v1/admin/config/versoes').body), {
        'motivo': 'Subir a taxa base',
        'partir_da_vigente': true,
        'parametros': [
          {'chave': 'taxa_base_bps', 'valor': 800},
        ],
      });
      expect(s.chamada('POST', '/v1/admin/config/versoes/v3/enviar'), isNotNull);

      s.respostas['POST /v1/admin/config/versoes/v2/aprovar'] = (200, {});
      s.respostas['POST /v1/admin/config/versoes/v2/publicar'] = (200, {});
      await api.aprovarConfig('v2', 'Aprovado pelo administrador');
      expect(s.chamadas.map((c) => c.url.path), containsAllInOrder([
        '/v1/admin/config/versoes/v2/aprovar',
        '/v1/admin/config/versoes/v2/publicar',
      ]));

      s.respostas['POST /v1/admin/config/versoes/v1/reverter'] = (201, {'id': 'v4'});
      await api.reverterConfig('v1', 'Voltar ao valor antigo');
      expect(jsonDecode(s.chamada('POST', '/v1/admin/config/versoes/v1/reverter').body), {'motivo': 'Voltar ao valor antigo'});
    });

    test('regra recusada pelo servidor chega como mensagem (422)', () async {
      s.respostas['POST /v1/admin/config/versoes'] = (422, {'detail': 'taxa_base_bps: valor fora da faixa.'});
      await expectLater(
        api.proporConfig({'taxa_base_bps': 99999}, 'Teste de limite'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'm', contains('fora da faixa'))),
      );
    });

    test('auditoria: filtros e verificação da cadeia', () async {
      s.respostas['GET /v1/admin/auditoria'] = (
        200,
        {
          'itens': [
            {
              'id': 5,
              'ocorrida_em': '2026-10-29T12:00:00Z',
              'ator_id': 'u-1',
              'ator_tipo': 'equipe',
              'acao': 'config.publicada',
              'entidade': 'config_versoes',
              'entidade_id': 'v2',
              'motivo': 'Aprovado',
            },
          ],
        },
      );
      s.respostas['POST /v1/admin/auditoria/verificar-cadeia'] = (200, {'integra': false, 'primeira_falha_id': 3});
      final lista = await api.listarAuditoria(acao: 'config.', ator: '');
      expect(lista.single.acao, 'config.publicada');
      expect(lista.single.hash, isNull);
      final q = s.chamada('GET', '/v1/admin/auditoria').url.queryParameters;
      expect(q['acao'], 'config.');
      expect(q.containsKey('ator_id'), isFalse);
      final c = await api.verificarCadeia();
      expect((c.ok, c.primeiraQuebraId), (false, 3));
    });

    test('sem internet vira mensagem simples', () async {
      final semRede = ApiAdminHttp(
        urlApi: 'https://api.teste',
        urlSupabase: 'https://sb.teste',
        chaveAnonSupabase: 'k',
        cliente: MockClient((_) async => throw http.ClientException('sem rede')),
      );
      await expectLater(
        semRede.entrar('a@b.c', 'senha-de-teste'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'm', contains('servidor'))),
      );
    });
  });
}
