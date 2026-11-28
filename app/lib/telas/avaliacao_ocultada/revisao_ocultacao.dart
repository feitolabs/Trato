/// Termos 11.8: quem escreveu a avaliação ocultada pede a revisão pelo app. Quem decide, o
/// protocolo, o prazo e a resposta vêm do servidor.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';

/// Limites de `justificativa` na rota.
const minimoDaJustificativa = 10;
const maximoDaJustificativa = 2000;

class PedidoDeRevisao {
  const PedidoDeRevisao({this.protocolo, this.status = '', this.responderAte, this.resposta});

  factory PedidoDeRevisao.deJson(Map<dynamic, dynamic> j) {
    String? texto(String chave) {
      final v = j[chave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return PedidoDeRevisao(
      protocolo: texto('protocolo'),
      status: texto('status') ?? '',
      responderAte: DateTime.tryParse(texto('responder_ate') ?? '')?.toLocal(),
      resposta: texto('resposta'),
    );
  }

  final String? protocolo;
  final String status;
  final DateTime? responderAte;
  final String? resposta;

  bool get decidido => status == 'aceita' || status == 'recusada';

  String get situacao => switch (status) {
        'aberta' => 'Pedido recebido',
        'em_analise' => 'Em análise',
        'aceita' => 'Pedido aceito',
        'recusada' => 'Pedido recusado',
        _ => 'Situação não informada',
      };
}

/// O que o servidor sabe do pedido desta avaliação. [disponivel] falso: servidor sem a consulta.
class ConsultaDeRevisao {
  const ConsultaDeRevisao({this.disponivel = true, this.pedido});

  final bool disponivel;
  final PedidoDeRevisao? pedido;
}

abstract interface class ServicoRevisaoOcultacao {
  Future<ConsultaDeRevisao> consultar(String avaliacaoId);
  Future<PedidoDeRevisao> pedir(String avaliacaoId, String justificativa);
}

class ServicoRevisaoOcultacaoApi implements ServicoRevisaoOcultacao {
  ServicoRevisaoOcultacaoApi(this._api);

  final ClienteApi _api;

  /// `GET /v1/me/avaliacoes/revisoes`: prefere o pedido em andamento desta avaliação.
  @override
  Future<ConsultaDeRevisao> consultar(String avaliacaoId) async {
    try {
      final j = await _api.get('/v1/me/avaliacoes/revisoes', consulta: {'limite': '100'});
      final itens = j is Map ? j['itens'] : null;
      final pedidos = [
        if (itens is List)
          for (final i in itens)
            if (i is Map &&
                i['avaliacao_id'] == avaliacaoId &&
                i['tipo'] == 'contestacao_ocultacao')
              PedidoDeRevisao.deJson(i),
      ];
      return ConsultaDeRevisao(
        pedido: pedidos.where((p) => !p.decidido).firstOrNull ?? pedidos.firstOrNull,
      );
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) {
        return const ConsultaDeRevisao(disponivel: false);
      }
      rethrow;
    }
  }

  /// `POST /v1/avaliacoes/{id}/revisoes`. Repetir com um pedido em andamento devolve o mesmo.
  @override
  Future<PedidoDeRevisao> pedir(String avaliacaoId, String justificativa) async {
    final j = await _api.post(
      '/v1/avaliacoes/${Uri.encodeComponent(avaliacaoId)}/revisoes',
      corpo: {'tipo': 'contestacao_ocultacao', 'justificativa': justificativa.trim()},
    );
    return PedidoDeRevisao.deJson(j is Map ? j : const {});
  }
}

class RevisaoOcultacaoTela extends StatelessWidget {
  const RevisaoOcultacaoTela({super.key, required this.servico, required this.avaliacaoId});

  final ServicoRevisaoOcultacao servico;
  final String avaliacaoId;

  @override
  Widget build(BuildContext context) => MolduraTelaComum(
        titulo: 'Avaliação ocultada',
        child: CarregadorTela<ConsultaDeRevisao>(
          carregar: () => servico.consultar(avaliacaoId),
          construir: (context, consulta, _) => _Conteudo(
            servico: servico,
            avaliacaoId: avaliacaoId,
            consulta: consulta,
          ),
        ),
      );
}

class _Conteudo extends StatefulWidget {
  const _Conteudo({required this.servico, required this.avaliacaoId, required this.consulta});

  final ServicoRevisaoOcultacao servico;
  final String avaliacaoId;
  final ConsultaDeRevisao consulta;

  @override
  State<_Conteudo> createState() => _ConteudoState();
}

class _ConteudoState extends State<_Conteudo> {
  final _texto = TextEditingController();
  PedidoDeRevisao? _enviado;
  var _enviando = false;
  String? _erroDoCampo;
  String? _erroDoEnvio;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final justificativa = _texto.text.trim();
    if (justificativa.length < minimoDaJustificativa) {
      setState(() => _erroDoCampo =
          'Explique o motivo com pelo menos $minimoDaJustificativa caracteres.');
      return;
    }
    setState(() {
      _enviando = true;
      _erroDoCampo = null;
      _erroDoEnvio = null;
    });
    try {
      final pedido = await widget.servico.pedir(widget.avaliacaoId, justificativa);
      if (mounted) setState(() => _enviado = pedido);
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erroDoEnvio = e.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erroDoEnvio = 'Não foi possível enviar o pedido. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  static String _data(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    if (!widget.consulta.disponivel) {
      return ListView(
        children: [
          Text(
            'O pedido de revisão pelo app está indisponível agora. '
            'Você também pode falar com o atendimento do Trato.',
            style: corpo,
          ),
        ],
      );
    }
    final pedido = _enviado ?? widget.consulta.pedido;
    // Pedido em andamento (ou recém-enviado): não há outro para mandar.
    final mostrarFormulario = _enviado == null && (pedido == null || pedido.decidido);
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        if (pedido != null) ...[
          CartaoTrato(
            key: const ValueKey('revisao-pedida'),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pedido.situacao, style: TipografiaTrato.tituloCartao),
                  if (pedido.protocolo != null)
                    Text('Protocolo ${pedido.protocolo}', style: corpo),
                  if (!pedido.decidido && pedido.responderAte != null)
                    Text('Resposta prevista até ${_data(pedido.responderAte!)}.', style: corpo),
                  if (pedido.resposta != null) Text(pedido.resposta!, style: corpo),
                ],
              ),
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
        ],
        if (mostrarFormulario) ...[
          Text(
            'Uma avaliação que você escreveu foi ocultada. O motivo está no aviso. '
            'Para pedir a revisão, explique por que você discorda.',
            style: corpo,
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('justificativa-revisao'),
            controller: _texto,
            enabled: !_enviando,
            minLines: 4,
            maxLines: 8,
            maxLength: maximoDaJustificativa,
            onChanged: (_) {
              if (_erroDoCampo != null) setState(() => _erroDoCampo = null);
            },
            decoration: InputDecoration(
              labelText: 'Por que você discorda',
              alignLabelWithHint: true,
              errorText: _erroDoCampo,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          if (_erroDoEnvio != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(_erroDoEnvio!, style: corpo.copyWith(color: c.vermelhoTexto)),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          BotaoPrimario(
            texto: _enviando ? 'Enviando...' : 'Pedir revisão',
            aoTocar: _enviando ? null : _enviar,
          ),
        ],
      ],
    );
  }
}
