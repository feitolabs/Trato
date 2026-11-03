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
    int maxTentativas = 3,
  }) async {
    final ehIdempotente = metodo == 'GET' || metodo == 'HEAD';
    final limiteTentativas = ehIdempotente ? maxTentativas : 1;

    for (var tentativa = 1; tentativa <= limiteTentativas; tentativa++) {
      final pedido = http.Request(metodo, uri)
        ..headers['Accept'] = 'application/json'
        ..headers.addAll(cabecalhos);
      if (corpo != null) {
        pedido.headers['Content-Type'] = 'application/json; charset=utf-8';
        pedido.body = jsonEncode(corpo);
      }
      try {
        final r = await http.Response.fromStream(await _cliente.send(pedido).timeout(tempoLimite));
        if (ehIdempotente &&
            (r.statusCode == 502 || r.statusCode == 503 || r.statusCode == 504) &&
            tentativa < limiteTentativas) {
          await Future<void>.delayed(Duration(milliseconds: 250 * tentativa));
          continue;
        }
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
        if (tentativa < limiteTentativas) {
          await Future<void>.delayed(Duration(milliseconds: 250 * tentativa));
          continue;
        }
        throw const ErroApi('O servidor demorou para responder. Tente de novo.');
      } on http.ClientException {
        if (tentativa < limiteTentativas) {
          await Future<void>.delayed(Duration(milliseconds: 250 * tentativa));
          continue;
        }
        throw const ErroApi('Não foi possível falar com o servidor.');
      }
    }
    throw const ErroApi('Não foi possível falar com o servidor.');
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
  Future<void> alterarStatusUsuario(String usuarioId, {required String status, required String motivo}) async {
    await _chamar(
      'POST',
      '/v1/admin/usuarios/$usuarioId/status',
      corpo: {'status': status, 'motivo': motivo},
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
  Future<List<Chamado>> listarChamados() async {
    final corpo = await _chamar('GET', '/v1/admin/chamados');
    final itens = _itens(corpo);
    return [
      for (final c in itens)
        Chamado(
          id: c['id'] as String,
          assunto: c['assunto'] as String,
          solicitante: c['solicitante'] as String,
          status: c['status'] as String,
          aberto: _data(c['aberto_em'] ?? c['aberto']),
        ),
    ];
  }

  @override
  Future<List<CategoriaAdmin>> listarCategorias() async {
    final corpo = await _chamar('GET', '/v1/admin/categorias');
    final itens = _itens(corpo);
    return [
      for (final c in itens)
        CategoriaAdmin(
          id: c['id'] as String,
          nome: c['nome'] as String,
          ativa: c['ativa'] as bool? ?? true,
          profissionais: _int(c['profissionais']),
        ),
    ];
  }

  @override
  Future<void> alterarCategoria(String id, {required bool ativa, required String motivo}) async {
    await _chamar(
      'PATCH',
      '/v1/admin/categorias/$id',
      corpo: {'ativa': ativa, 'motivo': motivo},
    );
  }

  @override
  Future<CategoriaAdmin> criarCategoria({
    required String nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int ordem = 0,
    bool ativa = true,
    required String motivo,
  }) async {
    final r = _mapa(await _chamar(
      'POST',
      '/v1/admin/categorias',
      corpo: {
        'nome': nome,
        'slug': slug,
        'icone': icone,
        'garantia_retrabalho_dias': garantiaDias,
        'ordem': ordem,
        'ativa': ativa,
        'motivo': motivo,
      },
    ));
    return CategoriaAdmin(
      id: r['id'] as String,
      nome: r['nome'] as String,
      slug: (r['slug'] as String?) ?? '',
      icone: r['icone'] as String?,
      garantiaDias: r['garantia_retrabalho_dias'] as int?,
      ordem: _int(r['ordem']),
      ativa: r['ativa'] as bool? ?? true,
      profissionais: _int(r['profissionais']),
    );
  }

  @override
  Future<CategoriaAdmin> editarCategoria(
    String id, {
    String? nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int? ordem,
    bool? ativa,
    required String motivo,
  }) async {
    final r = _mapa(await _chamar(
      'PUT',
      '/v1/admin/categorias/$id',
      corpo: {
        if (nome != null) 'nome': nome,
        if (slug != null) 'slug': slug,
        if (icone != null) 'icone': icone,
        if (garantiaDias != null) 'garantia_retrabalho_dias': garantiaDias,
        if (ordem != null) 'ordem': ordem,
        if (ativa != null) 'ativa': ativa,
        'motivo': motivo,
      },
    ));
    return CategoriaAdmin(
      id: r['id'] as String,
      nome: r['nome'] as String,
      slug: (r['slug'] as String?) ?? '',
      icone: r['icone'] as String?,
      garantiaDias: r['garantia_retrabalho_dias'] as int?,
      ordem: _int(r['ordem']),
      ativa: r['ativa'] as bool? ?? true,
      profissionais: _int(r['profissionais']),
    );
  }

  @override
  Future<void> excluirCategoria(String id, {required String motivo}) async {
    await _chamar(
      'DELETE',
      '/v1/admin/categorias/$id',
      consulta: {'motivo': motivo},
    );
  }

  @override
  Future<List<CidadeAdmin>> listarCidades() async {
    final corpo = await _chamar('GET', '/v1/admin/cidades');
    final itens = _itens(corpo);
    return [
      for (final c in itens)
        CidadeAdmin(
          id: c['id'] as String,
          nome: c['nome'] as String,
          uf: c['uf'] as String,
          ativa: c['ativa'] as bool? ?? true,
          centroLat: (c['centro_lat'] as num?)?.toDouble(),
          centroLng: (c['centro_lng'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<CidadeAdmin> criarCidade({
    required String nome,
    required String uf,
    bool ativa = true,
    double? centroLat,
    double? centroLng,
    required String motivo,
  }) async {
    final r = _mapa(await _chamar(
      'POST',
      '/v1/admin/cidades',
      corpo: {
        'nome': nome,
        'uf': uf,
        'ativa': ativa,
        'centro_lat': centroLat,
        'centro_lng': centroLng,
        'motivo': motivo,
      },
    ));
    return CidadeAdmin(
      id: r['id'] as String,
      nome: r['nome'] as String,
      uf: r['uf'] as String,
      ativa: r['ativa'] as bool? ?? true,
      centroLat: (r['centro_lat'] as num?)?.toDouble(),
      centroLng: (r['centro_lng'] as num?)?.toDouble(),
    );
  }

  @override
  Future<void> alterarCidade(String id, {required bool ativa, required String motivo}) async {
    await _chamar(
      'PATCH',
      '/v1/admin/cidades/$id',
      corpo: {'ativa': ativa, 'motivo': motivo},
    );
  }

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

  // ---------- Módulo 1: Dashboard ----------

  @override
  Future<MetricasDashboard> metricasDashboard() async {
    final m = _mapa(await _chamar('GET', '/v1/admin/dashboard/metricas'));
    return MetricasDashboard(
      gmvCentavos: _int(m['gmv_centavos']),
      receitaTaxaCentavos: _int(m['receita_taxa_centavos']),
      pedidosTotal: _int(m['pedidos_total']),
      pedidosConcluidos: _int(m['pedidos_concluidos']),
      pedidosEmAndamento: _int(m['pedidos_em_andamento']),
      pedidosAbertos: _int(m['pedidos_abertos']),
      pedidosDisputa: _int(m['pedidos_disputa']),
      clientesTotal: _int(m['clientes_total']),
      profissionaisTotal: _int(m['profissionais_total']),
      profissionaisPendentes: _int(m['profissionais_pendentes']),
      cidadesAtivas: _int(m['cidades_ativas']),
      categoriasAtivas: _int(m['categorias_ativas']),
    );
  }

  @override
  Future<SeriesDashboard> seriesDashboard({int dias = 7}) async {
    final m = _mapa(await _chamar('GET', '/v1/admin/dashboard/series', consulta: {'dias': '$dias'}));
    final hist = (m['historico_dias'] as List<dynamic>? ?? []);
    final funil = (m['funil'] as List<dynamic>? ?? []);
    return SeriesDashboard(
      historicoDias: [
        for (final p in hist)
          PontoSerieDashboard(
            data: p['data'] as String? ?? '',
            pedidos: _int(p['pedidos']),
            gmvCentavos: _int(p['gmv_centavos']),
          ),
      ],
      funil: [
        for (final f in funil)
          EtapaFunilDashboard(
            etapa: f['etapa'] as String? ?? '',
            quantidade: _int(f['quantidade']),
            taxaConversaoPct: (f['taxa_conversao_pct'] as num?)?.toDouble() ?? 0.0,
          ),
      ],
    );
  }

  // ---------- Módulo 2: Perguntas Dinâmicas da Categoria ----------

  @override
  Future<List<PerguntaCategoriaAdmin>> listarPerguntasCategoria(String categoriaId) async {
    final itens = _itens(await _chamar('GET', '/v1/admin/categorias/$categoriaId/perguntas'));
    return [
      for (final p in itens)
        PerguntaCategoriaAdmin(
          id: p['id'] as String,
          categoriaId: p['categoria_id'] as String,
          texto: p['texto'] as String,
          tipo: p['tipo'] as String,
          opcoes: (p['opcoes'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
          obrigatoria: p['obrigatoria'] as bool? ?? false,
          ordem: _int(p['ordem']),
          ativa: p['ativa'] as bool? ?? true,
        ),
    ];
  }

  @override
  Future<PerguntaCategoriaAdmin> criarPerguntaCategoria(
    String categoriaId, {
    required String texto,
    required String tipo,
    List<String>? opcoes,
    bool obrigatoria = false,
    int ordem = 0,
    required String motivo,
  }) async {
    final p = _mapa(await _chamar(
      'POST',
      '/v1/admin/categorias/$categoriaId/perguntas',
      corpo: {
        'texto': texto,
        'tipo': tipo,
        if (opcoes != null) 'opcoes': opcoes,
        'obrigatoria': obrigatoria,
        'ordem': ordem,
        'motivo': motivo,
      },
    ));
    return PerguntaCategoriaAdmin(
      id: p['id'] as String,
      categoriaId: p['categoria_id'] as String,
      texto: p['texto'] as String,
      tipo: p['tipo'] as String,
      opcoes: (p['opcoes'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      obrigatoria: p['obrigatoria'] as bool? ?? false,
      ordem: _int(p['ordem']),
      ativa: p['ativa'] as bool? ?? true,
    );
  }

  @override
  Future<PerguntaCategoriaAdmin> editarPerguntaCategoria(
    String categoriaId,
    String perguntaId, {
    String? texto,
    String? tipo,
    List<String>? opcoes,
    bool? obrigatoria,
    int? ordem,
    bool? ativa,
    required String motivo,
  }) async {
    final p = _mapa(await _chamar(
      'PUT',
      '/v1/admin/categorias/$categoriaId/perguntas/$perguntaId',
      corpo: {
        if (texto != null) 'texto': texto,
        if (tipo != null) 'tipo': tipo,
        if (opcoes != null) 'opcoes': opcoes,
        if (obrigatoria != null) 'obrigatoria': obrigatoria,
        if (ordem != null) 'ordem': ordem,
        if (ativa != null) 'ativa': ativa,
        'motivo': motivo,
      },
    ));
    return PerguntaCategoriaAdmin(
      id: p['id'] as String,
      categoriaId: p['categoria_id'] as String,
      texto: p['texto'] as String,
      tipo: p['tipo'] as String,
      opcoes: (p['opcoes'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      obrigatoria: p['obrigatoria'] as bool? ?? false,
      ordem: _int(p['ordem']),
      ativa: p['ativa'] as bool? ?? true,
    );
  }

  @override
  Future<void> desativarPerguntaCategoria(String categoriaId, String perguntaId, {required String motivo}) async {
    await _chamar('DELETE', '/v1/admin/categorias/$categoriaId/perguntas/$perguntaId', consulta: {'motivo': motivo});
  }

  // ---------- Módulo 3: Central Antifraude e Risco ----------

  @override
  Future<List<AlertaRisco>> listarAlertasRisco() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/risco/alertas'));
    return [
      for (final a in itens)
        AlertaRisco(
          id: a['id'] as String,
          usuarioId: a['usuario_id'] as String?,
          usuarioNome: a['usuario_nome'] as String?,
          tipo: a['tipo'] as String,
          severidade: a['severidade'] as String,
          detalhes: a['detalhes'] as String,
          resolvido: a['resolvido'] as bool? ?? false,
          criadoEm: a['criado_em'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<void> aplicarBloqueioPreventivo(String usuarioId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/bloqueio-preventivo', corpo: {'usuario_id': usuarioId, 'motivo': motivo});
  }

  @override
  Future<void> travarSaque(String usuarioId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/travar-saque', corpo: {'usuario_id': usuarioId, 'motivo': motivo});
  }

  @override
  Future<void> resolverAlertaRisco(String alertaId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/alertas/$alertaId/resolver', corpo: {'motivo': motivo});
  }

  // ---------- Módulo 4: Notificações em Massa & Campanhas ----------

  @override
  Future<List<CampanhaNotificacao>> listarCampanhasNotificacao() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/notificacoes/campanhas'));
    return [
      for (final c in itens)
        CampanhaNotificacao(
          id: c['id'] as String,
          titulo: c['titulo'] as String,
          mensagem: c['mensagem'] as String,
          segmento: c['segmento'] as String,
          categoriaId: c['categoria_id'] as String?,
          cidadeId: c['cidade_id'] as String?,
          totalDestinatarios: _int(c['total_destinatarios']),
          criadoEm: c['criado_em'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<CampanhaNotificacao> dispararCampanhaNotificacao({
    required String titulo,
    required String mensagem,
    required String segmento,
    String? categoriaId,
    String? cidadeId,
    required String motivo,
  }) async {
    final c = _mapa(await _chamar(
      'POST',
      '/v1/admin/notificacoes/disparar',
      corpo: {
        'titulo': titulo,
        'mensagem': mensagem,
        'segmento': segmento,
        if (categoriaId != null) 'categoria_id': categoriaId,
        if (cidadeId != null) 'cidade_id': cidadeId,
        'motivo': motivo,
      },
    ));
    return CampanhaNotificacao(
      id: c['id'] as String,
      titulo: c['titulo'] as String,
      mensagem: c['mensagem'] as String,
      segmento: c['segmento'] as String,
      categoriaId: c['categoria_id'] as String?,
      cidadeId: c['cidade_id'] as String?,
      totalDestinatarios: _int(c['total_destinatarios']),
      criadoEm: c['criado_em'] as String? ?? '',
    );
  }

  // ---------- Módulo 5: Gestão de Cupons ----------

  @override
  Future<List<CupomAdmin>> listarCupons() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/cupons'));
    return [
      for (final c in itens)
        CupomAdmin(
          id: c['id'] as String,
          codigo: c['codigo'] as String,
          tipo: c['tipo'] as String,
          valor: _int(c['valor']),
          valorMinimoCentavos: _int(c['valor_minimo_centavos']),
          limiteUsos: c['limite_usos'] != null ? _int(c['limite_usos']) : null,
          usosAtuais: _int(c['usos_atuais']),
          validoAte: c['valido_ate'] as String?,
          ativo: c['ativo'] as bool? ?? true,
          criadoEm: c['criado_em'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<CupomAdmin> criarCupom({
    required String codigo,
    required String tipo,
    required int valor,
    int valorMinimoCentavos = 0,
    int? limiteUsos,
    String? validoAte,
    required String motivo,
  }) async {
    final c = _mapa(await _chamar(
      'POST',
      '/v1/admin/cupons',
      corpo: {
        'codigo': codigo,
        'tipo': tipo,
        'valor': valor,
        'valor_minimo_centavos': valorMinimoCentavos,
        if (limiteUsos != null) 'limite_usos': limiteUsos,
        if (validoAte != null) 'valido_ate': validoAte,
        'motivo': motivo,
      },
    ));
    return CupomAdmin(
      id: c['id'] as String,
      codigo: c['codigo'] as String,
      tipo: c['tipo'] as String,
      valor: _int(c['valor']),
      valorMinimoCentavos: _int(c['valor_minimo_centavos']),
      limiteUsos: c['limite_usos'] != null ? _int(c['limite_usos']) : null,
      usosAtuais: _int(c['usos_atuais']),
      validoAte: c['valido_ate'] as String?,
      ativo: c['ativo'] as bool? ?? true,
      criadoEm: c['criado_em'] as String? ?? '',
    );
  }

  @override
  Future<CupomAdmin> alterarStatusCupom(String cupomId, {required bool ativo, required String motivo}) async {
    final c = _mapa(await _chamar(
      'PATCH',
      '/v1/admin/cupons/$cupomId/status',
      corpo: {'ativo': ativo, 'motivo': motivo},
    ));
    return CupomAdmin(
      id: c['id'] as String,
      codigo: c['codigo'] as String,
      tipo: c['tipo'] as String,
      valor: _int(c['valor']),
      valorMinimoCentavos: _int(c['valor_minimo_centavos']),
      limiteUsos: c['limite_usos'] != null ? _int(c['limite_usos']) : null,
      usosAtuais: _int(c['usos_atuais']),
      validoAte: c['valido_ate'] as String?,
      ativo: c['ativo'] as bool? ?? true,
      criadoEm: c['criado_em'] as String? ?? '',
    );
  }

  @override
  Future<void> excluirCupom(String cupomId, {required String motivo}) async {
    await _chamar('DELETE', '/v1/admin/cupons/$cupomId', consulta: {'motivo': motivo});
  }

  // ---------- Módulo 6: Equipe Interna ----------

  @override
  Future<List<MembroEquipeAdmin>> listarEquipe() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/equipe'));
    return [
      for (final m in itens)
        MembroEquipeAdmin(
          usuarioId: m['usuario_id'] as String,
          nome: m['nome'] as String,
          email: m['email'] as String,
          papel: m['papel'] as String,
          ativo: m['ativo'] as bool? ?? true,
          alcadaCentavos: _int(m['alcada_centavos']),
          criadoEm: m['criado_em'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<MembroEquipeAdmin> adicionarMembroEquipe({
    required String nome,
    required String email,
    required String papel,
    int alcadaCentavos = 0,
    required String motivo,
  }) async {
    final m = _mapa(await _chamar(
      'POST',
      '/v1/admin/equipe',
      corpo: {
        'nome': nome,
        'email': email,
        'papel': papel,
        'alcada_centavos': alcadaCentavos,
        'motivo': motivo,
      },
    ));
    return MembroEquipeAdmin(
      usuarioId: m['usuario_id'] as String,
      nome: m['nome'] as String,
      email: m['email'] as String,
      papel: m['papel'] as String,
      ativo: m['ativo'] as bool? ?? true,
      alcadaCentavos: _int(m['alcada_centavos']),
      criadoEm: m['criado_em'] as String? ?? '',
    );
  }

  @override
  Future<MembroEquipeAdmin> editarMembroEquipe(
    String usuarioId, {
    String? papel,
    int? alcadaCentavos,
    bool? ativo,
    required String motivo,
  }) async {
    final m = _mapa(await _chamar(
      'PATCH',
      '/v1/admin/equipe/$usuarioId',
      corpo: {
        if (papel != null) 'papel': papel,
        if (alcadaCentavos != null) 'alcada_centavos': alcadaCentavos,
        if (ativo != null) 'ativo': ativo,
        'motivo': motivo,
      },
    ));
    return MembroEquipeAdmin(
      usuarioId: m['usuario_id'] as String,
      nome: m['nome'] as String,
      email: m['email'] as String,
      papel: m['papel'] as String,
      ativo: m['ativo'] as bool? ?? true,
      alcadaCentavos: _int(m['alcada_centavos']),
      criadoEm: m['criado_em'] as String? ?? '',
    );
  }

  @override
  Future<void> revogarMembroEquipe(String usuarioId, {required String motivo}) async {
    await _chamar('DELETE', '/v1/admin/equipe/$usuarioId', consulta: {'motivo': motivo});
  }

  // ---------- Módulo 7: Exportação de Relatórios CSV ----------

  @override
  String urlRelatorioFinanceiroCsv() =>
      '$_api/v1/admin/relatorios/financeiro${_token != null ? '?token=$_token' : ''}';

  @override
  String urlRelatorioPedidosCsv() =>
      '$_api/v1/admin/relatorios/pedidos${_token != null ? '?token=$_token' : ''}';

  @override
  String urlRelatorioRepassesCsv() =>
      '$_api/v1/admin/relatorios/repasses${_token != null ? '?token=$_token' : ''}';
}

class _Resposta {
  const _Resposta(this.status, this.json);
  final int status;
  final Object? json;
  bool get ok => status >= 200 && status < 300;
}
