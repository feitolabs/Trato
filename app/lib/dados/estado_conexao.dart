import 'package:flutter/foundation.dart';

/// Sinal global de internet, alimentado pela própria camada de API (sem plugin nativo):
/// cai quando uma chamada falha por rede e volta na próxima resposta do servidor.
abstract final class EstadoConexao {
  /// `true` = online (padrão). O banner "Sem conexão" só aparece com `false`.
  static final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  static void marcarOffline() => online.value = false;

  static void marcarOnline() => online.value = true;
}
