import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show LinhaValor, formatarReais;
import '../profissional_apoio/apoio.dart';
import 'aditivo.dart';

/// F5.9 (cliente): aprovar ou recusar um aditivo. A resposta é do cliente; quem registra
/// e ajusta valores é o backend. O app nunca mostra o aditivo como "pago".
class ResponderAditivoTela extends StatelessWidget {
  const ResponderAditivoTela({
    super.key,
    required this.servico,
    required this.aditivoId,
    this.aoResponder,
  });

  final ServicoAditivo servico;
  final String aditivoId;

  /// Depois que o serviço aceitou a resposta (true = aprovou).
  final ValueChanged<bool>? aoResponder;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<DetalheAditivo?>(
      titulo: 'Aditivo',
      carregar: () => servico.carregar(aditivoId),
      estaVazio: (d) => d == null,
      iconeVazio: Icons.playlist_add_check,
      tituloVazio: 'Nenhum aditivo',
      textoVazio: 'Este serviço não tem aditivo para responder.',
      construir: (context, d) => _Corpo(
        detalhe: d!,
        servico: servico,
        aoResponder: aoResponder,
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({required this.detalhe, required this.servico, required this.aoResponder});

  final DetalheAditivo detalhe;
  final ServicoAditivo servico;
  final ValueChanged<bool>? aoResponder;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  late EstadoAditivo _estado = widget.detalhe.estado;
  bool? _enviando; // true = aprovando, false = recusando
  String? _erro;

  Future<void> _responder(bool aprovar) async {
    if (!aprovar) {
      final confirma = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Recusar o aditivo?'),
          content: const Text('O serviço segue pelo valor combinado antes.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Recusar')),
          ],
        ),
      );
      if (confirma != true || !mounted) return;
    }
    setState(() {
      _enviando = aprovar;
      _erro = null;
    });
    try {
      await widget.servico.responder(widget.detalhe.id, aprovar: aprovar);
      if (!mounted) return;
      setState(() {
        _enviando = null;
        _estado = aprovar ? EstadoAditivo.aprovado : EstadoAditivo.recusado;
      });
      widget.aoResponder?.call(aprovar);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = null;
        _erro = 'Não foi possível enviar sua resposta. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detalhe;
    final aguardando = _estado == EstadoAditivo.aguardando;
    return CorpoRolavel(
      rodape: aguardando
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_erro != null) ...[
                  AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                BotaoPrimario(
                  texto: 'Aprovar aditivo',
                  carregando: _enviando == true,
                  aoTocar: _enviando == null ? () => _responder(true) : null,
                ),
                const SizedBox(height: EspacosTrato.x2),
                BotaoSecundario(
                  texto: 'Recusar',
                  aoTocar: _enviando == null ? () => _responder(false) : null,
                ),
              ],
            )
          : null,
      children: [
        Text('Cobrança extra', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          '${d.profissional} pediu um valor a mais em "${d.pedidoTitulo}".',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        switch (_estado) {
          EstadoAditivo.aguardando =>
            const ChipStatus(texto: 'Aguardando sua resposta', tipo: TipoStatus.alerta),
          EstadoAditivo.aprovado => const ChipStatus(
              texto: 'Aditivo aprovado', tipo: TipoStatus.sucesso, icone: Icons.check),
          EstadoAditivo.recusado =>
            const ChipStatus(texto: 'Aditivo recusado', tipo: TipoStatus.perigo),
        },
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Motivo', style: TipografiaTrato.corpoForte),
              const SizedBox(height: EspacosTrato.x1),
              Text(d.motivo, style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x4),
              LinhaValor(rotulo: 'Valor do aditivo', valor: formatarReais(d.valorCentavos), destaque: true),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          'O aditivo só vale se você aprovar aqui. A cobrança segue o fluxo '
          'de pagamento do pedido.',
          style: TipografiaTrato.legenda,
        ),
      ],
    );
  }
}
