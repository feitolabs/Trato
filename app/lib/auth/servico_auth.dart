import 'dart:async';


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

/// Dados do cadastro (passo 1). O celular vai como metadado do usuário no Supabase (sem exigir
/// sessão). CPF e nascimento não vão para o login (dado sensível, iria no token): ficam para
/// o perfil, gravado pelo backend.
class DadosCadastro {
  const DadosCadastro({
    required this.nome,
    required this.email,
    required this.senha,
    required this.celular,
    this.cpf = '',
    this.perfil,
    this.termosAceitos = true,
  });

  final String nome;
  final String email;
  final String senha;

  /// Como digitado, ex.: "(31) 98765-4417".
  final String celular;

  /// Como digitado, ex.: "123.456.789-09". Não vai para o login: o backend grava.
  final String cpf;

  /// `cliente` ou `profissional` (escolha da tela "Como você quer usar o Trato?").
  final String? perfil;

  /// Aceite explícito dos Termos de Uso e Política de Privacidade.
  final bool termosAceitos;
}

/// Resultado do cadastro: entrou direto (confirmação de e-mail desligada) ou falta confirmar
/// o e-mail (caso real hoje).
sealed class ResultadoCadastro {
  const ResultadoCadastro();
}

class CadastroComSessao extends ResultadoCadastro {
  const CadastroComSessao(this.sessao);
  final SessaoAuth sessao;
}

class CadastroAguardandoEmail extends ResultadoCadastro {
  const CadastroAguardandoEmail(this.email);
  final String email;
}

/// Liga/desliga a confirmação do celular por SMS (D16: desligada no piloto). O código da tela
/// e do serviço continua no app; a tela só entra no fluxo se isto for `true`.
const kConfirmarCelularPorSms = false;

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
  emailNaoConfirmado,
  limiteEmail,
  cpfJaUsado,
  cpfNaoVerificado,
  dadosInvalidos,
  cadastroDesativado,
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
    TipoErroAuth.credenciaisInvalidas: 'E-mail, CPF, celular ou senha incorretos.',
    TipoErroAuth.emailJaUsado: 'Este e-mail já tem uma conta. Tente entrar.',
    TipoErroAuth.semInternet: 'Sem internet. Confira sua conexão e tente de novo.',
    TipoErroAuth.senhaFraca: 'Senha fraca. Use 8 ou mais caracteres, com letra e número.',
    TipoErroAuth.codigoInvalido: 'Código incorreto. Confira e tente de novo.',
    TipoErroAuth.tentativasEsgotadas: 'Muitas tentativas. Peça um código novo.',
    TipoErroAuth.reenvioMuitoCedo: 'Aguarde um pouco para pedir outro código.',
    TipoErroAuth.reenviosEsgotados: 'Você já pediu códigos demais. Tente mais tarde.',
    TipoErroAuth.provedorIndisponivel: 'Este tipo de entrada ainda não está disponível.',
    TipoErroAuth.emailNaoConfirmado: 'Confirme seu e-mail para entrar.',
    TipoErroAuth.limiteEmail: 'Muitos e-mails enviados. Espere alguns minutos e tente de novo.',
    TipoErroAuth.cpfJaUsado: 'Este CPF já está cadastrado em outra conta.',
    TipoErroAuth.cpfNaoVerificado: 'Não foi possível verificar o CPF agora. Tente de novo.',
    TipoErroAuth.dadosInvalidos: 'Confira os dados e tente de novo.',
    TipoErroAuth.cadastroDesativado: 'O cadastro está indisponível no momento.',
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

  /// Cria a conta. Com sessão, entra direto; sem sessão (confirmação de e-mail ligada),
  /// devolve [CadastroAguardandoEmail]. Antes de criar, confere se o CPF está livre; se já
  /// estiver em outra conta, lança [ErroAuth] com `cpfJaUsado`.
  Future<ResultadoCadastro> criarConta(DadosCadastro dados);

  /// Diz se o CPF pode ser usado numa conta nova. Não revela de quem é o CPF.
  Future<bool> cpfDisponivel(String cpf);

  /// Grava o CPF na conta logada (depois do primeiro login). Repetir o mesmo CPF não faz nada;
  /// CPF de outra conta lança [ErroAuth] com `cpfJaUsado`.
  Future<void> registrarCpf(String cpf);

  /// Reenvia o e-mail de confirmação do cadastro.
  Future<void> reenviarEmailConfirmacao(String email);

  Future<SessaoAuth> entrarComProvedor(ProvedorAuth provedor);

  Future<void> sair();

  /// Manda o e-mail de recuperação. O link volta para o app (`br.com.feitolabs.trato://login-callback`).
  Future<void> recuperarSenha(String email);

  /// Emite quando o app é aberto pelo link do e-mail de recuperação. Quem escuta leva a pessoa
  /// para a tela de nova senha. Se o link abriu o app antes de alguém escutar, o primeiro
  /// ouvinte recebe o aviso assim que escutar.
  Stream<void> get recuperacaoDeSenha;

  /// Troca a senha da conta que abriu o link de recuperação. Erros: [TipoErroAuth.senhaFraca],
  /// [TipoErroAuth.semInternet].
  Future<void> definirNovaSenha(String senha);

  /// Reenvia o código. Só depois de [LimitesCodigoCelular.segundosParaReenviar] s.
  Future<void> reenviarCodigoCelular(String celular);

  /// Confere o código de 6 dígitos. Erros: [TipoErroAuth.codigoInvalido],
  /// [TipoErroAuth.tentativasEsgotadas].
  Future<SessaoAuth> confirmarCelular({required String celular, required String codigo});
}

/// Serviço usado pelas telas quando ninguém passa um. O `main` coloca aqui o
/// `ServicoAuthSupabase`; sem ele (sem configuração) o login falha com erro claro.
abstract final class ServicoAuthPadrao {
  static ServicoAuth atual = const _AuthNaoConfigurado();
}

class _AuthNaoConfigurado implements ServicoAuth {
  const _AuthNaoConfigurado();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Login não configurado: faltam SUPABASE_URL e SUPABASE_ANON_KEY.');
}
