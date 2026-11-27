import 'package:flutter/material.dart';

class AbaTrato {
  const AbaTrato({required this.rotulo, required this.icone, this.badge = 0});

  final String rotulo;
  final IconData icone;
  final int badge;

  AbaTrato comBadge(int valor) => AbaTrato(rotulo: rotulo, icone: icone, badge: valor);
}

/// Itens da barra de topo do cliente (web): Início · Buscar · Pedidos · Mensagens. O Perfil
/// fica à parte, atrás do avatar — igual ao cabeçalho do site
/// (`Trato Feito — versão web.pdf`, págs. 5–6).
const abasCliente = [
  AbaTrato(rotulo: 'Início', icone: Icons.home_outlined),
  AbaTrato(rotulo: 'Buscar', icone: Icons.search),
  AbaTrato(rotulo: 'Pedidos', icone: Icons.format_list_bulleted),
  AbaTrato(rotulo: 'Mensagens', icone: Icons.chat_bubble_outline),
];

/// Índice da aba Perfil do cliente — fora de [abasCliente], aberta pelo avatar da barra de topo.
const indicePerfilCliente = 4;

/// Itens da barra lateral do profissional (web): Pedidos · Orçamentos · Agenda · Carteira ·
/// Perfil público — igual ao painel do PDF de referência (págs. 9–12). "Pedidos" já traz a
/// saudação e os números que no app ficam na aba Início.
const abasProfissional = [
  AbaTrato(rotulo: 'Pedidos', icone: Icons.format_list_bulleted),
  AbaTrato(rotulo: 'Orçamentos', icone: Icons.request_quote_outlined),
  AbaTrato(rotulo: 'Agenda', icone: Icons.calendar_today_outlined),
  AbaTrato(rotulo: 'Carteira', icone: Icons.account_balance_wallet_outlined),
  AbaTrato(rotulo: 'Perfil público', icone: Icons.person_outline),
];
