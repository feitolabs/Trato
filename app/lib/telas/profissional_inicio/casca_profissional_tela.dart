import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
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
    this.abaCarteira,
    this.abaPerfil,
    this.carregarDetalhe,
    this.recusarPedido,
  });

  /// Carrega o detalhe do pedido tocado (API). Sem isso, mostra [detalhe].
  final Future<DetalhePedido> Function(PedidoAberto pedido)? carregarDetalhe;

  /// Recusa o pedido tocado. Sem isso, usa [aoRecusar].
  final Future<void> Function(PedidoAberto pedido, MotivoRecusa motivo)? recusarPedido;

  /// Conteúdo da aba Carteira (extrato). Sem isso, a aba mostra "Em breve".
  final Widget? abaCarteira;

  /// Aba Perfil (perfil público e avaliações). Sem ela, mostra [EmBreveTela].
  final Widget? abaPerfil;

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
    Widget tela(DetalhePedido dados) => DetalhePedidoTela(
          dados: dados,
          aoFazerOrcamento: widget.aoFazerOrcamento,
          aoPerguntar: widget.aoPerguntar,
          aoRecusar: (motivo) {
            widget.aoRecusar?.call(motivo);
            widget.recusarPedido?.call(pedido, motivo);
            Navigator.of(context).pop();
          },
        );
    final carregar = widget.carregarDetalhe;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => carregar == null
            ? tela(widget.detalhe)
            : Carregador<DetalhePedido>(
                carregar: () => carregar(pedido),
                construir: (_, dados) => tela(dados),
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
      for (final (i, aba) in abasProfissional.indexed.skip(1))
        i == 3 && widget.abaCarteira != null
            ? widget.abaCarteira!
            : i == 4 && widget.abaPerfil != null
                ? widget.abaPerfil!
                : EmBreveTela(titulo: aba.rotulo),
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
