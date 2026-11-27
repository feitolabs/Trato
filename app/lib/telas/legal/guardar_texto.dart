/// Termos 1.5 e 24.3: o usuário guarda o texto legal pela folha de compartilhamento do aparelho
/// (salvar em arquivos, enviar, imprimir). Usa só o que o app já tem e não pede permissão.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/convite.dart' show compartilharArquivoNoAparelho;

/// Entrega o arquivo [nome] com [conteudo] para a pessoa guardar. Os testes trocam por um fake.
typedef GuardarTextoLegal = Future<void> Function(String nome, String conteudo);

Future<void> guardarTextoNoAparelho(String nome, String conteudo) async {
  final pasta = await getTemporaryDirectory();
  final arquivo = File('${pasta.path}/$nome');
  await arquivo.writeAsString(conteudo, flush: true);
  await compartilharArquivoNoAparelho(arquivo.path);
}

/// Botão "Guardar uma cópia". Se o aparelho não abrir o compartilhamento, oferece copiar o texto.
class BotaoGuardarTexto extends StatefulWidget {
  const BotaoGuardarTexto({
    super.key,
    required this.nomeArquivo,
    required this.conteudo,
    this.guardar = guardarTextoNoAparelho,
  });

  final String nomeArquivo;
  final String conteudo;
  final GuardarTextoLegal guardar;

  @override
  State<BotaoGuardarTexto> createState() => _BotaoGuardarTextoState();
}

class _BotaoGuardarTextoState extends State<BotaoGuardarTexto> {
  var _ocupado = false;
  var _falhou = false;
  var _copiado = false;

  Future<void> _guardar() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _falhou = false;
      _copiado = false;
    });
    try {
      await widget.guardar(widget.nomeArquivo, widget.conteudo);
    } on Object {
      if (mounted) setState(() => _falhou = true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: widget.conteudo));
    if (mounted) setState(() => _copiado = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BotaoSecundario(
          key: const Key('guardar-texto-legal'),
          texto: _ocupado ? 'Preparando…' : 'Guardar uma cópia',
          icone: Icons.ios_share,
          aoTocar: _guardar,
        ),
        if (_falhou) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(
            'Não foi possível abrir o compartilhamento. Tente de novo ou copie o texto.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
          ),
          Center(
            child: BotaoLink(
              key: const Key('copiar-texto-legal'),
              texto: _copiado ? 'Texto copiado' : 'Copiar texto',
              aoTocar: _copiar,
            ),
          ),
        ],
      ],
    );
  }
}
