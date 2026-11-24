import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path_provider/path_provider.dart';

/// Onde o cache de leitura guarda os textos (disco no app, memória nos testes).
abstract interface class ArmazenamentoCache {
  Future<String?> ler(String chave);
  Future<void> gravar(String chave, String conteudo);

  /// Apaga tudo (logout).
  Future<void> limpar();
}

class CacheMemoria implements ArmazenamentoCache {
  final Map<String, String> itens = {};

  @override
  Future<String?> ler(String chave) async => itens[chave];

  @override
  Future<void> gravar(String chave, String conteudo) async => itens[chave] = conteudo;

  @override
  Future<void> limpar() async => itens.clear();
}

/// Arquivos na pasta privada do app (nunca na galeria). O nome é um hash: a chave não aparece.
class CacheArquivo implements ArmazenamentoCache {
  CacheArquivo([Future<Directory> Function()? pasta])
      : _pasta = pasta ?? _pastaPadrao;

  final Future<Directory> Function() _pasta;

  static Future<Directory> _pastaPadrao() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/cache_leitura');
  }

  Future<File> _arquivo(String chave) async {
    final dir = await _pasta();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final nome = crypto.sha256.convert(utf8.encode(chave)).toString();
    return File('${dir.path}/$nome.json');
  }

  @override
  Future<String?> ler(String chave) async {
    final f = await _arquivo(chave);
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> gravar(String chave, String conteudo) async {
    final f = await _arquivo(chave);
    await f.writeAsString(conteudo, flush: true);
  }

  @override
  Future<void> limpar() async {
    final dir = await _pasta();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Últimas respostas de leitura (GET) guardadas por usuário, para mostrar sem internet.
/// Só caminhos da lista abaixo (pedidos, agenda, perfil...), nunca pagamento, anexos nem
/// documentos; e campos de segredo (token, código de início/conclusão, chaves) saem antes de
/// gravar. Sem usuário logado não grava nem lê. O logout limpa tudo.
class CacheLeitura {
  CacheLeitura(this._armazenamento, {required this.usuarioId});

  final ArmazenamentoCache _armazenamento;

  /// Id do usuário logado; nulo = sem cache.
  final String? Function() usuarioId;

  /// Passou disto, não vale a pena guardar.
  static const tamanhoMaximo = 512 * 1024;

  static final _permitidos = <RegExp>[
    RegExp(r'^/v1/pedidos$'),
    RegExp(r'^/v1/pedidos/[^/]+$'),
    RegExp(r'^/v1/pedidos/[^/]+/(dados|orcamentos|eventos|reagendamentos|interlocutor|saldo|mensagens|perfil-cliente)$'),
    RegExp(r'^/v1/orcamentos/[^/]+$'),
    RegExp(r'^/v1/me$'),
    RegExp(r'^/v1/me/(dados-pessoais|enderecos|favoritos|moedas)$'),
    RegExp(r'^/v1/notificacoes$'),
    RegExp(r'^/v1/indicacoes/meu-codigo$'),
    RegExp(r'^/v1/profissional/(pedidos-abertos(/[^/]+)?|orcamentos|perfil)$'),
    RegExp(r'^/v1/profissionais/me/saldo$'),
    RegExp(r'^/v1/profissionais/[^/]+$'),
  ];

  static final _segredo = RegExp(
    r'token|segredo|secret|senha|password|chave|authorization|codigo_(inicio|conclusao)|cpf|pix',
    caseSensitive: false,
  );

  static bool elegivel(String caminho) => _permitidos.any((r) => r.hasMatch(caminho));

  String? _chave(String caminho, Map<String, String>? consulta) {
    final id = usuarioId();
    if (id == null || id.isEmpty || !elegivel(caminho)) return null;
    final q = (consulta ?? const <String, String>{}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$id|$caminho?${q.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  static Object? _limpo(Object? v) {
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (!_segredo.hasMatch('${e.key}')) '${e.key}': _limpo(e.value),
      };
    }
    if (v is List) return [for (final x in v) _limpo(x)];
    return v;
  }

  Future<void> guardar(String caminho, Map<String, String>? consulta, Object? json) async {
    final chave = _chave(caminho, consulta);
    if (chave == null) return;
    final texto = jsonEncode(_limpo(json));
    if (texto.length > tamanhoMaximo) return;
    await _armazenamento.gravar(chave, texto);
  }

  /// A última resposta guardada para essa leitura, ou `(achou: false)`.
  Future<({bool achou, Object? valor})> buscar(String caminho, Map<String, String>? consulta) async {
    final chave = _chave(caminho, consulta);
    if (chave == null) return (achou: false, valor: null);
    final texto = await _armazenamento.ler(chave);
    if (texto == null) return (achou: false, valor: null);
    try {
      return (achou: true, valor: jsonDecode(texto));
    } on FormatException {
      return (achou: false, valor: null);
    }
  }

  Future<void> limpar() => _armazenamento.limpar();
}
