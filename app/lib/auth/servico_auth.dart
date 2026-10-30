import 'dart:async';

import 'servico_auth_fake.dart';

/// Provedores de login social.
enum ProvedorAuth { google, apple }

/// Quem está logado. Só o que o app precisa; nada de token aqui.
class SessaoAuth {
  const SessaoAuth({
    required this.id,
    required this.email,
    this.nome,
    this.celularConfirmado = false,
    this.perfil,
  });

  final String id;
  final String email;
  final String? nome;
  final bool celularConfirmado;

  /// Perfil escolhido no cadastro: `cliente` ou `profissional`. Nulo = cliente.
  final String? perfil;

  bool get ehProfissional => perfil == 'profissional';
}

/// Dados do cadastro (passo 1). CPF e nascimento não vão para o serviço de login:
/// ficam para o perfil, gravado pelo backend.
class DadosCadastro {
  const DadosCadastro({
    required this.nome,
    required this.email,
    required this.senha,
    required this.celular,
    this.perfil,
  });

  final String nome;
  final String email;
  final String senha;

  /// Como digitado, ex.: "(31) 98765-4417".
  final String celular;

  /// `cliente` ou `profissional` (escolha da tela "Como você quer usar o Trato?").
  final String? perfil;
}

enum TipoErroAuth {
  credenciaisInvalidas,
  emailJaUsado,
  semInternet,
  senhaFraca,
  codigoInvalido,
  tentativasEsgotadas,
  reenvioMuitoCedo,
  reenviosEsgotados,
  provedorIndisponivel,
  cancelado,
  desconhecido,
}

/// Erro de login já com mensagem em português para mostrar na tela.
class ErroAuth implements Exception {
  const ErroAuth(this.tipo, [String? mensagem]) : _mensagem = mensagem;

  final TipoErroAuth tipo;
  final String? _mensagem;

  String get mensagem => _mensagem ?? _padrao[tipo]!;

  static const _padrao = <TipoErroAuth, String>{
    TipoErroAuth.credenciaisInvalidas: 'E-mail ou senha incorretos.',
    TipoErroAuth.emailJaUsado: 'Este e-mail já tem uma conta. Tente entrar.',
    TipoErroAuth.semInternet: 'Sem internet. Confira sua conexão e tente de novo.',
    TipoErroAuth.senhaFraca: 'Senha fraca. Use 8 ou mais caracteres, com letra e número.',
    TipoErroAuth.codigoInvalido: 'Código incorreto. Confira e tente de novo.',
    TipoErroAuth.tentativasEsgotadas: 'Muitas tentativas. Peça um código novo.',
    TipoErroAuth.reenvioMuitoCedo: 'Aguarde um pouco para pedir outro código.',
    TipoErroAuth.reenviosEsgotados: 'Você já pediu códigos demais. Tente mais tarde.',
    TipoErroAuth.provedorIndisponivel: 'Este tipo de entrada ainda não está disponível.',
    TipoErroAuth.cancelado: 'Entrada cancelada.',
    TipoErroAuth.desconhecido: 'Algo deu errado. Tente de novo.',
  };

  @override
  String toString() => 'ErroAuth($tipo)';
}

/// Regras do código de confirmação do celular (D14). O serviço também aplica
/// os limites, mas a tela usa estes números para a contagem.
abstract final class LimitesCodigoCelular {
  static const segundosParaReenviar = 60;
  static const maxTentativas = 5;
  static const maxReenvios = 3;
}

/// Tudo o que o app precisa do login. Telas só conhecem esta interface.
abstract class ServicoAuth {
  /// O provedor está ligado no painel e configurado neste app?
  bool provedorHabilitado(ProvedorAuth provedor);

  SessaoAuth? get sessaoAtual;

  Stream<SessaoAuth?> get sessaoMudou;

  /// Token de acesso da sessão atual, para a API. Só quem liga a sessão ao cliente HTTP
  /// ([LigacaoSessao]) deve ler; nunca vai para log, tela ou código.
  String? get tokenAtual;

  /// Pede um token novo (o de acesso venceu ou a API recusou). Devolve o novo token, ou nulo
  /// se não há como renovar (a sessão acabou). Usado pelo cliente HTTP uma vez por 401.
  Future<String?> renovarToken();

  Future<SessaoAuth> entrarComEmail({required String email, required String senha});

  /// Cria a conta e já pede o código de 6 dígitos por SMS para o celular.
  Future<SessaoAuth> criarConta(DadosCadastro dados);

  Future<SessaoAuth> entrarComProvedor(ProvedorAuth provedor);

  Future<void> sair();

  Future<void> recuperarSenha(String email);

  /// Reenvia o código. Só depois de [LimitesCodigoCelular.segundosParaReenviar] s.
  Future<void> reenviarCodigoCelular(String celular);

  /// Confere o código de 6 dígitos. Erros: [TipoErroAuth.codigoInvalido],
  /// [TipoErroAuth.tentativasEsgotadas].
  Future<SessaoAuth> confirmarCelular({required String celular, required String codigo});
}

/// Serviço usado pelas telas quando ninguém passa um. Começa no fake (roda sem chaves);
/// o `main` troca por `ServicoAuthSupabase` quando houver configuração.
abstract final class ServicoAuthPadrao {
  static ServicoAuth atual = ServicoAuthFake();
}
