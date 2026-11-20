import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../nucleo/escopo.dart';
import '../nucleo/recuperacao_senha.dart';
import '../tema/tema.dart';

/// Mínimo de caracteres da senha nova. Se o servidor exigir mais, ele recusa e a tela mostra o erro.
const kSenhaMinimaCaracteres = 8;

/// "Definir nova senha": aberta pelo link de recuperação enviado por e-mail.
/// O token do link fica só em memória e nunca vai para log nem para a URL.
class NovaSenhaTela extends StatefulWidget {
  const NovaSenhaTela({super.key, required this.link, required this.aoConcluir});

  final LinkRecuperacao link;

  /// Chamado ao terminar (senha definida) ou ao desistir de um link vencido: volta ao login.
  final void Function({required bool definida}) aoConcluir;

  @override
  State<NovaSenhaTela> createState() => _NovaSenhaTelaState();
}

class _NovaSenhaTelaState extends State<NovaSenhaTela> {
  final _senha = TextEditingController();
  final _confirmar = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  String? get _erroSenha =>
      _senha.text.isNotEmpty && _senha.text.length < kSenhaMinimaCaracteres ? 'Use pelo menos $kSenhaMinimaCaracteres caracteres.' : null;

  String? get _erroConfirmar =>
      _confirmar.text.isNotEmpty && _confirmar.text != _senha.text ? 'As senhas não são iguais.' : null;

  bool get _valida => _senha.text.length >= kSenhaMinimaCaracteres && _senha.text == _confirmar.text;

  Future<void> _salvar() async {
    final token = widget.link.token;
    if (!_valida || token == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final api = context.api;
    try {
      await api.definirNovaSenha(token, _senha.text);
      if (mounted) widget.aoConcluir(definida: true);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vencido = widget.link.token == null || widget.link.expirado;
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
                  Semantics(header: true, child: Text('Definir nova senha', style: TipografiaTrato.titulo)),
                  const SizedBox(height: EspacosTrato.x3),
                  if (vencido) ...[
                    const BannerInfo(
                      'Este link expirou ou já foi usado. Volte ao login e use "Esqueci a senha" para receber outro.',
                      tom: Tom.alerta,
                    ),
                    const SizedBox(height: EspacosTrato.x5),
                    BotaoTrato.primario('Voltar ao login', aoPressionar: () => widget.aoConcluir(definida: false)),
                  ] else ...[
                    Text(
                      'Escolha a senha que você vai usar para entrar no painel.',
                      style: TipografiaTrato.corpo,
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    TextField(
                      key: const ValueKey('nova-senha'),
                      controller: _senha,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Nova senha',
                        helperText: 'Mínimo de $kSenhaMinimaCaracteres caracteres',
                        errorText: _erroSenha,
                      ),
                    ),
                    const SizedBox(height: EspacosTrato.x3),
                    TextField(
                      key: const ValueKey('confirmar-senha'),
                      controller: _confirmar,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _salvar(),
                      decoration: InputDecoration(labelText: 'Confirmar nova senha', errorText: _erroConfirmar),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: EspacosTrato.x3),
                      BannerInfo(_erro!, tom: Tom.erro),
                    ],
                    const SizedBox(height: EspacosTrato.x5),
                    BotaoTrato.primario(
                      'Definir senha',
                      aoPressionar: _valida && !_enviando ? _salvar : null,
                      carregando: _enviando,
                      rotuloCarregando: 'Salvando',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
