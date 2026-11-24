import 'package:flutter/foundation.dart';

/// Sinal global de internet, alimentado pela própria camada de API (sem plugin nativo):
/// cai quando uma chamada falha por rede e volta na próxima resposta do servidor.
abstract final class EstadoConexao {
  /// `true` = online (padrão). O banner "Sem conexão" só aparece com `false`.
  static final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// `true` quando a tela mostra a última leitura guardada (sem internet) em vez de dados novos.
  static final ValueNotifier<bool> dadosSalvos = ValueNotifier<bool>(false);

  static void marcarOffline() => online.value = false;

  static void marcarOnline() {
    online.value = true;
    dadosSalvos.value = false;
  }
}
