import 'dart:async';

import 'controle_codigo_celular.dart';
import 'servico_auth.dart';

/// Login em memória, para testes e para rodar o app sem chaves.
/// Por padrão aceita qualquer e-mail e senha; passe [contas] e
/// `aceitaQualquerLogin: false` para simular senha errada.
class ServicoAuthFake implements ServicoAuth {
  ServicoAuthFake({
    Map<String, String> contas = const {},
    this.aceitaQualquerLogin = true,
    this.codigoCelular = '123456',
    Set<ProvedorAuth> provedores = const {ProvedorAuth.google, ProvedorAuth.apple},
    DateTime Function()? agora,
  })  : _contas = {for (final e in contas.entries) _normalizar(e.key): e.value},
        _provedores = provedores,
        _codigo = ControleCodigoCelular(agora: agora);

  /// Código que o fake considera certo.
  final String codigoCelular;
  final bool aceitaQualquerLogin;

  final Map<String, String> _contas;
  final Set<ProvedorAuth> _provedores;
  final ControleCodigoCelular _codigo;
  final _controle = StreamController<SessaoAuth?>.broadcast();

  SessaoAuth? _sessao;

  /// Erro lançado uma vez na próxima chamada (ex.: `ErroAuth(TipoErroAuth.semInternet)`).
  ErroAuth? falharNaProxima;

  /// Quantas vezes o código foi enviado ou reenviado (para os testes).
  int get codigosEnviados => _codigo.envios;

  static String _normalizar(String email) => email.trim().toLowerCase();

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
  Future<SessaoAuth> entrarComEmail({required String email, required String senha}) async {
    _checarFalha();
    final chave = _normalizar(email);
    final certa = _contas[chave];
    final ok = certa != null ? certa == senha : aceitaQualquerLogin;
    if (!ok) throw const ErroAuth(TipoErroAuth.credenciaisInvalidas);
    return _entrou(SessaoAuth(id: 'fake-$chave', email: chave, celularConfirmado: true));
  }

  @override
  Future<SessaoAuth> criarConta(DadosCadastro dados) async {
    _checarFalha();
    final chave = _normalizar(dados.email);
    if (_contas.containsKey(chave)) throw const ErroAuth(TipoErroAuth.emailJaUsado);
    _contas[chave] = dados.senha;
    _codigo.novoCadastro();
    return _entrou(SessaoAuth(id: 'fake-$chave', email: chave, nome: dados.nome));
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

  @override
  Future<void> recuperarSenha(String email) async {
    _checarFalha();
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
    ));
  }
}
