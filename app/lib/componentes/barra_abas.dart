import 'package:flutter/material.dart';

import '../tema/tema.dart';

class AbaTrato {
  const AbaTrato({required this.rotulo, required this.icone});

  final String rotulo;
  final IconData icone;
}

/// Abas do cliente: Início · Buscar · Pedidos · Mensagens · Perfil.
const abasCliente = [
  AbaTrato(rotulo: 'Início', icone: Icons.home_outlined),
  AbaTrato(rotulo: 'Buscar', icone: Icons.search),
  AbaTrato(rotulo: 'Pedidos', icone: Icons.format_list_bulleted),
  AbaTrato(rotulo: 'Mensagens', icone: Icons.chat_bubble_outline),
  AbaTrato(rotulo: 'Perfil', icone: Icons.person_outline),
];

/// Abas do profissional: Início · Pedidos · Agenda · Carteira · Perfil.
const abasProfissional = [
  AbaTrato(rotulo: 'Início', icone: Icons.home_outlined),
  AbaTrato(rotulo: 'Pedidos', icone: Icons.format_list_bulleted),
  AbaTrato(rotulo: 'Agenda', icone: Icons.calendar_today_outlined),
  AbaTrato(rotulo: 'Carteira', icone: Icons.account_balance_wallet_outlined),
  AbaTrato(rotulo: 'Perfil', icone: Icons.person_outline),
];

/// Barra inferior: aba ativa com pílula azul-suave atrás do ícone e rótulo em negrito.
class BarraAbasTrato extends StatelessWidget {
  const BarraAbasTrato({
    super.key,
    required this.abas,
    required this.indiceAtual,
    required this.aoSelecionar,
  });

  final List<AbaTrato> abas;
  final int indiceAtual;
  final ValueChanged<int> aoSelecionar;

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: CoresTrato.superficie,
        indicatorColor: CoresTrato.azulSuave,
        surfaceTintColor: Colors.transparent,
        iconTheme: const WidgetStatePropertyAll(IconThemeData(color: CoresTrato.petroleo)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected)
              ? TipografiaTrato.corpoPequeno.copyWith(
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                )
              : TipografiaTrato.corpoPequeno,
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CoresTrato.borda)),
        ),
        child: NavigationBar(
          selectedIndex: indiceAtual,
          onDestinationSelected: aoSelecionar,
          destinations: [
            for (final aba in abas)
              NavigationDestination(icon: Icon(aba.icone), label: aba.rotulo),
          ],
        ),
      ),
    );
  }
}
