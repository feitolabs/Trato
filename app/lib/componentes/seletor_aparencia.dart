import 'package:flutter/material.dart';

import '../tema/tema.dart';
import 'cartao.dart';

/// Seletor limpo de aparência (Claro / Escuro / Sistema) conectado ao [ControladorTema].
class SeletorAparencia extends StatelessWidget {
  const SeletorAparencia({super.key, this.controlador});

  final ControladorTema? controlador;

  @override
  Widget build(BuildContext context) {
    final ctrl = controlador ?? ControladorTema.instancia;
    final c = context.cores;

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('APARÊNCIA',
                style: TipografiaTrato.sobretitulo.copyWith(color: c.textoSecundario)),
            const SizedBox(height: EspacosTrato.x3),
            CartaoTrato(
              child: Row(
                children: [
                  _OpcaoTema(
                    key: const ValueKey('tema-claro'),
                    rotulo: 'Claro',
                    icone: Icons.light_mode_outlined,
                    selecionado: ctrl.modo == ThemeMode.light,
                    aoTocar: () => ctrl.definir(ThemeMode.light),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  _OpcaoTema(
                    key: const ValueKey('tema-escuro'),
                    rotulo: 'Escuro',
                    icone: Icons.dark_mode_outlined,
                    selecionado: ctrl.modo == ThemeMode.dark,
                    aoTocar: () => ctrl.definir(ThemeMode.dark),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  _OpcaoTema(
                    key: const ValueKey('tema-sistema'),
                    rotulo: 'Sistema',
                    icone: Icons.brightness_auto_outlined,
                    selecionado: ctrl.modo == ThemeMode.system,
                    aoTocar: () => ctrl.definir(ThemeMode.system),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OpcaoTema extends StatelessWidget {
  const _OpcaoTema({
    super.key,
    required this.rotulo,
    required this.icone,
    required this.selecionado,
    required this.aoTocar,
  });

  final String rotulo;
  final IconData icone;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Expanded(
      child: Semantics(
        selected: selecionado,
        button: true,
        label: 'Tema $rotulo',
        child: Material(
          color: selecionado ? c.azulSuave : Colors.transparent,
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: aoTocar,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EspacosTrato.x2,
                vertical: EspacosTrato.x2 + 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icone,
                    size: 20,
                    color: selecionado ? c.texto : c.textoSecundario,
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      rotulo,
                      maxLines: 1,
                      style: TipografiaTrato.corpoPequeno.copyWith(
                        color: selecionado ? c.texto : c.textoSecundario,
                        fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
