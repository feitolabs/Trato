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
/// Feita à mão (e não com NavigationBar) para o rótulo nunca quebrar em duas linhas.
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
    // Cinco abas dividem a largura: a barra ignora escala de fonte acima de 1,0
    // (como as barras nativas de iOS e Android) e o rótulo encolhe se ainda faltar espaço.
    final midia = MediaQuery.of(context);
    return MediaQuery(
      data: midia.copyWith(textScaler: midia.textScaler.clamp(maxScaleFactor: 1)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: CoresTrato.superficie,
          border: Border(top: BorderSide(color: CoresTrato.borda)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
            child: Row(
              children: [
                for (var i = 0; i < abas.length; i++)
                  Expanded(
                    child: _ItemAba(
                      aba: abas[i],
                      selecionada: i == indiceAtual,
                      aoTocar: () => aoSelecionar(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemAba extends StatelessWidget {
  const _ItemAba({required this.aba, required this.selecionada, required this.aoTocar});

  final AbaTrato aba;
  final bool selecionada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final estilo = selecionada
        ? TipografiaTrato.corpoPequeno.copyWith(
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation('wght', 700)],
          )
        : TipografiaTrato.corpoPequeno;
    return Semantics(
      selected: selecionada,
      button: true,
      child: InkResponse(
        onTap: aoTocar,
        radius: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: selecionada ? CoresTrato.azulSuave : CoresTrato.superficie,
                borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
              ),
              child: Icon(aba.icone, color: CoresTrato.petroleo),
            ),
            const SizedBox(height: EspacosTrato.x1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(aba.rotulo, style: estilo, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
