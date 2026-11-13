/// Modelos simples das telas do profissional (Início e Detalhe do pedido).
/// Só exibição: filtro por região, distância, vagas de orçamento e prazos vêm do backend.
/// Valores em centavos inteiros.
library;

/// Atendimento já contratado, mostrado no cartão escuro do Início.
class ProximoAtendimento {
  const ProximoAtendimento({
    required this.quando,
    required this.titulo,
    required this.endereco,
    this.pedidoId,
    this.janelaInicio,
    this.emAndamento = false,
  });

  /// O serviço já começou (check-in feito).
  final bool emAndamento;

  /// Id do pedido na API (nulo nos dados de exemplo).
  final String? pedidoId;

  /// Início da visita combinada; nulo enquanto a data não foi marcada.
  final DateTime? janelaInicio;

  /// Ex.: "Hoje · 14h".
  final String quando;
  final String titulo;

  /// Endereço completo: o serviço já foi contratado, então pode aparecer.
  final String endereco;
}

/// Pedido que o cliente já aceitou (do orçamento do profissional): do aceite até o fim. É o que o
/// profissional acompanha na aba Pedidos. Antes do pagamento ele NÃO está mais "aberto" e, sem esta
/// lista, sumia da tela do profissional.
class PedidoContratado {
  const PedidoContratado({
    required this.pedidoId,
    required this.titulo,
    required this.situacao,
    required this.estadoApi,
    this.quando,
    this.janelaInicio,
  });

  final String pedidoId;

  /// Ex.: "Pedido #4F2A".
  final String titulo;

  /// Texto pronto da situação, ex.: "Aguardando o pagamento do cliente".
  final String situacao;

  /// Estado na API (`orcamento_aceito`, `pago_e_retido`, `agendado`...).
  final String estadoApi;

  /// Data combinada da visita, quando já existe.
  final String? quando;
  final DateTime? janelaInicio;

  bool get aguardandoPagamento =>
      estadoApi == 'orcamento_aceito' || estadoApi == 'aguardando_confirmacao';

  /// Entra na agenda (já pago, para agendar, agendado ou em execução).
  bool get naAgenda => const {'pago_e_retido', 'agendado', 'em_andamento'}.contains(estadoApi);
  bool get emAndamento => estadoApi == 'em_andamento';
}

/// Orçamento que o profissional enviou (a última versão), para ele acompanhar a resposta do cliente.
class OrcamentoEnviado {
  const OrcamentoEnviado({
    required this.pedidoId,
    required this.titulo,
    required this.valorCentavos,
    required this.versao,
    required this.situacao,
    this.enviadoEm,
  });

  final String pedidoId;

  /// Título do pedido, ou "Pedido #AAAA".
  final String titulo;
  final int valorCentavos;
  final int versao;

  /// `aguardando` (o cliente ainda decide), `aceito` ou `encerrado`.
  final String situacao;
  final DateTime? enviadoEm;

  bool get aguardando => situacao == 'aguardando';
  bool get aceito => situacao == 'aceito';
}

class ResumoCarteira {
  const ResumoCarteira({required this.retidoCentavos, required this.paraSacarCentavos});

  final int retidoCentavos;
  final int paraSacarCentavos;
}

/// Pedido aberto (ainda sem contratação): só bairro e distância, nunca o endereço completo.
class PedidoAberto {
  const PedidoAberto({
    required this.id,
    required this.titulo,
    required this.bairro,
    this.distanciaKm,
    required this.prazo,
    this.orcaram,
    this.limiteOrcamentos,
    this.faixaMinCentavos,
    this.faixaMaxCentavos,
    this.urgente = false,
    this.latitude,
    this.longitude,
    this.clienteId,
    this.clienteNome,
  });

  /// Quem pediu (foto de perfil e primeiro nome). Nunca contato.
  final String? clienteId;
  final String? clienteNome;

  final String id;
  final String titulo;
  final String bairro;
  final double? distanciaKm;

  /// Ponto aproximado do pedido (nunca o endereço exato); ausente = sem mapa.
  final double? latitude;
  final double? longitude;

  /// Texto pronto. Ex.: "até sexta, 30/10", "hoje", "próxima semana".
  final String prazo;
  final int? orcaram;
  final int? limiteOrcamentos;

  /// Faixa que o cliente pensa gastar; ausente = "Sem faixa".
  final int? faixaMinCentavos;
  final int? faixaMaxCentavos;
  final bool urgente;

  bool get temFaixa => faixaMinCentavos != null && faixaMaxCentavos != null;
}

class InicioProfissional {
  const InicioProfissional({
    required this.nome,
    required this.disponivelAgora,
    required this.carteira,
    required this.pedidos,
    this.proximo,
    this.contratados = const [],
    this.orcamentosEnviados = const [],
  });

  /// Os orçamentos que o profissional enviou, do mais novo ao mais antigo.
  final List<OrcamentoEnviado> orcamentosEnviados;

  /// Pedidos aceitos pelo cliente, do aceite ao fim (inclui "aguardando pagamento").
  final List<PedidoContratado> contratados;

  final String nome;
  final bool disponivelAgora;
  final ProximoAtendimento? proximo;
  final ResumoCarteira carteira;
  final List<PedidoAberto> pedidos;

  /// Mesmo início com outra lista de pedidos abertos (depois de aplicar filtros).
  InicioProfissional comPedidos(List<PedidoAberto> novos) => InicioProfissional(
        nome: nome,
        disponivelAgora: disponivelAgora,
        proximo: proximo,
        carteira: carteira,
        pedidos: novos,
        contratados: contratados,
        orcamentosEnviados: orcamentosEnviados,
      );
}

/// Linha "rótulo e valor" da tabela de detalhes (Serviços, Tomadas, Prazo...).
class LinhaDetalhe {
  const LinhaDetalhe(this.rotulo, this.valor);

  final String rotulo;
  final String valor;
}

class DetalhePedido {
  const DetalhePedido({
    required this.pedido,
    required this.fechaEm,
    required this.clienteResumo,
    required this.legendasFotos,
    required this.descricao,
    required this.linhas,
  });

  /// Dados da lista (título, bairro, distância, faixa, vagas).
  final PedidoAberto pedido;

  /// Texto pronto. Ex.: "Fecha em 31 horas".
  final String fechaEm;

  /// Ex.: "Mariana · nota 4,8 como cliente · 6 serviços".
  final String clienteResumo;
  final List<String> legendasFotos;
  final String descricao;

  /// Detalhes do pedido, na ordem. A faixa e o prazo vêm de [pedido].
  final List<LinhaDetalhe> linhas;
}

/// Motivos para recusar um pedido (escopo 6.2).
enum MotivoRecusa {
  foraDaRegiao('Fora da minha região'),
  semAgenda('Sem agenda'),
  foraDoEscopo('Fora do meu escopo');

  const MotivoRecusa(this.texto);

  final String texto;
}
