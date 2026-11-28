import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';

/// Termos 4.9: tela de conta inativa (`403 conta_inativa`). A pessoa continua logada para
/// reativar gratuitamente no app (`POST /v1/me/reativar`), falar com o suporte ou sair.
class ContaInativaTela extends StatefulWidget {
  const ContaInativaTela({
    super.key,
    this.mensagem,
    required this.aoReativar,
    required this.aoReativada,
    required this.aoFalar,
    required this.aoSair,
  });

  /// Mensagem devolvida pelo servidor (opcional).
  final String? mensagem;

  /// Chama `POST /v1/me/reativar`.
  final Future<void> Function() aoReativar;

  /// Chamado após reativação bem-sucedida para retomar o uso normal do app.
  final VoidCallback aoReativada;

  /// Abre o atendimento / suporte.
  final VoidCallback aoFalar;

  /// Encerra a sessão.
  final Future<void> Function() aoSair;

  @override
  State<ContaInativaTela> createState() => _ContaInativaTelaState();
}

class _ContaInativaTelaState extends State<ContaInativaTela> {
  var _reativando = false;
  var _saindo = false;
  String? _erro;

  Future<void> _reativar() async {
    if (_reativando) return;
    setState(() {
      _reativando = true;
      _erro = null;
    });
    try {
      await widget.aoReativar();
      if (!mounted) return;
      setState(() => _reativando = false);
      widget.aoReativada();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _reativando = false;
        _erro = e is ErroTrato
            ? e.mensagem
            : 'Não foi possível reativar sua conta agora. Tente de novo.';
      });
    }
  }

  Future<void> _sair() async {
    if (_saindo) return;
    setState(() => _saindo = true);
    try {
      await widget.aoSair();
    } finally {
      if (mounted) setState(() => _saindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x6),
          child: ConteudoResponsivo(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.pause_circle_outline, size: 48, color: c.petroleo),
                const SizedBox(height: EspacosTrato.x4),
                Text('Conta inativa', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  widget.mensagem ??
                      'Sua conta está inativa por falta de uso. Você pode reativá-la gratuitamente '
                          'agora para voltar a usar o Trato.',
                  key: const Key('motivo-inatividade'),
                  style: TipografiaTrato.corpo,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  'A reativação é gratuita e imediata. Se precisar de ajuda, fale com o suporte.',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  Text(
                    _erro!,
                    key: const Key('erro-reativar-conta'),
                    style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
                  ),
                ],
                const SizedBox(height: EspacosTrato.x5),
                BotaoPrimario(
                  key: const Key('botao-reativar-conta'),
                  texto: 'Reativar conta gratuitamente',
                  carregando: _reativando,
                  aoTocar: _reativando ? null : _reativar,
                ),
                const SizedBox(height: EspacosTrato.x3),
                BotaoSecundario(
                  key: const Key('botao-suporte-inativa'),
                  texto: 'Falar com o suporte',
                  icone: Icons.support_agent_outlined,
                  aoTocar: widget.aoFalar,
                ),
                const SizedBox(height: EspacosTrato.x3),
                BotaoLink(
                  key: const Key('botao-sair-inativa'),
                  texto: _saindo ? 'Saindo...' : 'Sair da conta',
                  aoTocar: _saindo ? null : _sair,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
