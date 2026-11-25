import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'servico_push_firebase.dart';

/// Uma mensagem de push como o app a enxerga: título, corpo e o `data` (tudo texto). Nunca
/// guarda nem mostra o token.
class MensagemPush {
  const MensagemPush({this.titulo, this.corpo, this.dados = const {}});

  final String? titulo;
  final String? corpo;
  final Map<String, dynamic> dados;

  factory MensagemPush.deFirebase(RemoteMessage m) => MensagemPush(
        titulo: m.notification?.title,
        corpo: m.notification?.body,
        dados: Map<String, dynamic>.of(m.data),
      );
}

/// Handler de mensagens com o app em segundo plano ou fechado. Roda num isolate próprio, por isso
/// é uma função de nível superior. Mensagens com `notification` a bandeja do sistema mostra sozinha;
/// as só-dados são ignoradas. Não navega e não faz nada que possa quebrar.
@pragma('vm:entry-point')
Future<void> tratarPushEmSegundoPlano(RemoteMessage mensagem) async {}

/// Liga os três momentos do push ao app:
/// - app FECHADO e aberto pelo toque: `getInitialMessage`;
/// - app em SEGUNDO PLANO e aberto pelo toque: `onMessageOpenedApp`;
/// - app ABERTO (primeiro plano): `onMessage` (o Android não mostra bandeja nesse caso).
///
/// Cada ponto de entrada pode ser trocado, para os testes não chamarem o Firebase real.
class ServicoToquePush {
  ServicoToquePush({
    Future<bool> Function()? garantirFirebase,
    Future<MensagemPush?> Function()? mensagemInicial,
    Stream<MensagemPush> Function()? aoAbrirPeloToque,
    Stream<MensagemPush> Function()? aoChegarComAppAberto,
  })  : _garantirFirebase = garantirFirebase ?? inicializarFirebaseComSeguranca,
        _mensagemInicial = mensagemInicial ?? _inicialPadrao,
        _aoAbrirPeloToque = aoAbrirPeloToque ?? _abertaPadrao,
        _aoChegarComAppAberto = aoChegarComAppAberto ?? _primeiroPlanoPadrao;

  final Future<bool> Function() _garantirFirebase;
  final Future<MensagemPush?> Function() _mensagemInicial;
  final Stream<MensagemPush> Function() _aoAbrirPeloToque;
  final Stream<MensagemPush> Function() _aoChegarComAppAberto;

  final _inscricoes = <StreamSubscription<MensagemPush>>[];

  static Future<MensagemPush?> _inicialPadrao() async {
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : MensagemPush.deFirebase(m);
  }

  static Stream<MensagemPush> _abertaPadrao() =>
      FirebaseMessaging.onMessageOpenedApp.map(MensagemPush.deFirebase);

  static Stream<MensagemPush> _primeiroPlanoPadrao() =>
      FirebaseMessaging.onMessage.map(MensagemPush.deFirebase);

  /// [aoToque]: a pessoa tocou na notificação. [aoChegar]: chegou uma com o app aberto.
  /// Qualquer falha de Firebase é engolida: o push é um extra, nunca impede o app de abrir.
  Future<void> ligar({
    required void Function(MensagemPush) aoToque,
    required void Function(MensagemPush) aoChegar,
  }) async {
    try {
      if (!await _garantirFirebase()) return;
    } on Object {
      return;
    }
    void ouvir(Stream<MensagemPush> Function() origem, void Function(MensagemPush) aoReceber) {
      try {
        _inscricoes.add(origem().listen(
          (m) {
            try {
              aoReceber(m);
            } on Object catch (e) {
              if (kDebugMode) debugPrint('push: falha ao tratar a mensagem ($e)');
            }
          },
          onError: (Object _) {},
        ));
      } on Object {
        // Sem Firebase neste ambiente.
      }
    }

    ouvir(_aoAbrirPeloToque, aoToque);
    ouvir(_aoChegarComAppAberto, aoChegar);
    try {
      final inicial = await _mensagemInicial();
      if (inicial != null) aoToque(inicial);
    } on Object {
      // Sem mensagem inicial ou sem Firebase: segue.
    }
  }

  Future<void> encerrar() async {
    for (final s in _inscricoes) {
      await s.cancel();
    }
    _inscricoes.clear();
  }
}
