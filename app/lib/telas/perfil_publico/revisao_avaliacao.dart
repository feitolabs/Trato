/// Termos 12.7: quem foi avaliado pede a revisão da avaliação pelo app. Quem decide é o Trato.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';

/// Os mesmos limites que o servidor aceita na justificativa.
const justificativaRevisaoMinima = 10;
const justificativaRevisaoMaxima = 2000;

/// Um pedido de revisão como o servidor informa.
class PedidoRevisaoAvaliacao {
  const PedidoRevisaoAvaliacao({
    required this.avaliacaoId,
    this.protocolo = '',
    this.status = '',
    this.abertaEm,
    this.responderAte,
    this.resposta,
  });

  final String avaliacaoId;
  final String protocolo;
  final String status;
  final DateTime? abertaEm;
  final DateTime? responderAte;
  final String? resposta;

  /// Ainda sem decisão.
  bool get emAndamento => status == 'aberta' || status == 'em_analise';

  String get situacao => switch (status) {
        'aberta' => 'Enviado',
        'em_analise' => 'Em análise',
        'aceita' => 'Aceito',
        'recusada' => 'Recusado',
        _ => 'Situação não informada',
      };

  /// Nulo: não é um pedido de revisão (ou veio sem a avaliação).
  static PedidoRevisaoAvaliacao? deJson(Object? json) {
    if (json is! Map) return null;
    final id = json['avaliacao_id'];
    if (id is! String || id.isEmpty) return null;
    // `contestacao_ocultacao` é de quem escreveu a avaliação: não é desta tela.
    if (json['tipo'] != null && json['tipo'] != 'revisao') return null;
    String texto(String chave) => json[chave] is String ? (json[chave] as String).trim() : '';
    final resposta = texto('resposta');
    return PedidoRevisaoAvaliacao(
      avaliacaoId: id,
      protocolo: texto('protocolo'),
      status: texto('status'),
      abertaEm: DateTime.tryParse(texto('aberta_em')),
      responderAte: DateTime.tryParse(texto('responder_ate')),
      resposta: resposta.isEmpty ? null : resposta,
    );
  }
}

abstract interface class RevisaoDeAvaliacao {
  /// Nulo: o servidor não tem a função (ou está indisponível): a tela não mostra nada dela.
  Future<List<PedidoRevisaoAvaliacao>?> pedidosDeRevisao();

  Future<void> pedirRevisao(String avaliacaoId, String justificativa);
}

/// O pedido que vale mostrar numa avaliação: o em andamento ou, sem ele, o mais recente.
PedidoRevisaoAvaliacao? pedidoDaAvaliacao(List<PedidoRevisaoAvaliacao> pedidos, String id) {
  PedidoRevisaoAvaliacao? escolhido;
  for (final p in pedidos.where((p) => p.avaliacaoId == id)) {
    if (p.emAndamento) return p;
    final antes = escolhido?.abertaEm;
    if (escolhido == null || (antes != null && (p.abertaEm?.isAfter(antes) ?? false))) {
      escolhido = p;
    }
  }
  return escolhido;
}

String _dia(DateTime data) {
  final d = data.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year}';
}

/// Pé do cartão da avaliação: situação do pedido e o botão "Pedir revisão".
class SecaoRevisaoAvaliacao extends StatelessWidget {
  const SecaoRevisaoAvaliacao({
    super.key,
    required this.avaliacaoId,
    required this.pedido,
    required this.aoPedir,
  });

  final String avaliacaoId;
  final PedidoRevisaoAvaliacao? pedido;
  final VoidCallback aoPedir;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final c = context.cores;
    final pequeno = TipografiaTrato.corpoPequeno.copyWith(color: c.texto);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Column(
            key: ValueKey('revisao-situacao-$avaliacaoId'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pedido de revisão: ${p.situacao}',
                style: pequeno.copyWith(fontWeight: FontWeight.w700),
              ),
              if (p.protocolo.isNotEmpty) Text('Protocolo ${p.protocolo}', style: pequeno),
              if (p.emAndamento && p.responderAte != null)
                Text('Resposta prevista até ${_dia(p.responderAte!)}', style: pequeno),
              if (p.resposta != null) Text('Resposta do Trato: ${p.resposta}', style: pequeno),
            ],
          ),
        ],
        if (!(p?.emAndamento ?? false))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey('pedir-revisao-$avaliacaoId'),
              onPressed: aoPedir,
              child: const Text('Pedir revisão'),
            ),
          ),
      ],
    );
  }
}

/// Folha para escrever o motivo. Fecha com `true` quando o servidor aceita o pedido.
class FolhaPedirRevisao extends StatefulWidget {
  const FolhaPedirRevisao({super.key, required this.aoEnviar});

  final Future<void> Function(String justificativa) aoEnviar;

  @override
  State<FolhaPedirRevisao> createState() => _FolhaPedirRevisaoState();
}

class _FolhaPedirRevisaoState extends State<FolhaPedirRevisao> {
  final _ctrl = TextEditingController();
  var _enviando = false;
  String? _erroCampo;
  String? _erroEnvio;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = _ctrl.text.trim();
    if (texto.length < justificativaRevisaoMinima) {
      setState(() {
        _erroCampo = 'Explique o motivo com pelo menos $justificativaRevisaoMinima caracteres.';
        _erroEnvio = null;
      });
      return;
    }
    setState(() {
      _enviando = true;
      _erroCampo = null;
      _erroEnvio = null;
    });
    try {
      await widget.aoEnviar(texto);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      final indisponivel = e is ErroTrato &&
          (e.codigoHttp == 503 || (e.codigoHttp == 404 && e.mensagem == 'Not Found'));
      setState(() {
        _enviando = false;
        _erroEnvio = indisponivel
            ? 'O pedido de revisão está indisponível agora. Tente mais tarde ou fale com o '
                'atendimento.'
            : e is ErroTrato
                ? e.mensagem
                : 'Não foi possível enviar agora. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: EspacosTrato.x5,
          right: EspacosTrato.x5,
          top: EspacosTrato.x5,
          bottom: MediaQuery.of(context).viewInsets.bottom + EspacosTrato.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pedir revisão', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'Conte por que esta avaliação deve ser revista. O Trato analisa e responde.',
              style: TipografiaTrato.corpo.copyWith(color: c.texto),
            ),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              key: const ValueKey('campo-revisao-avaliacao'),
              controller: _ctrl,
              enabled: !_enviando,
              minLines: 3,
              maxLines: 6,
              maxLength: justificativaRevisaoMaxima,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: InputDecoration(
                hintText: 'Motivo do pedido',
                errorText: _erroCampo,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: EspacosTrato.x3),
            if (_erroEnvio != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _erroEnvio!,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
                ),
              ),
              const SizedBox(height: EspacosTrato.x2),
            ],
            BotaoPrimario(
              key: const ValueKey('botao-enviar-revisao'),
              texto: 'Enviar pedido',
              carregando: _enviando,
              aoTocar: _enviando ? null : _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
