import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../fluxo/navegacao_casca.dart';
import '../fluxo/rotas.dart';

/// Casca do app do cliente: barra inferior com as 5 abas (Início · Buscar · Pedidos ·
/// Mensagens · Perfil). Cada aba guarda seu estado e recarrega ao alternar.
class CascaClienteTela extends StatefulWidget {
  const CascaClienteTela({super.key, this.abaInicial = 0});

  final int abaInicial;

  @override
  State<CascaClienteTela> createState() => _CascaClienteTelaState();
}

class _CascaClienteTelaState extends State<CascaClienteTela> {
  late int _aba = widget.abaInicial;
  late final Set<int> _visitadas = {widget.abaInicial};
  DateTime? _ultimaAtualizacaoAba;

  @override
  void initState() {
    super.initState();
    ControladorCasca.registrar(
      irParaAba: _ir,
      recarregarCasca: () => RotasTrato.pedidosMudaram.value++,
    );
  }

  @override
  void dispose() {
    ControladorCasca.desregistrar(_ir);
    super.dispose();
  }

  void _ir(int indice) {
    if (_aba == indice) return;
    final jaVisitada = _visitadas.contains(indice);
    setState(() {
      _aba = indice;
      _visitadas.add(indice);
    });
    if (jaVisitada) {
      final agora = DateTime.now();
      if (_ultimaAtualizacaoAba == null ||
          agora.difference(_ultimaAtualizacaoAba!) >= const Duration(milliseconds: 1500)) {
        _ultimaAtualizacaoAba = agora;
        RotasTrato.pedidosMudaram.value++;
      }
    }
  }

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
    return PopScope(
      canPop: _aba == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _aba != 0) _ir(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _aba, children: paginas),
        bottomNavigationBar: BarraAbasTrato(
          abas: abasCliente,
          indiceAtual: _aba,
          aoSelecionar: _ir,
        ),
      ),
    );
  }
}
