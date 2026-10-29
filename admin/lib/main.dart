import 'package:flutter/material.dart';

import 'app.dart';
import 'dados/api_fake.dart';

void main() {
  // Enquanto a API admin não existe, o painel roda com dados de exemplo.
  // Trocar por uma implementação HTTP de ApiAdmin (URL em TRATO_API_URL) quando o backend estiver pronto.
  runApp(PainelApp(api: ApiFake(atraso: const Duration(milliseconds: 250))));
}
