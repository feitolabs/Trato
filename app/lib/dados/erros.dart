/// Erro mostrado ao usuário. A mensagem já vem em português simples.
enum TipoErro { semInternet, sessaoExpirada, servidor, recusado, naoEncontrado, indisponivel }

class ErroTrato implements Exception {
  const ErroTrato(this.tipo, this.mensagem, {this.codigoHttp});

  final TipoErro tipo;
  final String mensagem;

  /// Código HTTP quando o erro veio da API (ex.: 409 de CPF repetido).
  final int? codigoHttp;

  static const semInternet = ErroTrato(
    TipoErro.semInternet,
    'Sem conexão com a internet. Confira o sinal e tente de novo.',
  );
  static const sessaoExpirada = ErroTrato(
    TipoErro.sessaoExpirada,
    'Sua sessão expirou. Entre de novo para continuar.',
  );
  static const servidor = ErroTrato(
    TipoErro.servidor,
    'Algo deu errado do nosso lado. Tente de novo em instantes.',
  );
  static const indisponivel = ErroTrato(
    TipoErro.indisponivel,
    'Esta função ainda não está disponível.',
  );

  @override
  String toString() => mensagem;
}
