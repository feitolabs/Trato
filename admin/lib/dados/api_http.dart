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
  int? _ultimoRegistro;

  @override
  int? get ultimoRegistroAuditoria => _ultimoRegistro;

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
    if (!ehIdempotente) _ultimoRegistro = null; // o número vale só para a ação em andamento
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
        final registro = int.tryParse(r.headers['x-auditoria-id'] ?? '');
        if (registro != null) _ultimoRegistro = registro;
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

  static String _codigoVerificacao(StatusVerificacao s) =>
      _statusVerificacao.entries.firstWhere((e) => e.value == s).key;

  @override
  Future<PaginaRemota<Verificacao>> listarVerificacoes({
    List<StatusVerificacao> status = const [],
    String busca = '',
    int deslocamento = 0,
    int limite = 50,
  }) async {
    final codigos = status.isEmpty ? _statusVerificacao.keys.toList() : status.map(_codigoVerificacao).toList();
    final uri = Uri.parse('$_api/v1/admin/verificacoes').replace(queryParameters: {
      'status': codigos,
      if (busca.trim().isNotEmpty) 'busca': [busca.trim()],
      'limite': ['$limite'],
      'deslocamento': ['$deslocamento'],
    });
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    final r = await _enviar('GET', uri, cabecalhos: {'Authorization': 'Bearer $token'});
    if (!r.ok) throw _erro(r);
    final itens = [
      for (final v in _itens(r.json))
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
            profissionalId: (v['profissional_id'] as String?) ?? '',
            profissional: (v['profissional_nome'] as String?) ?? 'Profissional',
            idPublico: (v['publico_id'] as String?) ?? '',
            nivel: _capitalizar((v['nivel_solicitado'] as String?) ?? ''),
            categorias: [for (final c in (v['categorias'] as List? ?? const [])) '$c'],
            cidade: (v['cidade'] as String?) ?? '',
            enviadaEm: _data(v['enviada_em']),
            cpfMascarado: v['cpf_mascarado'] as String?,
            documentos: rotulos,
            enviosAnteriores: [
              for (final e in (v['envios_anteriores'] as List? ?? const []))
                EnvioVerificacao(
                  enviadoEm: _data(_mapa(e)['enviado_em']),
                  aprovado: _mapa(e)['status'] == 'aprovada',
                  motivo: _mapa(e)['motivo'] as String?,
                ),
            ],
            status: _statusVerificacao[v['status']] ?? StatusVerificacao.enviada,
            motivoDecisao: v['motivo_recusa'] as String?,
            analistaId: v['analista_id'] as String?,
            analistaNome: v['analista_nome'] as String?,
          );
        }(),
    ];
    final total = r.json is Map ? _int((r.json as Map)['total']) : itens.length;
    return PaginaRemota(itens, total);
  }

  @override
  Future<Map<StatusVerificacao, int>> contarVerificacoes() async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/verificacoes/contagem'));
    return {for (final e in _statusVerificacao.entries) e.value: _int(corpo[e.key])};
  }

  @override
  Future<void> assumirVerificacao(String id, {required String motivo, bool substituir = false}) async {
    await _chamar('POST', '/v1/admin/verificacoes/$id/assumir', corpo: {'motivo': motivo, 'substituir': substituir});
  }

  static String _capitalizar(String t) {
    final limpo = t.replaceAll('_', ' ').trim();
    return limpo.isEmpty ? '' : '${limpo[0].toUpperCase()}${limpo.substring(1)}';
  }

  static String _rotuloDocumento(String tipo) => switch (tipo) {
        'documento_frente' => 'Frente do documento',
        'documento_verso' => 'Verso do documento',
        'selfie' => 'Selfie',
        _ => tipo.isEmpty ? 'Documento' : _capitalizar(tipo),
      };

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

  static String _codigoEstadoDisputa(StatusDisputa s) => switch (s) {
        StatusDisputa.aberta || StatusDisputa.aguardandoProfissional => 'aberta',
        StatusDisputa.emAnalise => 'em_analise',
        StatusDisputa.aguardandoSegundaPessoa => 'aguardando_aprovacao',
        StatusDisputa.decidida => 'decidida',
      };

  /// Uma chamada por página (antes era uma por disputa): o detalhe vem só ao abrir o caso.
  @override
  Future<PaginaRemota<Disputa>> listarDisputas({
    String situacao = 'abertas',
    int deslocamento = 0,
    int limite = 50,
  }) async {
    final corpo = await _chamar('GET', '/v1/admin/disputas', consulta: {
      'situacao': situacao,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    });
    final itens = [for (final d in _itens(corpo)) _disputa(d)];
    return PaginaRemota(itens, corpo is Map ? _int(corpo['total']) : itens.length);
  }

  @override
  Future<Disputa> obterDisputa(String id) async => _disputa(_mapa(await _chamar('GET', '/v1/admin/disputas/$id')));

  @override
  Future<void> assumirDisputa(String id, {required String motivo, bool substituir = false}) async {
    await _chamar('POST', '/v1/admin/disputas/$id/assumir', corpo: {'motivo': motivo, 'substituir': substituir});
  }

  @override
  Future<({int abertas, int decididas})> contarDisputas() async {
    final c = _mapa(await _chamar('GET', '/v1/admin/disputas/contagem'));
    return (abertas: _int(c['abertas']), decididas: _int(c['decididas']));
  }

  Disputa _disputa(Map<String, dynamic> d) {
    final decisao = DecisaoDisputa.values.where((x) => x.codigo == d['decisao']).firstOrNull;
    final divisao = d['divisao'] is Map ? _mapa(d['divisao']) : null;
    final motivo = _rotuloMotivo((d['motivo'] as String?) ?? '');
    final pedidoId = d['pedido_id'] as String;
    final numero = d['pedido_numero'];
    return Disputa(
      id: pedidoId,
      pedido: numero == null ? 'PED-${pedidoId.replaceAll('-', '').substring(0, 4).toUpperCase()}' : 'PED-$numero',
      titulo: (d['pedido_titulo'] as String?) ?? '',
      cliente: (d['cliente'] is Map ? _mapa(d['cliente'])['nome'] as String? : null) ??
          d['cliente_nome'] as String? ??
          'Cliente',
      profissional: (d['profissional'] is Map ? _mapa(d['profissional'])['nome'] as String? : null) ??
          d['profissional_nome'] as String? ??
          'Profissional',
      motivo: motivo,
      descricao: motivo,
      valorEmAnaliseCentavos: _int(d['valor_congelado_centavos']),
      decisaoAte: _data(d['decisao_ate']),
      respostaAte: d['resposta_ate'] == null ? null : _data(d['resposta_ate']),
      atrasada: d['atrasada'] == true,
      semResposta: d['sem_resposta'] == true,
      status: _estadoDisputa[d['estado']] ?? StatusDisputa.emAnalise,
      decisao: decisao,
      valorReembolsoCentavos: divisao == null ? null : _int(divisao['para_cliente_centavos']),
      decididoPor: d['decidido_por'] as String?,
      responsavelId: d['responsavel_id'] as String?,
      responsavelNome: d['responsavel_nome'] as String?,
      evidencias: [
        for (final e in (d['evidencias'] as List? ?? const []))
          EvidenciaDisputa(
            autor: _rotuloPapel(_mapa(e)['ator_papel'] as String?),
            tipo: _rotuloAcao((_mapa(e)['origem'] as String?) ?? 'prova'),
            texto: _texto(_mapa(e)['dados']),
          ),
      ],
      linhaDoTempo: [
        for (final e in (d['linha_do_tempo'] as List? ?? const []))
          EventoDisputa(
            _data(_mapa(e)['em']),
            _rotuloPapel(_mapa(e)['ator_papel'] as String?),
            _rotuloAcao('${_mapa(e)['acao']}'),
          ),
      ],
    );
  }

  static String _rotuloPapel(String? papel) => switch (papel) {
        'cliente' => 'Cliente',
        'profissional' => 'Profissional',
        'mediador' || 'equipe' => 'Equipe Trato',
        'sistema' || null => 'Sistema',
        final outro => _capitalizar(outro),
      };

  static String _rotuloMotivo(String motivo) => switch (motivo) {
        '' => 'Problema no serviço',
        final m => _capitalizar(m),
      };

  /// Ação técnica (`disputa_aberta`) em frase legível. Código desconhecido vira texto simples.
  static String _rotuloAcao(String acao) => switch (acao) {
        'disputa_aberta' => 'Disputa aberta pelo cliente',
        'disputa_respondida' => 'Profissional respondeu à disputa',
        'decisao_registrada' => 'Decisão registrada',
        'decisao_aprovada' => 'Decisão aprovada por uma segunda pessoa',
        'concluir' => 'Serviço marcado como concluído',
        'abrir_disputa' => 'Cliente relatou um problema',
        'responder_disputa' => 'Profissional respondeu',
        'decidir_disputa' => 'Disputa decidida pela equipe',
        final outro => _capitalizar(outro),
      };

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
    StatusDisputa? estadoEsperado,
  }) async {
    final corpo = await _chamar('POST', '/v1/admin/disputas/$id/decisao', corpo: {
      'resultado': decisao.codigo,
      'justificativa': justificativa,
      if (estadoEsperado != null) 'estado_esperado': _codigoEstadoDisputa(estadoEsperado),
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
  Future<ResumoConciliacao> resumoConciliacao({int? dias}) async {
    final r = _mapa(await _chamar('GET', '/v1/admin/pagamentos/resumo', consulta: {'dias': dias?.toString()}));
    return ResumoConciliacao(
      confirmadoCentavos: _int(r['confirmado_centavos']),
      estornadoCentavos: _int(r['estornado_centavos']),
      emAndamentoCentavos: _int(r['retido_centavos']),
      divergencias: _int(r['divergencias']),
      atualizadoEm: _data(r['atualizado_em']),
      cobrancas: _int(r['cobrancas']),
      reembolsos: _int(r['reembolsos']),
      valorDivergenteCentavos: _int(r['valor_divergente_centavos']),
    );
  }

  static const _statusPagamento = {
    'confirmado': StatusProvedor.confirmado,
    'estornado': StatusProvedor.reembolsado,
    'estornado_parcial': StatusProvedor.reembolsadoParcial,
  };

  @override
  Future<List<LancamentoEspelho>> extrato({int? dias}) async {
    final corpo = await _chamar('GET', '/v1/admin/pagamentos', consulta: {'limite': '100', 'dias': dias?.toString()});
    return [
      for (final p in _itens(corpo))
        LancamentoEspelho(
          id: p['lancamento_id'].toString(),
          data: _data(p['data']),
          descricao: 'Cobrança do pedido',
          tipo: p['status'] == 'estornado' ? 'Reembolso' : 'Cobrança',
          valorCentavos: _int(p['valor_centavos']),
          status: _statusPagamento[p['status']] ?? StatusProvedor.aguardandoConfirmacao,
          pedido: _codigoPedido(p['pedido_id'] as String?, p['pedido_numero']),
          refProvedor: (p['referencia_provedor'] as String?) ?? '—',
          divergente: p['divergente'] == true,
          taxaCentavos: (p['taxa_trato_centavos'] as num?)?.toInt(),
          liquidoCentavos: (p['liquido_profissional_centavos'] as num?)?.toInt(),
        ),
    ];
  }

  /// "PED-10482". Sem número curto, usa o começo do id para a pessoa ainda poder citar o pedido.
  static String _codigoPedido(String? id, Object? numero) {
    if (numero != null) return 'PED-$numero';
    if (id == null || id.isEmpty) return '—';
    return 'PED-${id.replaceAll('-', '').substring(0, 4).toUpperCase()}';
  }

  @override
  Future<void> conciliarDivergencia(String lancamentoId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/divergencias/$lancamentoId/conciliar', corpo: {'motivo': motivo});
  }

  // ---------- F7.4 busca ----------

  static String _tipoUsuario(Object? t) => switch (t) {
        'cliente' => 'Cliente',
        'profissional' => 'Profissional',
        'equipe' => 'Equipe',
        final outro => '$outro',
      };

  UsuarioBusca _usuario(Map<String, dynamic> u) => UsuarioBusca(
        id: u['id'] as String,
        nome: (u['nome'] as String?) ?? '—',
        tipo: _tipoUsuario(u['tipo']),
        status: (u['status'] as String?) ?? '—',
        idPublico: (u['publico_id'] as String?) ?? '',
        emailMascarado: u['email_mascarado'] as String?,
        telefoneMascarado: u['telefone_mascarado'] as String?,
        cidade: u['cidade'] as String?,
        categorias: [
          for (final c in (u['categorias'] as List? ?? const []))
            CategoriaProfissional(
              nome: _mapa(c)['nome'] as String,
              ativaNoPerfil: _mapa(c)['ativa_no_perfil'] == true,
              ativaNaPlataforma: _mapa(c)['ativa_na_plataforma'] == true,
            ),
        ],
        historico: [
          for (final e in (u['historico'] as List? ?? const []))
            EventoUsuario(_data(_mapa(e)['em']), _mapa(e)['texto'] as String),
        ],
      );

  @override
  Future<List<UsuarioBusca>> buscarUsuarios(String termo) async {
    final corpo = await _chamar('GET', '/v1/admin/usuarios', consulta: {'q': termo.trim(), 'limite': '100'});
    return [for (final u in _itens(corpo)) _usuario(u)];
  }

  @override
  Future<UsuarioBusca> detalheUsuario(String usuarioId) async =>
      _usuario(_mapa(await _chamar('GET', '/v1/admin/usuarios/$usuarioId')));

  @override
  Future<DiagnosticoPedido> diagnosticarPedido(String usuarioId, String pedido) async {
    final d = _mapa(await _chamar(
      'GET',
      '/v1/admin/usuarios/$usuarioId/diagnostico-pedido',
      consulta: {'pedido': pedido.trim()},
    ));
    final numero = d['pedido_numero'];
    return DiagnosticoPedido(
      pedido: numero == null ? pedido.trim() : 'PED-$numero',
      titulo: (d['pedido_titulo'] as String?) ?? '',
      categoria: (d['categoria'] as String?) ?? '',
      aparece: d['aparece'] == true,
      itens: [
        for (final i in (d['itens'] as List? ?? const []))
          ItemDiagnostico(
            ok: _mapa(i)['ok'] == true,
            titulo: _mapa(i)['titulo'] as String,
            detalhe: _mapa(i)['detalhe'] as String,
          ),
      ],
    );
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
          codigo: _codigoPedido(p['id'] as String?, p['numero']),
          titulo: (p['titulo'] as String?) ?? 'Pedido',
          cliente: (p['cliente_nome'] as String?) ?? '—',
          profissional: p['profissional_nome'] as String?,
          categoria: p['categoria'] as String?,
          cidade: p['cidade'] as String?,
          status: _rotuloEstadoPedido((p['estado'] as String?) ?? ''),
          valorCentavos: _int(p['valor_centavos']),
        ),
    ];
  }

  static String _rotuloEstadoPedido(String estado) => switch (estado) {
        'aberto' => 'Aberto',
        'orcamento_aceito' => 'Orçamento aceito',
        'pago_retido' => 'Pago e retido',
        'agendado' => 'Agendado',
        'em_andamento' => 'Em andamento',
        'em_confirmacao' => 'Em confirmação',
        'concluido' => 'Concluído',
        'retrabalho' => 'Retrabalho',
        'em_disputa' => 'Em disputa',
        'cancelado' => 'Cancelado',
        'expirado' => 'Expirado',
        final outro => _capitalizar(outro),
      };

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
          prioridade: (c['prioridade'] as String?) ?? 'normal',
          responsavel: c['responsavel'] as String?,
          prazo: c['prazo'] == null ? null : _data(c['prazo']),
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
                UnidadeConfig.quantidade,
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
      criadaPorNome: v['criada_por_nome'] as String?,
      aprovadaPorNome: v['aprovada_por_nome'] as String?,
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
  Future<void> recusarConfig(String versaoId, String motivo) async {
    await _chamar('DELETE', '/v1/admin/config/versoes/$versaoId', corpo: {'motivo': motivo});
  }

  @override
  Future<void> reverterConfig(String versaoId, String motivo) async {
    await _chamar('POST', '/v1/admin/config/versoes/$versaoId/reverter', corpo: {'motivo': motivo});
  }

  // ---------- F7.6 auditoria ----------

  @override
  Future<PaginaAuditoria> listarAuditoria({
    String? acao,
    String? ator,
    String? entidade,
    DateTime? desde,
    DateTime? ate,
    int limite = 25,
    int deslocamento = 0,
  }) async {
    final corpo = await _chamar('GET', '/v1/admin/auditoria', consulta: {
      'acao': acao?.trim(),
      'ator': ator?.trim(),
      'entidade': entidade?.trim(),
      'desde': desde?.toUtc().toIso8601String(),
      'ate': ate?.toUtc().toIso8601String(),
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    });
    return PaginaAuditoria(
      total: corpo is Map ? _int(corpo['total']) : 0,
      itens: [
        for (final e in _itens(corpo))
          EntradaAuditoria(
            id: _int(e['id']),
            ocorridaEm: _data(e['ocorrida_em']),
            ator: (e['ator_id'] as String?) ?? (e['ator_tipo'] as String?) ?? 'sistema',
            atorNome: e['ator_nome'] as String?,
            acao: (e['acao'] as String?) ?? '—',
            entidade: [e['entidade'], e['entidade_id']].where((x) => x != null).join(':'),
            entidadeNome: e['entidade_nome'] as String?,
            motivo: e['motivo'] as String?,
            detalhes: e['depois'] is Map ? _mapa(e['depois']) : const {},
          ),
      ],
    );
  }

  @override
  Future<ResultadoCadeia> verificarCadeia() async {
    final r = _mapa(await _chamar('POST', '/v1/admin/auditoria/verificar-cadeia'));
    return ResultadoCadeia(ok: r['integra'] == true, primeiraQuebraId: (r['primeira_falha_id'] as num?)?.toInt());
  }

  // ---------- Módulo 1: Dashboard ----------

  @override
  Future<MetricasDashboard> metricasDashboard({int dias = 30, DateTime? inicio, DateTime? fim}) async {
    final m = _mapa(await _chamar('GET', '/v1/admin/dashboard/metricas', consulta: _periodo(dias, inicio, fim)));
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
      gmvAnteriorCentavos: _int(m['gmv_anterior_centavos']),
      receitaTaxaAnteriorCentavos: _int(m['receita_taxa_anterior_centavos']),
      pedidosAtivos: _int(m['pedidos_ativos']),
      pedidosAtivosAnterior: _int(m['pedidos_ativos_anterior']),
      baseUsuarios: _int(m['base_usuarios']),
      baseUsuariosAnterior: _int(m['base_usuarios_anterior']),
      disputasAbertas: _int(m['disputas_abertas']),
      alertasRiscoAbertos: _int(m['alertas_risco_abertos']),
    );
  }

  static Map<String, String?> _periodo(int dias, DateTime? inicio, DateTime? fim) {
    String dia(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (inicio != null && fim != null) return {'inicio': dia(inicio), 'fim': dia(fim)};
    return {'dias': '$dias'};
  }

  @override
  Future<SeriesDashboard> seriesDashboard({int dias = 30, DateTime? inicio, DateTime? fim}) async {
    final m = _mapa(await _chamar('GET', '/v1/admin/dashboard/series', consulta: _periodo(dias, inicio, fim)));
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
          usuarioTipo: a['usuario_tipo'] as String?,
          usuarioStatus: a['usuario_status'] as String?,
          pedido: a['pedido_numero'] != null
              ? 'PED-${a['pedido_numero']}'
              : (a['pedido_id'] == null ? null : _codigoPedido(a['pedido_id'] as String, null)),
          tipo: a['tipo'] as String,
          severidade: a['severidade'] as String,
          detalhes: a['detalhes'] as String,
          status: (a['status'] as String?) ?? 'em_aberto',
          resultado: a['resultado'] as String?,
          responsavel: a['responsavel'] as String?,
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
  Future<void> desbloquearConta(String usuarioId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/desbloqueio', corpo: {'usuario_id': usuarioId, 'motivo': motivo});
  }

  @override
  Future<void> travarSaque(String usuarioId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/travar-saque', corpo: {'usuario_id': usuarioId, 'motivo': motivo});
  }

  @override
  Future<void> destravarSaque(String usuarioId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/destravar-saque', corpo: {'usuario_id': usuarioId, 'motivo': motivo});
  }

  @override
  Future<void> assumirAlertaRisco(String alertaId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/alertas/$alertaId/assumir', corpo: {'motivo': motivo});
  }

  @override
  Future<void> resolverAlertaRisco(String alertaId, {required String resultado, required String motivo}) async {
    await _chamar(
      'POST',
      '/v1/admin/risco/alertas/$alertaId/resolver',
      corpo: {'motivo': motivo, 'resultado': resultado},
    );
  }

  // ---------- Módulo 4: Notificações em Massa & Campanhas ----------

  static CampanhaNotificacao _campanha(Map<String, dynamic> c) => CampanhaNotificacao(
        id: c['id'] as String,
        titulo: c['titulo'] as String,
        mensagem: c['mensagem'] as String,
        segmento: c['segmento'] as String,
        tipo: (c['tipo'] as String?) ?? 'marketing',
        categoriaId: c['categoria_id'] as String?,
        cidadeId: c['cidade_id'] as String?,
        totalDestinatarios: _int(c['total_destinatarios']),
        criadoEm: c['criado_em'] as String? ?? '',
        autor: c['autor'] as String?,
        enviados: _int(c['enviados']),
        entregues: _int(c['entregues']),
        abertos: _int(c['abertos']),
      );

  @override
  Future<List<CampanhaNotificacao>> listarCampanhasNotificacao() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/notificacoes/campanhas'));
    return [for (final c in itens) _campanha(c)];
  }

  @override
  Future<EstimativaCampanha> estimarCampanhaNotificacao({
    required String segmento,
    required String tipo,
    String? categoriaId,
    String? cidadeId,
  }) async {
    final r = _mapa(await _chamar('GET', '/v1/admin/notificacoes/estimativa', consulta: {
      'segmento': segmento,
      'tipo': tipo,
      'categoria_id': categoriaId,
      'cidade_id': cidadeId,
    }));
    return EstimativaCampanha(destinatarios: _int(r['destinatarios']), desativaram: _int(r['desativaram']));
  }

  @override
  Future<CampanhaNotificacao> dispararCampanhaNotificacao({
    required String titulo,
    required String mensagem,
    required String segmento,
    String tipo = 'marketing',
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
        'tipo': tipo,
        if (categoriaId != null) 'categoria_id': categoriaId,
        if (cidadeId != null) 'cidade_id': cidadeId,
        'motivo': motivo,
      },
    ));
    return _campanha(c);
  }

  // ---------- Módulo 5: Gestão de Cupons ----------

  static CupomAdmin _cupom(Map<String, dynamic> c) => CupomAdmin(
        id: c['id'] as String,
        codigo: c['codigo'] as String,
        tipo: c['tipo'] as String,
        valor: _int(c['valor']),
        valorMinimoCentavos: _int(c['valor_minimo_centavos']),
        limiteUsos: c['limite_usos'] != null ? _int(c['limite_usos']) : null,
        usosAtuais: _int(c['usos_atuais']),
        validoAte: c['valido_ate'] as String?,
        validoDesde: c['valido_desde'] as String?,
        campanha: c['campanha'] as String?,
        limitePorUsuario: c['limite_por_usuario'] != null ? _int(c['limite_por_usuario']) : null,
        ativo: c['ativo'] as bool? ?? true,
        criadoEm: c['criado_em'] as String? ?? '',
      );

  @override
  Future<List<CupomAdmin>> listarCupons() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/cupons'));
    return [for (final c in itens) _cupom(c)];
  }

  @override
  Future<CupomAdmin> criarCupom({
    required String codigo,
    required String tipo,
    required int valor,
    int valorMinimoCentavos = 0,
    int? limiteUsos,
    int? limitePorUsuario,
    String? validoDesde,
    String? validoAte,
    String? campanha,
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
        if (limitePorUsuario != null) 'limite_por_usuario': limitePorUsuario,
        if (validoDesde != null) 'valido_desde': validoDesde,
        if (validoAte != null) 'valido_ate': validoAte,
        if (campanha != null && campanha.isNotEmpty) 'campanha': campanha,
        'motivo': motivo,
      },
    ));
    return _cupom(c);
  }

  @override
  Future<CupomAdmin> alterarStatusCupom(String cupomId, {required bool ativo, required String motivo}) async {
    final c = _mapa(await _chamar(
      'PATCH',
      '/v1/admin/cupons/$cupomId/status',
      corpo: {'ativo': ativo, 'motivo': motivo},
    ));
    return _cupom(c);
  }

  @override
  Future<void> excluirCupom(String cupomId, {required String motivo}) async {
    await _chamar('DELETE', '/v1/admin/cupons/$cupomId', consulta: {'motivo': motivo});
  }

  // ---------- Módulo 6: Equipe Interna ----------

  static MembroEquipeAdmin _membro(Map<String, dynamic> m) => MembroEquipeAdmin(
        usuarioId: m['usuario_id'] as String,
        nome: m['nome'] as String,
        email: m['email'] as String,
        papel: m['papel'] as String,
        ativo: m['ativo'] as bool? ?? true,
        alcadaCentavos: _int(m['alcada_centavos']),
        criadoEm: m['criado_em'] as String? ?? '',
        status: (m['status'] as String?) ?? 'ativo',
        ultimoAcesso: m['ultimo_acesso'] as String?,
        tetoPapelCentavos: _int(m['teto_papel_centavos']),
      );

  @override
  Future<List<MembroEquipeAdmin>> listarEquipe() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/equipe'));
    return [for (final m in itens) _membro(m)];
  }

  @override
  Future<Map<String, int>> tetosDosPapeis() async {
    final itens = _itens(await _chamar('GET', '/v1/admin/equipe/tetos'));
    return {for (final t in itens) t['papel'] as String: _int(t['teto_centavos'])};
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
    return _membro(m);
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
    return _membro(m);
  }

  @override
  Future<void> revogarMembroEquipe(String usuarioId, {required String motivo}) async {
    await _chamar('DELETE', '/v1/admin/equipe/$usuarioId', consulta: {'motivo': motivo});
  }

  // ---------- Financeiro: contestações, alertas, conciliação, fechamento ----------

  static String _dia(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _dataOuNada(Object? o) => o == null ? null : _data(o);

  static String _pedidoComTitulo(Map<String, dynamic> m) {
    final codigo = _codigoPedido(m['pedido_id'] as String?, m['pedido_numero']);
    final titulo = m['pedido_titulo'] as String?;
    return titulo == null || titulo.isEmpty ? codigo : '$codigo · $titulo';
  }

  static EventoEmRevisao _revisao(Map<String, dynamic> e) => EventoEmRevisao(
        eventoId: e['evento_id'] as String,
        tipo: e['tipo'] as String,
        recebidoEm: _data(e['recebido_em']),
        motivo: e['motivo'] as String,
      );

  @override
  Future<List<ContestacaoCartao>> listarContestacoes({String? status}) async {
    final corpo = await _chamar('GET', '/v1/admin/financeiro/contestacoes', consulta: {'status': status});
    return [
      for (final c in _itens(corpo))
        ContestacaoCartao(
          id: c['id'] as String,
          pedido: _pedidoComTitulo(c),
          valorCentavos: _int(c['valor_centavos']),
          motivo: c['motivo_legivel'] as String,
          status: c['status'] as String,
          abertaEm: _data(c['aberta_em']),
          prazoProvas: _dataOuNada(c['prazo_provas']),
          horasParaPrazo: (c['horas_para_prazo'] as num?)?.toInt(),
          encerradaEm: _dataOuNada(c['encerrada_em']),
          repasseLiberado: c['repasse_liberado'] == true,
          cobrancaId: c['cobranca_id'] as String?,
        ),
    ];
  }

  @override
  Future<AlertasFinanceiros> alertasFinanceiros() async {
    final r = _mapa(await _chamar('GET', '/v1/admin/financeiro/alertas'));
    return AlertasFinanceiros(
      minutosPagamentoParado: _int(r['minutos_pagamento_parado']),
      provedorLigado: r['provedor_ligado'] == true,
      pagamentosParados: [
        for (final p in _itens(r['pagamentos_parados']))
          PagamentoParado(
            cobrancaId: p['cobranca_id'] as String,
            pedido: _codigoPedido(p['pedido_id'] as String?, p['pedido_numero']),
            valorCentavos: _int(p['valor_centavos']),
            meio: p['meio'] as String,
            criadaEm: _data(p['criada_em']),
            minutosParado: _int(p['minutos_parado']),
            clienteAvisou: p['cliente_avisou'] == true,
          ),
      ],
      repassesComFalha: [for (final e in _itens(r['repasses_com_falha'])) _revisao(e)],
      estornosPendentes: [
        for (final o in _itens(r['estornos_pendentes']))
          EstornoPendente(
            pedido: _codigoPedido(o['pedido_id'] as String?, null),
            cobrancaId: o['cobranca_id'] as String,
            valorCentavos: _int(o['valor_centavos']),
            criadaEm: _data(o['criada_em']),
          ),
      ],
      eventosEmRevisao: [for (final e in _itens(r['eventos_em_revisao'])) _revisao(e)],
      contestacoesEmAberto: _int(r['contestacoes_em_aberto']),
    );
  }

  @override
  Future<ConsultaCobranca> consultarCobranca(String cobrancaId) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/financeiro/cobrancas/$cobrancaId/consultar'));
    return ConsultaCobranca(
      statusNoProvedor: r['status_no_provedor'] as String,
      statusNoTrato: r['status_no_trato'] as String?,
      orientacao: r['orientacao'] as String,
    );
  }

  @override
  Future<ConciliacaoDia> conciliacaoDoDia(DateTime dia) async {
    final r = _mapa(await _chamar('GET', '/v1/admin/financeiro/conciliacao', consulta: {'dia': _dia(dia)}));
    List<LinhaConciliacao> linhas(Object? lista) => [
          for (final l in _itens(lista))
            LinhaConciliacao(
              tipo: l['tipo'] as String,
              referencia: l['referencia'] as String,
              pedido: l['pedido_id'] == null ? null : _codigoPedido(l['pedido_id'] as String?, l['pedido_numero']),
              valorProvedorCentavos: _int(l['valor_provedor_centavos']),
              valorTratoCentavos: _int(l['valor_trato_centavos']),
              situacao: l['situacao'] as String,
            ),
        ];
    return ConciliacaoDia(
      dia: DateTime.parse(r['dia'] as String),
      confere: r['confere'] == true,
      cobradoProvedorCentavos: _int(r['cobrado_provedor_centavos']),
      cobradoTratoCentavos: _int(r['cobrado_trato_centavos']),
      taxasProvedorCentavos: _int(r['taxas_provedor_centavos']),
      divergencias: linhas(r['divergencias']),
      linhas: linhas(r['linhas']),
    );
  }

  @override
  Future<List<EventoProvedor>> listarEventosProvedor({int limite = 50}) async {
    final corpo = await _chamar('GET', '/v1/admin/webhooks/eventos', consulta: {'limite': '$limite'});
    return [
      for (final e in _itens(corpo))
        EventoProvedor(
          eventoId: e['evento_id'] as String,
          tipo: e['tipo'] as String,
          recebidoEm: _data(e['recebido_em']),
          pedidoId: e['pedido_id'] as String?,
          referencia: e['referencia'] as String?,
          valorCentavos: (e['valor_centavos'] as num?)?.toInt(),
          revisao: e['revisao'] as String?,
        ),
    ];
  }

  @override
  Future<List<MesFinanceiro>> listarMeses({int ultimos = 12}) async {
    final corpo = await _chamar('GET', '/v1/admin/financeiro/fechamentos', consulta: {'ultimos': '$ultimos'});
    return [
      for (final m in _itens(corpo))
        MesFinanceiro(
          mes: m['mes'] as String,
          fechado: m['fechado'] == true,
          podeFechar: m['pode_fechar'] == true,
          fechadoEm: _dataOuNada(m['fechado_em']),
        ),
    ];
  }

  static Map<String, int> _totais(Object? o) => {
        for (final e in (o as Map? ?? const {}).entries)
          if (e.value is num) e.key as String: (e.value as num).toInt(),
      };

  FechamentoMes _fechamento(Map<String, dynamic> r) => FechamentoMes(
        mes: r['mes'] as String,
        fechado: r['fechado'] == true,
        podeFechar: r['pode_fechar'] == true,
        totais: _totais(r['totais']),
        gravado: r['gravado'] == null ? null : _totais(r['gravado']),
        confere: r['confere'] as bool?,
        hash: r['hash'] as String?,
        fechadoPorNome: r['fechado_por_nome'] as String?,
        fechadoEm: _dataOuNada(r['fechado_em']),
        motivo: r['motivo'] as String?,
      );

  @override
  Future<FechamentoMes> verFechamento(String mes) async =>
      _fechamento(_mapa(await _chamar('GET', '/v1/admin/financeiro/fechamentos/$mes')));

  @override
  Future<FechamentoMes> fecharMes(String mes, {required String motivo}) async => _fechamento(
        _mapa(await _chamar('POST', '/v1/admin/financeiro/fechamentos/$mes/fechar', corpo: {'motivo': motivo})),
      );

  ArquivoPronto _arquivo(Object? corpo) {
    final r = _mapa(corpo);
    // O token de login nunca vai na URL: o link vale só uma vez e por poucos minutos.
    return ArquivoPronto(
      url: '$_api/v1/admin/relatorios/baixar/${r['codigo']}',
      nomeArquivo: r['nome_arquivo'] as String,
    );
  }

  @override
  Future<ArquivoPronto> exportarFechamento(String mes) async =>
      _arquivo(await _chamar('POST', '/v1/admin/financeiro/fechamentos/$mes/exportar'));

  @override
  Future<ArquivoPronto> extratoProfissional(
    String usuarioId, {
    required DateTime inicio,
    required DateTime fim,
    required String motivo,
  }) async =>
      _arquivo(await _chamar(
        'POST',
        '/v1/admin/financeiro/profissionais/$usuarioId/extrato',
        corpo: {'inicio': _dia(inicio), 'fim': _dia(fim), 'motivo': motivo},
      ));

  // ---------- Módulo 7: Exportação de Relatórios CSV ----------

  @override
  Future<RelatorioPronto> solicitarRelatorio(
    String tipo, {
    DateTime? inicio,
    DateTime? fim,
    String? cidadeId,
    String formato = 'excel_br',
    required String motivo,
  }) async {
    String dia(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = _mapa(await _chamar('POST', '/v1/admin/relatorios/$tipo', corpo: {
      if (inicio != null) 'inicio': dia(inicio),
      if (fim != null) 'fim': dia(fim),
      if (cidadeId != null) 'cidade_id': cidadeId,
      'formato': formato,
      'motivo': motivo,
    }));
    // O token de login nunca vai na URL: o link vale só uma vez e por poucos minutos.
    return RelatorioPronto(
      url: '$_api/v1/admin/relatorios/baixar/${r['codigo']}',
      nomeArquivo: r['nome_arquivo'] as String,
      linhas: _int(r['linhas']),
      colunas: _int(r['colunas']),
      comDadosPessoais: r['com_dados_pessoais'] == true,
    );
  }
}

class _Resposta {
  const _Resposta(this.status, this.json);
  final int status;
  final Object? json;
  bool get ok => status >= 200 && status < 300;
}
