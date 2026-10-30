import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Botão principal (fundo petróleo, largura total). Ex.: "Próximo", "Enviar orçamento".
class BotaoPrimario extends StatelessWidget {
  const BotaoPrimario({
    super.key,
    required this.texto,
    required this.aoTocar,
    this.icone,
    this.carregando = false,
  });

  final String texto;
  final VoidCallback? aoTocar;
  final IconData? icone;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: carregando ? null : aoTocar,
      child: _ConteudoBotao(texto: texto, icone: icone, carregando: carregando),
    );
  }
}

/// Botão secundário (fundo superfície com borda). Ex.: "Recusar", "Conversar".
class BotaoSecundario extends StatelessWidget {
  const BotaoSecundario({
    super.key,
    required this.texto,
    required this.aoTocar,
    this.icone,
    this.selecionado = false,
  });

  final String texto;
  final VoidCallback? aoTocar;
  final IconData? icone;

  /// Opção marcada num par de escolhas (ex.: "Eu forneço" / "Cliente fornece").
  final bool selecionado;

  @override
  Widget build(BuildContext context) {
    final estilo = selecionado
        ? OutlinedButton.styleFrom(
            backgroundColor: CoresTrato.azulSuave,
            side: const BorderSide(color: CoresTrato.petroleo, width: 1.5),
          )
        : null;
    return OutlinedButton(
      onPressed: aoTocar,
      style: estilo,
      child: _ConteudoBotao(texto: texto, icone: icone),
    );
  }
}

/// Link sublinhado. Ex.: "Pular", "Já tenho conta", "Adicionar item".
class BotaoLink extends StatelessWidget {
  const BotaoLink({super.key, required this.texto, required this.aoTocar});

  final String texto;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: aoTocar, child: Text(texto));
  }
}

class _ConteudoBotao extends StatelessWidget {
  const _ConteudoBotao({required this.texto, this.icone, this.carregando = false});

  final String texto;
  final IconData? icone;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const SizedBox.square(
        dimension: EspacosTrato.x5,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    // Botão tem altura fixa: em tela estreita com fonte grande o texto encolhe em vez de quebrar.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: icone == null
          ? Text(texto, maxLines: 1)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: EspacosTrato.x5),
                const SizedBox(width: EspacosTrato.x2),
                Text(texto, maxLines: 1),
              ],
            ),
    );
  }
}
