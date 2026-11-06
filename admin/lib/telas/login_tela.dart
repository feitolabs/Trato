import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';

class LoginTela extends StatefulWidget {
  const LoginTela({super.key});

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _enviando = false;
  String? _erro;

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

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: EspacosTrato.x4),
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
