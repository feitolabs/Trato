import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

const kDestinatariosPedidoInfo = {
  'cliente': 'Cliente',
  'profissional': 'Profissional',
};

const _kMensagemMaxima = 1000;
const _kMotivoMaximo = 500;

String nomeDestinatarioPedidoInfo(String papel) => kDestinatariosPedidoInfo[papel] ?? papel;

(String, Tom) chipStatusPedidoInfo(String status) => switch (status) {
      'aguardando_resposta' => ('Aguardando resposta', Tom.info),
      'vencido' => ('Prazo vencido', Tom.erro),
      'respondido' => ('Respondido', Tom.ok),
      'encerrado_sem_resposta' => ('Encerrado sem resposta', Tom.neutro),
      final outro => (outro, Tom.neutro),
    };

String mensagemErroPedidoInfo(Object erro) {
  if (erro is ErroApi) {
    return switch (erro.status) {
      403 => '${erro.mensagem} Confira se o seu papel tem permissão para esta ação.',
      404 => '${erro.mensagem} Atualize a disputa para conferir os registros atuais.',
      409 => '${erro.mensagem} Atualize a lista para ver o estado atual.',
      422 => erro.mensagem,
      503 => '${erro.mensagem} Tente novamente em alguns instantes.',
      _ => erro.mensagem,
    };
  }
  return erro.toString();
}

/// Seção de pedidos de informação adicional no detalhe da disputa (Termos 8.4).
/// Falha secundária aqui não derruba o detalhe da disputa.
class SecaoPedidosInfoDisputa extends StatefulWidget {
  const SecaoPedidosInfoDisputa({super.key, required this.disputa});

  final Disputa disputa;

  @override
  State<SecaoPedidosInfoDisputa> createState() => _SecaoPedidosInfoDisputaState();
}

class _SecaoPedidosInfoDisputaState extends State<SecaoPedidosInfoDisputa> {
  List<PedidoInfoDisputa>? _itens;
  String? _erro;
  bool _carregando = true;
  bool _iniciou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    _carregar();
  }

  @override
  void didUpdateWidget(covariant SecaoPedidosInfoDisputa oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disputa.id != widget.disputa.id) {
      _carregar();
    }
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await context.api.listarPedidosInfoDisputa(widget.disputa.id);
      if (!mounted) return;
      setState(() {
        _itens = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = mensagemErroPedidoInfo(e);
        _carregando = false;
      });
    }
  }

  Future<void> _abrirSolicitacao() async {
    final criou = await mostrarModal<bool>(
      context,
      construir: (_) => _ModalPedirInfo(disputaId: widget.disputa.id),
    );
    if (criou == true && mounted) await _carregar();
  }

  Future<void> _abrirEncerrar(PedidoInfoDisputa item) async {
    final encerrou = await mostrarModal<bool>(
      context,
      construir: (_) => _ModalEncerrarSemResposta(disputaId: widget.disputa.id, item: item),
    );
    if (encerrou == true && mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.disputa;
    final aberta = !d.status.encerrada && d.status != StatusDisputa.desconhecida;
    final podeDecidir = context.pode(Permissao.disputasDecidir);
    final itens = _itens ?? const <PedidoInfoDisputa>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: EspacosTrato.x4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            Text('Pedidos de informação adicional', style: TipografiaTrato.secao),
            if (podeDecidir && aberta)
              BotaoTrato.secundario('Pedir informação adicional', aoPressionar: _abrirSolicitacao),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: EspacosTrato.x3),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_erro != null) ...[
          BannerInfo(_erro!, titulo: 'Não foi possível carregar os pedidos de informação.', tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.secundario('Tentar novamente', aoPressionar: _carregar),
          ),
        ] else if (itens.isEmpty)
          Text(
            'Nenhum pedido de informação adicional nesta disputa.',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo),
          )
        else
          for (final item in itens)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
              child: _CartaoPedidoInfo(
                item,
                podeEncerrar: podeDecidir && item.status == 'vencido',
                aoEncerrar: () => _abrirEncerrar(item),
              ),
            ),
      ],
    );
  }
}

class _CartaoPedidoInfo extends StatelessWidget {
  const _CartaoPedidoInfo(
    this.item, {
    required this.podeEncerrar,
    required this.aoEncerrar,
  });

  final PedidoInfoDisputa item;
  final bool podeEncerrar;
  final VoidCallback aoEncerrar;

  @override
  Widget build(BuildContext context) {
    final (rotuloStatus, tom) = chipStatusPedidoInfo(item.status);
    return CartaoSecao(
      titulo: 'Pedido para ${nomeDestinatarioPedidoInfo(item.destinatarioPapel).toLowerCase()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ChipEstado(rotuloStatus, tom: tom),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Destinatário', nomeDestinatarioPedidoInfo(item.destinatarioPapel)),
          Linha('Solicitado em', formatarDataBrasilia(item.solicitadoEm)),
          Linha('Responder até', formatarDataBrasilia(item.responderAte)),
          Linha('Mensagem', item.mensagem),
          if (item.respondidoEm case final em?) Linha('Respondido em', formatarDataBrasilia(em)),
          if (item.respostaTexto case final texto? when texto.trim().isNotEmpty) Linha('Resposta', texto),
          if (item.encerradoSemRespostaEm case final em?)
            Linha('Encerrado sem resposta em', formatarDataBrasilia(em)),
          if (podeEncerrar) ...[
            const SizedBox(height: EspacosTrato.x2),
            Align(
              alignment: Alignment.centerRight,
              child: BotaoTrato.secundario('Encerrar sem resposta', aoPressionar: aoEncerrar),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModalPedirInfo extends StatefulWidget {
  const _ModalPedirInfo({required this.disputaId});

  final String disputaId;

  @override
  State<_ModalPedirInfo> createState() => _ModalPedirInfoState();
}

class _ModalPedirInfoState extends State<_ModalPedirInfo> {
  final _mensagem = TextEditingController();
  String? _destinatario;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _mensagem.dispose();
    super.dispose();
  }

  bool get _valido {
    final tamanho = _mensagem.text.trim().length;
    return _destinatario != null && tamanho >= kMotivoMinimo && tamanho <= _kMensagemMaxima;
  }

  Future<void> _enviar() async {
    if (_enviando || _destinatario == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final api = context.api;
    final dest = _destinatario!;
    final msg = _mensagem.text.trim();
    try {
      await api.solicitarInfoDisputa(widget.disputaId, destinatarioPapel: dest, mensagem: msg);
      if (!mounted) return;
      mostrarAviso(context, 'Pedido de informação enviado.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = mensagemErroPedidoInfo(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  List<Widget> _formulario() => [
        Text('Destinatário', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final e in kDestinatariosPedidoInfo.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _destinatario == e.key,
                onSelected: (_) => setState(() => _destinatario = e.key),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _mensagem,
          minLines: 3,
          maxLines: 6,
          maxLength: _kMensagemMaxima,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Mensagem',
            helperText: 'Entre $kMotivoMinimo e $_kMensagemMaxima caracteres',
          ),
        ),
      ];

  List<Widget> _revisao() => [
        Linha('Destinatário', nomeDestinatarioPedidoInfo(_destinatario!)),
        Linha('Mensagem', _mensagem.text.trim()),
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar pedido de informação?' : 'Pedir informação adicional',
        consequencia: 'A parte escolhida será notificada para responder dentro do prazo mínimo previsto nos Termos.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi possível enviar o pedido.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(_revisando ? _revisao() : _formulario()),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar envio',
                  carregando: _enviando,
                  rotuloCarregando: 'Enviando',
                  aoPressionar: _enviando ? null : _enviar,
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: _valido
                      ? () => setState(() {
                            _erro = null;
                            _revisando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}

class _ModalEncerrarSemResposta extends StatefulWidget {
  const _ModalEncerrarSemResposta({required this.disputaId, required this.item});

  final String disputaId;
  final PedidoInfoDisputa item;

  @override
  State<_ModalEncerrarSemResposta> createState() => _ModalEncerrarSemRespostaState();
}

class _ModalEncerrarSemRespostaState extends State<_ModalEncerrarSemResposta> {
  final _motivo = TextEditingController();
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _valido {
    final tamanho = _motivo.text.trim().length;
    return tamanho >= kMotivoMinimo && tamanho <= _kMotivoMaximo;
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final api = context.api;
    final motivo = _motivo.text.trim();
    try {
      await api.encerrarPedidoInfoSemResposta(widget.disputaId, widget.item.id, motivo: motivo);
      if (!mounted) return;
      mostrarAviso(context, 'Pedido encerrado sem resposta.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = mensagemErroPedidoInfo(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar encerramento sem resposta?' : 'Encerrar sem resposta',
        consequencia: 'Marca este pedido de informação vencido como encerrado sem resposta. A ação fica registrada na auditoria.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi possível encerrar o pedido.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          Linha('Destinatário', nomeDestinatarioPedidoInfo(item.destinatarioPapel)),
          Linha('Prazo vencido em', formatarDataBrasilia(item.responderAte)),
          const SizedBox(height: EspacosTrato.x3),
          if (_revisando)
            Linha('Motivo', _motivo.text.trim())
          else
            TextField(
              controller: _motivo,
              minLines: 2,
              maxLines: 5,
              maxLength: _kMotivoMaximo,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Motivo',
                helperText: 'Entre $kMotivoMinimo e $_kMotivoMaximo caracteres',
              ),
            ),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar encerramento',
                  carregando: _enviando,
                  rotuloCarregando: 'Enviando',
                  aoPressionar: _enviando ? null : _enviar,
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: _valido
                      ? () => setState(() {
                            _erro = null;
                            _revisando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}
