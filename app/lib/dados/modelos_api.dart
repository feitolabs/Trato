/// Modelos das respostas da API (`backend/src/trato/api/modelos.py`), escritos à mão.
/// Dinheiro sempre em centavos inteiros. Só leitura de JSON; nenhuma regra aqui.
library;

DateTime _data(Object? valor) => DateTime.parse(valor! as String);
DateTime? _dataOuNulo(Object? valor) => valor == null ? null : DateTime.parse(valor as String);

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
  });

  factory PedidoApi.deJson(Map<String, dynamic> j) => PedidoApi(
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

  /// Número curto para exibir ("#4F2A"): só os 4 primeiros caracteres do id.
  String get numero => '#${id.substring(0, id.length < 4 ? id.length : 4).toUpperCase()}';
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
    required this.taxaTratoCentavos,
  });

  factory SaldoPedidoApi.deJson(Map<String, dynamic> j) => SaldoPedidoApi(
        clientePagouCentavos: j['cliente_pagou_centavos'] as int,
        retidoCentavos: j['retido_centavos'] as int,
        aLiberarCentavos: j['a_liberar_centavos'] as int,
        liberadoCentavos: j['liberado_centavos'] as int,
        taxaTratoCentavos: j['taxa_trato_centavos'] as int,
      );

  final int clientePagouCentavos;
  final int retidoCentavos;
  final int aLiberarCentavos;
  final int liberadoCentavos;
  final int taxaTratoCentavos;
}

class LancamentoApi {
  const LancamentoApi({
    required this.id,
    required this.pedidoId,
    required this.tipo,
    required this.valorCentavos,
    required this.data,
    required this.estornoDe,
  });

  factory LancamentoApi.deJson(Map<String, dynamic> j) => LancamentoApi(
        id: j['id'] as String,
        pedidoId: j['pedido_id'] as String,
        tipo: j['tipo'] as String,
        valorCentavos: j['valor_centavos'] as int,
        data: _data(j['data']),
        estornoDe: j['estorno_de'] as String?,
      );

  final String id;
  final String pedidoId;
  final String tipo;
  final int valorCentavos;
  final DateTime data;
  final String? estornoDe;
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
