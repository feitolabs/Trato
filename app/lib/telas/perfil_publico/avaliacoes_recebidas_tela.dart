import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional_apoio/apoio.dart';
import 'perfil_publico.dart';
import 'perfil_publico_tela.dart' show CartaoAvaliacao;

/// Lista das avaliações que o profissional recebeu.
class AvaliacoesRecebidasTela extends StatefulWidget {
  const AvaliacoesRecebidasTela({super.key, required this.servico});

  final ServicoPerfilPublico servico;

  @override
  State<AvaliacoesRecebidasTela> createState() => _AvaliacoesRecebidasTelaState();
}

class _AvaliacoesRecebidasTelaState extends State<AvaliacoesRecebidasTela> {
  int _versao = 0;

  Future<void> _abrirResposta(Avaliacao avaliacao) async {
    final servico = widget.servico;
    final id = avaliacao.id;
    if (servico is! RespostaAvaliacao || id == null || id.isEmpty) return;

    final respondeu = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaRespostaAvaliacao(
        aoEnviar: (texto) => (servico as RespostaAvaliacao).responderAvaliacao(id, texto),
      ),
    );
    if (respondeu == true && mounted) {
      setState(() => _versao++);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Resposta enviada.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final podeResponder = widget.servico is RespostaAvaliacao;
    return PaginaCarregavel<List<Avaliacao>>(
      key: ValueKey(_versao),
      titulo: 'Avaliações recebidas',
      carregar: widget.servico.carregarAvaliacoes,
      estaVazio: (l) => l.isEmpty,
      iconeVazio: Icons.star_border,
      tituloVazio: 'Nenhuma avaliação ainda',
      textoVazio: 'Depois do primeiro serviço concluído, as avaliações dos clientes aparecem aqui.',
      construir: (context, lista) => CorpoRolavel(
        children: [
          Text(
            '${lista.length} ${lista.length == 1 ? 'avaliação' : 'avaliações'}',
            style: TipografiaTrato.tituloGrande,
          ),
          const SizedBox(height: EspacosTrato.x4),
          for (final a in lista)
            CartaoAvaliacao(
              avaliacao: a,
              aoResponder:
                  podeResponder && (a.id ?? '').isNotEmpty && (a.resposta ?? '').trim().isEmpty
                      ? () => _abrirResposta(a)
                      : null,
            ),
        ],
      ),
    );
  }
}

class _FolhaRespostaAvaliacao extends StatefulWidget {
  const _FolhaRespostaAvaliacao({required this.aoEnviar});

  final Future<String?> Function(String texto) aoEnviar;

  @override
  State<_FolhaRespostaAvaliacao> createState() => _FolhaRespostaAvaliacaoState();
}

class _FolhaRespostaAvaliacaoState extends State<_FolhaRespostaAvaliacao> {
  final _ctrl = TextEditingController();
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Escreva uma resposta antes de enviar.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.aoEnviar(texto);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = 'Não foi possível enviar agora. Tente de novo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: EspacosTrato.x5,
          right: EspacosTrato.x5,
          top: EspacosTrato.x5,
          bottom: MediaQuery.of(context).viewInsets.bottom + EspacosTrato.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Responder avaliação', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              key: const ValueKey('campo-resposta-avaliacao'),
              controller: _ctrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Escreva sua resposta para o cliente',
                errorText: _erro,
              ),
            ),
            const SizedBox(height: EspacosTrato.x4),
            BotaoPrimario(
              key: const ValueKey('botao-enviar-resposta'),
              texto: 'Enviar resposta',
              carregando: _enviando,
              aoTocar: _enviando ? null : _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
