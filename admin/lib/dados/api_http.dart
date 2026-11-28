import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../nucleo/papeis.dart';
import '../nucleo/navegador.dart';
import 'api_admin.dart';
import 'modelos.dart';

/// Cliente da API admin do backend (`docs/api-admin.md`).
///
/// - Login: senha no Supabase Auth (`/auth/v1/token`) com a chave pública (anon). O token fica só em
///   memória: não vai para o disco, para a URL nem para log.
/// - Cada chamada leva `Authorization: Bearer`. O backend lê o papel da tabela `equipe` e responde 401/403.
/// - Funções que o backend ainda não tem (categorias) respondem [ErroApi] em português.
class ApiAdminHttp implements ApiAdmin {
  ApiAdminHttp({
    required String urlApi,
    required String urlSupabase,
    required String chaveAnonSupabase,
    http.Client? cliente,
    this.tempoLimite = const Duration(seconds: 20),
    this._urlPublica,
  })  : _api = _semBarraFinal(urlApi),
        _supabase = _semBarraFinal(urlSupabase),
        _chaveAnon = chaveAnonSupabase,
        _cliente = cliente ?? http.Client();

  final String _api;
  final String _supabase;
  final String _chaveAnon;

  /// URL do próprio painel, para onde o link do e-mail de senha volta. Vazio = a origem em que o
  /// painel foi aberto (nunca um endereço fixo no código).
  final String? _urlPublica;
  final http.Client _cliente;
  final Duration tempoLimite;

  String? _token;
  int? _ultimoRegistro;

  @override
  int? get ultimoRegistroAuditoria => _ultimoRegistro;

  final _idsDocumentos = <String, String>{};

  static String _semBarraFinal(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;

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
    final codigo = r.json is Map && (r.json as Map)['codigo'] is String ? (r.json as Map)['codigo'] as String : null;
    final bruto = r.json is Map ? (r.json as Map)['maximo_centavos'] : null;
    final maximo = bruto is int ? bruto : null;
    switch (r.status) {
      case 401:
        _token = null;
        return const ErroApi('Sua sessão acabou. Entre de novo.', sessao: true);
      case 403:
        return ErroApi(texto ?? 'Seu papel não pode fazer isso.', proibido: true, status: 403, codigo: codigo);
      case 404:
        return ErroApi(texto ?? 'Não encontrado.', status: 404, codigo: codigo);
      case 409:
        final mapa = r.json is Map ? r.json as Map : const {};
        final campos = mapa['campos'];
        final quando = mapa['pode_valer_em'];
        return ErroApi(texto ?? 'O caso mudou ou já foi decidido. Atualize e confira.',
            status: 409,
            codigo: codigo,
            campos: campos is List ? [for (final c in campos) '$c'] : const [],
            podeValerEm: quando is String ? quando : null);
      case 422:
        return ErroApi(texto ?? 'Confira os campos: algum valor não foi aceito.', status: 422, codigo: codigo, maximoCentavos: maximo);
      case 503:
        return ErroApi(texto ?? 'Este recurso ainda não está configurado no servidor.', status: 503, codigo: codigo);
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

  String get _urlRetornoPainel {
    final configurada = (_urlPublica ?? '').trim();
    if (configurada.isNotEmpty) return configurada;
    final u = urlAtual();
    return u.hasAuthority ? u.origin : '';
  }

  @override
  Future<void> pedirRecuperacaoSenha(String email) async {
    final retorno = _urlRetornoPainel;
    final r = await _enviar(
      'POST',
      Uri.parse('$_supabase/auth/v1/recover').replace(queryParameters: {if (retorno.isNotEmpty) 'redirect_to': retorno}),
      corpo: {'email': email.trim()},
      cabecalhos: {'apikey': _chaveAnon},
    );
    // Sem pistas sobre a conta: só falha de verdade (limite de envios, servidor fora) vira erro.
    if (r.status == 429) throw const ErroApi('Muitos pedidos seguidos. Espere alguns minutos e tente de novo.');
    if (r.status >= 500) throw const ErroApi('Não foi possível enviar agora. Tente de novo em instantes.');
  }

  @override
  Future<void> definirNovaSenha(String token, String novaSenha) async {
    final r = await _enviar(
      'PUT',
      Uri.parse('$_supabase/auth/v1/user'),
      corpo: {'password': novaSenha},
      cabecalhos: {'apikey': _chaveAnon, 'Authorization': 'Bearer $token'},
    );
    if (r.ok) return;
    final json = r.json is Map ? (r.json as Map) : const {};
    final codigo = '${json['error_code'] ?? json['code'] ?? ''}';
    if (r.status == 401 || r.status == 403 && codigo != 'same_password') {
      throw const ErroApi('Este link expirou ou já foi usado. Volte ao login e use "Esqueci a senha" para receber outro.');
    }
    if (codigo == 'same_password') {
      throw const ErroApi('A nova senha precisa ser diferente da senha atual.');
    }
    if (r.status == 422 || codigo == 'weak_password') {
      throw const ErroApi('Senha fraca ou recusada. Use pelo menos 8 caracteres, misturando letras e números.');
    }
    throw ErroApi('Não foi possível definir a senha agora (${r.status}). Tente de novo.');
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
    'acordo': StatusDisputa.acordo,
  };

  static String _codigoEstadoDisputa(StatusDisputa s) => switch (s) {
        StatusDisputa.aberta || StatusDisputa.aguardandoProfissional => 'aberta',
        StatusDisputa.emAnalise => 'em_analise',
        StatusDisputa.aguardandoSegundaPessoa => 'aguardando_aprovacao',
        StatusDisputa.decidida => 'decidida',
        StatusDisputa.acordo => 'acordo',
        // Nunca é enviado: sem ação nesse estado.
        StatusDisputa.desconhecida => 'desconhecida',
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

  static PedidoInfoDisputa _pedidoInfoDisputa(Map<String, dynamic> c) => PedidoInfoDisputa(
        id: c['id'] as String,
        disputaId: c['disputa_id'] as String,
        pedidoId: c['pedido_id'] as String,
        solicitanteId: c['solicitante_id'] as String? ?? '',
        destinatarioPapel: c['destinatario_papel'] as String,
        mensagem: c['mensagem'] as String,
        solicitadoEm: _data(c['solicitado_em']),
        responderAte: _data(c['responder_ate']),
        respondidoEm: c['respondido_em'] == null ? null : _data(c['respondido_em']),
        respostaTexto: c['resposta_texto'] as String?,
        encerradoSemRespostaEm:
            c['encerrado_sem_resposta_em'] == null ? null : _data(c['encerrado_sem_resposta_em']),
        status: c['status'] as String,
      );

  @override
  Future<List<PedidoInfoDisputa>> listarPedidosInfoDisputa(String disputaId) async {
    final bruto = await _chamar('GET', '/v1/admin/disputas/${Uri.encodeComponent(disputaId)}/pedidos-informacao');
    if (bruto is List) {
      return bruto.map((e) => _pedidoInfoDisputa(_mapa(e))).toList();
    }
    return _itens(bruto).map(_pedidoInfoDisputa).toList();
  }

  @override
  Future<PedidoInfoDisputa> solicitarInfoDisputa(
    String disputaId, {
    required String destinatarioPapel,
    required String mensagem,
  }) async =>
      _pedidoInfoDisputa(_mapa(await _chamar(
        'POST',
        '/v1/admin/disputas/${Uri.encodeComponent(disputaId)}/pedidos-informacao',
        corpo: {'destinatario_papel': destinatarioPapel, 'mensagem': mensagem},
      )));

  @override
  Future<PedidoInfoDisputa> encerrarPedidoInfoSemResposta(
    String disputaId,
    String pedidoInfoId, {
    required String motivo,
  }) async =>
      _pedidoInfoDisputa(_mapa(await _chamar(
        'POST',
        '/v1/admin/disputas/${Uri.encodeComponent(disputaId)}/pedidos-informacao/${Uri.encodeComponent(pedidoInfoId)}/encerrar-sem-resposta',
        corpo: {'motivo': motivo},
      )));

  @override
  Future<List<FaltaRepetidaProfissional>> listarFaltasRepetidas({int dias = 90, int minimo = 2}) async {
    final bruto = await _chamar('GET', '/v1/admin/profissionais/faltas-repetidas', consulta: {
      'dias': '$dias',
      'minimo': '$minimo',
    });
    final lista = bruto is List ? bruto.map(_mapa) : _itens(bruto);
    return [
      for (final c in lista)
        FaltaRepetidaProfissional(
          profissionalId: c['profissional_id'] as String,
          totalCancelamentos: _int(c['total_cancelamentos']),
          ultimoCancelamentoEm: _data(c['ultimo_cancelamento_em']),
          periodoDias: _int(c['periodo_dias']),
        ),
    ];
  }

  static EventoForcaMaior _eventoForcaMaior(Map<String, dynamic> c) => EventoForcaMaior(
        id: c['id'] as String,
        pedidoId: c['pedido_id'] as String,
        solicitanteId: c['solicitante_id'] as String,
        solicitantePapel: c['solicitante_papel'] as String,
        acaoSolicitada: c['acao_solicitada'] as String,
        descricao: c['descricao'] as String? ?? '',
        comprovantes: [for (final item in (c['comprovantes'] as List? ?? const [])) '$item'],
        status: c['status'] as String,
        criadoEm: c['criado_em'] == null ? null : _data(c['criado_em']),
        analistaId: c['analista_id'] as String?,
        justificativaDecisao: c['justificativa_decisao'] as String?,
        decididoEm: c['decidido_em'] == null ? null : _data(c['decidido_em']),
        chaveIdempotencia: c['chave_idempotencia'] as String?,
        idempotente: c['idempotente'] == true,
      );

  @override
  Future<PaginaRemota<EventoForcaMaior>> listarForcaMaior({
    String? status = 'pendente',
    int deslocamento = 0,
    int limite = 20,
  }) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/forca-maior', consulta: {
      'status': ?status,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota(
      _itens(corpo).map(_eventoForcaMaior).toList(),
      _int(corpo['total']),
    );
  }

  @override
  Future<EventoForcaMaior> decidirForcaMaior(
    String eventoId, {
    required String decisao,
    required String justificativa,
    required String chaveIdempotencia,
  }) async =>
      _eventoForcaMaior(_mapa(await _chamar(
        'POST',
        '/v1/admin/forca-maior/${Uri.encodeComponent(eventoId)}/decisao',
        corpo: {
          'decisao': decisao,
          'justificativa': justificativa,
          'chave_idempotencia': chaveIdempotencia,
        },
      )));

  @override
  Future<void> assumirDisputa(String id, {required String motivo, bool substituir = false}) async {
    await _chamar('POST', '/v1/admin/disputas/$id/assumir', corpo: {'motivo': motivo, 'substituir': substituir});
  }

  @override
  Future<({int abertas, int decididas})> contarDisputas() async {
    final c = _mapa(await _chamar('GET', '/v1/admin/disputas/contagem'));
    return (abertas: _int(c['abertas']), decididas: _int(c['decididas']));
  }

  // ---------- exclusividade (Termos 13.6) ----------

  @override
  Future<({String resultado, int moedasDevolvidas})> registrarFalhaTrato(String exclusividadeId,
      {required String motivo}) async {
    final r = _mapa(await _chamar(
        'POST', '/v1/admin/exclusividades/${Uri.encodeComponent(exclusividadeId)}/falha-trato',
        corpo: {'motivo': motivo}));
    return (resultado: r['resultado'] as String, moedasDevolvidas: _int(r['moedas_devolvidas']));
  }

  // ---------- contestação da decisão de disputa (Termos 8.7) ----------

  static const _contestacoes = '/v1/admin/contestacoes-disputa';

  @override
  Future<PaginaRemota<ContestacaoDisputa>> listarContestacoesDisputa(FiltroContestacoes f,
      {int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', _contestacoes, consulta: {
      'status': f.status,
      'efeito_financeiro': f.efeito,
      'pedido_id': f.pedidoId,
      'atrasadas': f.atrasadas ? 'true' : null,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _contestacaoDisputa(x)], _int(corpo['total']));
  }

  @override
  Future<ContestacaoDisputa> obterContestacaoDisputa(String id) async =>
      _contestacaoDisputa(_mapa(await _chamar('GET', '$_contestacoes/$id')));

  @override
  Future<({ContestacaoDisputa contestacao, bool repetida})> registrarContestacaoDisputa(
      {required String pedidoId,
      required String contestanteId,
      required String chamadoId,
      required String oQueFaltou,
      List<String> anexos = const []}) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    // 201 é nova; 200 é a mesma já registrada.
    final r = await _enviar('POST', _uri(_contestacoes), cabecalhos: {
      'Authorization': 'Bearer $token'
    }, corpo: {
      'pedido_id': pedidoId,
      'contestante_id': contestanteId,
      'chamado_id': chamadoId,
      'o_que_faltou': oQueFaltou,
      'anexos': anexos,
    });
    if (!r.ok) throw _erro(r);
    return (contestacao: _contestacaoDisputa(_mapa(r.json)), repetida: r.status == 200);
  }

  @override
  Future<ContestacaoDisputa> decidirContestacaoDisputa(String id,
          {required String resultado,
          required String resposta,
          String? novaDecisao,
          int? novoValorReembolsoCentavos}) async =>
      _contestacaoDisputa(_mapa(await _chamar('POST', '$_contestacoes/$id/decisao', corpo: {
        'resultado': resultado,
        'resposta': resposta,
        'nova_decisao': novaDecisao,
        'novo_valor_reembolso_centavos': novoValorReembolsoCentavos,
      })));

  @override
  Future<ContestacaoDisputa> aprovarContestacaoDisputa(String id,
          {required bool aprovar, required String motivo}) async =>
      _contestacaoDisputa(_mapa(
          await _chamar('POST', '$_contestacoes/$id/aprovacao', corpo: {'aprovar': aprovar, 'motivo': motivo})));

  ContestacaoDisputa _contestacaoDisputa(Map<String, dynamic> c) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    DecisaoResumida? decisao(Object? v) => v is Map
        ? DecisaoResumida(_mapa(v)['resultado'] as String, _mapa(v)['reembolso_centavos'] as int)
        : null;
    return ContestacaoDisputa(
      id: c['id'] as String,
      protocolo: c['protocolo'] as String,
      pedidoId: c['pedido_id'] as String,
      disputaId: c['disputa_id'] as String,
      contestanteId: c['contestante_id'] as String,
      contestantePapel: c['contestante_papel'] as String?,
      oQueFaltou: c['o_que_faltou'] as String,
      anexos: [for (final a in (c['anexos'] as List? ?? const [])) '$a'],
      canal: c['canal'] as String,
      status: c['status'] as String,
      abertaEm: _data(c['aberta_em']),
      contestarAte: _data(c['contestar_ate']),
      responderAte: _data(c['responder_ate']),
      atrasada: c['atrasada'] == true,
      analistaId: c['analista_id'] as String?,
      resposta: c['resposta'] as String?,
      novaDecisao: c['nova_decisao'] as String?,
      novoValorReembolsoCentavos: c['novo_valor_reembolso_centavos'] as int?,
      aprovadaPor: c['aprovada_por'] as String?,
      decididaEm: data(c['decidida_em']),
      efeitoFinanceiro: c['efeito_financeiro'] as String,
      valorCongeladoCentavos: c['valor_congelado_centavos'] as int?,
      decisaoOriginal: decisao(c['decisao_original']),
      decisaoVigente: decisao(c['decisao_vigente']),
      decididaPor: c['decidida_por'] as String?,
      disputaAprovadaPor: c['disputa_aprovada_por'] as String?,
    );
  }

  // ---------- regresso (Termos 17.4) ----------

  static const _regressos = '/v1/admin/compensacoes/regressos';

  @override
  Future<PaginaRemota<Regresso>> listarRegressos({String? status, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', _regressos,
        consulta: {'status': status, 'limite': '$limite', 'deslocamento': '$deslocamento'}));
    return PaginaRemota([for (final x in _itens(corpo)) _regresso(x)], _int(corpo['total']));
  }

  @override
  Future<({String resultado, Regresso proposta})> proporRegresso(
          {required String pedidoId,
          required String referencia,
          required int valorCentavos,
          required String motivo}) async =>
      _resultadoRegresso(await _chamar('POST', _regressos, corpo: {
        'pedido_id': pedidoId,
        'referencia': referencia,
        'valor_centavos': valorCentavos,
        'motivo': motivo,
      }));

  @override
  Future<({String resultado, Regresso proposta, bool avisado})> aprovarRegresso(String id) async {
    final r = _mapa(await _chamar('POST', '$_regressos/$id/aprovacao'));
    final base = _resultadoRegresso(r);
    return (resultado: base.resultado, proposta: base.proposta, avisado: r['avisado'] == true);
  }

  @override
  Future<({String resultado, Regresso proposta})> recusarRegresso(String id, {required String motivo}) async =>
      _resultadoRegresso(await _chamar('POST', '$_regressos/$id/recusa', corpo: {'motivo': motivo}));

  ({String resultado, Regresso proposta}) _resultadoRegresso(Object? corpo) {
    final r = _mapa(corpo);
    return (resultado: r['resultado'] as String, proposta: _regresso(_mapa(r['proposta'])));
  }

  Regresso _regresso(Map<String, dynamic> x) => Regresso(
        id: x['id'] as String,
        pedidoId: x['pedido_id'] as String,
        profissionalId: x['profissional_id'] as String,
        referencia: x['referencia'] as String,
        valorCentavos: x['valor_centavos'] as int,
        motivo: x['motivo'] as String,
        status: x['status'] as String,
        propostaPor: x['proposta_por'] as String,
        propostaEm: _data(x['proposta_em']),
        decididaEm: x['decidida_em'] == null ? null : _data(x['decidida_em']),
        motivoDecisao: x['motivo_decisao'] as String?,
        compensacaoId: x['compensacao_id'] as String?,
      );

  // ---------- incidentes de segurança (Termos 9) ----------

  static const _incidentes = '/v1/admin/incidentes';

  @override
  Future<PaginaRemota<Incidente>> listarIncidentes(
      {String? status, String? pedidoId, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', _incidentes, consulta: {
      'status': status,
      'pedido_id': pedidoId,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _incidente(x)], _int(corpo['total']));
  }

  Future<Incidente> _acaoIncidente(String metodo, String caminho, [Object? corpo]) async =>
      _incidente(_mapa(await _chamar(metodo, '$_incidentes$caminho', corpo: corpo)));

  @override
  Future<Incidente> obterIncidente(String id) => _acaoIncidente('GET', '/$id');

  @override
  Future<({Incidente incidente, bool repetido})> registrarIncidente(
      {required String tipo,
      required String descricao,
      required String contato,
      required String canal,
      String? pedidoId}) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    // 201 é novo; 200 é o mesmo incidente de um toque repetido.
    final r = await _enviar('POST', _uri(_incidentes), cabecalhos: {
      'Authorization': 'Bearer $token'
    }, corpo: {
      'tipo': tipo,
      'descricao': descricao,
      'contato': contato,
      'canal': canal,
      'pedido_id': ?pedidoId,
    });
    if (!r.ok) throw _erro(r);
    return (incidente: _incidente(_mapa(r.json)), repetido: r.status == 200);
  }

  @override
  Future<Incidente> adicionarMedidaIncidente(String id, {required String tipo, required String descricao}) =>
      _acaoIncidente('POST', '/$id/medidas', {'tipo': tipo, 'descricao': descricao});

  @override
  Future<Incidente> mudarStatusIncidente(String id, String status) =>
      _acaoIncidente('POST', '/$id/status', {'status': status});

  @override
  Future<Incidente> encerrarIncidente(String id, {required String desfecho}) =>
      _acaoIncidente('POST', '/$id/encerrar', {'desfecho': desfecho});

  Incidente _incidente(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return Incidente(
      id: x['id'] as String,
      protocolo: x['protocolo'] as String,
      canal: x['canal'] as String,
      tipo: x['tipo'] as String,
      descricao: (x['descricao'] as String?) ?? '',
      contato: x['contato'] as String?,
      pedidoId: x['pedido_id'] as String?,
      status: x['status'] as String,
      abertoEm: _data(x['aberto_em']),
      cautelaAte: _data(x['cautela_ate']),
      cautelaAdotadaEm: data(x['cautela_adotada_em']),
      responsavelId: x['responsavel_id'] as String?,
      desfecho: x['desfecho'] as String?,
      encerradoEm: data(x['encerrado_em']),
      cautelaAtrasada: x['cautela_atrasada'] == true,
      sinaisAntifraude: [for (final s in (x['sinais_antifraude'] as List? ?? const [])) '$s'],
      medidas: [
        for (final m in (x['medidas'] as List? ?? const []).map(_mapa))
          MedidaIncidente(
            id: m['id'] as String,
            tipo: m['tipo'] as String,
            descricao: m['descricao'] as String,
            origem: m['origem'] as String,
            aplicadaEm: _data(m['aplicada_em']),
          ),
      ],
    );
  }

  // ---------- moderação de avaliações (Termos 12.6) ----------

  static const _avaliacoes = '/v1/admin/avaliacoes';

  @override
  Future<PaginaRemota<RevisaoAvaliacao>> listarRevisoesAvaliacao(
      {String? status, String? avaliacaoId, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', '$_avaliacoes/revisoes', consulta: {
      'status': status,
      'avaliacao_id': avaliacaoId,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _revisaoAvaliacao(x)], _int(corpo['total']));
  }

  @override
  Future<RevisaoAvaliacao> analisarRevisaoAvaliacao(String revisaoId) async =>
      _revisaoAvaliacao(_mapa(await _chamar('POST', '$_avaliacoes/revisoes/$revisaoId/analisar')));

  @override
  Future<RevisaoAvaliacao> decidirRevisaoAvaliacao(
    String revisaoId, {
    required String status,
    required String resposta,
    String? ocultarMotivo,
    String? mesmoAnalistaJustificativa,
    String? justificativaAdiamento,
  }) async =>
      _revisaoAvaliacao(_mapa(await _chamar('POST', '$_avaliacoes/revisoes/$revisaoId/decidir', corpo: {
        'status': status,
        'resposta': resposta,
        'ocultar_motivo': ?ocultarMotivo,
        'mesmo_analista_justificativa': ?mesmoAnalistaJustificativa,
        if (justificativaAdiamento != null) ...{
          'adiar_aviso': true,
          'justificativa_adiamento': justificativaAdiamento,
        },
      })));

  @override
  Future<OcultacaoAvaliacao> ocultarAvaliacao(
    String avaliacaoId, {
    required String motivo,
    required String explicacao,
    String? justificativaAdiamento,
  }) async =>
      _ocultacaoAvaliacao(_mapa(await _chamar('POST', '$_avaliacoes/$avaliacaoId/ocultar', corpo: {
        'motivo': motivo,
        'explicacao': explicacao,
        if (justificativaAdiamento != null) ...{
          'adiar_aviso': true,
          'justificativa_adiamento': justificativaAdiamento,
        },
      })));

  @override
  Future<OcultacaoAvaliacao> avisarAutorAvaliacao(String avaliacaoId) async =>
      _ocultacaoAvaliacao(_mapa(
          await _chamar('POST', '$_avaliacoes/${Uri.encodeComponent(avaliacaoId)}/avisar-autor')));

  @override
  Future<OcultacaoAvaliacao> reverterOcultacaoAvaliacao(String avaliacaoId, {required String motivo}) async =>
      _ocultacaoAvaliacao(_mapa(await _chamar('POST', '$_avaliacoes/$avaliacaoId/reverter-ocultacao', corpo: {
        'motivo': motivo,
      })));

  RevisaoAvaliacao _revisaoAvaliacao(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return RevisaoAvaliacao(
      id: x['id'] as String,
      protocolo: x['protocolo'] as String,
      avaliacaoId: x['avaliacao_id'] as String,
      tipo: x['tipo'] as String,
      ocultacaoId: x['ocultacao_id'] as String?,
      solicitanteId: x['solicitante_id'] as String,
      justificativa: (x['justificativa'] as String?) ?? '',
      anexos: [for (final a in (x['anexos'] as List? ?? const [])) '$a'],
      canal: (x['canal'] as String?) ?? 'app',
      abertaEm: _data(x['aberta_em']),
      responderAte: _data(x['responder_ate']),
      status: x['status'] as String,
      analistaId: x['analista_id'] as String?,
      resposta: x['resposta'] as String?,
      mesmoAnalistaJustificativa: x['mesmo_analista_justificativa'] as String?,
      decididaEm: data(x['decidida_em']),
      ocultacaoAplicadaId: x['ocultacao_aplicada_id'] as String?,
    );
  }

  OcultacaoAvaliacao _ocultacaoAvaliacao(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return OcultacaoAvaliacao(
      id: x['id'] as String,
      avaliacaoId: x['avaliacao_id'] as String,
      motivo: x['motivo'] as String,
      explicacao: x['explicacao'] as String,
      analistaId: x['analista_id'] as String,
      ocultadaEm: _data(x['ocultada_em']),
      statusAnterior: x['status_anterior'] as String,
      autorAvisadoEm: data(x['autor_avisado_em']),
      revertidaEm: data(x['revertida_em']),
      revertidaPor: x['revertida_por'] as String?,
    );
  }

  // ---------- pedidos de titular LGPD (Termos 14.9 e 14.10) ----------

  static const _lgpdPedidos = '/v1/admin/lgpd/pedidos';

  @override
  Future<PaginaRemota<PedidoTitularLgpd>> listarPedidosLgpd(
      {String? status, String? tipo, String? usuarioId, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', _lgpdPedidos, consulta: {
      'status': status,
      'tipo': tipo,
      'usuario_id': usuarioId,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _pedidoLgpd(x)], _int(corpo['total']));
  }

  @override
  Future<PedidoTitularLgpd> analisarPedidoLgpd(String pedidoId) async =>
      _pedidoLgpd(_mapa(await _chamar('POST', '$_lgpdPedidos/$pedidoId/analisar')));

  @override
  Future<PedidoTitularLgpd> responderPedidoLgpd(
    String pedidoId, {
    required String status,
    required String resposta,
    String? motivoNaoAtendido,
    String? criteriosInformados,
  }) async =>
      _pedidoLgpd(_mapa(await _chamar('POST', '$_lgpdPedidos/$pedidoId/responder', corpo: {
        'status': status,
        'resposta': resposta,
        'motivo_nao_atendido': ?motivoNaoAtendido,
        'criterios_informados': ?criteriosInformados,
      })));

  PedidoTitularLgpd _pedidoLgpd(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return PedidoTitularLgpd(
      id: x['id'] as String,
      protocolo: x['protocolo'] as String,
      usuarioId: x['usuario_id'] as String?,
      contato: x['contato'] as String?,
      tipo: x['tipo'] as String,
      decisaoAutomatizada: x['decisao_automatizada'] as String?,
      referenciaTipo: x['referencia_tipo'] as String?,
      referenciaId: x['referencia_id'] as String?,
      descricao: (x['descricao'] as String?) ?? '',
      canal: (x['canal'] as String?) ?? 'app',
      exclusaoId: x['exclusao_id'] as String?,
      abertoEm: _data(x['aberto_em']),
      responderAte: _data(x['responder_ate']),
      status: x['status'] as String,
      analistaId: x['analista_id'] as String?,
      resposta: x['resposta'] as String?,
      motivoNaoAtendido: x['motivo_nao_atendido'] as String?,
      criteriosInformados: x['criterios_informados'] as String?,
      respondidoEm: data(x['respondido_em']),
    );
  }

  // ---------- guarda de retenção do pedido (Termos 14.8 e 16.3) ----------

  static String _doPedido(String id) => '/v1/admin/pedidos/${Uri.encodeComponent(id)}';

  @override
  Future<List<GuardaPedido>> listarGuardasPedido(String pedidoId) async =>
      [for (final g in _itens(await _chamar('GET', '${_doPedido(pedidoId)}/guardas'))) _guardaPedido(g)];

  @override
  Future<({GuardaPedido guarda, bool repetida})> abrirGuardaPedido(String pedidoId,
      {required String tipo, required String motivo}) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    // 201 é nova; 200 é a mesma guarda que já estava aberta.
    final r = await _enviar('POST', _uri('${_doPedido(pedidoId)}/guardas'),
        cabecalhos: {'Authorization': 'Bearer $token'}, corpo: {'tipo': tipo, 'motivo': motivo});
    if (!r.ok) throw _erro(r);
    return (guarda: _guardaPedido(_mapa(r.json)), repetida: r.status == 200);
  }

  @override
  Future<GuardaPedido> encerrarGuardaPedido(String pedidoId, String guardaId, {required String motivo}) async =>
      _guardaPedido(_mapa(await _chamar(
          'POST', '${_doPedido(pedidoId)}/guardas/${Uri.encodeComponent(guardaId)}/encerrar',
          corpo: {'motivo': motivo})));

  @override
  Future<RetencaoPedido> obterRetencaoPedido(String pedidoId) async {
    final r = _mapa(await _chamar('GET', '${_doPedido(pedidoId)}/retencao'));
    return RetencaoPedido(
      pedidoId: r['pedido_id'] as String,
      situacao: r['situacao'] as String,
      prazoAnos: r['prazo_anos'] as int,
      concluidoEm: r['concluido_em'] == null ? null : _data(r['concluido_em']),
      guardaAte: r['guarda_ate'] == null ? null : _data(r['guarda_ate']),
      bloqueios: [for (final b in r['bloqueios'] as List) '$b'],
    );
  }

  GuardaPedido _guardaPedido(Map<String, dynamic> g) => GuardaPedido(
        id: g['id'] as String,
        pedidoId: g['pedido_id'] as String,
        tipo: g['tipo'] as String,
        motivo: g['motivo'] as String,
        aberta: g['aberta'] as bool,
        criadaPor: g['criada_por'] as String,
        criadaEm: _data(g['criada_em']),
        encerradaEm: g['encerrada_em'] == null ? null : _data(g['encerrada_em']),
        encerradaPor: g['encerrada_por'] as String?,
      );

  // ---------- contestação de materiais (Termos 6.9) ----------

  static const _materiais = '/v1/admin/materiais/contestacoes';

  @override
  Future<PaginaRemota<ContestacaoMaterial>> listarContestacoesMaterial(
      {String? status, String? pedidoId, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', _materiais, consulta: {
      'status': status,
      'pedido_id': pedidoId,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _contestacaoMaterial(x)], _int(corpo['total']));
  }

  @override
  Future<ContestacaoMaterial> analisarContestacaoMaterial(String contestacaoId) async =>
      _contestacaoMaterial(_mapa(await _chamar('POST', '$_materiais/$contestacaoId/analisar')));

  @override
  Future<ContestacaoMaterial> decidirContestacaoMaterial(String contestacaoId,
          {required String status, required String resposta, int? valorReconhecidoCentavos}) async =>
      _contestacaoMaterial(_mapa(await _chamar('POST', '$_materiais/$contestacaoId/decidir', corpo: {
        'status': status,
        'resposta': resposta,
        'valor_reconhecido_centavos': ?valorReconhecidoCentavos,
      })));

  @override
  Future<ContestacaoMaterial> aprovarFinanceiroContestacaoMaterial(String contestacaoId,
          {required String motivo}) async =>
      _contestacaoMaterial(_mapa(await _chamar(
          'POST', '$_materiais/${Uri.encodeComponent(contestacaoId)}/aprovar-financeiro',
          corpo: {'motivo': motivo})));

  @override
  Future<EstornoMaterial> executarEstornoMaterial(String contestacaoId,
      {required String motivo, required bool materialPagoNoApp}) async {
    final r = _mapa(await _chamar('POST', '$_materiais/${Uri.encodeComponent(contestacaoId)}/executar-estorno',
        corpo: {'motivo': motivo, 'material_pago_no_app': materialPagoNoApp}));
    // Dinheiro só em centavos inteiros: valor ausente ou quebrado é erro, nunca vira zero.
    return EstornoMaterial(
      resultado: r['resultado'] as String,
      contestacao: _contestacaoMaterial(_mapa(r['contestacao'])),
      valorReconhecidoCentavos: r['valor_reconhecido_centavos'] as int,
      valorRetidoCentavos: r['valor_retido_centavos'] as int,
      valorCompensacaoCentavos: r['valor_compensacao_centavos'] as int,
      custoParcelamentoCentavos: r['custo_parcelamento_centavos'] as int,
      totalEstornadoCentavos: r['total_estornado_centavos'] as int,
      compensacaoId: r['compensacao_id'] as String?,
      profissionalAvisado: r['profissional_avisado'] as bool?,
    );
  }

  @override
  Future<List<AnexoMaterial>> abrirAnexosContestacaoMaterial(String contestacaoId, {required String motivo}) async => [
        for (final a in _itens(await _chamar('POST', '$_materiais/$contestacaoId/anexos', corpo: {'motivo': motivo})))
          AnexoMaterial(
            tipo: a['tipo'] as String,
            enviadoPor: a['enviado_por'] as String?,
            url: a['url'] as String?,
            tipoConteudo: a['content_type'] as String?,
            expiraEmSegundos: (a['expira_em_segundos'] as num?)?.toInt(),
          ),
      ];

  ContestacaoMaterial _contestacaoMaterial(Map<String, dynamic> x) {
    return ContestacaoMaterial(
      id: x['id'] as String,
      protocolo: x['protocolo'] as String,
      pedidoId: x['pedido_id'] as String,
      notaId: x['nota_id'] as String,
      itemId: x['item_id'] as String?,
      clienteId: x['cliente_id'] as String,
      motivo: x['motivo'] as String,
      descricao: (x['descricao'] as String?) ?? '',
      anexos: [for (final a in (x['anexos'] as List?) ?? const []) '$a'],
      valorContestadoCentavos: _int(x['valor_contestado_centavos']),
      abertaEm: _data(x['aberta_em']),
      responderAte: _data(x['responder_ate']),
      status: x['status'] as String,
      analistaId: x['analista_id'] as String?,
      resposta: x['resposta'] as String?,
      // Ausente continua nulo: nunca vira zero.
      valorReconhecidoCentavos:
          x['valor_reconhecido_centavos'] == null ? null : _int(x['valor_reconhecido_centavos']),
      decididaEm: x['decidida_em'] == null ? null : _data(x['decidida_em']),
      efeitoFinanceiro: (x['efeito_financeiro'] as String?) ?? '',
    );
  }

  // ---------- retorno de conta e impedimentos (Termos 20.9) ----------

  static const _conta = '/v1/admin/conta';

  @override
  Future<PaginaRemota<PedidoRetornoConta>> listarRetornosConta(
      {String? status, String? usuarioId, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', '$_conta/retornos', consulta: {
      'status': status,
      'usuario_id': usuarioId,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _retornoConta(x)], _int(corpo['total']));
  }

  @override
  Future<PedidoRetornoConta> analisarRetornoConta(String retornoId) async =>
      _retornoConta(_mapa(await _chamar('POST', '$_conta/retornos/$retornoId/analisar')));

  @override
  Future<PedidoRetornoConta> aprovarRetornoConta(String retornoId, {required String motivo}) async =>
      _retornoConta(_mapa(await _chamar('POST', '$_conta/retornos/$retornoId/aprovar', corpo: {
        'motivo': motivo,
        'risco_identificado': false,
      })));

  @override
  Future<PedidoRetornoConta> recusarRetornoConta(String retornoId,
          {required String motivo, required bool riscoIdentificado}) async =>
      _retornoConta(_mapa(await _chamar('POST', '$_conta/retornos/$retornoId/recusar', corpo: {
        'motivo': motivo,
        'risco_identificado': riscoIdentificado,
      })));

  @override
  Future<PaginaRemota<ImpedimentoCadastro>> listarImpedimentosConta(
      {String? medidaId, bool apenasAtivos = false, int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', '$_conta/impedimentos', consulta: {
      'medida_id': medidaId,
      'apenas_ativos': apenasAtivos ? 'true' : 'false',
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _impedimentoCadastro(x)], _int(corpo['total']));
  }

  @override
  Future<ImpedimentoCadastro> revogarImpedimentoConta(String impedimentoId, {required String motivo}) async =>
      _impedimentoCadastro(_mapa(await _chamar('POST', '$_conta/impedimentos/$impedimentoId/revogar', corpo: {
        'motivo': motivo,
      })));

  PedidoRetornoConta _retornoConta(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return PedidoRetornoConta(
      id: x['id'] as String,
      protocolo: x['protocolo'] as String,
      usuarioId: x['usuario_id'] as String,
      medidaId: x['medida_id'] as String,
      justificativaUsuario: (x['justificativa_usuario'] as String?) ?? '',
      canal: (x['canal'] as String?) ?? 'app',
      status: x['status'] as String,
      solicitadoEm: _data(x['solicitado_em']),
      prazoDiasAplicado: _int(x['prazo_dias_aplicado']),
      elegivelAPartirDe: _data(x['elegivel_a_partir_de']),
      analistaId: x['analista_id'] as String?,
      decisaoMotivo: x['decisao_motivo'] as String?,
      riscoIdentificado: x['risco_identificado'] == true,
      decididoEm: data(x['decidido_em']),
    );
  }

  ImpedimentoCadastro _impedimentoCadastro(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return ImpedimentoCadastro(
      id: x['id'] as String,
      medidaId: x['medida_id'] as String,
      tipoIdentificador: x['tipo_identificador'] as String,
      criadoPor: x['criado_por'] as String,
      criadoEm: _data(x['criado_em']),
      revogadoEm: data(x['revogado_em']),
      revogadoPor: x['revogado_por'] as String?,
      motivoRevogacao: x['motivo_revogacao'] as String?,
    );
  }

  // ---------- compensações (Termos 8.6) ----------

  @override
  Future<PaginaRemota<Compensacao>> listarCompensacoes(
      {String? profissionalId,
      String? pedidoId,
      String? status,
      bool revisaoPendente = false,
      int deslocamento = 0,
      int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/compensacoes', consulta: {
      'revisao_pendente': revisaoPendente ? 'true' : null,
      'profissional_id': profissionalId,
      'pedido_id': pedidoId,
      'status': status,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _compensacao(x)], _int(corpo['total']));
  }

  @override
  Future<({String resultado, Compensacao compensacao, bool avisado})> registrarCompensacao(
      {required String pedidoId, String? contestacaoId, required int valorCentavos, required String motivo}) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/compensacoes', corpo: {
      'pedido_id': pedidoId,
      'contestacao_id': contestacaoId,
      'valor_centavos': valorCentavos,
      'motivo': motivo,
    }));
    return (
      resultado: r['resultado'] as String,
      compensacao: _compensacao(_mapa(r['compensacao'])),
      avisado: r['avisado'] == true,
    );
  }

  @override
  Future<({Compensacao compensacao, bool avisado})> avisarCompensacao(String id) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/compensacoes/$id/avisar'));
    return (compensacao: _compensacao(_mapa(r['compensacao'])), avisado: r['avisado'] == true);
  }

  @override
  Future<({String resultado, int devolvidoCentavos, Compensacao compensacao})> reduzirCompensacao(String id,
      {required String contestacaoId, required int novoValorCentavos, required String motivo}) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/compensacoes/$id/reduzir', corpo: {
      'contestacao_id': contestacaoId,
      'novo_valor_centavos': novoValorCentavos,
      'motivo': motivo,
    }));
    return (
      resultado: r['resultado'] as String,
      devolvidoCentavos: r['devolvido_centavos'] as int,
      compensacao: _compensacao(_mapa(r['compensacao'])),
    );
  }

  @override
  Future<({String resultado, int devolvidoCentavos, Compensacao compensacao})> cancelarCompensacao(String id,
      {required String motivo}) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/compensacoes/$id/cancelar', corpo: {'motivo': motivo}));
    return (
      resultado: r['resultado'] as String,
      devolvidoCentavos: r['devolvido_centavos'] as int,
      compensacao: _compensacao(_mapa(r['compensacao'])),
    );
  }

  /// Dinheiro só em centavos inteiros: valor ausente ou quebrado é erro, nunca vira zero.
  Compensacao _compensacao(Map<String, dynamic> x) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    return Compensacao(
      id: x['id'] as String,
      pedidoId: x['pedido_id'] as String,
      origem: x['origem'] as String,
      valorCentavos: x['valor_centavos'] as int,
      compensadoCentavos: x['compensado_centavos'] as int,
      restanteCentavos: x['restante_centavos'] as int,
      motivo: x['motivo'] as String,
      status: x['status'] as String,
      criadaEm: _data(x['criada_em']),
      avisadoEm: data(x['avisado_em']),
      canceladaEm: data(x['cancelada_em']),
      motivoCancelamento: x['motivo_cancelamento'] as String?,
      suspensa: x['suspensa'] == true,
      revisao: x['revisao'] as String?,
      revisaoContestacaoId: x['revisao_contestacao_id'] as String?,
      podeReduzir: x['pode_reduzir'] == true,
      reducaoMaximaCentavos: x['reducao_maxima_centavos'] as int?,
      podeCancelar: x['pode_cancelar'] == true,
      valorOriginalCentavos: x['valor_original_centavos'] as int?,
      reduzidoCentavos: (x['reduzido_centavos'] as int?) ?? 0,
      devolvidoReducaoCentavos: (x['devolvido_reducao_centavos'] as int?) ?? 0,
    );
  }

  @override
  Future<PaginaRemota<ExclusividadeCliente>> listarExclusividades(
      {String? pedidoId, String? clienteId, String? status, int deslocamento = 0, int limite = 20}) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/exclusividades', consulta: {
      'pedido_id': pedidoId,
      'cliente_id': clienteId,
      'status': status,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([
      for (final e in _itens(corpo))
        ExclusividadeCliente(
          id: e['id'] as String,
          pedidoId: e['pedido_id'] as String,
          clienteId: e['cliente_id'] as String,
          clienteNome: e['cliente_nome'] as String?,
          profissionalId: e['profissional_id'] as String,
          profissionalNome: e['profissional_nome'] as String?,
          status: e['status'] as String,
          moedas: _int(e['moedas']),
          estornada: e['estornada'] == true,
          criadaEm: _data(e['criada_em']),
          encerradaEm: e['encerrada_em'] == null ? null : _data(e['encerrada_em']),
          motivoEncerramento: e['motivo_encerramento'] as String?,
        ),
    ], _int(corpo['total']));
  }

  // ---------- medidas de conta (Termos 20) ----------

  @override
  Future<PaginaRemota<Medida>> listarMedidas(FiltroMedidas f, {int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/medidas', consulta: {
      'usuario_id': f.usuarioId,
      'tipo': f.tipo,
      'vigentes': f.vigentes ? 'true' : null,
      'contestacao_aberta': f.contestacaoAberta ? 'true' : null,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _medida(x)], _int(corpo['total']));
  }

  Future<Medida> _acaoMedida(String metodo, String caminho, [Object? corpo]) async =>
      _medida(_mapa(await _chamar(metodo, '/v1/admin/medidas$caminho', corpo: corpo)));

  @override
  Future<Medida> obterMedida(String id) => _acaoMedida('GET', '/$id');

  @override
  Future<int> prazoMaximoTravaFraude() async {
    final n = _mapa(await _chamar('GET', '/v1/admin/medidas/trava-fraude'))['prazo_maximo_dias'];
    if (n is! int || n < 1) throw const ErroApi('O servidor não informou o prazo máximo da trava.');
    return n;
  }

  @override
  Future<({Medida medida, bool repetida})> aplicarMedida(NovaMedida n) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    // Direto no transporte: 201 é medida nova e 200 é repetição, e a tela precisa saber.
    final r = await _enviar('POST', _uri('/v1/admin/medidas'), cabecalhos: {
      'Authorization': 'Bearer $token'
    }, corpo: {
      'usuario_id': n.usuarioId,
      'tipo': n.tipo,
      'motivo': n.motivo,
      'clausulas': n.clausulas,
      'dias': n.dias,
      'detalhe_adiado': n.detalheAdiado,
      // Campos com padrão no servidor só vão quando preenchidos.
      'efeito_pedidos_valores': ?n.efeito,
      'como_contestar': ?n.comoContestar,
      'justificativa_adiamento': ?n.justificativaAdiamento,
      'nota_interna': ?n.notaInterna,
      if (n.infracaoGrave) 'infracao_grave': true,
      'sem_falta': ?n.semFalta,
      if (n.impedirNovaConta) 'impedir_nova_conta': true,
      if (n.motivoFraude) ...{'motivo_fraude': true, 'limite_retencao_centavos': n.limiteRetencaoCentavos},
    });
    if (!r.ok) throw _erro(r);
    return (medida: _medida(_mapa(r.json)), repetida: r.status == 200);
  }

  @override
  Future<Medida> reverterMedida(String id, {required String motivo}) =>
      _acaoMedida('POST', '/$id/reverter', {'motivo': motivo});

  @override
  Future<Medida> registrarContestacaoMedida(String id, {required String versao, List<String> anexos = const []}) =>
      _acaoMedida('POST', '/$id/contestacao', {'versao': versao, 'anexos': anexos});

  @override
  Future<EnvioAssinado> pedirAnexoContestacao(String medidaId,
      {required String nomeArquivo, required String tipoConteudo, required int tamanhoBytes}) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/medidas/$medidaId/contestacao/anexos',
        corpo: {'nome_arquivo': nomeArquivo, 'content_type': tipoConteudo, 'tamanho_bytes': tamanhoBytes}));
    return EnvioAssinado(
        id: r['anexo_id'] as String, url: r['url'] as String, expiraEmSegundos: _int(r['expira_em_segundos']));
  }

  @override
  Future<List<AnexoContestacao>> abrirAnexosContestacao(String medidaId, {required String motivo}) async => [
        for (final a in _itens(await _chamar('POST', '/v1/admin/medidas/$medidaId/contestacao/anexos/abrir',
            corpo: {'motivo': motivo})))
          _anexoContestacao(a),
      ];

  AnexoContestacao _anexoContestacao(Map<String, dynamic> a) => AnexoContestacao(
        anexoId: a['anexo_id'] as String,
        tipoConteudo: a['content_type'] as String,
        tamanhoBytes: _int(a['tamanho_bytes']),
        url: a['url'] as String?,
        expiraEmSegundos: (a['expira_em_segundos'] as num?)?.toInt(),
      );

  @override
  Future<void> enviarArquivo(String url, {required String tipoConteudo, required List<int> bytes}) async {
    final destino = Uri.tryParse(url);
    if (destino == null || destino.scheme != 'https') {
      throw const ErroApi('O servidor mandou um link de envio inválido. Nada foi enviado.');
    }
    // Direto ao armazenamento: o link já autoriza. O token de login não vai junto.
    final pedido = http.Request('PUT', destino)
      ..headers['Content-Type'] = tipoConteudo
      ..headers['x-upsert'] = 'true'
      ..bodyBytes = bytes;
    try {
      final r = await _cliente.send(pedido).timeout(const Duration(seconds: 60));
      await r.stream.drain<void>();
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw ErroApi('O envio do arquivo foi recusado (${r.statusCode}). Tente de novo.');
      }
    } on TimeoutException {
      throw const ErroApi('O envio do arquivo demorou demais. Tente de novo.');
    } on http.ClientException {
      throw const ErroApi('Não foi possível enviar o arquivo.');
    }
  }

  ArquivoComprovante _comprovante(Map<String, dynamic> a) => ArquivoComprovante(
        arquivoId: a['arquivo_id'] as String,
        finalidade: a['finalidade'] as String,
        enviadoPor: a['enviado_por'] as String,
        tipoConteudo: a['content_type'] as String?,
        tamanhoBytes: _int(a['tamanho_bytes']),
        enviadoEm: _data(a['enviado_em']),
        url: a['url'] as String,
        expiraEmSegundos: _int(a['expira_em_segundos']),
      );

  @override
  Future<List<ArquivoComprovante>> listarComprovantes(String pedidoId, {required String motivo}) async => [
        for (final a in _itens(
            await _chamar('POST', '/v1/admin/ausencias/$pedidoId/arquivos', corpo: {'motivo': motivo})))
          _comprovante(a),
      ];

  @override
  Future<EnvioAssinado> pedirEnvioComprovante(String pedidoId,
      {required String motivo,
      required String nomeArquivo,
      required String tipoConteudo,
      required int tamanhoBytes}) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/ausencias/$pedidoId/arquivos/envio', corpo: {
      'motivo': motivo,
      'nome_arquivo': nomeArquivo,
      'content_type': tipoConteudo,
      'tamanho_bytes': tamanhoBytes,
    }));
    return EnvioAssinado(
        id: r['envio_id'] as String, url: r['url'] as String, expiraEmSegundos: _int(r['expira_em_segundos']));
  }

  @override
  Future<ArquivoComprovante> concluirComprovante(String pedidoId, String envioId, {required String motivo}) async =>
      _comprovante(_mapa(await _chamar(
          'POST', '/v1/admin/ausencias/$pedidoId/arquivos/envio/$envioId/concluir',
          corpo: {'motivo': motivo})));

  @override
  Future<Medida> decidirContestacaoMedida(String id,
          {required String resultado,
          required String resposta,
          int? diasAPartirDeHoje,
          String? mesmoAnalistaJustificativa}) =>
      _acaoMedida('POST', '/$id/contestacao/decisao', {
        'resultado': resultado,
        'resposta': resposta,
        'dias_a_partir_de_hoje': diasAPartirDeHoje,
        'mesmo_analista_justificativa': mesmoAnalistaJustificativa,
      });

  ResumoPedidos? _resumoPedidos(Map<String, dynamic> m) {
    if (m['pedidos_futuros_cancelados'] is! num) return null;
    List<String> ids(Object? v) => [if (v is List) for (final x in v) '$x'];
    return ResumoPedidos(
      futurosCancelados: (m['pedidos_futuros_cancelados'] as num).toInt(),
      emAndamento: (m['pedidos_em_andamento'] as num?)?.toInt() ?? 0,
      emAndamentoIds: ids(m['pedidos_em_andamento_ids']),
      futurosPendentesIds: ids(m['pedidos_futuros_pendentes_ids']),
    );
  }

  Medida _medida(Map<String, dynamic> m) {
    DateTime? data(Object? v) => v == null ? null : _data(v);
    final c = m['contestacao'] is Map ? _mapa(m['contestacao']) : null;
    return Medida(
      id: m['id'] as String,
      protocolo: m['protocolo'] as String?,
      usuarioId: m['usuario_id'] as String,
      usuarioNome: m['usuario_nome'] as String?,
      tipo: m['tipo'] as String,
      motivoAoUsuario: m['motivo'] as String,
      motivoCompleto: m['motivo_completo'] as String,
      clausulas: [for (final x in (m['clausulas'] as List)) '$x'],
      inicioEm: _data(m['inicio_em']),
      fimEm: data(m['fim_em']),
      avisadoEm: data(m['avisado_em']),
      efeito: m['efeito_pedidos_valores'] as String,
      comoContestar: m['como_contestar'] as String,
      detalheAdiado: m['detalhe_adiado'] == true,
      vigente: m['vigente'] == true,
      revertidaEm: data(m['revertida_em']),
      contestavelAte: data(m['contestavel_ate']),
      origem: (m['origem'] as String?) ?? 'analista',
      aplicadaPor: m['aplicada_por'] as String?,
      notaInterna: m['nota_interna'] as String?,
      justificativaAdiamento: m['justificativa_adiamento'] as String?,
      aplicadaPorNome: m['aplicada_por_nome'] as String?,
      contestacaoAnalistaNome: m['contestacao_analista_nome'] as String?,
      motivoFraude: m['motivo_fraude'] == true,
      limiteRetencaoCentavos: (m['limite_retencao_centavos'] as num?)?.toInt(),
      infracaoGrave: m['infracao_grave'] == true,
      semFalta: m['sem_falta'] is bool ? m['sem_falta'] as bool : null,
      impedirNovaConta: m['impedir_nova_conta'] == true,
      pedidos: _resumoPedidos(m),
      contestacao: c == null
          ? null
          : ContestacaoMedida(
              status: c['status'] as String,
              versao: c['versao'] as String,
              canal: c['canal'] as String,
              protocolo: c['protocolo'] as String?,
              abertaEm: _data(c['aberta_em']),
              responderAte: _data(c['responder_ate']),
              resposta: c['resposta'] as String?,
              decididaEm: data(c['decidida_em']),
              anexos: [for (final x in (c['anexos'] as List? ?? const [])) _anexoContestacao(_mapa(x))],
            ),
    );
  }

  // ---------- cliente ausente (Termos 7.6) ----------

  @override
  Future<List<CasoAusencia>> listarAusencias() async =>
      [for (final a in _itens(await _chamar('GET', '/v1/admin/ausencias'))) _ausencia(a)];

  @override
  Future<CasoAusencia> obterAusencia(String pedidoId) async =>
      _ausencia(_mapa(await _chamar('GET', '/v1/admin/ausencias/$pedidoId')));

  @override
  Future<CasoAusencia> decidirAusencia(
    String pedidoId, {
    required bool aceitarJustificativa,
    required String justificativa,
    int retencaoCentavos = 0,
    String? retencaoJustificativa,
    List<String> retencaoComprovantes = const [],
  }) async =>
      _ausencia(_mapa(await _chamar('POST', '/v1/admin/ausencias/$pedidoId/decisao', corpo: {
        'aceitar_justificativa': aceitarJustificativa,
        'justificativa': justificativa,
        'retencao_centavos': retencaoCentavos,
        'retencao_justificativa': retencaoJustificativa,
        'retencao_comprovantes': retencaoComprovantes,
      })));

  @override
  Future<CasoAusencia> confirmarAusencia(String pedidoId,
          {required bool retirarRetencao, required String motivo}) async =>
      _ausencia(_mapa(await _chamar('POST', '/v1/admin/ausencias/$pedidoId/confirmar',
          corpo: {'motivo': motivo, 'retirar_retencao': retirarRetencao})));

  @override
  Future<List<AnexoCaso>> anexosAusencia(String pedidoId, {required String motivo}) async => [
        // POST de propósito: o motivo vai no corpo e não fica em log de URL.
        for (final a in _itens(
            await _chamar('POST', '/v1/admin/ausencias/$pedidoId/anexos', corpo: {'motivo': motivo})))
          AnexoCaso(
            tipo: a['tipo'] as String,
            arquivoId: a['arquivo_id'] as String,
            enviadoPor: a['enviado_por'] as String?,
            url: a['url'] as String?,
            tipoConteudo: a['content_type'] as String?,
            expiraEmSegundos: (a['expira_em_segundos'] as num?)?.toInt(),
          ),
      ];

  @override
  Future<CasoAusencia> decidirContestacaoAusencia(String pedidoId,
          {required String resultado, required String resposta, int? retencaoCentavos}) async =>
      _ausencia(_mapa(await _chamar('POST', '/v1/admin/ausencias/$pedidoId/contestacao/decisao', corpo: {
        'resultado': resultado,
        'resposta': resposta,
        'retencao_centavos': retencaoCentavos,
      })));

  // ---------- conversa do pedido (Termos 11.3) ----------

  @override
  Future<List<ConversaLida>> lerConversas(String pedidoId,
      {required String motivo, required String base, String? referencia}) async {
    final r = _mapa(await _chamar('POST', '/v1/admin/pedidos/$pedidoId/conversas/leitura',
        corpo: {'motivo': motivo, 'base': base, 'referencia': referencia}));
    return [
      for (final c in (r['conversas'] as List? ?? const []).map(_mapa))
        ConversaLida(
          id: c['conversa_id'] as String,
          profissionalId: c['profissional_id'] as String,
          mensagens: [
            for (final x in (c['mensagens'] as List? ?? const []).map(_mapa))
              MensagemLida(
                autorId: x['autor_id'] as String,
                texto: x['texto'] as String,
                textoExibido: x['texto_exibido'] as String,
                mascarada: x['mascarada'] == true,
                enviadaEm: _data(x['enviada_em']),
              ),
          ],
        ),
    ];
  }

  CasoAusencia _ausencia(Map<String, dynamic> a) {
    DateTime? data(String chave) => a[chave] == null ? null : _data(a[chave]);
    List<String> textos(String chave) => [for (final x in (a[chave] as List? ?? const [])) '$x'];
    return CasoAusencia(
      pedidoId: a['pedido_id'] as String,
      status: a['status'] as String,
      chegadaEm: _data(a['chegada_em']),
      registradaEm: data('registrada_em'),
      justificativaAte: data('justificativa_ate'),
      justificativaTexto: a['justificativa_texto'] as String?,
      anexos: textos('anexos'),
      justificativaEnviadaEm: data('justificativa_enviada_em'),
      decisao: a['decisao'] as String?,
      retencaoCentavos: (a['retencao_centavos'] as num?)?.toInt(),
      retencaoJustificativa: a['retencao_justificativa'] as String?,
      retencaoComprovantes: textos('retencao_comprovantes'),
      cancelamentoStatus: a['cancelamento_status'] as String?,
      reembolsoCentavos: (a['reembolso_centavos'] as num?)?.toInt(),
      contestarAte: data('contestar_ate'),
      contestacao: a['contestacao'] is Map ? _contestacao(_mapa(a['contestacao'])) : null,
      valorServicoCentavos: (a['valor_servico_centavos'] as num?)?.toInt(),
      pedidoNumero: (a['pedido_numero'] as num?)?.toInt(),
      clienteNome: a['cliente_nome'] as String?,
      profissionalNome: a['profissional_nome'] as String?,
    );
  }

  ContestacaoAusencia _contestacao(Map<String, dynamic> c) => ContestacaoAusencia(
        status: c['status'] as String,
        texto: c['texto'] as String,
        abertaEm: _data(c['aberta_em']),
        responderAte: _data(c['responder_ate']),
        protocolo: c['protocolo'] as String?,
        resposta: c['resposta'] as String?,
        decididaEm: c['decidida_em'] == null ? null : _data(c['decidida_em']),
      );

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
      status: _estadoDisputa[d['estado']] ?? StatusDisputa.desconhecida,
      decisao: decisao,
      valorReembolsoCentavos: divisao == null ? null : _int(divisao['para_cliente_centavos']),
      divisao: divisao == null
          ? null
          : DivisaoDisputa(
              paraClienteCentavos: _int(divisao['para_cliente_centavos']),
              paraProfissionalCentavos: _int(divisao['para_profissional_centavos']),
              retidoCentavos: _int(divisao['retido_centavos']),
            ),
      decididoPor: d['decidido_por'] as String?,
      responsavelId: d['responsavel_id'] as String?,
      responsavelNome: d['responsavel_nome'] as String?,
      desistencia: d['desistencia'] == true,
      resultadoEsperado: d['resultado_esperado'] as String?,
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
        'cancelar_pessoa_diferente' => 'Pedido cancelado: chegou uma pessoa diferente da verificada',
        'abrir_disputa' => 'Cliente relatou um problema',
        'responder_disputa' => 'Profissional respondeu',
        'decidir_disputa' => 'Disputa decidida pela equipe',
        'proposta_retorno' => 'Proposta de acordo',
        'encerrar_disputa_por_acordo' => 'Disputa encerrada por acordo entre as partes',
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
    final estado = _estadoDisputa[_mapa(corpo)['estado']] ?? StatusDisputa.desconhecida;
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

  /// `trava_fraude_vigente`: ausente, null ou outro tipo = não informado.
  static bool? _travaVigente(Map<String, dynamic> m) {
    final v = m['trava_fraude_vigente'];
    return v is bool ? v : null;
  }

  UsuarioBusca _usuario(Map<String, dynamic> u) => UsuarioBusca(
        id: u['id'] as String,
        travaFraudeVigente: _travaVigente(u),
        nivelVerificacao: u['nivel_verificacao'] as String?,
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
  Future<ResumoPedidos?> alterarStatusUsuario(String usuarioId, {required String status, required String motivo, String? motivoUsuario, List<String> clausulas = const []}) async {
    final r = await _chamar(
      'POST',
      '/v1/admin/usuarios/$usuarioId/status',
      corpo: {'status': status, 'motivo': motivo, 'motivo_usuario': ?motivoUsuario, if (clausulas.isNotEmpty) 'clausulas': clausulas},
    );
    return r is Map ? _resumoPedidos(_mapa(r)) : null;
  }

  @override
  Future<ResultadoSeloAdmin> mudarSelo(String usuarioId, String operacao,
      {required String motivo, required String chaveIdempotencia}) async {
    final id = Uri.encodeComponent(usuarioId);
    final r = _mapa(await _chamar('POST', '/v1/admin/profissionais/$id/selo/$operacao',
        corpo: {'motivo': motivo, 'chave_idempotencia': chaveIdempotencia}));
    return ResultadoSeloAdmin(
      jaExistia: r['resultado'] == 'ja_existe',
      nivelVerificacao: (r['nivel_verificacao'] as String?) ?? '',
      retiradaAberta: r['retirada_aberta'] == true,
    );
  }

  @override
  Future<UsuarioBusca> inativarUsuario(String usuarioId, {required String motivo}) async {
    final id = Uri.encodeComponent(usuarioId);
    final r = _mapa(await _chamar('POST', '/v1/admin/usuarios/$id/inativar', corpo: {'motivo': motivo}));
    return _usuario(r);
  }

  @override
  Future<UsuarioBusca> reativarUsuario(String usuarioId, {required String motivo}) async {
    final id = Uri.encodeComponent(usuarioId);
    final r = _mapa(await _chamar('POST', '/v1/admin/usuarios/$id/reativar', corpo: {'motivo': motivo}));
    return _usuario(r);
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

  // ---------- atendimento (Termos 25) ----------

  @override
  Future<PaginaRemota<Chamado>> listarChamados(FiltroChamados filtro, {int deslocamento = 0, int limite = 50}) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/chamados', consulta: {
      'status': filtro.status,
      'categoria': filtro.categoria,
      'prioridade': filtro.prioridade,
      'responsavel_id': filtro.responsavelId,
      'protocolo': filtro.protocolo,
      'atrasados': filtro.atrasados ? 'true' : null,
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final c in _itens(corpo)) _chamado(c)], _int(corpo['total']));
  }

  Future<Chamado> _acaoChamado(String metodo, String caminho, [Object? corpo]) async =>
      _chamado(_mapa(await _chamar(metodo, '/v1/admin/chamados$caminho', corpo: corpo)));

  @override
  Future<Chamado> obterChamado(String id) => _acaoChamado('GET', '/$id');

  @override
  Future<Chamado> registrarContato(NovoContato c) => _acaoChamado('POST', '', {
        'canal': c.canal,
        'categoria': c.categoria,
        'assunto': c.assunto,
        'texto': c.texto,
        'nome_contato': c.nomeContato,
        'contato': c.contato,
        'usuario_id': c.usuarioId,
        'pedido_id': c.pedidoId,
        'prioridade': c.prioridade,
      });

  @override
  Future<Chamado> assumirChamado(String id, {bool substituir = false}) =>
      _acaoChamado('POST', '/$id/assumir', {'substituir': substituir});

  @override
  Future<Chamado> responderChamado(String id,
          {required String texto, bool interna = false, bool aguardarUsuario = false}) =>
      _acaoChamado('POST', '/$id/mensagens', {'texto': texto, 'interna': interna, 'aguardar_usuario': aguardarUsuario});

  @override
  Future<Chamado> estenderPrazoChamado(String id, {required DateTime ate, required String motivo}) =>
      _acaoChamado('POST', '/$id/prazo', {'novo_prazo_ate': ate.toUtc().toIso8601String(), 'motivo': motivo});

  @override
  Future<Chamado> encerrarChamado(String id, {required String mensagem}) =>
      _acaoChamado('POST', '/$id/encerrar', {'mensagem': mensagem});

  Chamado _chamado(Map<String, dynamic> c) {
    DateTime? data(String k) => c[k] == null ? null : _data(c[k]);
    return Chamado(
      id: c['id'] as String,
      protocolo: c['protocolo'] as String,
      assunto: c['assunto'] as String,
      solicitante: (c['solicitante'] as String?) ?? '',
      status: c['status'] as String,
      abertoEm: _data(c['aberto_em']),
      categoria: c['categoria'] as String,
      canal: c['canal'] as String,
      responderAte: _data(c['responder_ate']),
      prioridade: (c['prioridade'] as String?) ?? 'normal',
      usuarioId: c['usuario_id'] as String?,
      nomeContato: c['nome_contato'] as String?,
      contato: c['contato'] as String?,
      pedidoId: c['pedido_id'] as String?,
      responsavelId: c['responsavel_id'] as String?,
      responsavelNome: c['responsavel_nome'] as String?,
      contestacaoRetencao: c['contestacao_retencao'] == true,
      novoPrazoAte: data('novo_prazo_ate'),
      motivoExtensao: c['motivo_extensao'] as String?,
      primeiraRespostaEm: data('primeira_resposta_em'),
      encerradoEm: data('encerrado_em'),
      atrasado: c['atrasado'] == true,
      mensagens: [
        for (final x in (c['mensagens'] as List? ?? const []).map(_mapa))
          MensagemChamado(
            autor: x['autor'] as String,
            texto: x['texto'] as String,
            criadaEm: _data(x['criada_em']),
            interna: x['interna'] == true,
          ),
      ],
    );
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
          aceitaRemoto: c['aceita_remoto'] as bool? ?? false,
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
    bool aceitaRemoto = false,
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
        'aceita_remoto': aceitaRemoto,
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
      aceitaRemoto: r['aceita_remoto'] as bool? ?? false,
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
    bool? aceitaRemoto,
    required String motivo,
  }) async {
    final r = _mapa(await _chamar(
      'PUT',
      '/v1/admin/categorias/$id',
      corpo: {
        'nome': ?nome,
        'slug': ?slug,
        'icone': ?icone,
        'garantia_retrabalho_dias': ?garantiaDias,
        'ordem': ?ordem,
        'ativa': ?ativa,
        'aceita_remoto': ?aceitaRemoto,
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
      aceitaRemoto: r['aceita_remoto'] as bool? ?? false,
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
          if (v['parametros'] is List) return _versao(v);
          // Servidores antigos ou mocks podem devolver apenas o resumo; busca o detalhe se faltar.
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
    await _chamar('DELETE', '/v1/admin/config/versoes/$versaoId', consulta: {'motivo': motivo});
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
        'opcoes': ?opcoes,
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
        'texto': ?texto,
        'tipo': ?tipo,
        'opcoes': ?opcoes,
        'obrigatoria': ?obrigatoria,
        'ordem': ?ordem,
        'ativa': ?ativa,
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
          travaFraudeVigente: _travaVigente(a),
          usuarioId: a['usuario_id'] as String?,
          usuarioNome: a['usuario_nome'] as String?,
          usuarioTipo: a['usuario_tipo'] as String?,
          usuarioStatus: a['usuario_status'] as String?,
          pedidoId: a['pedido_id'] as String?,
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
  Future<void> aplicarBloqueioPreventivo(String usuarioId, {required String motivo, String? motivoUsuario, List<String> clausulas = const []}) async {
    await _chamar('POST', '/v1/admin/risco/bloqueio-preventivo', corpo: {'usuario_id': usuarioId, 'motivo': motivo, 'motivo_usuario': ?motivoUsuario, if (clausulas.isNotEmpty) 'clausulas': clausulas});
  }

  @override
  Future<void> desbloquearConta(String usuarioId, {required String motivo}) async {
    await _chamar('POST', '/v1/admin/risco/desbloqueio', corpo: {'usuario_id': usuarioId, 'motivo': motivo});
  }

  @override
  Future<String?> travarSaque(String usuarioId,
          {required String motivo,
          String? motivoUsuario,
          List<String> clausulas = const [],
          bool motivoFraude = false,
          int? limiteRetencaoCentavos,
          int? dias}) async =>
      _mensagemDe(await _chamar('POST', '/v1/admin/risco/travar-saque', corpo: {
        'usuario_id': usuarioId,
        'motivo': motivo,
        'motivo_usuario': ?motivoUsuario,
        if (clausulas.isNotEmpty) 'clausulas': clausulas,
        // O limite só vai com fraude: sem ela o backend recusa o campo.
        if (motivoFraude) ...{'motivo_fraude': true, 'limite_retencao_centavos': limiteRetencaoCentavos},
        'dias': ?dias,
      }));

  @override
  Future<String?> destravarSaque(String usuarioId, {required String motivo}) async =>
      _mensagemDe(await _chamar('POST', '/v1/admin/risco/destravar-saque', corpo: {'usuario_id': usuarioId, 'motivo': motivo}));

  static String? _mensagemDe(Object? corpo) {
    final texto = corpo is Map ? corpo['mensagem'] : null;
    return texto is String && texto.trim().isNotEmpty ? texto.trim() : null;
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
        'categoria_id': ?categoriaId,
        'cidade_id': ?cidadeId,
        'motivo': motivo,
      },
    ));
    return _campanha(c);
  }

  // ---------- Módulo 5: Gestão de Cupons ----------

  // ---------- falhas da plataforma (Termos 22.3) ----------

  JanelaIndisponibilidade _janela(Map<String, dynamic> j) => JanelaIndisponibilidade(
        id: j['id'] as String,
        origem: j['origem'] as String,
        inicioEm: _data(j['inicio_em']),
        fimEm: j['fim_em'] == null ? null : _data(j['fim_em']),
        ativa: j['ativa'] == true,
        motivo: j['motivo'] as String,
        criadaPor: j['criada_por'] as String,
        encerradaPor: j['encerrada_por'] as String?,
      );

  @override
  Future<PaginaRemota<JanelaIndisponibilidade>> listarIndisponibilidades(
      {String? origem, bool abertas = false, int deslocamento = 0, int limite = 20}) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/indisponibilidades', consulta: {
      'origem': origem,
      'abertas': '$abertas',
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota([for (final x in _itens(corpo)) _janela(x)], _int(corpo['total']));
  }

  @override
  Future<({JanelaIndisponibilidade janela, bool repetida})> registrarIndisponibilidade(
      {required String origem, required String inicioEm, String? fimEm, required String motivo}) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    // Direto no transporte: 201 é registro novo e 200 é repetição.
    final r = await _enviar('POST', _uri('/v1/admin/indisponibilidades'),
        cabecalhos: {'Authorization': 'Bearer $token'},
        corpo: {'origem': origem, 'inicio_em': inicioEm, 'fim_em': fimEm, 'motivo': motivo});
    if (!r.ok) throw _erro(r);
    return (janela: _janela(_mapa(r.json)), repetida: r.status == 200);
  }

  @override
  Future<JanelaIndisponibilidade> encerrarIndisponibilidade(String id,
          {String? fimEm, required String motivo}) async =>
      _janela(_mapa(await _chamar('POST', '/v1/admin/indisponibilidades/${Uri.encodeComponent(id)}/encerrar',
          corpo: {'motivo': motivo, 'fim_em': fimEm})));

  static CasoCheckoutSemCodigo _casoCheckoutSemCodigo(Map<String, dynamic> c) => CasoCheckoutSemCodigo(
        id: c['id'] as String,
        pedidoId: c['pedido_id'] as String,
        clienteId: c['cliente_id'] as String,
        profissionalId: c['profissional_id'] as String?,
        checkOutEm: _data(c['check_out_em']),
        contatadoEm: c['contatado_em'] == null ? null : _data(c['contatado_em']),
        canal: c['canal'] as String?,
        responderAte: c['responder_ate'] == null ? null : _data(c['responder_ate']),
        vencido: c['vencido'] == true,
      );

  @override
  Future<PaginaRemota<CasoCheckoutSemCodigo>> listarCheckoutSemCodigo({int deslocamento = 0, int limite = 20}) async {
    final corpo = _mapa(await _chamar('GET', '/v1/admin/checkout-sem-codigo', consulta: {
      'limite': '$limite',
      'deslocamento': '$deslocamento',
    }));
    return PaginaRemota(
      _itens(corpo).map(_casoCheckoutSemCodigo).toList(),
      _int(corpo['total']),
    );
  }

  @override
  Future<CasoCheckoutSemCodigo> registrarContatoCheckoutSemCodigo(
    String casoId, {
    required String canal,
    required String motivo,
  }) async =>
      _casoCheckoutSemCodigo(_mapa(await _chamar(
        'POST',
        '/v1/admin/checkout-sem-codigo/${Uri.encodeComponent(casoId)}/contato',
        corpo: {'canal': canal, 'motivo': motivo},
      )));

  @override
  Future<ResultadoDecisaoCheckoutSemCodigo> decidirCheckoutSemCodigo(
    String casoId, {
    required String decisao,
    required String motivo,
    required String chaveIdempotencia,
  }) async {
    final c = _mapa(await _chamar(
      'POST',
      '/v1/admin/checkout-sem-codigo/${Uri.encodeComponent(casoId)}/decisao',
      corpo: {
        'decisao': decisao,
        'motivo': motivo,
        'chave_idempotencia': chaveIdempotencia,
      },
    ));
    return ResultadoDecisaoCheckoutSemCodigo(
      id: c['id'] as String,
      pedidoId: c['pedido_id'] as String,
      estadoPedido: c['estado_pedido'] as String,
      decisao: c['decisao'] as String,
      analistaId: c['analista_id'] as String? ?? '',
      justificativa: c['justificativa'] as String? ?? '',
      decididoEm: _data(c['decidido_em']),
      chaveIdempotencia: c['chave_idempotencia'] as String? ?? chaveIdempotencia,
      idempotente: c['idempotente'] == true,
    );
  }

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
        'limite_usos': ?limiteUsos,
        'limite_por_usuario': ?limitePorUsuario,
        'valido_desde': ?validoDesde,
        'valido_ate': ?validoAte,
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

  // ---------- Moedas ----------

  static MoedasConfig _moedasConfig(Map<String, dynamic> c) => MoedasConfig(
        ativo: c['ativo'] as bool? ?? false,
        bonusAvaliacaoMoedas: _int(c['bonus_avaliacao_moedas']),
        valorMoedaCentavos: _int(c['valor_moeda_centavos']),
        tetoMensalMoedas: _int(c['teto_mensal_moedas']),
        minServicoCentavos: _int(c['min_servico_centavos']),
        maxBonusPorProfissionalMes: _int(c['max_bonus_por_profissional_mes']),
        maxDescontoPercentual: _int(c['max_desconto_percentual']),
        validadeDias: (c['validade_dias'] as num?)?.toInt(),
        orcamentoMensalDescontoCentavos: _int(c['orcamento_mensal_desconto_centavos']),
        avisoPercentual: _int(c['aviso_percentual']),
        tetoDescontoClienteMesCentavos: _int(c['teto_desconto_cliente_mes_centavos']),
        tetoDiarioDescontoCentavos: _int(c['teto_diario_desconto_centavos']),
        diasLiberacaoBonus: _int(c['dias_liberacao_bonus']),
        extras: {
          for (final k in MoedasConfig.chavesExtras)
            if (c[k] is num) k: (c[k] as num).toInt(),
        },
      );

  @override
  Future<MoedasOrcamento> orcamentoMoedas() async {
    final o = _mapa(await _chamar('GET', '/v1/admin/moedas/orcamento'));
    return MoedasOrcamento(
      mesRef: o['mes_ref'] as String? ?? '',
      orcamentoCentavos: _int(o['orcamento_centavos']),
      usadoCentavos: _int(o['usado_centavos']),
      percentualUsado: (o['percentual_usado'] as num?)?.toDouble() ?? 0,
      aviso: o['aviso'] as bool? ?? false,
      diaRef: o['dia_ref'] as String? ?? '',
      usadoDiaCentavos: _int(o['usado_dia_centavos']),
      tetoDiaCentavos: _int(o['teto_dia_centavos']),
    );
  }

  @override
  Future<MoedasConfig> carregarMoedasConfig() async =>
      _moedasConfig(_mapa(await _chamar('GET', '/v1/admin/moedas/config')));

  @override
  Future<ResultadoAvisoPrevio> enviarAvisoTratinhos(
      {required String referencia,
      required DateTime vigencia,
      required String resumo,
      required String motivo,
      Map<String, Object> mudancas = const {}}) =>
      _enviarAvisoPrevio('tratinhos', referencia, vigencia, {
        'resumo': resumo,
        'motivo': motivo,
        if (mudancas.isNotEmpty) 'mudancas': mudancas,
      });

  @override
  Future<ResultadoAvisoPrevio> enviarAvisoTermos(
          {required String referencia,
          required DateTime vigencia,
          required String resumo,
          required String motivo,
          required String link}) =>
      _enviarAvisoPrevio('termos', referencia, vigencia, {'resumo': resumo, 'motivo': motivo, 'link': link});

  @override
  Future<ResultadoAvisoPrevio> enviarAvisoInatividade(
          {required String usuarioId, required String referencia, required DateTime vigencia}) =>
      _enviarAvisoPrevio('inatividade', referencia, vigencia, {'usuario_id': usuarioId});

  Future<ResultadoAvisoPrevio> _enviarAvisoPrevio(
      String tipo, String referencia, DateTime vigencia, Map<String, Object> campos) async {
    String dois(int n) => n.toString().padLeft(2, '0');
    final r = _mapa(await _chamar('POST', '/v1/admin/avisos-previos', corpo: {
      'tipo': tipo,
      'referencia': referencia,
      'vigencia': '${vigencia.year}-${dois(vigencia.month)}-${dois(vigencia.day)}',
      ...campos,
    }));
    // Resposta sem os números não pode virar "enviado": falha explícita.
    int numero(String chave) {
      final n = r[chave];
      if (n is! int) throw const ErroApi('O servidor não informou o resultado do envio. Confira na auditoria.');
      return n;
    }

    return ResultadoAvisoPrevio(
      antecedenciaMinimaDias: numero('antecedencia_minima_dias'),
      destinatarios: numero('destinatarios'),
      avisosNovos: numero('avisos_novos'),
      falhas: numero('falhas'),
    );
  }

  @override
  Future<MoedasConfig> salvarMoedasConfig(MoedasConfig config, {required String motivo, String? avisoReferencia}) async {
    final r = _mapa(await _chamar(
      'PUT',
      '/v1/admin/moedas/config',
      corpo: {
        'ativo': config.ativo,
        'bonus_avaliacao_moedas': config.bonusAvaliacaoMoedas,
        'valor_moeda_centavos': config.valorMoedaCentavos,
        'teto_mensal_moedas': config.tetoMensalMoedas,
        'min_servico_centavos': config.minServicoCentavos,
        'max_bonus_por_profissional_mes': config.maxBonusPorProfissionalMes,
        'max_desconto_percentual': config.maxDescontoPercentual,
        'validade_dias': config.validadeDias,
        'orcamento_mensal_desconto_centavos': config.orcamentoMensalDescontoCentavos,
        'aviso_percentual': config.avisoPercentual,
        'teto_desconto_cliente_mes_centavos': config.tetoDescontoClienteMesCentavos,
        'teto_diario_desconto_centavos': config.tetoDiarioDescontoCentavos,
        'dias_liberacao_bonus': config.diasLiberacaoBonus,
        ...config.extras,
        'motivo': motivo,
        'aviso_referencia': ?avisoReferencia,
      },
    ));
    return _moedasConfig(r);
  }

  static PendenteMoedaUsuario _pendenteMoeda(Map<String, dynamic> p) => PendenteMoedaUsuario(
        chaveIdempotencia: p['chave_idempotencia'] as String? ?? '',
        pedidoId: p['pedido_id'] as String?,
        quantidade: _int(p['quantidade']),
        liberarEm: _data(p['liberar_em']),
        criadaEm: _data(p['criada_em']),
        tipoLancamento: p['tipo_lancamento'] as String? ?? '',
        status: p['status'] as String? ?? '',
      );

  static LancamentoMoedaUsuario _lancamentoMoeda(Map<String, dynamic> l) => LancamentoMoedaUsuario(
        tipo: l['tipo'] as String? ?? '',
        quantidade: _int(l['quantidade']),
        carteira: l['carteira'] as String? ?? 'cliente',
        chaveIdempotencia: l['chave_idempotencia'] as String? ?? '',
        criadaEm: _data(l['criada_em']),
        expiraEm: _dataOuNada(l['expira_em']),
        referenciaId: l['referencia_id'] as String?,
      );

  @override
  Future<MoedasUsuario> consultarMoedasUsuario(String usuarioId, {int limite = 30}) async {
    final id = Uri.encodeComponent(usuarioId);
    final r = _mapa(await _chamar('GET', '/v1/admin/moedas/usuarios/$id', consulta: {'limite': '$limite'}));
    return MoedasUsuario(
      usuarioId: r['usuario_id'] as String? ?? usuarioId,
      saldoCliente: _int(r['saldo_cliente']),
      saldoProfissional: _int(r['saldo_profissional']),
      pendentesCliente: [for (final p in _itens(r['pendentes_cliente'])) _pendenteMoeda(p)],
      pendentesProfissional: [for (final p in _itens(r['pendentes_profissional'])) _pendenteMoeda(p)],
      extratoCliente: [for (final l in _itens(r['extrato_cliente'])) _lancamentoMoeda(l)],
      extratoProfissional: [for (final l in _itens(r['extrato_profissional'])) _lancamentoMoeda(l)],
    );
  }

  @override
  Future<ResultadoConcederMoedas> concederMoedasUsuario(
    String usuarioId, {
    required String carteira,
    required int quantidade,
    int? validadeDias,
    required String motivo,
    String? chaveIdempotencia,
    String? referenciaId,
  }) async {
    final id = Uri.encodeComponent(usuarioId);
    final r = _mapa(await _chamar(
      'POST',
      '/v1/admin/moedas/usuarios/$id/conceder',
      corpo: {
        'carteira': carteira,
        'quantidade': quantidade,
        'validade_dias': ?validadeDias,
        'motivo': motivo,
        'chave_idempotencia': ?chaveIdempotencia,
        'referencia_id': ?referenciaId,
      },
    ));
    return ResultadoConcederMoedas(
      usuarioId: r['usuario_id'] as String? ?? usuarioId,
      carteira: r['carteira'] as String? ?? carteira,
      quantidade: _int(r['quantidade']),
      expiraEm: _data(r['expira_em']),
      chaveIdempotencia: r['chave_idempotencia'] as String? ?? '',
      idempotente: r['idempotente'] as bool? ?? false,
      saldoAtual: _int(r['saldo_atual']),
    );
  }

  @override
  Future<ResultadoCancelarFraudeMoedas> cancelarFraudeMoedasUsuario(
    String usuarioId, {
    required String carteira,
    required int quantidade,
    required bool cancelarPendentes,
    required String motivo,
    String? chaveIdempotencia,
    String? referenciaId,
  }) async {
    final id = Uri.encodeComponent(usuarioId);
    final r = _mapa(await _chamar(
      'POST',
      '/v1/admin/moedas/usuarios/$id/cancelar-fraude',
      corpo: {
        'carteira': carteira,
        'quantidade': quantidade,
        'cancelar_pendentes': cancelarPendentes,
        'motivo': motivo,
        'chave_idempotencia': ?chaveIdempotencia,
        'referencia_id': ?referenciaId,
      },
    ));
    return ResultadoCancelarFraudeMoedas(
      usuarioId: r['usuario_id'] as String? ?? usuarioId,
      carteira: r['carteira'] as String? ?? carteira,
      quantidadeDebitada: _int(r['quantidade_debitada']),
      pendentesCancelados: _int(r['pendentes_cancelados']),
      chaveIdempotencia: r['chave_idempotencia'] as String? ?? '',
      idempotente: r['idempotente'] as bool? ?? false,
      saldoAtual: _int(r['saldo_atual']),
    );
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
        'papel': ?papel,
        'alcada_centavos': ?alcadaCentavos,
        'ativo': ?ativo,
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

  @override
  Future<void> baixarArquivo(String url, String nomeArquivo) async {
    final token = _token;
    if (token == null) throw const ErroApi('Entre de novo para continuar.', sessao: true);
    // Só baixa do próprio backend: o login não pode seguir para outro endereço.
    if (!url.startsWith('$_api/')) throw const ErroApi('Endereço de download inválido.');
    try {
      final r = await http.Response.fromStream(
        await _cliente
            .send(http.Request('GET', Uri.parse(url))..headers['Authorization'] = 'Bearer $token')
            .timeout(tempoLimite),
      );
      if (r.statusCode < 200 || r.statusCode >= 300) {
        Object? json;
        try {
          json = jsonDecode(utf8.decode(r.bodyBytes));
        } on FormatException {
          json = null;
        }
        throw _erro(_Resposta(r.statusCode, json));
      }
      final tipo = r.headers['content-type'] ?? 'application/octet-stream';
      salvarArquivo(r.bodyBytes, nomeArquivo, tipo);
    } on TimeoutException {
      throw const ErroApi('O servidor demorou para responder. Tente de novo.');
    } on http.ClientException {
      throw const ErroApi('Não foi possível falar com o servidor.');
    }
  }

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
      'cidade_id': ?cidadeId,
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
