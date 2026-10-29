import 'dart:async';

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart';
import '../../tema/tema.dart';

/// Depois de criar a cobrança, o app fica aqui até o BACKEND dizer que o pagamento foi
/// confirmado (webhook assinado do provedor). O app nunca mostra "pago" por conta própria
/// (D14/D15): consulta o status de tempos em tempos.
class AguardandoPagamentoTela extends StatefulWidget {
  const AguardandoPagamentoTela({
    super.key,
    required this.consultar,
    required this.aoConfirmar,
    this.cobranca,
    this.intervalo = const Duration(seconds: 3),
  });

  final Future<StatusPagamento> Function() consultar;
  final VoidCallback aoConfirmar;
  final Cobranca? cobranca;
  final Duration intervalo;

  @override
  State<AguardandoPagamentoTela> createState() => _AguardandoPagamentoTelaState();
}

class _AguardandoPagamentoTelaState extends State<AguardandoPagamentoTela> {
  Timer? _timer;
  String? _erro;
  var _falhou = false;
  var _consultando = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.intervalo, (_) => _consultar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _consultar() async {
    if (_consultando) return;
    _consultando = true;
    try {
      final status = await widget.consultar();
      if (!mounted) return;
      switch (status) {
        case StatusPagamento.pago:
          _timer?.cancel();
          widget.aoConfirmar();
        case StatusPagamento.falhou:
          _timer?.cancel();
          setState(() => _falhou = true);
        case StatusPagamento.aguardando:
          if (_erro != null) setState(() => _erro = null);
      }
    } on ErroTrato catch (erro) {
      // Falha de rede não cancela a espera: tenta de novo na próxima rodada.
      if (mounted) setState(() => _erro = erro.mensagem);
    } finally {
      _consultando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pix = widget.cobranca?.pixCopiaECola;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: ListView(
            children: [
              Text(
                _falhou ? 'O pagamento não foi concluído' : 'Aguardando confirmação do pagamento',
                style: TipografiaTrato.tituloGrande,
              ),
              const SizedBox(height: EspacosTrato.x3),
              Text(
                _falhou
                    ? 'Nada foi cobrado. Volte e tente de novo.'
                    : 'Assim que o parceiro de pagamento confirmar, o Trato avisa aqui. '
                        'Isso pode levar alguns instantes.',
                style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
              ),
              if (!_falhou) ...[
                const SizedBox(height: EspacosTrato.x5),
                Center(
                  child: Semantics(
                    label: 'Aguardando',
                    child: const CircularProgressIndicator(color: CoresTrato.petroleo),
                  ),
                ),
              ],
              if (pix != null && !_falhou) ...[
                const SizedBox(height: EspacosTrato.x5),
                CartaoTrato(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pix copia e cola', style: TipografiaTrato.tituloCartao),
                      const SizedBox(height: EspacosTrato.x2),
                      SelectableText(pix, style: TipografiaTrato.corpoPequeno),
                    ],
                  ),
                ),
              ],
              if (_erro != null && !_falhou) ...[
                const SizedBox(height: EspacosTrato.x4),
                Text(
                  _erro!,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
              if (_falhou) ...[
                const SizedBox(height: EspacosTrato.x5),
                BotaoPrimario(texto: 'Voltar', aoTocar: () => Navigator.of(context).maybePop()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
