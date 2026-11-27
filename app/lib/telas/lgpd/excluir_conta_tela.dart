import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/desconto_moedas.dart';
import '../comuns/estados.dart';
import '../comuns/textos_dos_termos.dart';
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

  SaldoTratinhos? _saldo;
  var _lendoSaldo = false;
  var _falhaNoSaldo = false;

  @override
  void initState() {
    super.initState();
    _lerSaldo();
  }

  Future<void> _lerSaldo() async {
    final Object servico = widget.servico;
    if (servico is! ConsultaDeTratinhos) return;
    setState(() {
      _lendoSaldo = true;
      _falhaNoSaldo = false;
    });
    try {
      final saldo = await servico.saldoDeTratinhos();
      if (mounted) setState(() => _saldo = saldo);
    } on Object {
      if (mounted) setState(() => _falhaNoSaldo = true);
    } finally {
      if (mounted) setState(() => _lendoSaldo = false);
    }
  }

  /// O que acontece com os Tratinhos, com o saldo do servidor. Falha no saldo não impede o
  /// encerramento: o aviso aparece sempre.
  List<Widget> _avisoDosTratinhos() {
    final s = _saldo;
    final aPerder = s?.tratinhosAPerder;
    final cliente = s?.cliente;
    final profissional = s?.profissional ?? 0;
    String valor(int quantidade) => textoTratinhosEmReais(quantidade, s?.valorMoedaCentavos);
    final String texto;
    if (_lendoSaldo) {
      texto = 'Conferindo o seu saldo de Tratinhos…';
    } else if (_falhaNoSaldo) {
      texto = 'Não deu para ver o seu saldo de Tratinhos agora.';
    } else if (aPerder != null) {
      texto = aPerder > 0
          ? 'Você perderá ${valor(aPerder)} ao encerrar a conta por vontade própria.'
          : 'Você não tem Tratinhos disponíveis agora. Eventual saldo não é mantido ao encerrar por vontade própria.';
    } else if (cliente == null) {
      texto = 'O saldo de Tratinhos não foi informado agora.';
    } else if (profissional > 0) {
      texto = 'Saldo como cliente: ${valor(cliente)}.\n'
          'Saldo como profissional: ${valor(profissional)}.';
    } else {
      texto = cliente == 0 ? 'Você não tem Tratinhos agora.' : 'Seu saldo: ${valor(cliente)}.';
    }
    final guarda = s?.guardadosAte;
    String dois(int n) => n.toString().padLeft(2, '0');
    return [
      if (s != null && s.pendencias.isNotEmpty) ...[
        CartaoTrato(
          key: const Key('pendencias-exclusao'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pendências da conta', style: TipografiaTrato.tituloCartao),
              const SizedBox(height: EspacosTrato.x2),
              for (final p in s.pendencias) Text('• $p', style: TipografiaTrato.corpo),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
      ],
      CartaoTrato(
        key: const Key('aviso-tratinhos-encerramento'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Seus Tratinhos', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x2),
            // Com guarda informada pelo servidor, o aviso de perda não se aplica.
            if (guarda != null)
              Text(
                'Seus Tratinhos ficam guardados até '
                '${dois(guarda.day)}/${dois(guarda.month)}/${guarda.year}.',
                key: const Key('tratinhos-guardados'),
                style: TipografiaTrato.corpoForte,
              )
            else ...[
              Text(textoTratinhosNoEncerramento, style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                texto,
                key: const Key('saldo-no-encerramento'),
                style: TipografiaTrato.corpoForte,
              ),
            ],
            if (_falhaNoSaldo) BotaoLink(texto: 'Tentar de novo', aoTocar: _lerSaldo),
          ],
        ),
      ),
    ];
  }

  @override
  void dispose() {
    _confirmacao.dispose();
    super.dispose();
  }

  bool get _confirmado =>
      _confirmacao.text.trim().toUpperCase() == ExcluirContaTela.palavraConfirmacao;

  Future<void> _excluir() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.servico.solicitarExclusao();
      if (!mounted) return;
      widget.aoContaExcluida?.call();
    } on ErroTrato catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.mensagem);
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
        const SizedBox(height: EspacosTrato.x3),
        ..._avisoDosTratinhos(),
        const SizedBox(height: EspacosTrato.x5),
        Text('O que guardamos por obrigação legal', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        const _Item(
          'Registros de pagamentos e repasses, exigidos por normas fiscais e financeiras.',
        ),
        const _Item('Registros necessários para resolver disputas e cumprir ordens da lei.'),
        const _Item(
            'Esses registros ficam pelo prazo que a lei determina e só são usados para isso.'),
        const SizedBox(height: EspacosTrato.x6),
        BotaoPrimario(texto: 'Continuar', aoTocar: () => setState(() => _passo = 2)),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(texto: 'Cancelar', aoTocar: () => Navigator.of(context).maybePop()),
      ];

  List<Widget> _passoDois() => [
        ..._avisoDosTratinhos(),
        const SizedBox(height: EspacosTrato.x4),
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
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
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
          Padding(
            padding: const EdgeInsets.only(top: 2, right: EspacosTrato.x2),
            child: Icon(Icons.circle, size: 8, color: context.cores.petroleo),
          ),
          Expanded(child: Text(texto, style: TipografiaTrato.corpo)),
        ],
      ),
    );
  }
}
