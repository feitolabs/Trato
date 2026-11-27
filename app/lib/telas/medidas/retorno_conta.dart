/// Termos 20.9: quem teve a conta encerrada pede o retorno e acompanha. Prazo, elegibilidade e
/// decisão são do servidor (`/v1/me/conta/retorno`): o app só pede e mostra.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';

const _semFuncao = 'O pedido de retorno pelo app ainda não está disponível. Fale com o Trato.';

const justificativaMinima = 10;
const justificativaMaxima = 4000;

/// Um pedido de retorno. Campo ausente vira vazio.
class PedidoRetorno {
  const PedidoRetorno({
    this.id = '',
    this.protocolo = '',
    this.justificativa = '',
    this.status = '',
    this.solicitadoEm,
    this.prazoDias,
    this.elegivelAPartirDe,
    this.decisaoMotivo,
    this.decididoEm,
  });

  factory PedidoRetorno.deJson(Map<Object?, Object?> json) {
    String? texto(String chave) {
      final v = json[chave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    DateTime? data(String chave) => DateTime.tryParse(texto(chave) ?? '')?.toLocal();
    final prazo = json['prazo_dias_aplicado'];

    return PedidoRetorno(
      id: texto('id') ?? '',
      protocolo: texto('protocolo') ?? '',
      justificativa: texto('justificativa_usuario') ?? '',
      status: texto('status') ?? '',
      solicitadoEm: data('solicitado_em'),
      prazoDias: prazo is int && prazo >= 0 ? prazo : null,
      elegivelAPartirDe: data('elegivel_a_partir_de'),
      decisaoMotivo: texto('decisao_motivo'),
      decididoEm: data('decidido_em'),
    );
  }

  final String id;
  final String protocolo;
  final String justificativa;
  final String status;
  final DateTime? solicitadoEm;
  final int? prazoDias;
  final DateTime? elegivelAPartirDe;
  final String? decisaoMotivo;
  final DateTime? decididoEm;

  bool get emAndamento => status == 'aberto' || status == 'em_analise';
}

abstract interface class ServicoRetornoConta {
  /// Nulo: o servidor não tem a função (404/503).
  Future<List<PedidoRetorno>?> listarRetornos();

  Future<PedidoRetorno> pedirRetorno(String justificativa);
}

String _data(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';

(String, TipoStatus) _situacao(String status) => switch (status) {
      'aberto' => ('Pedido recebido', TipoStatus.info),
      'em_analise' => ('Em análise', TipoStatus.info),
      'aprovado' => ('Aprovado', TipoStatus.sucesso),
      'recusado' => ('Recusado', TipoStatus.perigo),
      _ => ('Situação não informada', TipoStatus.info),
    };

class RetornoContaTela extends StatelessWidget {
  const RetornoContaTela({super.key, required this.servico});

  final ServicoRetornoConta servico;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Retorno da conta',
      child: CarregadorTela<List<PedidoRetorno>?>(
        carregar: servico.listarRetornos,
        construir: (context, pedidos, recarregar) => pedidos == null
            ? EstadoVazio(
                icone: Icons.info_outline,
                titulo: 'Ainda não disponível',
                texto: _semFuncao,
                textoAcao: 'Tentar de novo',
                aoAcao: recarregar,
              )
            : _Conteudo(servico: servico, pedidos: pedidos, recarregar: recarregar),
      ),
    );
  }
}

class _Conteudo extends StatefulWidget {
  const _Conteudo({required this.servico, required this.pedidos, required this.recarregar});

  final ServicoRetornoConta servico;
  final List<PedidoRetorno> pedidos;
  final VoidCallback recarregar;

  @override
  State<_Conteudo> createState() => _ConteudoState();
}

class _ConteudoState extends State<_Conteudo> {
  final _justificativa = TextEditingController();
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _justificativa.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _justificativa.text.trim();
    if (texto.length < justificativaMinima) {
      setState(() => _erro = 'Escreva pelo menos $justificativaMinima caracteres.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final pedido = await widget.servico.pedirRetorno(texto);
      if (!mounted) return;
      final protocolo = pedido.protocolo.isEmpty ? '' : ' Protocolo ${pedido.protocolo}.';
      messenger.showSnackBar(
        SnackBar(content: Text('Pedido de retorno registrado.$protocolo')),
      );
      widget.recarregar();
    } on Object catch (e) {
      if (!mounted) return;
      final semFuncao = e is ErroTrato && (e.codigoHttp == 404 || e.codigoHttp == 503);
      setState(() {
        _enviando = false;
        _erro = semFuncao
            ? _semFuncao
            : e is ErroTrato
                ? e.mensagem
                : 'Não foi possível enviar o pedido. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final podeEscrever = !widget.pedidos.any((p) => p.emAndamento || p.status == 'aprovado');
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x8),
      children: [
        Text(
          'Se a sua conta foi encerrada sem infração grave, você pode pedir para voltar depois '
          'do prazo mínimo. O Trato analisa caso a caso e o pedido pode ser recusado.',
          style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (widget.pedidos.isEmpty)
          Text(
            'Você ainda não pediu o retorno.',
            style: TipografiaTrato.corpo.copyWith(color: c.texto),
          ),
        for (final p in widget.pedidos) ...[
          _CartaoRetorno(p),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (podeEscrever) ...[
          const SizedBox(height: EspacosTrato.x4),
          Text(
            'Por que você quer voltar?',
            style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
          ),
          const SizedBox(height: EspacosTrato.x2),
          TextField(
            key: const ValueKey('justificativa-retorno'),
            controller: _justificativa,
            enabled: !_enviando,
            minLines: 4,
            maxLines: 8,
            maxLength: justificativaMaxima,
            decoration: const InputDecoration(hintText: 'Explique o seu pedido'),
          ),
          const SizedBox(height: EspacosTrato.x3),
          if (_erro != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                _erro!,
                key: const ValueKey('erro-retorno'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
              ),
            ),
            const SizedBox(height: EspacosTrato.x3),
          ],
          BotaoPrimario(
            key: const ValueKey('botao-enviar-retorno'),
            texto: 'Pedir retorno',
            carregando: _enviando,
            aoTocar: _enviar,
          ),
        ],
      ],
    );
  }
}

class _CartaoRetorno extends StatelessWidget {
  const _CartaoRetorno(this.pedido);

  final PedidoRetorno pedido;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (situacao, tipo) = _situacao(pedido.status);
    final corpo = TipografiaTrato.corpoPequeno.copyWith(color: c.texto);
    return CartaoTrato(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChipStatus(texto: situacao, tipo: tipo),
            const SizedBox(height: EspacosTrato.x2),
            SelectableText(
              'Protocolo: ${pedido.protocolo.isEmpty ? 'não informado' : pedido.protocolo}',
              style: corpo,
            ),
            if (pedido.solicitadoEm != null)
              Text('Pedido em ${_data(pedido.solicitadoEm!)}', style: corpo),
            if (pedido.prazoDias != null)
              Text('Prazo mínimo aplicado: ${pedido.prazoDias} dias', style: corpo),
            if (pedido.elegivelAPartirDe != null)
              Text('Podia pedir a partir de ${_data(pedido.elegivelAPartirDe!)}', style: corpo),
            if (pedido.justificativa.isNotEmpty) ...[
              const SizedBox(height: EspacosTrato.x3),
              Text('O que você escreveu', style: corpo.copyWith(fontWeight: FontWeight.w600)),
              Text(pedido.justificativa, style: corpo),
            ],
            if (pedido.decididoEm != null || pedido.decisaoMotivo != null) ...[
              const SizedBox(height: EspacosTrato.x3),
              Text(
                pedido.decididoEm == null ? 'Decisão' : 'Decisão em ${_data(pedido.decididoEm!)}',
                style: corpo.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(pedido.decisaoMotivo ?? 'Motivo não informado.', style: corpo),
            ],
          ],
        ),
      ),
    );
  }
}
