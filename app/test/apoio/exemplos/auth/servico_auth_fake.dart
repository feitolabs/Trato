import 'dart:async';

import 'package:trato/auth/controle_codigo_celular.dart';
import 'package:trato/auth/servico_auth.dart';

/// Login em memória, para testes e para rodar o app sem chaves.
/// Por padrão aceita qualquer e-mail e senha; passe [contas] e
/// `aceitaQualquerLogin: false` para simular senha errada.
class ServicoAuthFake implements ServicoAuth {
  ServicoAuthFake({
    Map<String, String> contas = const {},
    this.aceitaQualquerLogin = true,
    this.exigeConfirmacaoEmail = false,
    this.codigoCelular = '123456',
    Set<ProvedorAuth> provedores = const {ProvedorAuth.google, ProvedorAuth.apple},
    DateTime Function()? agora,
  })  : _contas = {for (final e in contas.entries) _normalizar(e.key): e.value},
        _provedores = provedores,
        _codigo = ControleCodigoCelular(agora: agora);

  /// Código que o fake considera certo.
  final String codigoCelular;
  final bool aceitaQualquerLogin;

  /// Simula a confirmação de e-mail ligada: o cadastro não abre sessão e o login só funciona
  /// depois de [confirmarEmail].
  final bool exigeConfirmacaoEmail;
  final Set<String> _naoConfirmados = {};

  /// Quantos e-mails de confirmação foram reenviados (para os testes).
  int emailsReenviados = 0;

  /// Marca o e-mail como confirmado (o clique no link, nos testes).
  void confirmarEmail(String email) => _naoConfirmados.remove(_normalizar(email));

  final Map<String, String> _contas;
  final Map<String, String> _donoDoCpf = {}; // CPF (11 dígitos) -> conta
  final Map<String, String> _cpfDaConta = {}; // conta -> CPF (11 dígitos)
  final Set<ProvedorAuth> _provedores;
  final ControleCodigoCelular _codigo;
  final _controle = StreamController<SessaoAuth?>.broadcast();

  SessaoAuth? _sessao;
  final Map<String, String?> _perfis = {};

  /// Quantas renovações de token foram pedidas (para os testes).
  int renovacoes = 0;

  /// Se verdadeiro, [renovarToken] devolve nulo (refresh token vencido).
  bool renovacaoFalha = false;

  /// Erro lançado uma vez na próxima chamada (ex.: `ErroAuth(TipoErroAuth.semInternet)`).
  ErroAuth? falharNaProxima;

  /// Quantas vezes o código foi enviado ou reenviado (para os testes).
  int get codigosEnviados => _codigo.envios;

  static String _normalizar(String email) => email.trim().toLowerCase();

  static String _digitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  void _ocuparCpf(String conta, String cpf) {
    final digitos = _digitos(cpf);
    final atual = _cpfDaConta[conta];
    if (atual == digitos) return;
    final dono = _donoDoCpf[digitos];
    if ((dono != null && dono != conta) || atual != null) {
      throw const ErroAuth(TipoErroAuth.cpfJaUsado);
    }
    _donoDoCpf[digitos] = conta;
    _cpfDaConta[conta] = digitos;
  }

  void _checarFalha() {
    final erro = falharNaProxima;
    if (erro != null) {
      falharNaProxima = null;
      throw erro;
    }
  }

  SessaoAuth _entrou(SessaoAuth sessao) {
    _sessao = sessao;
    _controle.add(sessao);
    return sessao;
  }

  @override
  bool provedorHabilitado(ProvedorAuth provedor) => _provedores.contains(provedor);

  @override
  SessaoAuth? get sessaoAtual => _sessao;

  @override
  Stream<SessaoAuth?> get sessaoMudou => _controle.stream;

  /// Token de teste, só existe enquanto há sessão.
  @override
  String? get tokenAtual => _sessao == null ? null : 'token-de-teste-${_sessao!.id}';

  @override
  Future<String?> renovarToken() async {
    renovacoes++;
    if (_sessao == null || renovacaoFalha) return null;
    return 'token-renovado-$renovacoes-${_sessao!.id}';
  }

  @override
  Future<SessaoAuth> entrarComEmail({required String email, required String senha}) async {
    _checarFalha();
    var chave = _normalizar(email);
    if (!chave.contains('@')) {
      final digitos = _digitos(chave);
      final dono = _donoDoCpf[digitos];
      if (dono != null && dono.startsWith('fake-')) {
        chave = dono.substring(5);
      } else if (dono != null) {
        chave = dono;
      }
    }
    final certa = _contas[chave];
    final ok = certa != null ? certa == senha : aceitaQualquerLogin;
    if (!ok) throw const ErroAuth(TipoErroAuth.credenciaisInvalidas);
    if (_naoConfirmados.contains(chave)) throw const ErroAuth(TipoErroAuth.emailNaoConfirmado);
    final emailEfetivo = chave.contains('@') ? chave : '$chave@trato.app';
    return _entrou(SessaoAuth(
      id: 'fake-$chave',
      email: emailEfetivo,
      celularConfirmado: true,
      perfil: _perfis[chave],
    ));
  }

  @override
  Future<ResultadoCadastro> criarConta(DadosCadastro dados) async {
    _checarFalha();
    final chave = _normalizar(dados.email);
    if (_contas.containsKey(chave)) throw const ErroAuth(TipoErroAuth.emailJaUsado);
    final conta = 'fake-$chave';
    _ocuparCpf(conta, dados.cpf);
    _contas[chave] = dados.senha;
    _codigo.novoCadastro();
    _perfis[chave] = dados.perfil;
    if (exigeConfirmacaoEmail) {
      _naoConfirmados.add(chave);
      return CadastroAguardandoEmail(chave);
    }
    return CadastroComSessao(_entrou(
      SessaoAuth(id: conta, email: chave, nome: dados.nome, perfil: dados.perfil),
    ));
  }

  @override
  Future<bool> cpfDisponivel(String cpf) async {
    _checarFalha();
    return !_donoDoCpf.containsKey(_digitos(cpf));
  }

  @override
  Future<void> registrarCpf(String cpf) async {
    _checarFalha();
    final sessao = _sessao;
    if (sessao == null) throw const ErroAuth(TipoErroAuth.desconhecido);
    _ocuparCpf(sessao.id, cpf);
  }

  @override
  Future<void> reenviarEmailConfirmacao(String email) async {
    _checarFalha();
    emailsReenviados++;
  }

  @override
  Future<SessaoAuth> entrarComProvedor(ProvedorAuth provedor) async {
    _checarFalha();
    if (!provedorHabilitado(provedor)) throw const ErroAuth(TipoErroAuth.provedorIndisponivel);
    return _entrou(SessaoAuth(
      id: 'fake-${provedor.name}',
      email: 'teste@${provedor.name}.fake',
      celularConfirmado: true,
    ));
  }

  @override
  Future<void> sair() async {
    _sessao = null;
    _controle.add(null);
  }

  /// E-mails para os quais foi pedida a recuperação de senha (para os testes).
  final List<String> recuperacoesPedidas = [];

  /// Senhas novas gravadas por [definirNovaSenha], na ordem (para os testes).
  final List<String> senhasDefinidas = [];

  final _recuperacao = StreamController<void>.broadcast();
  String? _emailRecuperando;

  /// O clique no link do e-mail de recuperação: abre o app para [email] na tela de nova senha.
  void simularLinkDeRecuperacao(String email) {
    _emailRecuperando = _normalizar(email);
    _recuperacao.add(null);
  }

  @override
  Stream<void> get recuperacaoDeSenha => _recuperacao.stream;

  @override
  Future<void> definirNovaSenha(String senha) async {
    _checarFalha();
    if (senha.length < 8) throw const ErroAuth(TipoErroAuth.senhaFraca);
    senhasDefinidas.add(senha);
    final email = _emailRecuperando;
    if (email != null) _contas[email] = senha;
  }

  @override
  Future<void> recuperarSenha(String email) async {
    _checarFalha();
    recuperacoesPedidas.add(_normalizar(email));
  }

  @override
  Future<void> reenviarCodigoCelular(String celular) async {
    _checarFalha();
    _codigo.registrarReenvio();
  }

  @override
  Future<SessaoAuth> confirmarCelular({required String celular, required String codigo}) async {
    _checarFalha();
    _codigo.checarTentativa();
    if (codigo != codigoCelular) throw _codigo.registrarErro();
    final atual = _sessao;
    return _entrou(SessaoAuth(
      id: atual?.id ?? 'fake-celular',
      email: atual?.email ?? '',
      nome: atual?.nome,
      celularConfirmado: true,
      perfil: atual?.perfil,
    ));
  }
}
