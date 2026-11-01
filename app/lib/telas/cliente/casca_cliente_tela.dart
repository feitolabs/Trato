import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../fluxo/rotas.dart';

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
  late final Set<int> _visitadas = {widget.abaInicial};

  void _ir(int indice) => setState(() {
        _aba = indice;
        _visitadas.add(indice);
      });

  @override
  Widget build(BuildContext context) {
    final construtores = <Widget Function()>[
      () => RotasTrato.abaInicio(aoBuscar: () => _ir(1)),
      RotasTrato.abaBuscar,
      RotasTrato.abaPedidos,
      RotasTrato.abaMensagens,
      RotasTrato.abaPerfil,
    ];
    final paginas = <Widget>[
      for (var i = 0; i < construtores.length; i++)
        _visitadas.contains(i) ? construtores[i]() : const SizedBox.shrink(),
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
