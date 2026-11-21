import 'erros.dart';

/// Abre o login quando a sessão expirou. Quem monta o app liga (`main.dart`); sem ligação,
/// "Tentar de novo" só recarrega. Evita o laço "Sua sessão expirou" + "Tentar de novo".
void Function()? abrirLoginPorSessaoExpiradaHook;

/// Se [erro] é de sessão expirada, leva ao login e devolve `true` (não recarregar).
bool tratarSessaoExpirada(Object? erro) {
  if (erro is ErroTrato && erro.tipo == TipoErro.sessaoExpirada) {
    final abrir = abrirLoginPorSessaoExpiradaHook;
    if (abrir != null) {
      abrir();
      return true;
    }
  }
  return false;
}
