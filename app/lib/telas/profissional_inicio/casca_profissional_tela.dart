import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../em_breve_tela.dart';
import 'detalhe_pedido_tela.dart';
import 'dados_exemplo.dart';
import 'inicio_profissional_tela.dart';
import 'modelos.dart';

/// Casca do app do profissional: barra inferior com as 5 abas (Início · Pedidos · Agenda ·
/// Carteira · Perfil). Só o Início tem tela aqui; as outras mostram [EmBreveTela]
/// (a Carteira vem de outra tarefa). Cada aba guarda seu estado.
///
/// Os callbacks de ações que dependem de outras telas (orçamento, check-in, recusa)
/// ficam em aberto para quem integra ligar.
class CascaProfissionalTela extends StatefulWidget {
  const CascaProfissionalTela({
    super.key,
    this.abaInicial = 0,
    this.inicio = inicioProfissionalExemplo,
    this.detalhe = detalhePedidoExemplo,
    this.aoFazerCheckIn,
    this.aoFazerOrcamento,
    this.aoPerguntar,
    this.aoRecusar,
  });

  final int abaInicial;
  final InicioProfissional inicio;

  /// Detalhe mostrado ao tocar num pedido aberto (provisório: o backend entrega o do pedido tocado).
  final DetalhePedido detalhe;
  final VoidCallback? aoFazerCheckIn;
  final VoidCallback? aoFazerOrcamento;
  final VoidCallback? aoPerguntar;
  final ValueChanged<MotivoRecusa>? aoRecusar;

  @override
  State<CascaProfissionalTela> createState() => _CascaProfissionalTelaState();
}

class _CascaProfissionalTelaState extends State<CascaProfissionalTela> {
  late int _aba = widget.abaInicial;

  void _ir(int indice) => setState(() => _aba = indice);

  void _abrirDetalhe(PedidoAberto pedido) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetalhePedidoTela(
          dados: widget.detalhe,
          aoFazerOrcamento: widget.aoFazerOrcamento,
          aoPerguntar: widget.aoPerguntar,
          aoRecusar: (motivo) {
            widget.aoRecusar?.call(motivo);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _filtros() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EmBreveTela(titulo: 'Filtros')),
      );

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      InicioProfissionalTela(
        dados: widget.inicio,
        aoFazerCheckIn: widget.aoFazerCheckIn,
        aoAbrirCarteira: () => _ir(3),
        aoAbrirFiltros: _filtros,
        aoAbrirPedido: _abrirDetalhe,
      ),
      for (final aba in abasProfissional.skip(1)) EmBreveTela(titulo: aba.rotulo),
    ];
    return Scaffold(
      body: IndexedStack(index: _aba, children: paginas),
      bottomNavigationBar: BarraAbasTrato(
        abas: abasProfissional,
        indiceAtual: _aba,
        aoSelecionar: _ir,
      ),
    );
  }
}
