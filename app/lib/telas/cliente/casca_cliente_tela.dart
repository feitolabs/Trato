import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../fluxo/rotas.dart';
import 'buscar_tela.dart';
import 'inicio_tela.dart';

/// Casca do app do cliente: barra inferior com as 5 abas (Início · Buscar · Pedidos ·
/// Mensagens · Perfil). Cada aba guarda seu estado.
class CascaClienteTela extends StatefulWidget {
  const CascaClienteTela({super.key, this.abaInicial = 0});

  final int abaInicial;

  @override
  State<CascaClienteTela> createState() => _CascaClienteTelaState();
}

class _CascaClienteTelaState extends State<CascaClienteTela> {
  late int _aba = widget.abaInicial;

  void _ir(int indice) => setState(() => _aba = indice);

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      InicioTela(aoBuscar: () => _ir(1)),
      const BuscarTela(),
      RotasTrato.abaPedidos(),
      RotasTrato.abaMensagens(),
      RotasTrato.abaPerfil(),
    ];
    return Scaffold(
      body: IndexedStack(index: _aba, children: paginas),
      bottomNavigationBar: BarraAbasTrato(
        abas: abasCliente,
        indiceAtual: _aba,
        aoSelecionar: _ir,
      ),
    );
  }
}
