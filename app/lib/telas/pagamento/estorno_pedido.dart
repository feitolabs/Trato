// Termos 6.10: status e prazo do estorno dentro do pedido. O app só mostra o que o servidor diz.
import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show formatarData, formatarReais;
import 'modelos.dart';

/// Estorno de uma cobrança do pedido.
class EstornoDoPedido {
  const EstornoDoPedido({
    required this.status,
    this.prazoEstimado,
    this.cobrancaCentavos,
    this.meio,
    this.valorCentavos,
    this.solicitadoEm,
    this.enviadoEm,
  });

  final String status;
  final String? prazoEstimado;

  /// Valor da cobrança original.
  final int? cobrancaCentavos;

  /// Quanto foi MANDADO devolver. Não confirma nada: quem diz isso é o [status].
  final int? valorCentavos;

  /// Quando o estorno foi registrado.
  final DateTime? solicitadoEm;

  /// Envio ao provedor de pagamento; não é a data em que o dinheiro cai.
  final DateTime? enviadoEm;
  final String? meio;

  /// Item de `GET /v1/pedidos/{id}/cobrancas`. Sem `estorno_status`: nulo.
  static EstornoDoPedido? deJson(Object? bruto) {
    if (bruto is! Map) return null;
    String? texto(String chave) {
      final v = bruto[chave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final status = texto('estorno_status');
    if (status == null) return null;
    final valor = bruto['valor_centavos'];
    final devolver = bruto['estorno_valor_centavos'];
    DateTime? data(String chave) => DateTime.tryParse(texto(chave) ?? '')?.toLocal();
    return EstornoDoPedido(
      status: status,
      prazoEstimado: texto('estorno_prazo_estimado'),
      cobrancaCentavos: valor is int ? valor : null,
      meio: texto('meio'),
      valorCentavos: devolver is int && devolver > 0 ? devolver : null,
      solicitadoEm: data('estorno_solicitado_em'),
      enviadoEm: data('estorno_enviado_em'),
    );
  }

  /// Linhas do estorno que o servidor informou (cada campo é opcional).
  List<String> get linhas => [
        if (valorCentavos case final v?) 'Valor mandado devolver: ${formatarReais(v)}',
        if (textoCobranca case final t?) t,
        if (solicitadoEm case final d?) 'Estorno registrado em ${formatarData(d)}',
        if (enviadoEm case final d?)
          'Enviado ao provedor de pagamento em ${formatarData(d)} '
              '(não é a data em que o dinheiro cai)',
        if (prazoEstimado case final p?) p,
      ];

  /// "Cobrança original: R$ 150,00 no Pix". Nulo sem o valor.
  String? get textoCobranca {
    final valor = cobrancaCentavos;
    if (valor == null) return null;
    final por = switch (meio) {
      'pix' => ' no Pix',
      'cartao' => ' no cartão',
      _ => '',
    };
    return 'Cobrança original: ${formatarReais(valor)}$por';
  }
}

/// Some quando não há estorno. Falha na consulta aparece aqui, com "Tentar de novo".
class SecaoEstorno extends StatefulWidget {
  const SecaoEstorno({
    super.key,
    required this.carregar,
    this.atualizarQuando,
    this.mostrarCarregando = false,
  });

  final Future<List<EstornoDoPedido>> Function() carregar;
  final Listenable? atualizarQuando;

  /// No pedido cancelado, avisa que está consultando.
  final bool mostrarCarregando;

  @override
  State<SecaoEstorno> createState() => _SecaoEstornoState();
}

class _SecaoEstornoState extends State<SecaoEstorno> {
  List<EstornoDoPedido>? _itens;
  String? _erro;
  var _consulta = 0;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final consulta = ++_consulta;
    if (_erro != null) setState(() => _erro = null);
    try {
      final itens = await widget.carregar();
      if (mounted && consulta == _consulta) setState(() => _itens = itens);
    } on Object catch (e) {
      // Com estorno já na tela, uma falha de atualização não o apaga.
      if (mounted && consulta == _consulta && (_itens ?? const []).isEmpty) {
        setState(() => _erro = mensagemErroTrato(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final apoio = TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario);
    final erro = _erro;
    if (erro != null) {
      return Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível ver o estorno deste pedido. $erro',
              key: const ValueKey('erro-estorno-pedido'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
            ),
            BotaoLink(
              key: const ValueKey('tentar-estorno-pedido'),
              texto: 'Tentar de novo',
              aoTocar: _carregar,
            ),
          ],
        ),
      );
    }
    final itens = _itens;
    if (itens == null) {
      return widget.mostrarCarregando
          ? Padding(
              padding: const EdgeInsets.only(top: EspacosTrato.x4),
              child: Text('Verificando se há estorno…', style: apoio),
            )
          : const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in itens) ...[
          const SizedBox(height: EspacosTrato.x4),
          CartaoTrato(
            key: const ValueKey('cartao-estorno-pedido'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotuloEstornoStatus(e.status)!, style: TipografiaTrato.corpoForte),
                for (final linha in e.linhas) ...[
                  const SizedBox(height: EspacosTrato.x1),
                  Text(linha, style: apoio),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
