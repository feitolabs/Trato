import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/relogio_de_atualizacao.dart';
import '../../dados/repositorios.dart' show FiltroPedidosAbertos;
import '../agenda/agenda_tela.dart';
import '../cliente/modelos.dart' show CategoriaServico;
import '../fluxo/navegacao_casca.dart';
import '../fluxo/rotas.dart';
import '../mensagens/mensagens_tela.dart';
import '../mensagens/modelos.dart';
import 'detalhe_pedido_tela.dart';
import 'filtros_pedidos_tela.dart';
import 'inicio_profissional_tela.dart';
import 'modelos.dart';
import 'primeiros_passos.dart';
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
    required this.inicio,
    this.detalhe,
    this.aoFazerCheckIn,
    this.aoAvisarACaminho,
    this.aoFazerOrcamento,
    this.aoFazerOrcamentoDoPedido,
    this.aoPerguntar,
    this.aoPerguntarDoPedido,
    this.aoRecusar,
    this.abaCarteira,
    this.abaPerfil,
    this.abaAgenda,
    this.abaConversas,
    this.carregarDetalhe,
    this.recusarPedido,
    this.pedirExclusividade,
    this.carregarPedidos,
    this.carregarCategorias,
    this.aoAbrirNotificacoes,
    this.aoUsarComoCliente,
    this.aoGerenciarProximo,
    this.aoAbrirContratado,
    this.aoAbrirOrcamentoEnviado,
    this.aoAbrirMapa,
    this.recarregarInicio,
    this.aoAlterarDisponivel,
    this.atualizarACada,
    this.atualizarQuando,
    this.carregarPrimeirosPassos,
    this.aoAbrirContaRecebimento,
  });

  /// Busca os dados da trilha dos primeiros passos; nulo = a trilha não aparece.
  final Future<DadosPrimeirosPassos> Function()? carregarPrimeirosPassos;

  /// Abre a conta de recebimento (passo 1 da trilha, quando é o que falta).
  final VoidCallback? aoAbrirContaRecebimento;

  /// Atualiza "Disponível agora" no backend (prioriza e notifica pedidos urgentes).
  final Future<bool> Function(bool disponivel)? aoAlterarDisponivel;

  /// Toque num pedido que o cliente já aceitou (aba Pedidos > Em andamento).
  final ValueChanged<PedidoContratado>? aoAbrirContratado;

  /// Abre o endereço de um pedido contratado no mapa do aparelho.
  final ValueChanged<String>? aoAbrirMapa;

  /// Toque num orçamento que o profissional enviou (abre a conversa do pedido).
  final ValueChanged<OrcamentoEnviado>? aoAbrirOrcamentoEnviado;

  /// Busca o Início de novo (pedidos abertos, pedidos aceitos, carteira). Com [atualizarACada], a
  /// casca se atualiza sozinha: pedido novo e pedido aceito aparecem sem fechar o app.
  final Future<InicioProfissional> Function()? recarregarInicio;
  final Duration? atualizarACada;
  final Listenable? atualizarQuando;

  /// Permite trocar para a casca do cliente.
  final VoidCallback? aoUsarComoCliente;
  final ValueChanged<ProximoAtendimento?>? aoGerenciarProximo;

  /// Carrega o detalhe do pedido tocado (API). Sem isso, mostra [detalhe].
  final Future<DetalhePedido> Function(PedidoAberto pedido)? carregarDetalhe;

  /// Recusa o pedido tocado. Sem isso, usa [aoRecusar].
  final Future<void> Function(PedidoAberto pedido, MotivoRecusa motivo)? recusarPedido;

  /// Pede exclusividade de 48h no pedido tocado.
  final Future<ExclusividadeProfissional> Function(
    PedidoAberto pedido,
    String chaveIdempotencia,
  )? pedirExclusividade;

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
  final DetalhePedido? detalhe;
  final VoidCallback? aoFazerCheckIn;

  /// "Estou a caminho" no cartão do pedido agendado.
  final Future<AvisoACaminho> Function(String pedidoId, int? etaMinutos)? aoAvisarACaminho;
  final VoidCallback? aoFazerOrcamento;

  /// Chamado para fazer orçamento do pedido aberto tocado.
  final ValueChanged<PedidoAberto>? aoFazerOrcamentoDoPedido;
  final VoidCallback? aoPerguntar;

  /// Chamado para tirar dúvidas no chat do pedido aberto tocado.
  final ValueChanged<PedidoAberto>? aoPerguntarDoPedido;
  final ValueChanged<MotivoRecusa>? aoRecusar;

  @override
  State<CascaProfissionalTela> createState() => _CascaProfissionalTelaState();
}

class _CascaProfissionalTelaState extends State<CascaProfissionalTela> {
  late int _aba = widget.abaInicial;
  late final Set<int> _visitadas = {widget.abaInicial};
  late InicioProfissional _inicio = widget.inicio;
  var _filtro = const FiltroPedidosAbertos();
  var _carregandoPedidos = false;
  DateTime? _ultimaAtualizacaoAba;
  RelogioDeAtualizacao? _relogio;

  @override
  void initState() {
    super.initState();
    ControladorCasca.registrar(
      irParaAba: _ir,
      recarregarCasca: _atualizarEmSilencio,
    );
    widget.atualizarQuando?.addListener(_aoAtualizarExternamente);
    final intervalo = widget.atualizarACada;
    if (intervalo != null && widget.recarregarInicio != null) {
      _relogio = RelogioDeAtualizacao(
        intervalo: intervalo,
        aoAtualizar: _atualizarEmSilencio,
        // Só atualiza quando o Início ou Pedidos estão visíveis (pausa nas demais abas).
        deveAtualizar: () =>
            mounted &&
            (_aba == 0 || _aba == 1) &&
            !_carregandoPedidos &&
            (ModalRoute.of(context)?.isCurrent ?? true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CascaProfissionalTela antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.atualizarQuando != widget.atualizarQuando) {
      antigo.atualizarQuando?.removeListener(_aoAtualizarExternamente);
      widget.atualizarQuando?.addListener(_aoAtualizarExternamente);
    }
    if (antigo.inicio != widget.inicio) {
      _inicio = widget.inicio;
    }
  }

  @override
  void dispose() {
    ControladorCasca.desregistrar(_ir);
    widget.atualizarQuando?.removeListener(_aoAtualizarExternamente);
    _relogio?.parar();
    super.dispose();
  }

  void _aoAtualizarExternamente() {
    if (widget.recarregarInicio != null) _atualizarEmSilencio();
  }

  /// Traz o Início de novo sem tela de carregando. Mantém o filtro de pedidos escolhido.
  Future<void> _atualizarEmSilencio() async {
    if (widget.recarregarInicio == null) return;
    try {
      final novo = await widget.recarregarInicio!();
      var pedidos = novo.pedidos;
      if (_filtrosAtivos > 0) {
        final filtrados = await widget.carregarPedidos?.call(_filtro);
        if (filtrados != null) pedidos = filtrados;
      }
      if (!mounted) return;
      setState(() => _inicio = novo.comPedidos(pedidos));
    } on Object {
      // Falha em segundo plano mantém o que já está visível.
    }
  }

  Future<void> _alterarDisponivel(bool disponivel) async {
    final salvar = widget.aoAlterarDisponivel;
    if (salvar == null) return;
    final mensagens = ScaffoldMessenger.of(context);
    setState(() => _inicio = _inicio.comDisponivel(disponivel));
    try {
      final salvo = await salvar(disponivel);
      if (!mounted) return;
      setState(() => _inicio = _inicio.comDisponivel(salvo));
      await _atualizarEmSilencio();
    } on Object catch (erro) {
      if (!mounted) return;
      setState(() => _inicio = _inicio.comDisponivel(!disponivel));
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              erro is ErroTrato
                  ? erro.mensagem
                  : 'Não foi possível atualizar sua disponibilidade agora.',
            ),
          ),
        );
    }
  }

  void _ir(int indice) {
    if (_aba == indice) return;
    setState(() {
      _aba = indice;
      _visitadas.add(indice);
    });
    final agora = DateTime.now();
    if (_ultimaAtualizacaoAba == null ||
        agora.difference(_ultimaAtualizacaoAba!) >= const Duration(milliseconds: 1500)) {
      _ultimaAtualizacaoAba = agora;
      if (widget.recarregarInicio != null) _atualizarEmSilencio();
      RotasTrato.pedidosMudaram.value++;
    }
  }

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
          aoPerguntar: widget.aoPerguntarDoPedido != null
              ? () => widget.aoPerguntarDoPedido!(pedido)
              : widget.aoPerguntar,
          aoPedirExclusividade: widget.pedirExclusividade == null
              ? null
              : (chave) async {
                  final nova = await widget.pedirExclusividade!(pedido, chave);
                  await _atualizarEmSilencio();
                  return nova;
                },
          aoRecusar: (motivo) async {
            final navegador = Navigator.of(context);
            final mensagens = ScaffoldMessenger.of(context);
            widget.aoRecusar?.call(motivo);
            try {
              if (widget.recusarPedido != null) {
                await widget.recusarPedido!(pedido, motivo);
                await _atualizarEmSilencio();
              }
              if (mounted) {
                navegador.pop();
                mensagens
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Pedido recusado e removido da lista.')),
                  );
              }
            } on Object catch (erro) {
              if (!mounted) return;
              mensagens
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      erro is ErroTrato ? erro.mensagem : 'Não foi possível recusar agora.',
                    ),
                  ),
                );
            }
          },
        );
    final carregar = widget.carregarDetalhe;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => carregar == null
            ? tela(widget.detalhe!)
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
              erro is ErroTrato
                  ? erro.mensagem
                  : 'Não foi possível aplicar os filtros. Tente de novo.',
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
        aoAlterarDisponivel: widget.aoAlterarDisponivel == null ? null : _alterarDisponivel,
        aoFazerCheckIn: widget.aoGerenciarProximo != null
            ? () => widget.aoGerenciarProximo!(_inicio.proximo)
            : widget.aoFazerCheckIn,
        aoAvisarACaminho: widget.aoAvisarACaminho,
        aoAbrirFiltros: _filtros,
        aoAbrirPedido: _abrirDetalhe,
        aoAbrirNotificacoes: widget.aoAbrirNotificacoes,
        aoUsarComoCliente: widget.aoUsarComoCliente,
        carregarPrimeirosPassos: widget.carregarPrimeirosPassos,
        aoCompletarPerfil: (destino) {
          if (destino == DestinoCompletar.contaRecebimento &&
              widget.aoAbrirContaRecebimento != null) {
            widget.aoAbrirContaRecebimento!();
          } else {
            _ir(4);
          }
        },
        aoVerPedidos: () => _ir(1),
        aoVerAgenda: () => _ir(2),
      ),
      PedidosProfissionalTela(
        pedidos: _inicio.pedidos,
        contratados: _inicio.contratados,
        aoAbrirContratado: widget.aoAbrirContratado,
        orcamentosEnviados: _inicio.orcamentosEnviados,
        aoAbrirOrcamentoEnviado: widget.aoAbrirOrcamentoEnviado,
        aoAbrirMapa: widget.aoAbrirMapa,
        carregando: _carregandoPedidos,
        filtrosAtivos: _filtrosAtivos,
        aoAbrirFiltros: _filtros,
        aoAbrirPedido: _abrirDetalhe,
        conversas: widget.abaConversas ??
            const ListaConversas(
              servico: _SemConversas(),
              textoVazio: 'Quando um cliente conversar com você sobre um pedido, aparece aqui.',
            ),
      ),
      _visitadas.contains(2)
          ? (widget.abaAgenda ??
              AgendaTela(
                carregar: () async => const [],
                aoFazerCheckIn: (_) => widget.aoFazerCheckIn?.call(),
              ))
          : const SizedBox.shrink(),
      _visitadas.contains(3)
          ? (widget.abaCarteira ?? const SizedBox.shrink())
          : const SizedBox.shrink(),
      _visitadas.contains(4)
          ? (widget.abaPerfil ?? const SizedBox.shrink())
          : const SizedBox.shrink(),
    ];
    return PopScope(
      canPop: _aba == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _aba != 0) _ir(0);
      },
      child: AtualizadorTela(
        recarregar: _atualizarEmSilencio,
        child: Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: _aba,
            children: [
              for (var i = 0; i < paginas.length; i++)
                TickerMode(enabled: _aba == i, child: paginas[i]),
            ],
          ),
          bottomNavigationBar: ValueListenableBuilder<int>(
            valueListenable: RotasTrato.mensagensNaoLidas,
            builder: (context, naoLidas, _) {
              final abas = naoLidas > 0
                  ? [
                      for (var i = 0; i < abasProfissional.length; i++)
                        i == 1 ? abasProfissional[i].comBadge(naoLidas) : abasProfissional[i],
                    ]
                  : abasProfissional;
              return BarraAbasFlutuante(
                abas: abas,
                indiceAtual: _aba,
                aoSelecionar: _ir,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Aba de conversas sem origem de dados: lista vazia (o `rotas.dart` sempre entrega a real).
class _SemConversas implements ServicoMensagens {
  const _SemConversas();

  @override
  Future<List<ConversaResumo>> listar() async => const [];
}
