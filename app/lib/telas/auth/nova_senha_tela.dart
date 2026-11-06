import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'estrutura_auth.dart';
import 'login_tela.dart';
import 'validacao.dart';

/// Abre quando o link do e-mail de recuperação traz a pessoa de volta ao app. O link já abriu
/// uma sessão curta só para trocar a senha: aqui a pessoa escolhe a senha nova; ao terminar
/// (ou ao desistir) a sessão é encerrada e ela entra de novo com a senha nova.
class NovaSenhaTela extends StatefulWidget {
  const NovaSenhaTela({super.key, this.servico});

  /// Se nulo, usa [ServicoAuthPadrao.atual].
  final ServicoAuth? servico;

  @override
  State<NovaSenhaTela> createState() => _NovaSenhaTelaState();
}

class _NovaSenhaTelaState extends State<NovaSenhaTela> {
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  var _tentou = false;
  var _carregando = false;
  var _mostrar = false;
  String? _erroServico;

  ServicoAuth get _servico => widget.servico ?? ServicoAuthPadrao.atual;

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  String? get _erroSenha => _tentou ? ValidacaoAuth.senhaNova(_senha.text) : null;

  String? get _erroConfirmacao => _tentou && _senha.text != _confirmacao.text
      ? 'As senhas não são iguais. Digite a mesma senha nos dois campos.'
      : null;

  void _irParaLogin(String aviso) {
    final navegador = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
    navegador.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => LoginTela(servico: widget.servico)),
      (_) => false,
    );
  }

  Future<void> _salvar() async {
    if (_carregando) return;
    setState(() => _tentou = true);
    if (_erroSenha != null || _erroConfirmacao != null) return;
    setState(() {
      _carregando = true;
      _erroServico = null;
    });
    try {
      await _servico.definirNovaSenha(_senha.text);
    } on ErroAuth catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroServico = e.mensagem;
      });
      return;
    }
    // Termina a sessão do link: a pessoa entra de verdade com a senha nova.
    try {
      await _servico.sair();
    } on ErroAuth {
      // Sem rede para encerrar: o login seguinte troca a sessão do mesmo jeito.
    }
    if (!mounted) return;
    _irParaLogin('Senha alterada. Entre com a senha nova.');
  }

  Future<void> _desistir() async {
    try {
      await _servico.sair();
    } on ErroAuth {
      // Segue para o login mesmo assim.
    }
    if (!mounted) return;
    _irParaLogin('A senha não foi alterada.');
  }

  @override
  Widget build(BuildContext context) {
    // Sem voltar pelo gesto: a sessão do link só serve para esta tela.
    return PopScope(
      canPop: false,
      child: EstruturaAuth(
        comVoltar: false,
        rodape: BotaoLink(texto: 'Cancelar', aoTocar: _desistir),
        children: [
          const SizedBox(height: EspacosTrato.x4),
          Text('Criar senha nova', style: TipografiaTrato.tituloGrande),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Escolha uma senha nova para a sua conta. Use pelo menos 8 caracteres, com letras e números.',
            style: TipografiaTrato.corpo,
          ),
          const SizedBox(height: EspacosTrato.x6),
          CampoTrato(
            rotulo: 'Senha nova',
            controlador: _senha,
            senha: !_mostrar,
            erro: _erroSenha,
            textoAcao: _mostrar ? 'Ocultar' : 'Mostrar',
            aoTocarAcao: () => setState(() => _mostrar = !_mostrar),
            aoMudar: (_) => setState(() {}),
          ),
          const SizedBox(height: EspacosTrato.x5),
          CampoTrato(
            rotulo: 'Repita a senha nova',
            controlador: _confirmacao,
            senha: !_mostrar,
            erro: _erroConfirmacao,
            aoMudar: (_) => setState(() {}),
          ),
          const SizedBox(height: EspacosTrato.x5),
          MensagemErroAuth(_erroServico),
          BotaoPrimario(texto: 'Salvar senha', aoTocar: _salvar, carregando: _carregando),
        ],
      ),
    );
  }
}
