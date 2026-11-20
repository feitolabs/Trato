import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';

class LoginTela extends StatefulWidget {
  const LoginTela({super.key, this.aviso});

  /// Mensagem de sucesso mostrada acima do formulário (ex.: senha definida).
  final String? aviso;

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _enviando = false;
  String? _erro;
  String? _aviso;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_email.text.trim().isEmpty || _senha.text.isEmpty) {
      setState(() => _erro = 'Preencha e-mail e senha.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final sessao = context.sessao;
    try {
      final usuario = await context.api.entrar(_email.text, _senha.text);
      sessao.entrou(usuario);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _esqueci() async {
    final api = context.api;
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoEsqueci(inicial: _email.text.trim()),
    );
    if (email == null || !mounted) return;
    try {
      await api.pedirRecuperacaoSenha(email);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
      return;
    } catch (_) {
      // Qualquer outra falha também não pode revelar nada sobre a conta.
    }
    if (mounted) {
      setState(() {
        _erro = null;
        _aviso = 'Se esse e-mail tiver conta na equipe, enviamos um link para criar a senha. Olhe também o spam.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = _aviso ?? widget.aviso;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(EspacosTrato.x4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: CartaoSecao(
              padding: const EdgeInsets.all(EspacosTrato.x8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Trato', style: TipografiaTrato.marca),
                  const SizedBox(height: EspacosTrato.x1),
                  Text('PAINEL ADMIN', style: TipografiaTrato.sobretitulo),
                  const SizedBox(height: EspacosTrato.x6),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'E-mail da equipe'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: _senha,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _entrar(),
                    decoration: const InputDecoration(labelText: 'Senha'),
                  ),
                  if (aviso != null) ...[
                    const SizedBox(height: EspacosTrato.x3),
                    BannerInfo(aviso, tom: Tom.ok),
                  ],
                  if (_erro != null) ...[
                    const SizedBox(height: EspacosTrato.x3),
                    BannerInfo(_erro!, tom: Tom.erro),
                  ],
                  const SizedBox(height: EspacosTrato.x5),
                  BotaoTrato.primario(
                    'Entrar',
                    aoPressionar: _enviando ? null : _entrar,
                    carregando: _enviando,
                    rotuloCarregando: 'Entrando',
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  BotaoTrato.link('Esqueci a senha', aoPressionar: _enviando ? null : _esqueci),
                  const SizedBox(height: EspacosTrato.x2),
                  const AvisoAuditoria(texto: 'Cada acesso e cada ação ficam registrados com o seu nome.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogoEsqueci extends StatefulWidget {
  const _DialogoEsqueci({required this.inicial});
  final String inicial;

  @override
  State<_DialogoEsqueci> createState() => _DialogoEsqueciState();
}

class _DialogoEsqueciState extends State<_DialogoEsqueci> {
  late final _email = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _valido => _email.text.contains('@') && _email.text.trim().length > 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Esqueci a senha'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Digite o e-mail da equipe. Se ele tiver conta, enviamos um link para criar a senha.'),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('esqueci-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'E-mail da equipe'),
          ),
        ],
      ),
      actions: [
        BotaoTrato.link('Cancelar', aoPressionar: () => Navigator.of(context).pop()),
        BotaoTrato.primario(
          'Enviar link',
          aoPressionar: _valido ? () => Navigator.of(context).pop(_email.text.trim()) : null,
        ),
      ],
    );
  }
}
