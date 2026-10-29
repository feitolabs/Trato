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
  });

  /// Id do pedido na API (nulo nos dados de exemplo).
  final String? pedidoId;

  /// Ex.: "Hoje · 14h".
  final String quando;
  final String titulo;

  /// Endereço completo: o serviço já foi contratado, então pode aparecer.
  final String endereco;
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
    required this.distanciaKm,
    required this.prazo,
    required this.orcaram,
    required this.limiteOrcamentos,
    this.faixaMinCentavos,
    this.faixaMaxCentavos,
    this.urgente = false,
  });

  final String id;
  final String titulo;
  final String bairro;
  final double distanciaKm;

  /// Texto pronto. Ex.: "até sexta, 30/10", "hoje", "próxima semana".
  final String prazo;
  final int orcaram;
  final int limiteOrcamentos;

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
  });

  final String nome;
  final bool disponivelAgora;
  final ProximoAtendimento? proximo;
  final ResumoCarteira carteira;
  final List<PedidoAberto> pedidos;
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
