import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Botões do DS (4.1): primário (verde-petróleo), secundário (superfície com borda), destrutivo
/// (texto e borda em perigo), link de ação (texto sublinhado) e ícone (com rótulo acessível).
///
/// O rótulo é o verbo da ação ("Aprovar", "Travar saques"), nunca "OK". Estados: padrão, hover,
/// foco (anel de 2 px), pressionado, desabilitado e carregando (spinner + [rotuloCarregando]).
enum _Variante { primario, secundario, destrutivo, link }

class BotaoTrato extends StatelessWidget {
  const BotaoTrato.primario(
    this.rotulo, {
    super.key,
    this.aoPressionar,
    this.icone,
    this.carregando = false,
    this.rotuloCarregando,
    this.largura,
  }) : _variante = _Variante.primario;

  const BotaoTrato.secundario(
    this.rotulo, {
    super.key,
    this.aoPressionar,
    this.icone,
    this.carregando = false,
    this.rotuloCarregando,
    this.largura,
  }) : _variante = _Variante.secundario;

  const BotaoTrato.destrutivo(
    this.rotulo, {
    super.key,
    this.aoPressionar,
    this.icone,
    this.carregando = false,
    this.rotuloCarregando,
    this.largura,
  }) : _variante = _Variante.destrutivo;

  const BotaoTrato.link(
    this.rotulo, {
    super.key,
    this.aoPressionar,
    this.icone,
    this.largura,
  })  : _variante = _Variante.link,
        carregando = false,
        rotuloCarregando = null;

  final String rotulo;
  final VoidCallback? aoPressionar;
  final IconData? icone;
  final bool carregando;
  final String? rotuloCarregando;
  final double? largura;
  final _Variante _variante;

  @override
  Widget build(BuildContext context) {
    final desabilitado = aoPressionar == null || carregando;
    final texto = carregando ? (rotuloCarregando ?? rotulo) : rotulo;
    final cor = switch (_variante) {
      _Variante.primario => CoresTrato.textoSobrePrimaria,
      _Variante.destrutivo => CoresTrato.perigoTexto,
      _Variante.secundario => CoresTrato.primaria,
      _Variante.link => CoresTrato.textoLink,
    };
    final corAtual = desabilitado && !carregando ? CoresTrato.textoMudo : cor;

    final filho = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (carregando) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: corAtual),
          ),
          const SizedBox(width: EspacosTrato.x2),
        ] else if (icone != null) ...[
          Icon(icone, size: 16),
          const SizedBox(width: EspacosTrato.x2),
        ],
        Flexible(child: Text(texto, overflow: TextOverflow.ellipsis)),
      ],
    );

    final acao = desabilitado ? null : aoPressionar;
    final Widget botao = switch (_variante) {
      _Variante.primario => FilledButton(onPressed: acao, child: filho),
      _Variante.secundario => OutlinedButton(onPressed: acao, child: filho),
      _Variante.destrutivo => OutlinedButton(
          onPressed: acao,
          style: OutlinedButton.styleFrom(
            foregroundColor: CoresTrato.perigoTexto,
            disabledForegroundColor: CoresTrato.textoMudo,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (e) => e.contains(WidgetState.focused)
                  ? const BorderSide(color: CoresTrato.foco, width: EspacosTrato.aneldeFoco)
                  : BorderSide(
                      color: e.contains(WidgetState.disabled) ? CoresTrato.bordaSuave : CoresTrato.perigoTexto,
                    ),
            ),
          ),
          child: filho,
        ),
      _Variante.link => TextButton(onPressed: acao, child: filho),
    };
    return largura == null ? botao : SizedBox(width: largura, child: botao);
  }
}

/// Botão só de ícone: o [rotulo] é obrigatório (vira dica e leitura de tela).
class BotaoIcone extends StatelessWidget {
  const BotaoIcone({
    super.key,
    required this.icone,
    required this.rotulo,
    required this.aoPressionar,
    this.destrutivo = false,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback? aoPressionar;
  final bool destrutivo;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icone, size: 20),
      tooltip: rotulo,
      onPressed: aoPressionar,
      color: destrutivo ? CoresTrato.perigoTexto : CoresTrato.primaria,
    );
  }
}
