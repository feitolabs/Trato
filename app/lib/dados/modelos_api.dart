/// Modelos das respostas da API (`backend/src/trato/api/modelos.py`), escritos à mão.
/// Dinheiro sempre em centavos inteiros. Só leitura de JSON; nenhuma regra aqui.
library;

import '../telas/comuns/formato_aparelho.dart';

DateTime _data(Object? valor) => DateTime.parse(valor! as String).toLocal();
DateTime? _dataOuNulo(Object? valor) =>
    valor == null ? null : DateTime.parse(valor as String).toLocal();

class PedidoApi {
  const PedidoApi({
    required this.id,
    required this.estado,
    required this.estadoNome,
    required this.clienteId,
    required this.profissionalId,
    required this.abertoEm,
    required this.concluidoEm,
    required this.acoesPermitidas,
    required this.codigoInicio,
    required this.codigoConclusao,
    this.janelaInicio,
    this.janelaFim,
    this.modalidade = 'presencial',
    this.jaAvaliou = false,
    this.titulo,
    this.categoriaNome,
    this.descricao,
    this.clienteNome,
    this.profissionalNome,
    this.pagamentoConfirmado = false,
    this.contratadoEm,
    this.checkOutSemCodigo = false,
    this.urgente = false,
  });

  /// Verdadeiro quando o profissional concluiu o check-out sem código (Plano B).
  final bool checkOutSemCodigo;

  /// Pedido marcado como urgente pelo cliente.
  final bool urgente;

  /// Quando o cliente aceitou o orçamento.
  final DateTime? contratadoEm;

  /// Só o webhook do parceiro de pagamento deixa isto verdadeiro.
  final bool pagamentoConfirmado;

  /// O que o cliente pediu ("Montagem de móveis"). Nulo em servidor antigo.
  final String? titulo;

  /// Nome da categoria (`categoria_nome`, opcional). Quando vem, é o título do pedido: o
  /// `titulo` pode ser o nome da pergunta ("Orçamento geral").
  final String? categoriaNome;

  /// O que o cliente descreveu (`descricao`, opcional na lista); subtítulo na lista de pedidos.
  final String? descricao;

  /// Nome abreviado do cliente ("Mariana S."); só vem para o profissional do pedido.
  final String? clienteNome;

  /// Nome abreviado do profissional contratado ("Carlos M."); só vem para o cliente do pedido.
  final String? profissionalNome;

  /// Título para mostrar: o do serviço, ou "Pedido #AB12" quando não houver.
  String get rotulo {
    final c = categoriaNome?.trim() ?? '';
    final t = c.isNotEmpty ? c : (titulo?.trim() ?? '');
    return t.isEmpty ? 'Pedido $numero' : t;
  }

  /// Quem consultou já avaliou este serviço (o app não oferece "Avaliar" de novo).
  final bool jaAvaliou;

  /// `presencial` ou `remoto`.
  final String modalidade;

  bool get remoto => modalidade == 'remoto';

  factory PedidoApi.deJson(Map<String, dynamic> j) => PedidoApi(
        modalidade: (j['modalidade'] as String?) ?? 'presencial',
        jaAvaliou: j['ja_avaliou'] == true,
        titulo: j['titulo'] as String?,
        categoriaNome: j['categoria_nome'] as String?,
        descricao: j['descricao'] as String?,
        clienteNome: j['cliente_nome'] as String?,
        profissionalNome: j['profissional_nome'] as String?,
        pagamentoConfirmado: j['pagamento_confirmado'] == true,
        contratadoEm: _dataOuNulo(j['contratado_em']),
        janelaInicio: _dataOuNulo((j['janela'] as Map<String, dynamic>?)?['inicio']),
        janelaFim: _dataOuNulo((j['janela'] as Map<String, dynamic>?)?['fim']),
        id: j['id'] as String,
        estado: j['estado'] as String,
        estadoNome: j['estado_nome'] as String,
        clienteId: j['cliente_id'] as String,
        profissionalId: j['profissional_id'] as String?,
        abertoEm: _data(j['aberto_em']),
        concluidoEm: _dataOuNulo(j['concluido_em']),
        acoesPermitidas: [for (final a in (j['acoes_permitidas'] as List)) a as String],
        codigoInicio: j['codigo_inicio'] as String?,
        codigoConclusao: j['codigo_conclusao'] as String?,
        checkOutSemCodigo: j['check_out_sem_codigo'] == true,
        urgente: j['urgente'] == true,
      );

  final String id;
  final String estado;
  final String estadoNome;
  final String clienteId;
  final String? profissionalId;
  final DateTime abertoEm;
  final DateTime? concluidoEm;
  final List<String> acoesPermitidas;
  final String? codigoInicio;
  final String? codigoConclusao;

  /// Janela da visita combinada (só existe depois de `confirmar_agenda`).
  final DateTime? janelaInicio;
  final DateTime? janelaFim;

  /// "06/11 · 9:00 AM às 11:00 AM" (ou 24 h), no horário e no formato do aparelho; nulo se a
  /// visita não foi marcada.
  String? get janelaRotulo {
    final i = janelaInicio;
    final f = janelaFim;
    if (i == null) return null;
    final inicio = '${diaMesDoAparelho(i)} · ${horaDoAparelho(i)}';
    return f == null ? inicio : '$inicio às ${horaDoAparelho(f)}';
  }

  /// Número curto para exibir ("#4F2A"): só os 4 primeiros caracteres do id.
  String get numero => numeroDe(id);

  /// "#AB12": as 4 primeiras letras do id. Só para mostrar.
  static String numeroDe(String id) =>
      '#${id.substring(0, id.length < 4 ? id.length : 4).toUpperCase()}';
}

class EventoApi {
  const EventoApi({required this.acao, required this.para, required this.em});

  factory EventoApi.deJson(Map<String, dynamic> j) =>
      EventoApi(acao: j['acao'] as String, para: j['para'] as String, em: _data(j['em']));

  final String acao;
  final String para;
  final DateTime em;
}

class SaldoPedidoApi {
  const SaldoPedidoApi({
    required this.clientePagouCentavos,
    required this.retidoCentavos,
    required this.aLiberarCentavos,
    required this.liberadoCentavos,
  });

  factory SaldoPedidoApi.deJson(Map<String, dynamic> j) => SaldoPedidoApi(
        clientePagouCentavos: j['cliente_pagou_centavos'] as int,
        retidoCentavos: j['retido_centavos'] as int,
        aLiberarCentavos: j['a_liberar_centavos'] as int,
        liberadoCentavos: j['liberado_centavos'] as int,
      );

  final int clientePagouCentavos;
  final int retidoCentavos;
  final int aLiberarCentavos;
  final int liberadoCentavos;
}

class LancamentoApi {
  const LancamentoApi({
    required this.id,
    required this.pedidoId,
    required this.tipo,
    required this.valorCentavos,
    required this.data,
    required this.estornoDe,
    this.contaDebito,
    this.contaCredito,
  });

  factory LancamentoApi.deJson(Map<String, dynamic> j) => LancamentoApi(
        id: j['id'] as String,
        pedidoId: j['pedido_id'] as String,
        tipo: j['tipo'] as String,
        valorCentavos: j['valor_centavos'] as int,
        data: _data(j['data']),
        estornoDe: j['estorno_de'] as String?,
        contaDebito: _tipoDaConta(j['debito']),
        contaCredito: _tipoDaConta(j['credito']),
      );

  static String? _tipoDaConta(Object? conta) =>
      conta is Map && conta['tipo'] is String ? conta['tipo'] as String : null;

  final String id;
  final String pedidoId;
  final String tipo;
  final int valorCentavos;
  final DateTime data;
  final String? estornoDe;

  /// Tipo das contas do lançamento (`debito.tipo` e `credito.tipo`).
  final String? contaDebito;
  final String? contaCredito;

  /// Desconto de uma compensação no repasse (Termos 8.6 e 17.4).
  bool get ehCompensacao => contaCredito == 'a_compensar';

  /// Devolução de um desconto, quando a compensação é cancelada.
  bool get ehCompensacaoDevolvida => contaDebito == 'a_compensar';
}

class ExclusividadeApi {
  const ExclusividadeApi({
    required this.id,
    required this.pedidoId,
    required this.clienteId,
    required this.status,
    required this.moedasCobradas,
    required this.criadaEm,
    this.responderAte,
    this.respondidaEm,
    this.expiraEm,
    this.encerradaEm,
    this.saldoRestante,
    this.bloqueadoAte,
    this.pagador = 'profissional',
  });

  factory ExclusividadeApi.deJson(Map<String, dynamic> j) => ExclusividadeApi(
        id: j['id'] as String,
        pedidoId: j['pedido_id'] as String,
        clienteId: (j['cliente_id'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'aguardando_cliente',
        moedasCobradas: (j['moedas_cobradas'] as num?)?.toInt() ?? 100,
        criadaEm: _data(j['criada_em']),
        responderAte: _dataOuNulo(j['responder_ate']),
        respondidaEm: _dataOuNulo(j['respondida_em']),
        expiraEm: _dataOuNulo(j['expira_em']),
        encerradaEm: _dataOuNulo(j['encerrada_em']),
        saldoRestante: (j['saldo_restante'] as num?)?.toInt(),
        bloqueadoAte: DateTime.tryParse('${j['bloqueado_ate'] ?? ''}'),
        pagador: (j['pagador'] as String?) ?? 'profissional',
      );

  /// `cliente` (Termos 13.6) ou `profissional` (modelo antigo).
  final String pagador;

  final String id;
  final String pedidoId;
  final String clienteId;
  final String status;
  final int moedasCobradas;
  final DateTime criadaEm;
  final DateTime? responderAte;
  final DateTime? respondidaEm;
  final DateTime? expiraEm;
  final DateTime? encerradaEm;
  final int? saldoRestante;

  /// Fim do bloqueio depois de uma recusa (só em `recusada`). Pode já ter passado.
  final DateTime? bloqueadoAte;
}

class ListaExclusividadesApi {
  const ListaExclusividadesApi({
    required this.itens,
    required this.ativasOuPendentes,
    required this.limiteMaximo,
    required this.saldoProfissional,
  });

  factory ListaExclusividadesApi.deJson(Map<String, dynamic> j) => ListaExclusividadesApi(
        itens: [
          for (final item in (j['itens'] as List? ?? const []))
            if (item is Map<String, dynamic>)
              ExclusividadeApi.deJson(item)
            else if (item is Map)
              ExclusividadeApi.deJson(Map<String, dynamic>.from(item)),
        ],
        ativasOuPendentes: (j['ativas_ou_pendentes'] as num?)?.toInt() ?? 0,
        limiteMaximo: (j['limite_maximo'] as num?)?.toInt() ?? 3,
        saldoProfissional: (j['saldo_profissional'] as num?)?.toInt() ?? 0,
      );

  final List<ExclusividadeApi> itens;
  final int ativasOuPendentes;
  final int limiteMaximo;
  final int saldoProfissional;
}

class OfertaExclusividadeApi {
  const OfertaExclusividadeApi({
    required this.id,
    required this.pedidoId,
    required this.profissionalId,
    required this.status,
    this.profissionalNome,
    this.notaPublica,
    this.responderAte,
    this.expiraEm,
    this.texto = 'Sem compromisso',
  });

  factory OfertaExclusividadeApi.deJson(Map<String, dynamic> j) => OfertaExclusividadeApi(
        id: j['id'] as String,
        pedidoId: j['pedido_id'] as String,
        profissionalId: (j['profissional_id'] as String?) ?? '',
        profissionalNome: j['profissional_nome'] as String?,
        notaPublica: (j['nota_publica'] as num?)?.toDouble(),
        status: (j['status'] as String?) ?? 'aguardando_cliente',
        responderAte: _dataOuNulo(j['responder_ate']),
        expiraEm: _dataOuNulo(j['expira_em']),
        texto: (j['texto'] as String?) ?? 'Sem compromisso',
      );

  final String id;
  final String pedidoId;
  final String profissionalId;
  final String? profissionalNome;
  final double? notaPublica;
  final String status;
  final DateTime? responderAte;
  final DateTime? expiraEm;
  final String texto;
}

class RespostaExclusividadeApi {
  const RespostaExclusividadeApi({
    required this.id,
    required this.pedidoId,
    required this.status,
    required this.pedidoEstado,
    this.expiraEm,
    this.outrosOrcamentosContinuamVisiveis = true,
  });

  factory RespostaExclusividadeApi.deJson(Map<String, dynamic> j) => RespostaExclusividadeApi(
        id: j['id'] as String,
        pedidoId: j['pedido_id'] as String,
        status: (j['status'] as String?) ?? 'recusada',
        expiraEm: _dataOuNulo(j['expira_em']),
        pedidoEstado: (j['pedido_estado'] as String?) ?? 'aberto',
        outrosOrcamentosContinuamVisiveis: j['outros_orcamentos_continuam_visiveis'] != false,
      );

  final String id;
  final String pedidoId;
  final String status;
  final DateTime? expiraEm;
  final String pedidoEstado;
  final bool outrosOrcamentosContinuamVisiveis;
}

class ExtratoApi {
  const ExtratoApi({required this.itens, required this.total});

  factory ExtratoApi.deJson(Map<String, dynamic> j) => ExtratoApi(
        itens: [
          for (final i in (j['itens'] as List)) LancamentoApi.deJson(i as Map<String, dynamic>),
        ],
        total: j['total'] as int,
      );

  final List<LancamentoApi> itens;
  final int total;
}
