/// Modelos simples das telas do profissional (Início e Detalhe do pedido).
/// Só exibição: filtro por região, distância, vagas de orçamento e prazos vêm do backend.
/// Valores em centavos inteiros.
library;

import '../profissional/servico_orcamento.dart' show ItemMaterial;

/// Atendimento já contratado, mostrado no cartão escuro do Início.
class ProximoAtendimento {
  const ProximoAtendimento({
    required this.quando,
    required this.titulo,
    required this.endereco,
    this.pedidoId,
    this.janelaInicio,
    this.emAndamento = false,
    this.remoto = false,
    this.estadoApi,
  });

  /// Serviço remoto: sem endereço, sem foto e sem localização no check-in.
  final bool remoto;

  /// O serviço já começou (check-in feito).
  final bool emAndamento;

  /// Estado na API (ex.: `pago_e_retido`, `agendado`, `em_andamento`).
  final String? estadoApi;

  /// Id do pedido na API (nulo nos dados de exemplo).
  final String? pedidoId;

  /// Início da visita combinada; nulo enquanto a data não foi marcada.
  final DateTime? janelaInicio;

  /// Ex.: "Hoje · 14h".
  final String quando;
  final String titulo;

  /// Endereço completo: o serviço já foi contratado, então pode aparecer.
  final String endereco;

  bool get precisaAgendarVisita =>
      estadoApi == 'pago_e_retido' ||
      (!emAndamento &&
          janelaInicio == null &&
          quando.toLowerCase().contains('não marcada'));
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
    this.remoto = false,
    this.endereco,
    this.consultaMapa,
    this.cliente,
  });

  /// Nome abreviado do cliente ("Mariana S."), quando o servidor manda.
  final String? cliente;

  /// Serviço remoto (sem endereço).
  final bool remoto;

  /// Endereço por extenso (presencial, já contratado). Nulo se o cliente não informou.
  final String? endereco;

  /// Texto para abrir no mapa.
  final String? consultaMapa;

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
    this.orcamentoId = '',
    required this.pedidoId,
    required this.titulo,
    required this.valorCentavos,
    required this.versao,
    required this.situacao,
    this.enviadoEm,
    this.prazoExecucaoDias,
  });

  final String orcamentoId;
  final String pedidoId;

  /// Título do pedido, ou "Pedido #AAAA".
  final String titulo;
  final int valorCentavos;
  final int versao;

  /// `aguardando` (o cliente ainda decide), `aceito` ou `encerrado`.
  final String situacao;
  final DateTime? enviadoEm;
  final int? prazoExecucaoDias;

  bool get aguardando => situacao == 'aguardando';
  bool get aceito => situacao == 'aceito';
}

/// Linha de item de um orçamento já enviado (horas, deslocamento, material, etc.).
class ItemOrcamentoEnviado {
  const ItemOrcamentoEnviado({
    required this.tipo,
    required this.descricao,
    required this.quantidade,
    required this.valorUnitarioCentavos,
    required this.totalCentavos,
  });

  final String tipo;
  final String descricao;
  final String quantidade;
  final int valorUnitarioCentavos;
  final int totalCentavos;
}

/// Detalhe completo do orçamento enviado pelo profissional.
class DetalheOrcamentoEnviado {
  const DetalheOrcamentoEnviado({
    required this.orcamentoId,
    required this.pedidoId,
    required this.tituloPedido,
    required this.versao,
    required this.situacao,
    required this.valorCentavos,
    this.taxaCentavos,
    this.liquidoCentavos,
    this.prazoExecucaoDias,
    this.garantiaDias,
    this.foraDoEscopo,
    this.observacoes,
    this.validoAte,
    this.horasDeslocamento,
    this.horasTrabalhadas,
    this.itens = const [],
  });

  final String orcamentoId;
  final String pedidoId;
  final String tituloPedido;
  final int versao;
  final String situacao;
  final int valorCentavos;
  final int? taxaCentavos;
  final int? liquidoCentavos;
  final int? prazoExecucaoDias;
  final int? garantiaDias;
  final String? foraDoEscopo;
  final String? observacoes;
  final DateTime? validoAte;
  final String? horasDeslocamento;
  final String? horasTrabalhadas;
  final List<ItemOrcamentoEnviado> itens;

  bool get podeEditar => situacao == 'aguardando';

  int get valorHoraCentavos {
    for (final item in itens) {
      if ((item.tipo == 'horas' || item.tipo == 'deslocamento') && item.valorUnitarioCentavos > 0) {
        return item.valorUnitarioCentavos;
      }
    }
    return 10000;
  }

  int get decimosDeslocamento => _decimos(horasDeslocamento, 'deslocamento');

  int get decimosTrabalhadas => _decimos(horasTrabalhadas, 'horas');

  int _decimos(String? resumo, String tipo) {
    final parsed = resumo == null ? null : double.tryParse(resumo.replaceAll(',', '.'));
    if (parsed != null) return (parsed * 10).round();
    var soma = 0.0;
    for (final item in itens) {
      if (item.tipo == tipo) {
        soma += double.tryParse(item.quantidade.replaceAll(',', '.')) ?? 0;
      }
    }
    return (soma * 10).round();
  }

  List<ItemMaterial> get materiais => [
        for (final item in itens)
          if (item.tipo == 'material')
            ItemMaterial(nome: item.descricao, centavos: item.totalCentavos),
      ];
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
    this.modalidade = 'presencial',
    this.convidado = false,
  });

  /// Verdadeiro quando o cliente direcionou este pedido diretamente a este profissional.
  final bool convidado;

  /// `presencial` ou `remoto`.
  final String modalidade;
  bool get remoto => modalidade == 'remoto';

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
    this.emAnalise = false,
  });

  /// Cadastro ainda aguardando aprovação de documentos pela equipe.
  final bool emAnalise;

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
        emAnalise: emAnalise,
      );

  /// Mesmo início com o estado de "Disponível agora" atualizado.
  InicioProfissional comDisponivel(bool disponivel) => InicioProfissional(
        nome: nome,
        disponivelAgora: disponivel,
        proximo: proximo,
        carteira: carteira,
        pedidos: pedidos,
        contratados: contratados,
        orcamentosEnviados: orcamentosEnviados,
        emAnalise: emAnalise,
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
