import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/tema.dart';

/// Campo de texto com rótulo em cima e ajuda embaixo, como no cadastro do protótipo.
class CampoTrato extends StatelessWidget {
  const CampoTrato({
    super.key,
    required this.rotulo,
    this.controlador,
    this.dica,
    this.ajuda,
    this.erro,
    this.prefixo,
    this.sufixo,
    this.iconeInicio,
    this.teclado,
    this.formatadores,
    this.senha = false,
    this.aoMudar,
  });

  final String rotulo;
  final TextEditingController? controlador;
  final String? dica;

  /// Texto pequeno abaixo do campo. Ex.: "Pelo menos 8 caracteres, com letra e número."
  final String? ajuda;
  final String? erro;

  /// Texto fixo antes/depois do valor. Ex.: "R$ " e "h" na calculadora.
  final String? prefixo;
  final String? sufixo;
  final IconData? iconeInicio;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatadores;
  final bool senha;
  final ValueChanged<String>? aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rótulo em uma linha só: encolhe em colunas estreitas em vez de quebrar a palavra.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rotulo, style: TipografiaTrato.corpoForte, maxLines: 1),
        ),
        const SizedBox(height: EspacosTrato.x2),
        TextField(
          controller: controlador,
          obscureText: senha,
          keyboardType: teclado,
          inputFormatters: formatadores,
          onChanged: aoMudar,
          style: TipografiaTrato.corpo,
          decoration: InputDecoration(
            hintText: dica,
            errorText: erro,
            // prefixText/suffixText somem sem foco; no protótipo "R$" e "h" ficam sempre visíveis.
            prefixIcon: prefixo != null
                ? _TextoFixo(prefixo!, inicio: true)
                : (iconeInicio == null ? null : Icon(iconeInicio)),
            prefixIconConstraints: const BoxConstraints(),
            suffixIcon: sufixo == null ? null : _TextoFixo(sufixo!, inicio: false),
            suffixIconConstraints: const BoxConstraints(),
          ),
        ),
        if (ajuda != null && erro == null) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(ajuda!, style: TipografiaTrato.legenda),
        ],
      ],
    );
  }
}

class _TextoFixo extends StatelessWidget {
  const _TextoFixo(this.texto, {required this.inicio});

  final String texto;
  final bool inicio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: inicio ? EspacosTrato.x4 : 0,
        right: inicio ? EspacosTrato.x1 : EspacosTrato.x4,
      ),
      child: Text(texto, style: TipografiaTrato.corpo),
    );
  }
}
