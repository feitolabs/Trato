import '../telas/carteira/modelos.dart';
import '../telas/conclusao/dados_exemplo.dart';
import '../telas/orcamentos/modelos.dart';
import '../telas/pagamento/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/modelos.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_orcamento.dart';
import '../telas/profissional_inicio/modelos.dart';

/// Portas de dados do app. As telas não conhecem a rede: quem liga (rotas.dart) entrega a
/// implementação certa (API ou demonstração). Dinheiro em centavos; nenhuma regra aqui.

class PedidosDoCliente {
  const PedidosDoCliente({this.emAndamento = const [], this.finalizados = const []});

  final List<PedidoResumo> emAndamento;
  final List<PedidoResumo> finalizados;

  bool get vazio => emAndamento.isEmpty && finalizados.isEmpty;
}

abstract interface class RepositorioPedidos {
  Future<PedidosDoCliente> listar();

  /// Abre o pedido e devolve o id.
  Future<String> criar(RascunhoPedido rascunho);

  /// Linha do tempo e código de início do pedido.
  Future<PedidoEmExecucao> acompanhar(String pedidoId);

  Future<ResumoConclusao> conclusao(String pedidoId);

  /// Cliente confirma o serviço. O backend decide a liberação.
  Future<void> confirmarConclusao(String pedidoId);

  Future<DadosRelatoProblema> dadosRelato(String pedidoId);

  /// "Relatar problema": abre a disputa; o valor congelado é do backend.
  Future<void> relatarProblema(String pedidoId, EnvioRelato relato);

  Future<void> avaliar(String pedidoId, EnvioAvaliacao avaliacao);

  Future<DadosAvaliacao> dadosAvaliacao(String pedidoId);

  Future<DadosGarantia> garantia(String pedidoId);

  Future<void> pedirRetrabalho(String pedidoId, String descricao);
}

class OrcamentosDoPedido {
  const OrcamentosDoPedido({required this.pedido, required this.orcamentos});

  final ResumoPedido pedido;
  final List<Orcamento> orcamentos;
}

abstract interface class RepositorioOrcamentos {
  Future<OrcamentosDoPedido> listar(String pedidoId);

  /// Só pede ao backend. Taxa e líquido nunca são calculados no app.
  Future<void> aceitar(String pedidoId, String orcamentoId);
}

enum StatusPagamento { aguardando, pago, falhou }

class Cobranca {
  const Cobranca({required this.id, this.pixCopiaECola, this.urlCheckout});

  final String id;

  /// Código Pix "copia e cola" (modo teste do provedor).
  final String? pixCopiaECola;
  final String? urlCheckout;
}

abstract interface class RepositorioPagamento {
  Future<DadosPagamento> dados(String pedidoId);

  /// Cria a cobrança (modo teste). O app NUNCA marca como pago: só o backend, depois do
  /// webhook assinado do provedor (D14/D15).
  Future<Cobranca> criarCobranca(String pedidoId, MetodoPagamento metodo);

  Future<StatusPagamento> status(String pedidoId);
}

abstract interface class RepositorioChat {
  Future<ConversaPedido> conversa(String pedidoId);
  Future<void> enviar(String pedidoId, String texto);
}

class Notificacao {
  const Notificacao({
    required this.id,
    required this.titulo,
    required this.texto,
    required this.quando,
    this.lida = false,
    this.tipo,
    this.destinoId,
  });

  final String id;
  final String titulo;
  final String texto;

  /// Quando o backend informa: `disputa` ou `retrabalho` (abrem a tela do profissional).
  final String? tipo;

  /// Id da disputa (ou do pedido) que o toque abre.
  final String? destinoId;

  /// Já formatado ("há 2 h").
  final String quando;
  final bool lida;
}

abstract interface class RepositorioNotificacoes {
  Future<List<Notificacao>> listar();
}

abstract interface class RepositorioPerfil {
  Future<PerfilCliente> carregar();
}

abstract interface class RepositorioProfissional {
  Future<InicioProfissional> inicio();
  Future<DetalhePedido> detalhe(String pedidoId);
  Future<void> recusar(String pedidoId, MotivoRecusa motivo);

  /// Carteira como EXTRATO (D15): sem saldo próprio, sem saque.
  Future<List<ItemExtrato>> extrato();

  /// Calculadora: taxa e líquido vêm do backend.
  ServicoOrcamento servicoOrcamento(String pedidoId);

  /// Check-in/out do pedido.
  ServicoCheckIn servicoCheckIn(String pedidoId);
}
