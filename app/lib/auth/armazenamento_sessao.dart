import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Onde a sessão (refresh token) fica guardada. Interface pequena para trocar por um fake
/// nos testes. A versão real usa Keychain (iOS) e Keystore (Android).
abstract interface class ArmazenamentoSessao {
  Future<String?> ler(String chave);
  Future<void> gravar(String chave, String valor);
  Future<void> apagar(String chave);
}

/// Armazenamento cifrado do sistema. Nada de `SharedPreferences` para token.
class ArmazenamentoSessaoSeguro implements ArmazenamentoSessao {
  const ArmazenamentoSessaoSeguro([
    this._cofre = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    ),
  ]);

  final FlutterSecureStorage _cofre;

  @override
  Future<String?> ler(String chave) => _cofre.read(key: chave);

  @override
  Future<void> gravar(String chave, String valor) => _cofre.write(key: chave, value: valor);

  @override
  Future<void> apagar(String chave) => _cofre.delete(key: chave);
}

/// Para teste e demonstração: guarda na memória.
class ArmazenamentoSessaoMemoria implements ArmazenamentoSessao {
  final Map<String, String> dados = {};

  @override
  Future<String?> ler(String chave) async => dados[chave];

  @override
  Future<void> gravar(String chave, String valor) async => dados[chave] = valor;

  @override
  Future<void> apagar(String chave) async => dados.remove(chave);
}

/// Antigo lugar da sessão (texto puro em `SharedPreferences`), usado só para migrar.
abstract interface class SessaoAntiga {
  Future<String?> ler(String chave);
  Future<void> apagar(String chave);
}

class SessaoAntigaPreferencias implements SessaoAntiga {
  const SessaoAntigaPreferencias();

  @override
  Future<String?> ler(String chave) async =>
      (await SharedPreferences.getInstance()).getString(chave);

  @override
  Future<void> apagar(String chave) async => (await SharedPreferences.getInstance()).remove(chave);
}

/// Ponte entre o Supabase e o [ArmazenamentoSessao]. Na primeira abertura depois da
/// atualização, move a sessão antiga para o cofre e **apaga** o valor em texto puro.
class LocalStorageSeguro extends sb.LocalStorage {
  LocalStorageSeguro({
    required this.chave,
    ArmazenamentoSessao? armazenamento,
    SessaoAntiga? antiga,
  })  : _cofre = armazenamento ?? const ArmazenamentoSessaoSeguro(),
        _antiga = antiga ?? const SessaoAntigaPreferencias();

  /// Mesma chave que o Supabase usava, para a migração achar a sessão antiga.
  static String chaveDaUrl(String url) => 'sb-${Uri.parse(url).host.split('.').first}-auth-token';

  final String chave;
  final ArmazenamentoSessao _cofre;
  final SessaoAntiga _antiga;

  @override
  Future<void> initialize() async {
    final velho = await _antiga.ler(chave);
    if (velho == null) return;
    if ((await _cofre.ler(chave)) == null) await _cofre.gravar(chave, velho);
    await _antiga.apagar(chave);
  }

  @override
  Future<bool> hasAccessToken() async => (await _cofre.ler(chave)) != null;

  @override
  Future<String?> accessToken() => _cofre.ler(chave);

  @override
  Future<void> removePersistedSession() => _cofre.apagar(chave);

  @override
  Future<void> persistSession(String sessao) => _cofre.gravar(chave, sessao);
}
