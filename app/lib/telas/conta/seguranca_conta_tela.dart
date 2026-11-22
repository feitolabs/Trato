import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../auth/validacao.dart';
import '../comuns/estados.dart';

/// Alteração de e-mail e senha com a sessão autenticada aberta.
class SegurancaContaTela extends StatefulWidget {
  const SegurancaContaTela({super.key, this.auth});

  final ServicoAuth? auth;

  @override
  State<SegurancaContaTela> createState() => _SegurancaContaTelaState();
}

class _SegurancaContaTelaState extends State<SegurancaContaTela> {
  ServicoAuth get _auth => widget.auth ?? ServicoAuthPadrao.atual;

  late final _emailCtrl = TextEditingController(text: _auth.sessaoAtual?.email ?? '');
  final _senhaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  var _salvandoEmail = false;
  var _salvandoSenha = false;
  String? _erroEmail;
  String? _avisoEmail;
  String? _erroSenha;
  String? _avisoSenha;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _atualizarEmail() async {
    if (_salvandoEmail) return;
    final novo = _emailCtrl.text.trim();
    final err = ValidacaoAuth.email(novo);
    if (err != null) {
      setState(() {
        _erroEmail = err;
        _avisoEmail = null;
      });
      return;
    }
    setState(() {
      _salvandoEmail = true;
      _erroEmail = null;
      _avisoEmail = null;
    });
    try {
      await _auth.alterarEmail(novo);
      if (!mounted) return;
      setState(() {
        _avisoEmail =
            'Pedido de troca enviado. Se exigido, confirme pelo link no novo e-mail.';
      });
    } on ErroAuth catch (e) {
      if (mounted) setState(() => _erroEmail = e.mensagem);
    } on Object {
      if (mounted) setState(() => _erroEmail = 'Não foi possível atualizar o e-mail.');
    } finally {
      if (mounted) setState(() => _salvandoEmail = false);
    }
  }

  Future<void> _atualizarSenha() async {
    if (_salvandoSenha) return;
    final nova = _senhaCtrl.text;
    final conf = _confirmarCtrl.text;
    final err = ValidacaoAuth.senhaNova(nova);
    if (err != null) {
      setState(() {
        _erroSenha = err;
        _avisoSenha = null;
      });
      return;
    }
    if (nova != conf) {
      setState(() {
        _erroSenha = 'As senhas digitadas não conferem.';
        _avisoSenha = null;
      });
      return;
    }
    setState(() {
      _salvandoSenha = true;
      _erroSenha = null;
      _avisoSenha = null;
    });
    try {
      await _auth.definirNovaSenha(nova);
      if (!mounted) return;
      _senhaCtrl.clear();
      _confirmarCtrl.clear();
      setState(() {
        _avisoSenha = 'Senha atualizada com sucesso.';
      });
    } on ErroAuth catch (e) {
      if (mounted) setState(() => _erroSenha = e.mensagem);
    } on Object {
      if (mounted) setState(() => _erroSenha = 'Não foi possível atualizar a senha.');
    } finally {
      if (mounted) setState(() => _salvandoSenha = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailAtual = _auth.sessaoAtual?.email;
    return MolduraTelaComum(
      titulo: 'E-mail e senha',
      child: ListView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          if (emailAtual != null && emailAtual.isNotEmpty) ...[
            Text(
              'Conta conectada como $emailAtual',
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x4),
          ],
          CartaoTrato(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alterar e-mail de acesso', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x3),
                CampoTrato(
                  key: const Key('campo-novo-email'),
                  rotulo: 'Novo e-mail',
                  controlador: _emailCtrl,
                  teclado: TextInputType.emailAddress,
                  dica: 'nome@exemplo.com',
                  erro: _erroEmail,
                ),
                if (_avisoEmail != null) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    _avisoEmail!,
                    style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.verdeTexto),
                  ),
                ],
                const SizedBox(height: EspacosTrato.x4),
                BotaoPrimario(
                  key: const Key('botao-atualizar-email'),
                  texto: 'Atualizar e-mail',
                  carregando: _salvandoEmail,
                  aoTocar: _salvandoEmail ? null : _atualizarEmail,
                ),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
          CartaoTrato(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alterar senha', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x3),
                CampoTrato(
                  key: const Key('campo-nova-senha'),
                  rotulo: 'Nova senha',
                  controlador: _senhaCtrl,
                  senha: true,
                  ajuda: 'Pelo menos 8 caracteres, com letra e número.',
                ),
                const SizedBox(height: EspacosTrato.x3),
                CampoTrato(
                  key: const Key('campo-confirmar-senha'),
                  rotulo: 'Confirmar nova senha',
                  controlador: _confirmarCtrl,
                  senha: true,
                  erro: _erroSenha,
                ),
                if (_avisoSenha != null) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    _avisoSenha!,
                    style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.verdeTexto),
                  ),
                ],
                const SizedBox(height: EspacosTrato.x4),
                BotaoPrimario(
                  key: const Key('botao-atualizar-senha'),
                  texto: 'Atualizar senha',
                  carregando: _salvandoSenha,
                  aoTocar: _salvandoSenha ? null : _atualizarSenha,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
