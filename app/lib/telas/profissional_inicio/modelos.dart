/// Modelos simples das telas do profissional (Início e Detalhe do pedido).
/// Só exibição: filtro por região, distância, vagas de orçamento e prazos vêm do backend.
/// Valores em centavos inteiros.
library;

import '../profissional/servico_orcamento.dart' show ItemMaterial;

/// Atendimento já contratado, mostrado no cartão escuro do Início.
/// Resposta de `POST /v1/profissional/pedidos/{id}/a-caminho`.
class AvisoACaminho {
  const AvisoACaminho({required this.enviado, this.etaMinutos});

  /// Falso quando o profissional já avisou há pouco (o servidor não repete o aviso).
  final bool enviado;
  final int? etaMinutos;
}

/// "O que fazer agora" do profissional, em uma linha, por estado do pedido. Nulo quando não há
/// nada a fazer (estado desconhecido ou cancelado). Só texto: quem decide o estado é o backend.
String? oQueFazerAgora(String? estadoApi, {bool remoto = false}) => switch (estadoApi) {
      'orcamento_aceito' => 'Aguardar o pagamento do cliente',
      'pago_e_retido' => remoto ? 'Combinar início' : 'Marcar a data da visita',
      'agendado' => remoto ? 'Iniciar atendimento' : 'Fazer check-in',
      'em_andamento' => 'Pedir o código de conclusão ao cliente',
      'em_confirmacao' => 'Aguardar confirmação do cliente',
      'retrabalho' => 'Atender retrabalho',
      'em_disputa' => 'Responder à disputa',
      'concluido' => 'Avaliar cliente',
      _ => null,
    };

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

  /// Visita marcada e serviço ainda não começou: só aí vale o aviso "Estou a caminho".
  bool get agendado => estadoApi == 'agendado' && !emAndamento && pedidoId != null;

  bool get precisaAgendarVisita =>
      estadoApi == 'pago_e_retido' ||
      (!emAndamento && janelaInicio == null && quando.toLowerCase().contains('não marcada'));
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

/// Um repasse previsto: pedido, valor em centavos e a data prevista (pode faltar).
class LiberacaoPrevista {
  const LiberacaoPrevista({
    required this.pedidoNumero,
    required this.valorCentavos,
    this.liberacaoPrevistaEm,
  });

  final String pedidoNumero;
  final int valorCentavos;
  final DateTime? liberacaoPrevistaEm;
}

class ResumoCarteira {
  const ResumoCarteira({
    required this.retidoCentavos,
    required this.paraSacarCentavos,
    this.proximaLiberacao,
    this.liberacoesPrevistas = const [],
    this.retidoDesdePagamentoCentavos,
  });

  /// Valor retido desde o pagamento do cliente (`retido_centavos` do saldo); nulo/0 = sem linha.
  final int? retidoDesdePagamentoCentavos;

  final int retidoCentavos;
  final int paraSacarCentavos;

  /// Repasses a caminho (`liberacoes_previstas`); vazio quando o backend não informa.
  final List<LiberacaoPrevista> liberacoesPrevistas;

  /// Próxima liberação do repasse (`proxima_liberacao_em`); nulo = sem data.
  final DateTime? proximaLiberacao;
}

/// Oferta de exclusividade de 48h vista pelo profissional.
class ExclusividadeProfissional {
  const ExclusividadeProfissional({
    required this.id,
    required this.pedidoId,
    required this.status,
    this.clienteId = '',
    this.moedasCobradas = 100,
    this.responderAte,
    this.expiraEm,
    this.saldoRestante,
    this.tituloPedido,
    this.bloqueadoRecusa = false,
    this.bloqueadoAte,
  });

  final String id;
  final String pedidoId;
  final String clienteId;

  /// `aguardando_cliente`, `ativa`, `recusada`, `expirada_sem_resposta`,
  /// `concluida`, `expirada_sem_atendimento` ou `cancelada`.
  final String status;
  final int moedasCobradas;
  final DateTime? responderAte;
  final DateTime? expiraEm;
  final int? saldoRestante;
  final String? tituloPedido;
  final bool bloqueadoRecusa;

  /// Fim do bloqueio depois de recusa (API). Nulo ou no passado: sem bloqueio.
  final DateTime? bloqueadoAte;

  bool get aguardandoCliente => status == 'aguardando_cliente';
  bool get ativa => status == 'ativa';
  bool get emAndamento => aguardandoCliente || ativa;

  String get rotuloStatus => switch (status) {
        'aguardando_cliente' => 'Aguardando o cliente',
        'ativa' => 'Ativa (48h)',
        'recusada' => 'Recusada',
        'expirada_sem_resposta' => 'Tratinhos devolvidos',
        'concluida' => 'Concluída',
        'expirada_sem_atendimento' => 'Expirada sem orçamento',
        'cancelada' => 'Cancelada (estornada)',
        _ => status,
      };
}

/// Resumo da carteira de Tratinhos do profissional e suas exclusividades.
/// Moeda de profissional não tem valor em dinheiro (nunca converter em reais).
class ResumoExclusividades {
  const ResumoExclusividades({
    this.itens = const [],
    this.ativasOuPendentes = 0,
    this.limiteMaximo = 3,
    this.saldoProfissional = 0,
    this.moedasPendentesProfissional = 0,
    this.moedasPendentesLiberacao,
    this.moedaValorCentavos,
  });

  final List<ExclusividadeProfissional> itens;
  final int ativasOuPendentes;
  final int limiteMaximo;
  final int saldoProfissional;
  final int moedasPendentesProfissional;

  /// Quando os Tratinhos pendentes são liberados (`proxima_liberacao_profissional`); opcional.
  final DateTime? moedasPendentesLiberacao;

  /// Valor de 1 Tratinho em centavos (`valor_moeda_centavos`), só para mostrar em reais; opcional.
  final int? moedaValorCentavos;

  ResumoExclusividades comPendentes(int pendentes) => ResumoExclusividades(
        itens: itens,
        ativasOuPendentes: ativasOuPendentes,
        limiteMaximo: limiteMaximo,
        saldoProfissional: saldoProfissional,
        moedasPendentesProfissional: pendentes,
        moedasPendentesLiberacao: moedasPendentesLiberacao,
        moedaValorCentavos: moedaValorCentavos,
      );

  ResumoExclusividades comNovaOferta(ExclusividadeProfissional oferta) {
    final jaExiste = itens.any((i) => i.id == oferta.id);
    final novaLista =
        jaExiste ? [for (final i in itens) i.id == oferta.id ? oferta : i] : [oferta, ...itens];
    final emAndamento = novaLista.where((i) => i.emAndamento).length;
    return ResumoExclusividades(
      itens: novaLista,
      ativasOuPendentes: emAndamento,
      limiteMaximo: limiteMaximo,
      saldoProfissional: oferta.saldoRestante ?? saldoProfissional,
      moedasPendentesProfissional: moedasPendentesProfissional,
      moedasPendentesLiberacao: moedasPendentesLiberacao,
      moedaValorCentavos: moedaValorCentavos,
    );
  }
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
    this.estado = 'aberto',
    this.permiteExclusividade = true,
    this.exclusividade,
  });

  /// Verdadeiro quando o cliente direcionou este pedido diretamente a este profissional.
  final bool convidado;

  /// Estado do pedido (`aberto`, `reservado`, ...). Backend antigo = `aberto`.
  final String estado;

  /// Se a categoria do pedido permite exclusividade. Backend antigo = `true`.
  final bool permiteExclusividade;

  /// Oferta de exclusividade deste profissional para este pedido, se houver.
  final ExclusividadeProfissional? exclusividade;

  bool get reservado => estado == 'reservado' || (exclusividade?.ativa ?? false);

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
    this.notificacoesNaoLidas = 0,
    this.exclusividades,
  });

  /// Cadastro ainda aguardando aprovação de documentos pela equipe.
  final bool emAnalise;
  final int notificacoesNaoLidas;
  final ResumoExclusividades? exclusividades;

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
        notificacoesNaoLidas: notificacoesNaoLidas,
        exclusividades: exclusividades,
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
        notificacoesNaoLidas: notificacoesNaoLidas,
        exclusividades: exclusividades,
      );

  InicioProfissional comNotificacoesNaoLidas(int naoLidas) => InicioProfissional(
        nome: nome,
        disponivelAgora: disponivelAgora,
        proximo: proximo,
        carteira: carteira,
        pedidos: pedidos,
        contratados: contratados,
        orcamentosEnviados: orcamentosEnviados,
        emAnalise: emAnalise,
        notificacoesNaoLidas: naoLidas,
        exclusividades: exclusividades,
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
    this.exclusividade,
    this.exclusividades,
    this.bloqueadoRecusa = false,
    this.bloqueadoAte,
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

  /// Oferta de exclusividade em andamento (ou última oferta) para este pedido.
  final ExclusividadeProfissional? exclusividade;

  /// Saldo e contador do profissional (X de 3), quando carregados.
  final ResumoExclusividades? exclusividades;

  /// Verdadeiro se este profissional foi recusado por este cliente dentro do prazo de bloqueio.
  final bool bloqueadoRecusa;

  /// Quando o bloqueio termina (só preenchido com bloqueio ativo).
  final DateTime? bloqueadoAte;
}

/// Motivos para recusar um pedido (escopo 6.2).
enum MotivoRecusa {
  foraDaRegiao('Fora da minha região'),
  semAgenda('Sem agenda'),
  foraDoEscopo('Fora do meu escopo');

  const MotivoRecusa(this.texto);

  final String texto;
}
