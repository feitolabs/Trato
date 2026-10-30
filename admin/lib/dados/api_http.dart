import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../nucleo/papeis.dart';
import 'api_admin.dart';
import 'modelos.dart';

/// Cliente da API admin do backend (`docs/api-admin.md`).
///
/// - Login: senha no Supabase Auth (`/auth/v1/token`) com a chave pública (anon). O token fica só em
///   memória: não vai para o disco, para a URL nem para log.
/// - Cada chamada leva `Authorization: Bearer`. O backend lê o papel da tabela `equipe` e responde 401/403.
/// - Funções que o backend ainda não tem (chamados, categorias) respondem [ErroApi] em português.
class ApiAdminHttp implements ApiAdmin {
  ApiAdminHttp({
    required String urlApi,
    required String urlSupabase,
    required String chaveAnonSupabase,
    http.Client? cliente,
    this.tempoLimite = const Duration(seconds: 20),
  })  : _api = _semBarraFinal(urlApi),
        _supabase = _semBarraFinal(urlSupabase),
        _chaveAnon = chaveAnonSupabase,
        _cliente = cliente ?? http.Client();

  final String _api;
  final String _supabase;
  final String _chaveAnon;
  final http.Client _cliente;
  final Duration tempoLimite;

  String? _token;
  final _idsDocumentos = <String, String>{};

  static String _semBarraFinal(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;

  static const _semRota = 'Esta função ainda não existe no servidor.';

  // ---------- transporte ----------

  Future<_Resposta> _enviar(
    String metodo,
    Uri uri, {
    Object? corpo,
    Map<String, String> cabecalhos = const {},
  }) async {
    final pedido = http.Request(metodo, uri)
      ..headers['Accept'] = 'application/json'
      ..headers.addAll(cabecalhos);
    if (corpo != null) {
      pedido.headers['Content-Type'] = 'application/json; charset=utf-8';
      pedido.body = jsonEncode(corpo);
    }
    try {
      final r = await http.Response.fromStream(await _cliente.send(pedido).timeout(tempoLimite));
      final texto = utf8.decode(r.bodyBytes);
      Object? json;
      if (texto.isNotEmpty) {
        try {
          json = jsonDecode(texto);
        } on FormatException {
          json = null;
        }
      }
      return _Resposta(r.statusCode, json);
    } on TimeoutException {
      throw const ErroApi('O servidor demorou para responder. Tente de novo.');
    } on http.ClientException {
      throw const ErroApi('Não foi possível falar com o servidor.');
    }
  }

  Uri _uri(String caminho, [Map<String, String?> consulta = const {}]) {
    final limpa = {for (final e in consulta.entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('$_api$caminho').replace(queryParameters: limpa.isEmpty ? null : limpa);
  }

  /// Chamada autenticada. Erros viram [ErroApi] com texto para mostrar na tela.
  Future<Object?> _chamar(
    String metodo,
    String caminho, {
    Map<String, String?> consulta = const {},
    Object? corpo,
    bool aceita404 = false,
  }) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    final r = await _enviar(metodo, _uri(caminho, consulta), corpo: corpo, cabecalhos: {'Authorization': 'Bearer $token'});
    if (r.ok) return r.json;
    if (r.status == 404 && aceita404) return null;
    throw _erro(r);
  }

  ErroApi _erro(_Resposta r) {
    final detalhe = r.json is Map ? (r.json as Map)['detail'] : null;
    final texto = detalhe is String ? detalhe : null;
    switch (r.status) {
      case 401:
        _token = null;
        return const ErroApi('Sua sessão acabou. Entre de novo.', sessao: true);
      case 403:
        return ErroApi(texto ?? 'Seu papel não pode fazer isso.', proibido: true);
      case 404:
        return ErroApi(texto ?? 'Não encontrado.');
      case 422:
        return ErroApi(texto ?? 'Confira os campos: algum valor não foi aceito.');
      case 503:
        return ErroApi(texto ?? 'Este recurso ainda não está configurado no servidor.');
      default:
        return ErroApi(texto ?? 'Algo deu errado no servidor (${r.status}).');
    }
  }

  // ---------- leitura de JSON ----------

  static Map<String, dynamic> _mapa(Object? o) => (o as Map).cast<String, dynamic>();

  static List<Map<String, dynamic>> _itens(Object? corpo) {
    final lista = corpo is Map ? corpo['itens'] : corpo;
    return [for (final e in (lista as List? ?? const [])) _mapa(e)];
  }

  static DateTime _data(Object? o) => DateTime.parse(o as String).toLocal();

  static int _int(Object? o) => (o as num?)?.toInt() ?? 0;

  // ---------- sessão ----------

  @override
  Future<UsuarioEquipe> entrar(String email, String senha) async {
    final r = await _enviar(
      'POST',
      Uri.parse('$_supabase/auth/v1/token').replace(queryParameters: {'grant_type': 'password'}),
      corpo: {'email': email.trim(), 'password': senha},
      cabecalhos: {'apikey': _chaveAnon},
    );
    final token = r.json is Map ? (r.json as Map)['access_token'] : null;
    if (!r.ok || token is! String) {
      throw const ErroApi('E-mail ou senha incorretos.');
    }
    _token = token;
    try {
      // Rota que o backend ainda precisa expor: ver docs/painel-admin.md ("GET /v1/admin/eu").
      final eu = _mapa(await _chamar('GET', '/v1/admin/eu'));
      final papel = Papel.doCodigo(eu['papel'] as String? ?? '');
      if (papel == null) throw const ErroApi('Esta conta não tem papel na equipe.', proibido: true);
      return UsuarioEquipe(
        id: eu['id'] as String,
        nome: (eu['nome'] as String?) ?? papel.rotulo,
        email: (eu['email'] as String?) ?? email.trim(),
        papel: papel,
        alcadaCentavos: _int(eu['alcada_centavos']),
      );
    } catch (_) {
      _token = null;
      rethrow;
    }
  }

  @override
  Future<void> sair() async {
    _token = null;
    _idsDocumentos.clear();
  }

  // ---------- F7.1 verificação ----------

  static const _statusVerificacao = {
    'enviada': StatusVerificacao.enviada,
    'em_analise': StatusVerificacao.emAnalise,
    'aprovada': StatusVerificacao.aprovada,
    'recusada': StatusVerificacao.recusada,
  };

  @override
  Future<List<Verificacao>> listarVerificacoes() async {
    final corpo = await _chamar('GET', '/v1/admin/verificacoes', consulta: {'limite': '100'});
    return [
      for (final v in _itens(corpo))
        () {
          final rotulos = <String>[];
          for (final d in (v['documentos'] as List? ?? const [])) {
            final doc = _mapa(d);
            var rotulo = _rotuloDocumento(doc['tipo'] as String? ?? 'Documento');
            if (rotulos.contains(rotulo)) rotulo = '$rotulo (${rotulos.length + 1})';
            rotulos.add(rotulo);
            _idsDocumentos['${v['id']}|$rotulo'] = doc['id'] as String;
          }
          return Verificacao(
            id: v['id'] as String,
            profissional: (v['profissional_nome'] as String?) ?? 'Profissional',
            categoria: 'Nível ${v['nivel_solicitado'] ?? '-'}',
            cidade: '',
            enviadaEm: _data(v['enviada_em']),
            cpfMascarado: (v['cpf_mascarado'] as String?) ?? '—',
            documentos: rotulos,
            status: _statusVerificacao[v['status']] ?? StatusVerificacao.enviada,
            motivoDecisao: v['motivo_recusa'] as String?,
          );
        }(),
    ];
  }

  static String _rotuloDocumento(String tipo) {
    final t = tipo.replaceAll('_', ' ');
    return t.isEmpty ? 'Documento' : '${t[0].toUpperCase()}${t.substring(1)}';
  }

  @override
  Future<String?> revelarDocumento(String verificacaoId, String documento, String motivo) async {
    final id = _idsDocumentos['$verificacaoId|$documento'];
    if (id == null) throw const ErroApi('Documento não encontrado. Atualize a lista.');
    final corpo = _mapa(await _chamar(
      'POST',
      '/v1/admin/verificacoes/$verificacaoId/documentos/$id/url',
      corpo: {'motivo': motivo},
    ));
    return corpo['url'] as String?;
  }

  @override
  Future<void> decidirVerificacao(String id, {required bool aprovar, required String motivo}) async {
    await _chamar('POST', '/v1/admin/verificacoes/$id/decisao', corpo: {'aprovar': aprovar, 'motivo': motivo});
  }

  // ---------- F7.2 disputas ----------

  static const _estadoDisputa = {
    'aberta': StatusDisputa.aberta,
    'em_analise': StatusDisputa.emAnalise,
    'aguardando_aprovacao': StatusDisputa.aguardandoSegundaPessoa,
    'decidida': StatusDisputa.decidida,
  };

  @override
  Future<List<Disputa>> listarDisputas() async {
    final corpo = await _chamar('GET', '/v1/admin/disputas', consulta: {'limite': '100'});
    final ids = [for (final d in _itens(corpo)) d['pedido_id'] as String];
    return Future.wait([for (final id in ids) _detalheDisputa(id)]);
  }

  Future<Disputa> _detalheDisputa(String pedidoId) async =>
      _disputa(_mapa(await _chamar('GET', '/v1/admin/disputas/$pedidoId')));

  Disputa _disputa(Map<String, dynamic> d) {
    final decisao = DecisaoDisputa.values.where((x) => x.codigo == d['decisao']).firstOrNull;
    final divisao = d['divisao'] is Map ? _mapa(d['divisao']) : null;
    final motivo = (d['motivo'] as String?) ?? '';
    return Disputa(
      id: d['pedido_id'] as String,
      pedido: d['pedido_id'] as String,
      cliente: (d['cliente'] is Map ? _mapa(d['cliente'])['nome'] as String? : null) ?? 'Cliente',
      profissional: (d['profissional'] is Map ? _mapa(d['profissional'])['nome'] as String? : null) ?? 'Profissional',
      motivo: motivo,
      descricao: motivo,
      valorEmAnaliseCentavos: _int(d['valor_congelado_centavos']),
      decisaoAte: _data(d['decisao_ate']),
      status: _estadoDisputa[d['estado']] ?? StatusDisputa.emAnalise,
      decisao: decisao,
      valorReembolsoCentavos: divisao == null ? null : _int(divisao['para_cliente_centavos']),
      decididoPor: d['decidido_por'] as String?,
      evidencias: [
        for (final e in (d['evidencias'] as List? ?? const []))
          EvidenciaDisputa(
            autor: (_mapa(e)['ator_papel'] as String?) ?? '—',
            tipo: (_mapa(e)['origem'] as String?) ?? 'prova',
            texto: _texto(_mapa(e)['dados']),
          ),
      ],
      linhaDoTempo: [
        for (final e in (d['linha_do_tempo'] as List? ?? const []))
          EventoDisputa(
            _data(_mapa(e)['em']),
            (_mapa(e)['ator_papel'] as String?) ?? 'sistema',
            '${_mapa(e)['acao']}${_mapa(e)['de'] != null ? ': ${_mapa(e)['de']} → ${_mapa(e)['para']}' : ''}',
          ),
      ],
    );
  }

  static String _texto(Object? dados) {
    if (dados is Map) {
      return dados.entries.where((e) => e.value != null).map((e) => '${e.key}: ${e.value}').join(' · ');
    }
    return dados?.toString() ?? '';
  }

  @override
  Future<ResultadoDecisao> decidirDisputa(
    String id, {
    required DecisaoDisputa decisao,
    int? valorReembolsoCentavos,
    required String justificativa,
  }) async {
    final corpo = await _chamar('POST', '/v1/admin/disputas/$id/decisao', corpo: {
      'resultado': decisao.codigo,
      'justificativa': justificativa,
      if (decisao == DecisaoDisputa.reembolsoParcial) 'valor_cliente_centavos': valorReembolsoCentavos,
    });
    return _resultado(corpo);
  }

  @override
  Future<ResultadoDecisao> aprovarDisputa(String id, {required String justificativa}) async =>
      _resultado(await _chamar('POST', '/v1/admin/disputas/$id/aprovacao', corpo: {'justificativa': justificativa}));

  ResultadoDecisao _resultado(Object? corpo) {
    final estado = _estadoDisputa[_mapa(corpo)['estado']] ?? StatusDisputa.emAnalise;
    return ResultadoDecisao(
      status: estado,
      mensagem: estado == StatusDisputa.aguardandoSegundaPessoa
          ? 'Acima da alçada: aguarda a aprovação de outra pessoa.'
          : 'Decisão registrada.',
    );
  }

  // ---------- F7.3 pagamentos ----------

  @override
  Future<ResumoConciliacao> resumoConciliacao() async {
    final r = _mapa(await _chamar('GET', '/v1/admin/pagamentos/resumo'));
    return ResumoConciliacao(
      confirmadoCentavos: _int(r['confirmado_centavos']),
      estornadoCentavos: _int(r['estornado_centavos']),
      emAndamentoCentavos: _int(r['retido_centavos']),
      divergencias: _int(r['divergencias']),
      atualizadoEm: _data(r['atualizado_em']),
    );
  }

  static const _statusPagamento = {
    'confirmado': StatusProvedor.confirmado,
    'estornado': StatusProvedor.reembolsado,
    'estornado_parcial': StatusProvedor.reembolsadoParcial,
  };

  @override
  Future<List<LancamentoEspelho>> extrato() async {
    final corpo = await _chamar('GET', '/v1/admin/pagamentos', consulta: {'limite': '100'});
    return [
      for (final p in _itens(corpo))
        LancamentoEspelho(
          id: p['lancamento_id'].toString(),
          data: _data(p['data']),
          descricao: 'Cobrança do pedido',
          valorCentavos: _int(p['valor_centavos']),
          status: _statusPagamento[p['status']] ?? StatusProvedor.aguardandoConfirmacao,
          pedido: (p['pedido_id'] as String?) ?? '—',
          refProvedor: (p['referencia_provedor'] as String?) ?? '—',
          divergente: p['divergente'] == true,
        ),
    ];
  }

  // ---------- F7.4 busca ----------

  @override
  Future<List<UsuarioBusca>> buscarUsuarios(String termo) async {
    final corpo = await _chamar('GET', '/v1/admin/usuarios', consulta: {'q': termo.trim(), 'limite': '100'});
    return [
      for (final u in _itens(corpo))
        UsuarioBusca(
          id: u['id'] as String,
          nome: (u['nome'] as String?) ?? '—',
          tipo: switch (u['tipo']) {
            'cliente' => 'Cliente',
            'profissional' => 'Profissional',
            'equipe' => 'Equipe',
            final outro => '$outro',
          },
          status: (u['status'] as String?) ?? '—',
        ),
    ];
  }

  @override
  Future<DadosPessoais> revelarDadosPessoais(String usuarioId, String motivo) async {
    final d = _mapa(await _chamar('POST', '/v1/admin/usuarios/$usuarioId/dados-pessoais', corpo: {'motivo': motivo}));
    return DadosPessoais(
      cpf: (d['cpf'] as String?) ?? '—',
      telefone: (d['telefone'] as String?) ?? '—',
      nascimento: d['data_nascimento'] as String?,
    );
  }

  @override
  Future<List<PedidoBusca>> buscarPedidos(String termo) async {
    final corpo = await _chamar('GET', '/v1/admin/pedidos', consulta: {'q': termo.trim(), 'limite': '100'});
    return [
      for (final p in _itens(corpo))
        PedidoBusca(
          id: p['id'] as String,
          titulo: (p['titulo'] as String?) ?? 'Pedido',
          cliente: (p['cliente_nome'] as String?) ?? '—',
          status: ((p['estado'] as String?) ?? '').replaceAll('_', ' '),
          valorCentavos: _int(p['valor_centavos']),
        ),
    ];
  }

  @override
  Future<List<Chamado>> listarChamados() => Future.error(const ErroApi(_semRota));

  @override
  Future<List<CategoriaAdmin>> listarCategorias() => Future.error(const ErroApi(_semRota));

  @override
  Future<void> alterarCategoria(String id, {required bool ativa, required String motivo}) =>
      Future.error(const ErroApi(_semRota));

  // ---------- F7.5 configurações ----------

  static const _statusVersao = {
    'rascunho': StatusVersao.rascunho,
    'aguardando_aprovacao': StatusVersao.aguardandoAprovacao,
    'aprovada': StatusVersao.aprovada,
    'vigente': StatusVersao.vigente,
    'substituida': StatusVersao.substituida,
    'revertida': StatusVersao.revertida,
  };

  @override
  Future<ConfigAtual> carregarConfig() async {
    final defs = _itens(await _chamar('GET', '/v1/admin/config/definicoes'));
    final lista = _itens(await _chamar('GET', '/v1/admin/config/versoes', consulta: {'limite': '10'}));
    final versoes = await Future.wait([
      for (final v in lista)
        () async {
          // A lista não traz os itens; o detalhe traz.
          final d = _mapa(await _chamar('GET', '/v1/admin/config/versoes/${v['id']}'));
          return _versao(d);
        }(),
    ]);
    return ConfigAtual(
      definicoes: [
        for (final d in defs)
          ConfigDefinicao(
            chave: d['chave'] as String,
            descricao: (d['descricao'] as String?) ?? d['chave'] as String,
            unidade: UnidadeConfig.values.where((u) => u.codigo == d['unidade']).firstOrNull ??
                (d['unidade'] == 'dias_uteis' ? UnidadeConfig.dias : UnidadeConfig.quantidade),
            minimo: _int(d['minimo']),
            maximo: _int(d['maximo']),
            exigeDuplaAprovacao: d['exige_dupla_aprovacao'] == true,
          ),
      ],
      versoes: versoes,
    );
  }

  ConfigVersao _versao(Map<String, dynamic> v) {
    final valores = <String, int>{};
    for (final p in (v['parametros'] as List? ?? const [])) {
      final m = _mapa(p);
      final escopo = m['escopo_tipo'];
      if (escopo == null || escopo == 'global') valores[m['chave'] as String] = _int(m['valor']);
    }
    return ConfigVersao(
      id: v['id'] as String,
      numero: _int(v['numero']),
      status: _statusVersao[v['status']] ?? StatusVersao.rascunho,
      motivo: (v['motivo'] as String?) ?? '',
      criadaPor: (v['criada_por'] as String?) ?? '',
      criadaEm: _data(v['criado_em']),
      aprovadaPor: v['aprovada_por'] as String?,
      valores: valores,
    );
  }

  @override
  Future<void> proporConfig(Map<String, int> valores, String motivo) async {
    final criada = _mapa(await _chamar('POST', '/v1/admin/config/versoes', corpo: {
      'motivo': motivo,
      'partir_da_vigente': true,
      'parametros': [for (final e in valores.entries) {'chave': e.key, 'valor': e.value}],
    }));
    await _chamar('POST', '/v1/admin/config/versoes/${criada['id']}/enviar', corpo: {'motivo': motivo});
  }

  @override
  Future<void> aprovarConfig(String versaoId, String motivo) async {
    await _chamar('POST', '/v1/admin/config/versoes/$versaoId/aprovar', corpo: {'motivo': motivo});
    await publicarConfig(versaoId, motivo);
  }

  @override
  Future<void> publicarConfig(String versaoId, String motivo) async {
    await _chamar('POST', '/v1/admin/config/versoes/$versaoId/publicar', corpo: {'motivo': motivo});
  }

  @override
  Future<void> reverterConfig(String versaoId, String motivo) async {
    await _chamar('POST', '/v1/admin/config/versoes/$versaoId/reverter', corpo: {'motivo': motivo});
  }

  // ---------- F7.6 auditoria ----------

  @override
  Future<List<EntradaAuditoria>> listarAuditoria({String? acao, String? ator}) async {
    final corpo = await _chamar('GET', '/v1/admin/auditoria', consulta: {
      'acao': acao?.trim(),
      'ator_id': ator?.trim(),
      'limite': '100',
    });
    return [
      for (final e in _itens(corpo))
        EntradaAuditoria(
          id: _int(e['id']),
          ocorridaEm: _data(e['ocorrida_em']),
          ator: (e['ator_id'] as String?) ?? (e['ator_tipo'] as String?) ?? 'sistema',
          acao: (e['acao'] as String?) ?? '—',
          entidade: [e['entidade'], e['entidade_id']].where((x) => x != null).join(':'),
          motivo: e['motivo'] as String?,
        ),
    ];
  }

  @override
  Future<ResultadoCadeia> verificarCadeia() async {
    final r = _mapa(await _chamar('POST', '/v1/admin/auditoria/verificar-cadeia'));
    return ResultadoCadeia(ok: r['integra'] == true, primeiraQuebraId: (r['primeira_falha_id'] as num?)?.toInt());
  }
}

class _Resposta {
  const _Resposta(this.status, this.json);
  final int status;
  final Object? json;
  bool get ok => status >= 200 && status < 300;
}
