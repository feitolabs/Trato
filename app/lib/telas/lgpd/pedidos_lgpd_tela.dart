import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart' show AtualizadorTela;
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'modelos.dart';

const _semFuncao = 'Os pedidos pelo app ainda não estão disponíveis. Fale com o Encarregado de '
    'dados: veja como em "Termos e políticas".';

String _data(DateTime momento) {
  final t = momento.toLocal();
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
}

(String, TipoStatus) _situacao(String status) => switch (status) {
      'aberto' => ('Recebido', TipoStatus.info),
      'em_analise' => ('Em análise', TipoStatus.info),
      'aguardando_titular' => ('Aguardando você', TipoStatus.alerta),
      'atendido' => ('Atendido', TipoStatus.sucesso),
      'atendido_parcial' => ('Atendido em parte', TipoStatus.alerta),
      'negado' => ('Não atendido', TipoStatus.perigo),
      _ => ('Situação não informada', TipoStatus.info),
    };

/// Termos 14.9 e 14.10: a pessoa abre e acompanha pedidos sobre os próprios dados. Igual para
/// cliente e profissional. Prazo, situação e resposta vêm do backend.
class PedidosLgpdTela extends StatelessWidget {
  const PedidosLgpdTela({super.key, required this.servico});

  final PedidosDoTitular servico;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Pedidos sobre dados',
      child: CarregadorTela<PaginaPedidosLgpd?>(
        carregar: servico.listarPedidosLgpd,
        construir: (context, pagina, recarregar) {
          if (pagina == null) {
            return EstadoVazio(
              icone: Icons.info_outline,
              titulo: 'Ainda não disponível',
              texto: _semFuncao,
              textoAcao: 'Tentar de novo',
              aoAcao: recarregar,
            );
          }
          return _Lista(servico: servico, pagina: pagina, recarregar: recarregar);
        },
      ),
    );
  }
}

class _Lista extends StatefulWidget {
  const _Lista({required this.servico, required this.pagina, required this.recarregar});

  final PedidosDoTitular servico;
  final PaginaPedidosLgpd pagina;
  final VoidCallback recarregar;

  @override
  State<_Lista> createState() => _ListaState();
}

class _ListaState extends State<_Lista> {
  /// Páginas buscadas em "Ver mais", depois da primeira.
  final _mais = <PedidoLgpd>[];
  var _fim = false;
  var _buscando = false;
  String? _erroMais;

  List<PedidoLgpd> get _itens => [...widget.pagina.itens, ..._mais];

  @override
  void didUpdateWidget(covariant _Lista antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.pagina != widget.pagina) {
      _mais.clear();
      _fim = false;
      _erroMais = null;
    }
  }

  Future<void> _verMais() async {
    setState(() {
      _buscando = true;
      _erroMais = null;
    });
    try {
      final pagina = await widget.servico.listarPedidosLgpd(deslocamento: _itens.length);
      if (!mounted) return;
      setState(() {
        if (pagina == null || pagina.itens.isEmpty) {
          _fim = true;
        } else {
          _mais.addAll(pagina.itens);
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _erroMais = mensagemErroTrato(e));
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _novo() async {
    final messenger = ScaffoldMessenger.of(context);
    final antes = {for (final p in _itens) p.id};
    final pedido = await Navigator.of(context).push(
      MaterialPageRoute<PedidoLgpd>(
        builder: (_) => NovoPedidoLgpdTela(servico: widget.servico),
      ),
    );
    if (pedido == null || !mounted) return;
    final repetido = pedido.id.isNotEmpty && antes.contains(pedido.id);
    final protocolo = pedido.protocolo.isEmpty ? '' : ' Protocolo ${pedido.protocolo}.';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${repetido ? 'Você já tinha um pedido igual em aberto.' : 'Pedido registrado.'}'
            '$protocolo',
          ),
        ),
      );
    widget.recarregar();
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itens;
    final temMais = !_fim && itens.length < widget.pagina.total;
    final atualizar = AtualizadorTela.de(context);
    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        Text(
          'Peça gratuitamente informações ou mudanças nos seus dados, ou a revisão por uma '
          'pessoa de uma decisão automática, e acompanhe a resposta aqui.',
          style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        BotaoPrimario(
          key: const ValueKey('botao-novo-pedido-lgpd'),
          texto: 'Fazer um pedido',
          aoTocar: _novo,
        ),
        const SizedBox(height: EspacosTrato.x5),
        if (itens.isEmpty)
          Text(
            'Você ainda não fez nenhum pedido.',
            style: TipografiaTrato.corpo.copyWith(color: context.cores.texto),
          ),
        for (final p in itens) ...[
          _CartaoPedido(p),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_erroMais != null) _TextoErro(_erroMais!),
        if (temMais)
          BotaoSecundario(
            texto: _buscando ? 'Carregando...' : 'Ver mais',
            aoTocar: _buscando ? null : _verMais,
          ),
      ],
    );
    return atualizar == null ? lista : RefreshIndicator(onRefresh: atualizar, child: lista);
  }
}

class _CartaoPedido extends StatelessWidget {
  const _CartaoPedido(this.pedido);

  final PedidoLgpd pedido;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (situacao, tipoStatus) = _situacao(pedido.status);
    final corpo = TipografiaTrato.corpoPequeno.copyWith(color: c.texto);

    Widget bloco(String titulo, String texto) => Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: TipografiaTrato.corpoForte.copyWith(color: c.texto)),
              Text(texto, style: corpo),
            ],
          ),
        );

    final decisao = pedido.decisaoAutomatizada;
    final respondido = pedido.respondidoEm;
    return CartaoTrato(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChipStatus(texto: situacao, tipo: tipoStatus),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              tiposPedidoLgpd[pedido.tipo] ?? 'Pedido sobre seus dados',
              style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
            ),
            if (decisao != null)
              Text(
                'Decisão: ${decisoesAutomatizadas[decisao] ?? 'Outra decisão automática'}',
                style: corpo,
              ),
            const SizedBox(height: EspacosTrato.x2),
            SelectableText(
              'Protocolo: ${pedido.protocolo.isEmpty ? 'não informado' : pedido.protocolo}',
              style: corpo,
            ),
            Text(
              pedido.responderAte == null
                  ? 'Prazo para resposta não informado.'
                  : 'Prazo para resposta: até ${_data(pedido.responderAte!)}',
              style: corpo,
            ),
            if (pedido.descricao.isNotEmpty) bloco('O que você escreveu', pedido.descricao),
            if (pedido.resposta != null)
              bloco(
                respondido == null ? 'Resposta' : 'Resposta em ${_data(respondido)}',
                pedido.resposta!,
              ),
            if (pedido.motivoNaoAtendido != null)
              bloco('Motivo do que não foi atendido', pedido.motivoNaoAtendido!),
            if (pedido.criteriosInformados != null)
              bloco('Critérios usados na decisão', pedido.criteriosInformados!),
          ],
        ),
      ),
    );
  }
}

class _TextoErro extends StatelessWidget {
  const _TextoErro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
        child: Semantics(
          liveRegion: true,
          child: Text(
            texto,
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
          ),
        ),
      );
}

/// Formulário do pedido. Fecha devolvendo o pedido que o servidor registrou.
class NovoPedidoLgpdTela extends StatefulWidget {
  const NovoPedidoLgpdTela({super.key, required this.servico});

  final PedidosDoTitular servico;

  @override
  State<NovoPedidoLgpdTela> createState() => _NovoPedidoLgpdTelaState();
}

class _NovoPedidoLgpdTelaState extends State<NovoPedidoLgpdTela> {
  final _descricao = TextEditingController();
  String? _tipo;
  String? _decisao;
  var _enviando = false;
  String? _erro;

  bool get _revisao => _tipo == tipoRevisaoAutomatizada;

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final tipo = _tipo;
    if (tipo == null || (_revisao && _decisao == null)) {
      setState(
        () => _erro = tipo == null
            ? 'Escolha o que você quer pedir.'
            : 'Escolha qual decisão você quer que uma pessoa revise.',
      );
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final pedido = await widget.servico.abrirPedidoLgpd(
        tipo: tipo,
        descricao: _descricao.text.trim(),
        decisaoAutomatizada: _revisao ? _decisao : null,
      );
      if (mounted) Navigator.of(context).pop(pedido);
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

  Widget _opcao(String chave, String texto, bool marcada, VoidCallback aoTocar) {
    final c = context.cores;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: marcada,
      child: ListTile(
        key: ValueKey(chave),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: c.petroleo,
        ),
        title: Text(texto, style: TipografiaTrato.corpo.copyWith(color: c.texto)),
        onTap: _enviando
            ? null
            : () => setState(() {
                  _erro = null;
                  aoTocar();
                }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = TipografiaTrato.corpoForte.copyWith(color: context.cores.texto);
    return MolduraTelaComum(
      titulo: 'Fazer um pedido',
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('O que você quer pedir?', style: titulo),
            for (final t in tiposPedidoLgpd.entries)
              _opcao('tipo-${t.key}', t.value, _tipo == t.key, () => _tipo = t.key),
            if (_revisao) ...[
              const SizedBox(height: EspacosTrato.x4),
              const AvisoFaixa(
                texto: 'Você pode pedir que uma pessoa revise uma decisão tomada só de forma '
                    'automática. Os critérios usados são informados, respeitado o segredo '
                    'comercial.',
                tipo: TipoStatus.info,
              ),
              const SizedBox(height: EspacosTrato.x3),
              Text('Qual decisão?', style: titulo),
              for (final d in decisoesAutomatizadas.entries)
                _opcao('decisao-${d.key}', d.value, _decisao == d.key, () => _decisao = d.key),
            ],
            const SizedBox(height: EspacosTrato.x4),
            Text('Detalhes (opcional)', style: titulo),
            const SizedBox(height: EspacosTrato.x2),
            TextField(
              key: const ValueKey('descricao-pedido-lgpd'),
              controller: _descricao,
              enabled: !_enviando,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(hintText: 'Conte o que você precisa'),
            ),
            const SizedBox(height: EspacosTrato.x3),
            if (_erro != null) _TextoErro(_erro!),
            BotaoPrimario(
              key: const ValueKey('botao-enviar-pedido-lgpd'),
              texto: 'Enviar pedido',
              carregando: _enviando,
              aoTocar: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
