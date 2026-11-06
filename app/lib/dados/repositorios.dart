import '../telas/carteira/modelos.dart';
import '../telas/conclusao/dados_exemplo.dart';
import '../telas/orcamentos/modelos.dart';
import '../telas/pagamento/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/modelos.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_check_out.dart';
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

/// O que o cliente descreveu no pedido e ainda pode mudar antes de aceitar um orçamento.
class DadosDoPedido {
  const DadosDoPedido({
    required this.titulo,
    required this.descricao,
    this.faixaMaxCentavos,
    this.logradouro,
    this.numero,
    this.bairro,
    this.complemento,
  });

  final String titulo;
  final String descricao;
  final int? faixaMaxCentavos;
  final String? logradouro;
  final String? numero;
  final String? bairro;
  final String? complemento;

  /// "Rua das Flores, 10 · Centro", ou nulo se não há endereço.
  String? get enderecoResumo {
    final rua = logradouro;
    if (rua == null || rua.isEmpty) return null;
    final n = (numero == null || numero!.isEmpty) ? '' : ', $numero';
    final b = (bairro == null || bairro!.isEmpty) ? '' : ' · $bairro';
    return '$rua$n$b';
  }
}

abstract interface class RepositorioPedidos {
  Future<PedidosDoCliente> listar();

  /// Descrição, valor pretendido e endereço do pedido.
  Future<DadosDoPedido> dados(String pedidoId);

  /// Troca esses dados. Só o cliente e só enquanto o pedido aguarda orçamentos (o backend decide).
  /// [faixaMaxCentavos] 0 = sem limite. Campos nulos ficam como estão.
  Future<DadosDoPedido> editar(
    String pedidoId, {
    String? descricao,
    int? faixaMaxCentavos,
    String? logradouro,
    String? numero,
    String? bairro,
    String? complemento,
  });

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

  /// Cliente propõe um valor menor (vai para a conversa do profissional). O backend valida.
  Future<void> contraproporValor(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    String? mensagem,
  });

  /// Profissional aceita a contraproposta: o orçamento ganha uma nova versão no valor combinado.
  Future<void> aceitarContraproposta(String pedidoId, String orcamentoId, int valorCentavos);
}

enum StatusPagamento { aguardando, pago, falhou }

class Cobranca {
  const Cobranca({
    required this.id,
    this.pixCopiaECola,
    this.urlCheckout,
    this.segredoCartao,
    this.clienteCartaoId,
    this.chaveEfemera,
  });

  /// Cartão: o que a folha do provedor precisa (nunca aparece na tela).
  final String? segredoCartao;
  final String? clienteCartaoId;
  final String? chaveEfemera;

  bool get precisaDaFolhaDeCartao =>
      segredoCartao != null && clienteCartaoId != null && chaveEfemera != null;

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
  Future<ConversaPedido> conversa(String pedidoId, {String? profissionalId});
  Future<void> enviar(String pedidoId, String texto, {String? profissionalId});
  Future<void> enviarFoto(String pedidoId, String referencia, {String? profissionalId});
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
  String? get nomeSalvo;

  /// Foto de perfil de qualquer usuário (URL curta do backend) ou `null` se não tiver.
  Future<String?> fotoDe(String usuarioId);

  /// Envia a foto de perfil de quem está logado (a que o cliente e o profissional veem).
  Future<void> enviarFoto(String caminhoLocal);
}

/// Filtros de `GET /v1/profissional/pedidos-abertos`. O backend aplica; o app só pede.
class FiltroPedidosAbertos {
  const FiltroPedidosAbertos({
    this.categoriaId,
    this.bairro,
    this.precoMinCentavos,
    this.precoMaxCentavos,
    this.ordenar = 'recentes',
    this.limite = 50,
  });

  final String? categoriaId;
  final String? bairro;
  final int? precoMinCentavos;
  final int? precoMaxCentavos;

  /// `recentes`, `antigos`, `urgentes`, `maior_valor` ou `menor_valor`.
  final String ordenar;
  final int limite;

  Map<String, String> get consulta => {
        if (categoriaId != null) 'categoria_id': categoriaId!,
        if (bairro != null && bairro!.isNotEmpty) 'bairro': bairro!,
        if (precoMinCentavos != null) 'preco_min_centavos': '$precoMinCentavos',
        if (precoMaxCentavos != null) 'preco_max_centavos': '$precoMaxCentavos',
        'ordenar': ordenar,
        'limite': '$limite',
      };
}

abstract interface class RepositorioProfissional {
  /// Pedidos abertos com filtros (a tela de filtros ainda não existe).
  Future<List<PedidoAberto>> pedidosAbertos(FiltroPedidosAbertos filtro);

  Future<InicioProfissional> inicio();
  Future<DetalhePedido> detalhe(String pedidoId);
  Future<void> recusar(String pedidoId, MotivoRecusa motivo);

  /// Marca a visita de um pedido já pago. Sem isso o check-in não é liberado.
  Future<void> confirmarAgenda(String pedidoId, DateTime inicio, DateTime fim);

  /// Carteira como EXTRATO (D15): sem saldo próprio, sem saque.
  Future<List<ItemExtrato>> extrato();

  /// Calculadora: taxa e líquido vêm do backend.
  ServicoOrcamento servicoOrcamento(String pedidoId);

  /// Check-in do pedido.
  ServicoCheckIn servicoCheckIn(String pedidoId);

  /// Check-out do pedido: foto final e código de conclusão que o cliente informa.
  ServicoCheckOut servicoCheckOut(String pedidoId);
}
