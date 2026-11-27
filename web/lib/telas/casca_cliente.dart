import 'package:flutter/material.dart';

import '../auth/sessao_auth.dart';
import '../componentes/barra_abas.dart';
import '../componentes/barra_topo.dart';
import '../dados/pedidos.dart';
import '../dados/perfil.dart';
import '../tema/tema.dart';
import 'abas/aba_em_breve.dart';
import 'abas/aba_inicio.dart';
import 'abas/aba_pedidos.dart';
import 'abas/aba_perfil.dart';

/// Casca do cliente: navegação no topo (Início · Buscar · Pedidos · Mensagens) + avatar,
/// no estilo do site (`Trato Feito — versão web.pdf`, págs. 5–6).
class CascaCliente extends StatefulWidget {
  const CascaCliente({
    super.key,
    required this.perfil,
    required this.repositorioPedidos,
    required this.servicoAuth,
  });

  final PerfilTrato perfil;
  final RepositorioPedidos repositorioPedidos;
  final ServicoAuthWeb servicoAuth;

  @override
  State<CascaCliente> createState() => _CascaClienteState();
}

class _CascaClienteState extends State<CascaCliente> {
  var _aba = 0;

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      AbaInicio(perfil: widget.perfil),
      const AbaEmBreve(
        titulo: 'Buscar',
        explicacao:
            'A busca de profissionais ainda não tem rota própria no backend (também é assim '
            'no app mobile hoje).',
      ),
      AbaPedidos(repositorio: widget.repositorioPedidos),
      const AbaEmBreve(
        titulo: 'Mensagens',
        explicacao: 'As conversas de um pedido ainda não têm rota própria no backend.',
      ),
      AbaPerfil(perfil: widget.perfil, servicoAuth: widget.servicoAuth),
    ];
    return Scaffold(
      backgroundColor: CoresTrato.creme,
      appBar: BarraTopoTrato(
        abas: abasCliente,
        indiceAtual: _aba,
        aoSelecionar: (i) => setState(() => _aba = i),
        indicePerfil: indicePerfilCliente,
        perfil: widget.perfil,
      ),
      body: IndexedStack(index: _aba, children: paginas),
    );
  }
}
