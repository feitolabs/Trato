import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart' show FiltroPedidosAbertos;
import '../agenda/agenda_tela.dart';
import '../carteira/carteira_tela.dart';
import '../cliente/modelos.dart' show CategoriaServico;
import '../mensagens/mensagens_tela.dart';
import '../mensagens/servico_fake.dart';
import '../perfil_publico/perfil_publico.dart';
import '../perfil_publico/perfil_publico_tela.dart';
import 'detalhe_pedido_tela.dart';
import 'dados_exemplo.dart';
import 'filtros_pedidos_tela.dart';
import 'inicio_profissional_tela.dart';
import 'modelos.dart';
import 'pedidos_profissional_tela.dart';

/// Casca do app do profissional: barra inferior com as 5 abas (Início · Pedidos · Agenda ·
/// Carteira · Perfil). Pedidos traz os pedidos abertos (com filtros) e as conversas. Cada aba
/// guarda seu estado.
///
/// Os callbacks de ações que dependem de outras telas (orçamento, check-in, recusa)
/// ficam em aberto para quem integra ligar. Sem as abas de [abaAgenda], [abaCarteira],
/// [abaPerfil] e [abaConversas], a casca mostra as telas com dados de demonstração.
class CascaProfissionalTela extends StatefulWidget {
  const CascaProfissionalTela({
    super.key,
    this.abaInicial = 0,
    this.inicio = inicioProfissionalExemplo,
    this.detalhe = detalhePedidoExemplo,
    this.aoFazerCheckIn,
    this.aoFazerOrcamento,
    this.aoFazerOrcamentoDoPedido,
    this.aoPerguntar,
    this.aoRecusar,
    this.abaCarteira,
    this.abaPerfil,
    this.abaAgenda,
    this.abaConversas,
    this.carregarDetalhe,
    this.recusarPedido,
    this.carregarPedidos,
    this.carregarCategorias,
    this.aoAbrirNotificacoes,
  });

  /// Carrega o detalhe do pedido tocado (API). Sem isso, mostra [detalhe].
  final Future<DetalhePedido> Function(PedidoAberto pedido)? carregarDetalhe;

  /// Recusa o pedido tocado. Sem isso, usa [aoRecusar].
  final Future<void> Function(PedidoAberto pedido, MotivoRecusa motivo)? recusarPedido;

  /// Pede ao backend os pedidos abertos com o filtro escolhido. Sem isso, o filtro não muda a lista.
  final Future<List<PedidoAberto>> Function(FiltroPedidosAbertos filtro)? carregarPedidos;

  /// Categorias oferecidas na tela de filtros.
  final Future<List<CategoriaServico>> Function()? carregarCategorias;

  /// Conteúdo da aba Carteira (extrato).
  final Widget? abaCarteira;

  /// Aba Perfil (perfil público e avaliações).
  final Widget? abaPerfil;

  /// Aba Agenda (lista por dia com check-in).
  final Widget? abaAgenda;

  /// Lista de conversas, dentro da aba Pedidos.
  final Widget? abaConversas;

  /// Abre as notificações (sino do Início).
  final VoidCallback? aoAbrirNotificacoes;

  final int abaInicial;
  final InicioProfissional inicio;

  /// Detalhe mostrado ao tocar num pedido aberto (provisório: o backend entrega o do pedido tocado).
  final DetalhePedido detalhe;
  final VoidCallback? aoFazerCheckIn;
  final VoidCallback? aoFazerOrcamento;

  /// Chamado para fazer orçamento do pedido aberto tocado.
  final ValueChanged<PedidoAberto>? aoFazerOrcamentoDoPedido;
  final VoidCallback? aoPerguntar;
  final ValueChanged<MotivoRecusa>? aoRecusar;

  @override
  State<CascaProfissionalTela> createState() => _CascaProfissionalTelaState();
}

class _CascaProfissionalTelaState extends State<CascaProfissionalTela> {
  late int _aba = widget.abaInicial;
  late InicioProfissional _inicio = widget.inicio;
  var _filtro = const FiltroPedidosAbertos();
  var _carregandoPedidos = false;

  void _ir(int indice) => setState(() => _aba = indice);

  int get _filtrosAtivos => [
        if (_filtro.categoriaId != null) 1,
        if (_filtro.bairro != null) 1,
        if (_filtro.precoMinCentavos != null || _filtro.precoMaxCentavos != null) 1,
        if (_filtro.ordenar != 'recentes') 1,
      ].length;

  void _abrirDetalhe(PedidoAberto pedido) {
    Widget tela(DetalhePedido dados) => DetalhePedidoTela(
          dados: dados,
          aoFazerOrcamento: widget.aoFazerOrcamentoDoPedido != null
              ? () => widget.aoFazerOrcamentoDoPedido!(pedido)
              : widget.aoFazerOrcamento,
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

  Future<void> _filtros() async {
    final navegador = Navigator.of(context);
    final mensagens = ScaffoldMessenger.of(context);
    final categorias = await widget.carregarCategorias?.call().catchError(
              (Object _) => <CategoriaServico>[],
            ) ??
        <CategoriaServico>[];
    if (!mounted) return;
    final novo = await navegador.push<FiltroPedidosAbertos>(
      MaterialPageRoute(
        builder: (_) => FiltrosPedidosAbertosTela(atual: _filtro, categorias: categorias),
      ),
    );
    if (novo == null || !mounted) return;
    setState(() {
      _filtro = novo;
      _carregandoPedidos = true;
    });
    try {
      final lista = await widget.carregarPedidos?.call(novo);
      if (!mounted) return;
      setState(() {
        if (lista != null) _inicio = _inicio.comPedidos(lista);
        _carregandoPedidos = false;
      });
    } on Object catch (erro) {
      if (!mounted) return;
      setState(() => _carregandoPedidos = false);
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              erro is ErroTrato ? erro.mensagem : 'Não foi possível aplicar os filtros. Tente de novo.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      InicioProfissionalTela(
        dados: _inicio,
        aoFazerCheckIn: widget.aoFazerCheckIn,
        aoAbrirCarteira: () => _ir(3),
        aoAbrirFiltros: _filtros,
        aoAbrirPedido: _abrirDetalhe,
        aoAbrirNotificacoes: widget.aoAbrirNotificacoes,
      ),
      PedidosProfissionalTela(
        pedidos: _inicio.pedidos,
        carregando: _carregandoPedidos,
        filtrosAtivos: _filtrosAtivos,
        aoAbrirFiltros: _filtros,
        aoAbrirPedido: _abrirDetalhe,
        conversas: widget.abaConversas ??
            const ListaConversas(
              servico: ServicoMensagensFake(),
              textoVazio: 'Quando um cliente conversar com você sobre um pedido, aparece aqui.',
            ),
      ),
      widget.abaAgenda ??
          AgendaTela(
            carregar: () async => const [],
            aoFazerCheckIn: (_) => widget.aoFazerCheckIn?.call(),
          ),
      widget.abaCarteira ?? const CarteiraTela(soExtrato: true),
      widget.abaPerfil ?? PerfilPublicoTela(servico: ServicoPerfilPublicoFake()),
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
