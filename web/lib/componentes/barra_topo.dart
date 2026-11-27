import 'package:flutter/material.dart';

import '../dados/perfil.dart';
import '../tema/tema.dart';
import 'barra_abas.dart';

/// Barra de navegação do topo (cliente), no estilo do site (`Trato | Início Pedidos Mensagens |
/// avatar`) — ver `Trato Feito — versão web.pdf`, págs. 5 e 6.
class BarraTopoTrato extends StatelessWidget implements PreferredSizeWidget {
  const BarraTopoTrato({
    super.key,
    required this.abas,
    required this.indiceAtual,
    required this.aoSelecionar,
    required this.indicePerfil,
    required this.perfil,
  });

  final List<AbaTrato> abas;
  final int indiceAtual;
  final ValueChanged<int> aoSelecionar;
  final int indicePerfil;
  final PerfilTrato perfil;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CoresTrato.petroleo,
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x6),
      height: preferredSize.height,
      child: Row(
        children: [
          Text(
            'Trato',
            style: TipografiaTrato.marcaPequena.copyWith(color: CoresTrato.creme, fontSize: 22),
          ),
          const SizedBox(width: EspacosTrato.x8),
          for (var i = 0; i < abas.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: EspacosTrato.x5),
              child: _LinkTopo(
                texto: abas[i].rotulo,
                selecionado: i == indiceAtual,
                aoTocar: () => aoSelecionar(i),
              ),
            ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
            onTap: () => aoSelecionar(indicePerfil),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: CoresTrato.azulClaro,
                  child: Text(
                    (perfil.nome?.isNotEmpty ?? false) ? perfil.nome!.substring(0, 1) : '?',
                    style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo),
                  ),
                ),
                const SizedBox(width: EspacosTrato.x2),
                Text(
                  perfil.nome?.split(' ').first ?? 'Perfil',
                  style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.creme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTopo extends StatelessWidget {
  const _LinkTopo({required this.texto, required this.selecionado, required this.aoTocar});

  final String texto;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
        child: Text(
          texto,
          style: TipografiaTrato.corpoForte.copyWith(
            color: selecionado ? CoresTrato.creme : CoresTrato.azulClaro,
            decoration: selecionado ? TextDecoration.underline : TextDecoration.none,
            decorationColor: CoresTrato.creme,
          ),
        ),
      ),
    );
  }
}
