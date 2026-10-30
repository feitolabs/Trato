import 'package:flutter/material.dart';

import 'app.dart';
import 'dados/config_painel.dart';

void main() {
  // Sem --dart-define=ADMIN_MODO=api o painel roda com dados de exemplo (ver config_painel.dart).
  runApp(PainelApp(api: criarApi(ConfigPainel.doAmbiente)));
}
