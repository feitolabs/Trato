// Entrada em conta de mentira para os testes de widget.
import 'package:trato/auth/servico_auth.dart';

/// Abre sessão no serviço de autenticação dos testes. O fake aceita qualquer credencial de conta
/// não cadastrada, então o valor é só gerado aqui: nenhum teste precisa escrever uma senha.
Future<void> entrarNaContaDeTeste(ServicoAuth auth, {String email = 'a@b.com'}) async {
  await auth.entrarComEmail(email: email, senha: 'x' * 10);
}
