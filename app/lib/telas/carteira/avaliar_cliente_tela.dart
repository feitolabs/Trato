import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../conclusao/campo_longo.dart';
import '../conclusao/estrelas_nota.dart';
import '../profissional_apoio/apoio.dart';

/// O profissional avalia o cliente depois do serviço concluído (uma vez por pedido). Só pede e
/// manda: quem aceita, recusa e guarda é o servidor.
class AvaliarClienteTela extends StatefulWidget {
  const AvaliarClienteTela({super.key, required this.pedidoNumero, required this.aoEnviar});

  final String pedidoNumero;

  /// Manda a avaliação. Lança erro com mensagem se o servidor recusar.
  final Future<void> Function(int nota, String comentario) aoEnviar;

  @override
  State<AvaliarClienteTela> createState() => _AvaliarClienteTelaState();
}

class _AvaliarClienteTelaState extends State<AvaliarClienteTela> {
  final _comentario = TextEditingController();
  var _nota = 0;
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.aoEnviar(_nota, _comentario.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaginaTrato(
      titulo: 'Avaliar o cliente',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erro != null) ...[
            AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          BotaoPrimario(
            texto: 'Enviar avaliação',
            carregando: _enviando,
            aoTocar: _nota == 0 ? null : _enviar,
          ),
        ],
      ),
      children: [
        Text('Como foi atender neste pedido?', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Pedido ${widget.pedidoNumero}. Sua nota ajuda outros profissionais.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        EstrelasNota(
          rotulo: 'Nota do cliente',
          nota: _nota,
          aoMudar: (n) => setState(() => _nota = n),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoLongo(
          rotulo: 'Comentário (opcional)',
          controlador: _comentario,
          dica: 'Ex.: local organizado, pagamento em dia',
          linhas: 3,
        ),
      ],
    );
  }
}
