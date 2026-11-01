import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../fluxo/rotas.dart';
import '../onboarding/escolha_perfil_tela.dart';
import 'estrutura_auth.dart';

/// "Confirme seu e-mail", passo 2 de 2 (D16: sem SMS no piloto).
/// O Supabase manda um link para o e-mail; a pessoa abre no celular e volta ao app.
/// "Já confirmei" tenta entrar com e-mail e senha; o reenvio só libera depois de 60 s.
class ConfirmarEmailTela extends StatefulWidget {
  const ConfirmarEmailTela({
    super.key,
    required this.email,
    required this.senha,
    this.perfil = PerfilUso.cliente,
    this.servico,
  });

  /// Se nulo, usa [ServicoAuthPadrao.atual].
  final ServicoAuth? servico;

  final String email;

  /// Só fica na memória desta tela, para o "Já confirmei" entrar sem pedir de novo.
  final String senha;

  /// Perfil escolhido no cadastro: decide para onde o usuário vai depois de confirmar.
  final PerfilUso perfil;

  static const segundosParaReenviar = 60;

  @override
  State<ConfirmarEmailTela> createState() => _ConfirmarEmailTelaState();
}

class _ConfirmarEmailTelaState extends State<ConfirmarEmailTela> {
  Timer? _timer;
  var _restante = ConfirmarEmailTela.segundosParaReenviar;
  var _carregando = false;
  String? _erroServico;
  String? _aviso;

  ServicoAuth get _servico => widget.servico ?? ServicoAuthPadrao.atual;

  @override
  void initState() {
    super.initState();
    _iniciarContagem();
  }

  void _iniciarContagem() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_restante <= 1) t.cancel();
      setState(() => _restante--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reenviar() async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erroServico = null;
      _aviso = null;
    });
    String? erro;
    try {
      await _servico.reenviarEmailConfirmacao(widget.email);
    } on ErroAuth catch (e) {
      erro = e.mensagem;
    }
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _erroServico = erro;
      if (erro == null) {
        _aviso = 'Enviamos um e-mail novo.';
        _restante = ConfirmarEmailTela.segundosParaReenviar;
        _iniciarContagem();
      }
    });
  }

  Future<void> _jaConfirmei() async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erroServico = null;
      _aviso = null;
    });
    String? erro;
    try {
      await _servico.entrarComEmail(email: widget.email, senha: widget.senha);
    } on ErroAuth catch (e) {
      erro = e.tipo == TipoErroAuth.emailNaoConfirmado
          ? 'Ainda não confirmamos. Abra o link do e-mail e volte aqui.'
          : e.mensagem;
    }
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _erroServico = erro;
    });
    if (erro != null) return;
    RotasTrato.irParaDepoisDoCadastro(context, widget.perfil);
  }

  String get _tempo => '${_restante ~/ 60}:${(_restante % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return EstruturaAuth(
      tituloBarra: 'Passo 2 de 2',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MensagemErroAuth(_erroServico),
          BotaoPrimario(texto: 'Já confirmei', aoTocar: _jaConfirmei, carregando: _carregando),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Text('Confirme seu e-mail', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x3),
        Text.rich(
          TextSpan(
            style: TipografiaTrato.corpo,
            children: [
              const TextSpan(text: 'Enviamos um link para '),
              TextSpan(
                text: widget.email,
                style: TipografiaTrato.corpo.copyWith(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '. Abra o e-mail neste celular e toque no link.'),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (_restante > 0)
          Text(
            'Reenviar e-mail em $_tempo',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          )
        else
          BotaoLink(texto: 'Reenviar e-mail', aoTocar: _reenviar),
        if (_aviso != null)
          Text(_aviso!, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.azulTexto)),
        BotaoLink(texto: 'Trocar e-mail', aoTocar: () => Navigator.of(context).pop()),
        const SizedBox(height: EspacosTrato.x4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(EspacosTrato.x4),
          decoration: BoxDecoration(
            color: CoresTrato.azulSuave,
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mail_outline, size: 22, color: CoresTrato.azulTexto),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Text(
                  'Não achou? Olhe a caixa de spam ou lixo eletrônico.',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
