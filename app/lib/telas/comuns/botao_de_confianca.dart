import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Depois da avaliação: favorita o profissional ("Salvar como de confiança").
/// Já favorito: mostra "Já é de confiança". Erro de rede nunca trava o fluxo.
class BotaoDeConfianca extends StatefulWidget {
  const BotaoDeConfianca({
    super.key,
    required this.jaEFavorito,
    required this.favoritar,
    this.clara = false,
  });

  /// Para fundo escuro (tela dos Tratinhos ganhos).
  final bool clara;

  /// Consulta se o profissional já está nos favoritos. Falha = trata como não favorito.
  final Future<bool> Function() jaEFavorito;

  /// Favorita (PUT). Repetir é seguro.
  final Future<void> Function() favoritar;

  @override
  State<BotaoDeConfianca> createState() => _BotaoDeConfiancaState();
}

class _BotaoDeConfiancaState extends State<BotaoDeConfianca> {
  var _favorito = false;
  var _salvando = false;

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  Future<void> _consultar() async {
    try {
      final ja = await widget.jaEFavorito();
      if (mounted && ja) setState(() => _favorito = true);
    } on Object {
      // sem resposta: segue com o botão normal
    }
  }

  Future<void> _salvar() async {
    if (_salvando || _favorito) return;
    setState(() => _salvando = true);
    final mensagens = ScaffoldMessenger.of(context);
    try {
      await widget.favoritar();
      if (mounted) setState(() => _favorito = true);
    } on Object {
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
              content:
                  Text('Não deu para salvar agora. Tente de novo mais tarde.')),
        );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_favorito) {
      final cor = widget.clara ? CoresTrato.creme : null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 18, color: cor),
            const SizedBox(width: 6),
            Text('Profissional de confiança',
                key: const Key('ja-de-confianca'),
                style: TextStyle(color: cor)),
          ],
        ),
      );
    }
    if (widget.clara) {
      return TextButton(
        key: const Key('salvar-de-confianca'),
        style: TextButton.styleFrom(foregroundColor: CoresTrato.creme),
        onPressed: _salvar,
        child: const Text('Salvar como profissional de confiança'),
      );
    }
    return BotaoLink(
      key: const Key('salvar-de-confianca'),
      texto: 'Salvar como profissional de confiança',
      aoTocar: _salvar,
    );
  }
}
