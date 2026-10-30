/// Uma conversa na lista de Mensagens: há uma por pedido.
/// O chat em si é `ChatPedidoTela` (telas/pedidos/chat_pedido_tela.dart).
class ConversaResumo {
  const ConversaResumo({
    required this.pedidoId,
    required this.tituloPedido,
    required this.interlocutor,
    required this.iniciais,
    required this.ultimaMensagem,
    required this.quando,
    this.naoLidas = 0,
  });

  final String pedidoId;
  final String tituloPedido;
  final String interlocutor;
  final String iniciais;
  final String ultimaMensagem;

  /// Texto pronto, ex.: "10h20" ou "ontem".
  final String quando;
  final int naoLidas;
}

/// Contrato com o backend. A tela só pede e mostra.
abstract interface class ServicoMensagens {
  Future<List<ConversaResumo>> listar();
}
