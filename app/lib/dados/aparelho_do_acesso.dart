/// Termos 14.3 e 16.1: o que o app declara sobre o aparelho. O identificador é sorteado pelo
/// próprio app e guardado nele; nada vem de IMEI, id de publicidade ou dado de hardware.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../dispositivo/relato_bug.dart' show versaoDoApp;

const chaveDoIdDeAcesso = 'trato_id_de_acesso';

final _formato = RegExp(r'^[0-9a-f]{32}$');

String _sortearId() {
  final sorte = Random.secure();
  return List.generate(16, (_) => sorte.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// O id guardado; sem um válido, sorteia e grava.
Future<String> idDeAcessoDoApp() async {
  final guarda = await SharedPreferences.getInstance();
  final atual = guarda.getString(chaveDoIdDeAcesso);
  if (atual != null && _formato.hasMatch(atual)) return atual;
  final novo = _sortearId();
  await guarda.setString(chaveDoIdDeAcesso, novo);
  return novo;
}

/// Cabeçalhos opcionais. Se não der para guardar o id, ele não vai (e o app abre do mesmo jeito).
/// Do sistema vai só o nome: o texto completo da versão pode trazer dados do modelo.
Future<Map<String, String>> carregarCabecalhosDoAparelho({
  Duration limite = const Duration(seconds: 2),
}) async {
  final (tipo, sistema) = kIsWeb
      ? ('web', 'Web')
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => ('android', 'Android'),
          TargetPlatform.iOS => ('ios', 'iOS'),
          TargetPlatform.windows => ('desktop', 'Windows'),
          TargetPlatform.macOS => ('desktop', 'macOS'),
          TargetPlatform.linux => ('desktop', 'Linux'),
          TargetPlatform.fuchsia => ('outro', 'Fuchsia'),
        };
  String? id;
  try {
    id = await idDeAcessoDoApp().timeout(limite);
  } on Object {
    id = null;
  }
  return {
    if (id != null) 'X-Dispositivo-Id': id,
    'X-Aparelho-Tipo': tipo,
    'X-Sistema-Operacional': sistema,
    'X-App-Versao': versaoDoApp,
  };
}
