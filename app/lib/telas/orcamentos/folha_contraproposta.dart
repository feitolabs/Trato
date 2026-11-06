import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../pedidos/pedido_aberto_tela.dart' show centavosDoTexto;

/// Pergunta ao cliente quanto ele propõe pagar pelo orçamento. Devolve (valor em centavos,
/// mensagem opcional) ou nulo se cancelar. A regra "menor que o orçamento" é conferida aqui só
/// para avisar cedo; quem decide é o backend.
Future<(int, String?)?> pedirContraproposta(BuildContext context, int atualCentavos) {
  return showModalBottomSheet<(int, String?)>(
    context: context,
    isScrollControlled: true,
    builder: (folha) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(folha).viewInsets.bottom),
      child: _FolhaContraproposta(atualCentavos: atualCentavos),
    ),
  );
}

class _FolhaContraproposta extends StatefulWidget {
  const _FolhaContraproposta({required this.atualCentavos});

  final int atualCentavos;

  @override
  State<_FolhaContraproposta> createState() => _FolhaContrapropostaState();
}

class _FolhaContrapropostaState extends State<_FolhaContraproposta> {
  final _valor = TextEditingController();
  final _mensagem = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    _mensagem.dispose();
    super.dispose();
  }

  void _enviar() {
    final centavos = centavosDoTexto(_valor.text);
    if (centavos == null || centavos <= 0) {
      setState(() => _erro = 'Digite o valor que você propõe.');
      return;
    }
    if (centavos >= widget.atualCentavos) {
      setState(() => _erro = 'Proponha menos que ${formatarReais(widget.atualCentavos)}.');
      return;
    }
    Navigator.of(context).pop((centavos, _mensagem.text));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EspacosTrato.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fazer contraproposta', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'O orçamento atual é ${formatarReais(widget.atualCentavos)}. O profissional '
              'recebe sua proposta na conversa e pode aceitar.',
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x4),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quanto você propõe pagar',
                prefixText: 'R\$ ',
                errorText: _erro,
              ),
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
            ),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              controller: _mensagem,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Mensagem (opcional)'),
            ),
            const SizedBox(height: EspacosTrato.x3),
            BotaoPrimario(texto: 'Enviar contraproposta', aoTocar: _enviar),
          ],
        ),
      ),
    );
  }
}
