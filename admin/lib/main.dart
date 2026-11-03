import 'package:flutter/material.dart';

import 'app.dart';
import 'dados/config_painel.dart';

void main() {
  final ambiente = ConfigPainel.doAmbiente();
  // Se não foi passado --dart-define, conecta na API local real por padrão para desenvolvimento completo
  final config = ambiente.modo.isNotEmpty
      ? ambiente
      : const ConfigPainel(
          modo: 'api',
          urlApi: 'http://127.0.0.1:8000',
          urlSupabase: 'https://ornaoshsvuszquntkqsk.supabase.co',
          chaveAnon: 'sb_publishable_GwIISqsEKuOu6iK4IBlRvQ__TVCCgj8',
        );
  runApp(PainelApp(api: criarApi(config), ambienteTeste: !config.ehProducao));
}
