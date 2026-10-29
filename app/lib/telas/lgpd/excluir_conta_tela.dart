import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

/// Exclusão da conta em 2 passos: (1) o que acontece e o que a lei manda reter;
/// (2) confirmação digitando [palavraConfirmacao]. Só no passo 2 o serviço é chamado.
class ExcluirContaTela extends StatefulWidget {
  const ExcluirContaTela({super.key, required this.servico, this.aoContaExcluida});

  static const palavraConfirmacao = 'EXCLUIR';

  final ServicoPrivacidade servico;
  final VoidCallback? aoContaExcluida;

  @override
  State<ExcluirContaTela> createState() => _ExcluirContaTelaState();
}

class _ExcluirContaTelaState extends State<ExcluirContaTela> {
  final _confirmacao = TextEditingController();
  var _passo = 1;
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _confirmacao.dispose();
    super.dispose();
  }

  bool get _confirmado => _confirmacao.text.trim().toUpperCase() == ExcluirContaTela.palavraConfirmacao;

  Future<void> _excluir() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.servico.solicitarExclusao();
      if (!mounted) return;
      widget.aoContaExcluida?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _erro = 'Não foi possível pedir a exclusão agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Excluir minha conta',
      child: ListView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          Text('PASSO $_passo DE 2', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          if (_passo == 1) ..._passoUm() else ..._passoDois(),
        ],
      ),
    );
  }

  List<Widget> _passoUm() => [
        Text('O que acontece', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        const _Item('Você perde o acesso à conta, ao histórico e às conversas.'),
        const _Item('Pedidos em andamento ou em disputa precisam ser resolvidos antes.'),
        const _Item('Seus dados pessoais são apagados ou anonimizados.'),
        const SizedBox(height: EspacosTrato.x5),
        Text('O que guardamos por obrigação legal', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        const _Item(
          'Registros de pagamentos e repasses, exigidos por normas fiscais e financeiras.',
        ),
        const _Item('Registros necessários para resolver disputas e cumprir ordens da lei.'),
        const _Item('Esses registros ficam pelo prazo que a lei determina e só são usados para isso.'),
        const SizedBox(height: EspacosTrato.x6),
        BotaoPrimario(texto: 'Continuar', aoTocar: () => setState(() => _passo = 2)),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(texto: 'Cancelar', aoTocar: () => Navigator.of(context).maybePop()),
      ];

  List<Widget> _passoDois() => [
        Text(
          'Para confirmar, digite ${ExcluirContaTela.palavraConfirmacao} no campo abaixo.',
          style: TipografiaTrato.corpo,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Confirmação',
          controlador: _confirmacao,
          dica: ExcluirContaTela.palavraConfirmacao,
          aoMudar: (_) => setState(() {}),
        ),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Semantics(
            liveRegion: true,
            child: Text(
              _erro!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto),
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x6),
        BotaoPrimario(
          texto: 'Excluir minha conta',
          carregando: _enviando,
          aoTocar: _confirmado && !_enviando ? _excluir : null,
        ),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(
          texto: 'Voltar',
          aoTocar: _enviando ? null : () => setState(() => _passo = 1),
        ),
      ];
}

class _Item extends StatelessWidget {
  const _Item(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: EspacosTrato.x2),
            child: Icon(Icons.circle, size: 8, color: CoresTrato.petroleo),
          ),
          Expanded(child: Text(texto, style: TipografiaTrato.corpo)),
        ],
      ),
    );
  }
}
