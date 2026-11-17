import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/foco_rolagem.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../pedidos/pedido_aberto_tela.dart' show centavosDoTexto;

/// Resultado da folha de negociação de valor e/ou prazo em dias.
class PropostaNegociacao {
  const PropostaNegociacao({
    required this.valorCentavos,
    this.prazoExecucaoDias,
    this.mensagem,
  });

  final int valorCentavos;
  final int? prazoExecucaoDias;
  final String? mensagem;
}

/// Pergunta ao cliente quanto ele propõe pagar pelo orçamento. Devolve (valor em centavos,
/// mensagem opcional) ou nulo se cancelar. A regra de validação final é conferida no backend.
Future<(int, String?)?> pedirContraproposta(BuildContext context, int atualCentavos) async {
  final res = await showModalBottomSheet<PropostaNegociacao>(
    context: context,
    isScrollControlled: true,
    builder: (folha) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(folha).viewInsets.bottom),
      child: _FolhaNegociacao(
        atualCentavos: atualCentavos,
        mostrarPrazo: false,
        modoProfissional: false,
      ),
    ),
  );
  if (res == null) return null;
  return (res.valorCentavos, res.mensagem);
}

/// Versão completa da contraproposta do cliente: permite ajustar valor e/ou prazo em dias.
Future<PropostaNegociacao?> pedirContrapropostaCompleta(
  BuildContext context, {
  required int atualCentavos,
  int? prazoAtualDias,
}) {
  return showModalBottomSheet<PropostaNegociacao>(
    context: context,
    isScrollControlled: true,
    builder: (folha) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(folha).viewInsets.bottom),
      child: _FolhaNegociacao(
        atualCentavos: atualCentavos,
        prazoAtualDias: prazoAtualDias,
        mostrarPrazo: true,
        modoProfissional: false,
      ),
    ),
  );
}

/// Folha usada pelo profissional dentro do chat para enviar nova proposta de valor e prazo.
Future<PropostaNegociacao?> pedirNovaPropostaProfissional(
  BuildContext context, {
  int? valorAtualCentavos,
  int? prazoAtualDias,
}) {
  return showModalBottomSheet<PropostaNegociacao>(
    context: context,
    isScrollControlled: true,
    builder: (folha) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(folha).viewInsets.bottom),
      child: _FolhaNegociacao(
        atualCentavos: valorAtualCentavos,
        prazoAtualDias: prazoAtualDias ?? 3,
        mostrarPrazo: true,
        modoProfissional: true,
      ),
    ),
  );
}

String _formatarEntradaReais(int centavos) {
  final inteiro = centavos ~/ 100;
  final resto = (centavos % 100).toString().padLeft(2, '0');
  return '$inteiro,$resto';
}

class _FolhaNegociacao extends StatefulWidget {
  const _FolhaNegociacao({
    required this.atualCentavos,
    required this.mostrarPrazo,
    required this.modoProfissional,
    this.prazoAtualDias,
  });

  final int? atualCentavos;
  final int? prazoAtualDias;
  final bool mostrarPrazo;
  final bool modoProfissional;

  @override
  State<_FolhaNegociacao> createState() => _FolhaNegociacaoState();
}

class _FolhaNegociacaoState extends State<_FolhaNegociacao> {
  final _scroll = ScrollController();
  late final TextEditingController _valor = TextEditingController(
    text: (widget.mostrarPrazo && widget.atualCentavos != null)
        ? _formatarEntradaReais(widget.atualCentavos!)
        : '',
  );
  late final TextEditingController _dias = TextEditingController(
    text: widget.prazoAtualDias == null ? '' : '${widget.prazoAtualDias}',
  );
  final _mensagem = TextEditingController();

  final _keyValor = GlobalKey();
  final _keyDias = GlobalKey();
  final _focoValor = FocusNode();
  final _focoDias = FocusNode();

  String? _erroValor;
  String? _erroDias;

  @override
  void dispose() {
    _scroll.dispose();
    _valor.dispose();
    _dias.dispose();
    _mensagem.dispose();
    _focoValor.dispose();
    _focoDias.dispose();
    super.dispose();
  }

  void _enviar() {
    String? errValor;
    String? errDias;
    final centavos = centavosDoTexto(_valor.text);
    final diasTexto = _dias.text.trim();
    final dias = diasTexto.isEmpty ? null : int.tryParse(diasTexto);

    if (centavos == null || centavos <= 0) {
      errValor = 'Digite um valor maior que zero.';
    }
    if (widget.mostrarPrazo) {
      if (widget.modoProfissional) {
        if (dias == null || dias < 1 || dias > 365) {
          errDias = 'Informe um prazo entre 1 e 365 dias.';
        }
      } else if (diasTexto.isNotEmpty && (dias == null || dias < 1 || dias > 365)) {
        errDias = 'Informe um prazo entre 1 e 365 dias.';
      }
    }

    if (!widget.modoProfissional && errValor == null && widget.atualCentavos != null) {
      final prazoMudou = dias != null && dias != widget.prazoAtualDias;
      if (prazoMudou) {
        if (centavos! > widget.atualCentavos!) {
          errValor = 'Proponha no máximo ${formatarReais(widget.atualCentavos!)}.';
        }
      } else if (centavos! >= widget.atualCentavos!) {
        errValor = 'Proponha menos que ${formatarReais(widget.atualCentavos!)}'
            '${widget.mostrarPrazo ? ' ou altere o prazo em dias.' : '.'}';
      }
    }

    setState(() {
      _erroValor = errValor;
      _erroDias = errDias;
    });

    if (errValor != null || errDias != null) {
      focarPrimeiroErro([
        EntradaCampoErro(key: _keyValor, focusNode: _focoValor, temErro: () => _erroValor != null),
        EntradaCampoErro(key: _keyDias, focusNode: _focoDias, temErro: () => _erroDias != null),
      ]);
      return;
    }

    Navigator.of(context).pop(
      PropostaNegociacao(
        valorCentavos: centavos!,
        prazoExecucaoDias: dias,
        mensagem: _mensagem.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.modoProfissional ? 'Enviar nova proposta' : 'Fazer contraproposta';
    final subtitulo = widget.modoProfissional
        ? 'Defina o novo valor e o prazo em dias. O cliente pode aceitar e pagar direto na conversa.'
        : (widget.atualCentavos == null
            ? 'Sugira um valor e prazo para negociar com o profissional.'
            : 'O orçamento atual é ${formatarReais(widget.atualCentavos!)}. O profissional '
                'recebe sua proposta na conversa e pode aceitar.');

    return SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(EspacosTrato.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              subtitulo,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x4),
            KeyedSubtree(
              key: _keyValor,
              child: TextField(
                controller: _valor,
                focusNode: _focoValor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.modoProfissional ? 'Novo valor do orçamento' : 'Quanto você propõe pagar',
                  prefixText: 'R\$ ',
                  errorText: _erroValor,
                ),
                onChanged: (_) {
                  if (_erroValor != null) setState(() => _erroValor = null);
                },
              ),
            ),
            if (widget.mostrarPrazo) ...[
              const SizedBox(height: EspacosTrato.x3),
              KeyedSubtree(
                key: _keyDias,
                child: TextField(
                  controller: _dias,
                  focusNode: _focoDias,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Prazo de execução (dias)',
                    hintText: 'Ex.: 3',
                    suffixText: 'dias',
                    errorText: _erroDias,
                  ),
                  onChanged: (_) {
                    if (_erroDias != null) setState(() => _erroDias = null);
                  },
                ),
              ),
            ],
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              controller: _mensagem,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Mensagem (opcional)'),
            ),
            const SizedBox(height: EspacosTrato.x3),
            BotaoPrimario(
              texto: widget.modoProfissional ? 'Enviar proposta' : 'Enviar contraproposta',
              aoTocar: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
