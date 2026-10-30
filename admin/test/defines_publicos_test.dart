import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/config_painel.dart';
import 'package:trato_admin/dados/defines_publicos.dart';

void main() {
  test('painel recusa (debug) variável com cara de segredo, sem mostrar o valor', () {
    expect(
      () => filtrarDefines({'ADMIN_MODO': 'api', 'ADMIN_SERVICE_ROLE_KEY': 'valor-secreto'}),
      throwsA(isA<StateError>().having((e) => e.message, 'mensagem', isNot(contains('valor-secreto')))),
    );
  });

  test('só as variáveis públicas montam a configuração', () {
    final c = ConfigPainel.deValores(filtrarDefines({
      'ADMIN_MODO': 'api',
      'ADMIN_API_URL': 'https://api.teste',
      'ADMIN_SUPABASE_URL': 'https://x.supabase.co',
      'ADMIN_SUPABASE_ANON_KEY': 'publica',
    }));
    expect(c.usaApi, isTrue);
  });
}
