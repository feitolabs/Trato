import 'package:flutter/foundation.dart';

/// Quantas vezes a pessoa negou a localização ao enviar pedido (nesta sessão do app).
/// Depois de [limite] negações o app para de perguntar a cada envio: envia sem ponto e a tela
/// mostra uma linha discreta ("Sem localização: o profissional vê só o bairro").
class LocalizacaoDoPedido {
  const LocalizacaoDoPedido._();

  static const limite = 2;

  static final negacoes = ValueNotifier<int>(0);

  static bool get naoPerguntarMais => negacoes.value >= limite;

  static void registrarNegacao() => negacoes.value++;

  /// Só para testes.
  @visibleForTesting
  static void zerar() => negacoes.value = 0;
}
