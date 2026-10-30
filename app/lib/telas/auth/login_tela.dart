import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import '../onboarding/escolha_perfil_tela.dart';
import '../fluxo/rotas.dart';
import 'estrutura_auth.dart';
import 'recuperar_senha_tela.dart';
import 'validacao.dart';

/// Tela 4 do protótipo: "Entrar na sua conta".
/// Entrar com e-mail, Google e Apple usam o [ServicoAuth]; biometria ainda abre [EmBreveTela].
/// Google e Apple só aparecem se o serviço diz que o provedor está habilitado (Apple só no iOS).
class LoginTela extends StatefulWidget {
  const LoginTela({super.key, this.servico});

  /// Se nulo, usa [ServicoAuthPadrao.atual] (fake até haver chaves).
  final ServicoAuth? servico;

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _identificador = TextEditingController();
  final _senha = TextEditingController();
  var _mostrarSenha = false;
  var _tentou = false;
  var _carregando = false;
  String? _erroServico;

  ServicoAuth get _servico => widget.servico ?? ServicoAuthPadrao.atual;

  bool _mostra(ProvedorAuth p) =>
      _servico.provedorHabilitado(p) &&
      (p != ProvedorAuth.apple || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _identificador.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _abrir(Widget tela) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tela));

  void _emBreve(String titulo) => _abrir(EmBreveTela(titulo: titulo));

  String? get _erroIdentificador {
    if (!_tentou) return null;
    final vazio = ValidacaoAuth.obrigatorio(_identificador.text, 'Informe e-mail, CPF ou telefone.');
    if (vazio != null) return vazio;
    // Por enquanto o login real é só por e-mail (D14).
    return ValidacaoAuth.email(_identificador.text) == null
        ? null
        : 'Entre com o e-mail da sua conta.';
  }

  String? get _erroSenha =>
      _tentou ? ValidacaoAuth.obrigatorio(_senha.text, 'Informe sua senha.') : null;

  /// Roda [acao]; se der certo vai para o app, se não mostra o erro em português.
  Future<void> _tentar(Future<SessaoAuth> Function() acao) async {
    setState(() {
      _carregando = true;
      _erroServico = null;
    });
    try {
      await acao();
    } on ErroAuth catch (e) {
      if (!mounted) return;
      // Cancelar o Google/Apple não é erro.
      setState(() {
        _carregando = false;
        _erroServico = e.tipo == TipoErroAuth.cancelado ? null : e.mensagem;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _carregando = false);
    RotasTrato.irParaCliente(context);
  }

  void _entrar() {
    if (_carregando) return;
    setState(() => _tentou = true);
    if (_erroIdentificador != null || _erroSenha != null) return;
    _tentar(() => _servico.entrarComEmail(
          email: _identificador.text.trim(),
          senha: _senha.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return EstruturaAuth(
      comVoltar: false,
      rodape: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Não tem conta? ', style: TipografiaTrato.corpo),
          BotaoLink(
            texto: 'Criar conta',
            aoTocar: () => _abrir(EscolhaPerfilTela(servico: widget.servico)),
          ),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x6),
        Text('Trato', style: TipografiaTrato.marcaPequena.copyWith(fontSize: 40)),
        const SizedBox(height: EspacosTrato.x2),
        Text('Entrar na sua conta', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x6),
        CampoTrato(
          rotulo: 'E-mail, CPF ou telefone',
          controlador: _identificador,
          teclado: TextInputType.emailAddress,
          erro: _erroIdentificador,
          aoMudar: (_) => setState(() {}),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoTrato(
          rotulo: 'Senha',
          controlador: _senha,
          senha: !_mostrarSenha,
          erro: _erroSenha,
          textoAcao: _mostrarSenha ? 'Ocultar' : 'Mostrar',
          aoTocarAcao: () => setState(() => _mostrarSenha = !_mostrarSenha),
          aoMudar: (_) => setState(() {}),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: BotaoLink(
            texto: 'Esqueci minha senha',
            aoTocar: () => _abrir(RecuperarSenhaTela(servico: widget.servico)),
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        MensagemErroAuth(_erroServico),
        BotaoPrimario(texto: 'Entrar', aoTocar: _entrar, carregando: _carregando),
        const SizedBox(height: EspacosTrato.x4),
        const _DivisorOu(),
        const SizedBox(height: EspacosTrato.x4),
        if (_mostra(ProvedorAuth.google)) ...[
          BotaoSecundario(
            texto: 'Entrar com Google',
            aoTocar: _carregando
                ? null
                : () => _tentar(() => _servico.entrarComProvedor(ProvedorAuth.google)),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_mostra(ProvedorAuth.apple)) ...[
          BotaoSecundario(
            texto: 'Entrar com Apple',
            aoTocar: _carregando
                ? null
                : () => _tentar(() => _servico.entrarComProvedor(ProvedorAuth.apple)),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        BotaoSecundario(
          texto: 'Entrar com biometria',
          icone: Icons.fingerprint,
          aoTocar: () => _emBreve('Entrar com biometria'),
        ),
        const SizedBox(height: EspacosTrato.x4),
      ],
    );
  }
}

class _DivisorOu extends StatelessWidget {
  const _DivisorOu();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
          child: Text(
            'ou',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
