import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show LinhaValor, formatarReais;
import 'acordo.dart';

/// Os valores do acordo, como o servidor informar (o que ele não mandar não aparece).
class ValoresAcordo extends StatelessWidget {
  const ValoresAcordo({super.key, required this.acordo});

  final AcordoDisputa acordo;

  @override
  Widget build(BuildContext context) {
    final devolvido = acordo.reembolsoCentavos;
    final liberado = acordo.liberadoCentavos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (devolvido != null)
          LinhaValor(rotulo: 'Devolução ao cliente', valor: formatarReais(devolvido)),
        if (liberado != null) ...[
          const SizedBox(height: EspacosTrato.x2),
          LinhaValor(rotulo: 'Liberado ao profissional', valor: formatarReais(liberado)),
        ],
      ],
    );
  }
}

/// No pedido: a proposta de devolução (o cliente aceita) ou o acordo fechado (os dois veem).
/// Sem nada disso, não ocupa espaço.
class SecaoAcordoDisputa extends StatefulWidget {
  const SecaoAcordoDisputa({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.profissional,
    this.atualizarQuando,
    this.aoMudar,
  });

  final ServicoAcordoDisputa servico;
  final String pedidoId;
  final bool profissional;
  final Listenable? atualizarQuando;

  /// Chamado depois do acordo aceito, para o pedido se atualizar.
  final VoidCallback? aoMudar;

  @override
  State<SecaoAcordoDisputa> createState() => _SecaoAcordoDisputaState();
}

class _SecaoAcordoDisputaState extends State<SecaoAcordoDisputa> {
  SituacaoDisputa? _dados;
  var _falhou = false;
  var _enviando = false;
  var _geracao = 0;
  String? _erro;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_buscar);
    _buscar();
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_buscar);
    super.dispose();
  }

  Future<void> _buscar() async {
    final minha = ++_geracao;
    try {
      final dados = await widget.servico.ver(widget.pedidoId);
      if (!mounted || minha != _geracao) return;
      setState(() {
        _dados = dados;
        _falhou = false;
      });
    } on Object {
      // Com um dado já lido, ele continua na tela.
      if (mounted && minha == _geracao) setState(() => _falhou = _dados == null);
    }
  }

  Future<void> _aceitar(PropostaDisputa proposta) async {
    if (_enviando) return;
    final valor = formatarReais(proposta.reembolsoCentavos!);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Aceitar a proposta?'),
        content: Text('Voltam $valor para você. Ao aceitar, o acordo encerra a disputa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          TextButton(
            key: const Key('confirmar-acordo'),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Aceitar acordo'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted || _enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final novo = await widget.servico.aceitar(widget.pedidoId, proposta);
      if (!mounted) return;
      if (novo != null) {
        _geracao++; // uma leitura antiga em andamento não sobrescreve o acordo
        setState(() => _dados = novo);
      } else {
        await _buscar();
      }
      widget.aoMudar?.call();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _erro = e is ErroTrato
          ? e.mensagem
          : 'Não foi possível aceitar agora. Tente de novo em instantes.');
      // 409: a proposta mudou ou não se aceita mais.
      if (e is ErroTrato && e.codigoHttp == 409) await _buscar();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    final acordo = d?.acordo;
    final proposta = d?.propostaAberta;
    final encerrada = acordo != null || d?.estado == 'acordo';
    if (!_falhou && !encerrada && proposta == null && _erro == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: const Key('secao-acordo-disputa'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_falhou) ...[
              Text('Não deu para conferir a disputa agora.', style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x3),
              BotaoSecundario(texto: 'Tentar de novo', aoTocar: _buscar),
            ] else if (encerrada) ...[
              Text('Disputa encerrada por acordo', style: TipografiaTrato.tituloCartao),
              if (acordo != null) ...[
                const SizedBox(height: EspacosTrato.x3),
                ValoresAcordo(acordo: acordo),
              ],
            ] else if (proposta != null) ...[
              Text('Proposta de devolução', style: TipografiaTrato.tituloCartao),
              const SizedBox(height: EspacosTrato.x1),
              Text(
                widget.profissional
                    ? 'Você propôs devolver este valor. O cliente decide se aceita.'
                    : 'O profissional propôs devolver este valor. Você decide se aceita.',
                style: TipografiaTrato.corpo,
              ),
              const SizedBox(height: EspacosTrato.x3),
              LinhaValor(
                rotulo: 'Devolução proposta',
                valor: formatarReais(proposta.reembolsoCentavos!),
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: EspacosTrato.x2),
              Semantics(
                liveRegion: true,
                child: Text(
                  _erro!,
                  key: const Key('erro-acordo'),
                  style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
                ),
              ),
            ],
            if (!_falhou && proposta != null && !widget.profissional) ...[
              const SizedBox(height: EspacosTrato.x3),
              BotaoPrimario(
                key: const Key('aceitar-proposta'),
                texto: 'Aceitar proposta',
                carregando: _enviando,
                aoTocar: _enviando ? null : () => _aceitar(proposta),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
