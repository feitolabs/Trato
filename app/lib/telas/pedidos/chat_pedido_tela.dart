import '../cliente/avatar_de_usuario.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../comuns/formato_aparelho.dart';
import 'modelos.dart';
import 'pecas.dart';

/// Tela 17 — Chat do pedido. O envio real, a guarda como prova e a ocultação de telefones e
/// e-mails são do backend (`GET/POST /v1/pedidos/{id}/mensagens`). Quando [aoRecarregar] é
/// fornecido, a tela busca novas mensagens periodicamente.
class ChatPedidoTela extends StatefulWidget {
  const ChatPedidoTela({
    super.key,
    required this.conversa,
    this.aoEnviar,
    this.aoTocarCamera,
    this.aoCapturarFoto,
    this.aoEnviarFoto,
    this.aoRecarregar,
    this.aoAceitarContraproposta,
    this.intervaloAtualizacao = const Duration(seconds: 4),
    this.horaAgora = _horaPadrao,
  });

  final ConversaPedido conversa;
  final ValueChanged<String>? aoEnviar;
  final VoidCallback? aoTocarCamera;
  final Future<String?> Function()? aoCapturarFoto;
  final ValueChanged<String>? aoEnviarFoto;
  final Future<ConversaPedido> Function()? aoRecarregar;

  /// Profissional aceita a contraproposta do cliente (só aparece nas mensagens que ele recebe).
  final Future<void> Function(ContrapropostaChat)? aoAceitarContraproposta;
  final Duration intervaloAtualizacao;

  /// Hora mostrada na mensagem recém-enviada (injetável nos testes).
  final String Function() horaAgora;

  static String _horaPadrao() {
    return horaDoAparelho(DateTime.now());
  }

  @override
  State<ChatPedidoTela> createState() => _ChatPedidoTelaState();
}

class _ChatPedidoTelaState extends State<ChatPedidoTela> {
  final _controlador = TextEditingController();
  late List<MensagemChat> _mensagens = [...widget.conversa.mensagens];
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    if (widget.aoRecarregar != null) {
      _relogio =
          Timer.periodic(widget.intervaloAtualizacao, (_) => _sincronizar());
    }
  }

  Future<void> _sincronizar() async {
    final recarregar = widget.aoRecarregar;
    if (recarregar == null || !mounted) return;
    try {
      final atualizada = await recarregar();
      if (!mounted) return;
      if (atualizada.mensagens.length >= _mensagens.length) {
        setState(() => _mensagens = [...atualizada.mensagens]);
      }
    } on Object {
      // Silencioso em segundo plano; próxima leitura tenta novamente.
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _controlador.dispose();
    super.dispose();
  }

  void _enviar([String? texto]) {
    final conteudo = (texto ?? _controlador.text).trim();
    if (conteudo.isEmpty) return;
    setState(() {
      _mensagens.add(
        MensagemChat(
            tipo: TipoMensagem.texto,
            texto: conteudo,
            hora: widget.horaAgora(),
            minha: true),
      );
      _controlador.clear();
    });
    widget.aoEnviar?.call(conteudo);
  }

  Future<void> _tocarCamera() async {
    widget.aoTocarCamera?.call();
    if (widget.aoCapturarFoto != null) {
      final ref = await widget.aoCapturarFoto!();
      if (ref != null && mounted) {
        setState(() {
          _mensagens.add(
            MensagemChat(
              tipo: TipoMensagem.foto,
              texto: ref,
              hora: widget.horaAgora(),
              minha: true,
            ),
          );
        });
        widget.aoEnviarFoto?.call(ref);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversa = widget.conversa;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Cabecalho(conversa: conversa),
            const _AvisoPrivacidade(),
            Expanded(
              child: ConteudoResponsivo(
                child: ListView(
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  children: [
                    // reverse: a lista começa colada embaixo, perto do campo de envio.
                    for (final m in _mensagens.reversed)
                      _LinhaMensagem(
                        mensagem: m,
                        aoAceitarContraproposta:
                            widget.aoAceitarContraproposta == null
                                ? null
                                : (c) async {
                                    await widget.aoAceitarContraproposta!(c);
                                    await _sincronizar();
                                  },
                      ),
                  ],
                ),
              ),
            ),
            _RespostasRapidas(
                respostas: conversa.respostasRapidas, aoTocar: _enviar),
            _CampoEnvio(
              controlador: _controlador,
              aoEnviar: _enviar,
              aoTocarCamera: _tocarCamera,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.conversa});

  final ConversaPedido conversa;

  @override
  Widget build(BuildContext context) {
    return ConteudoResponsivo(
      comMargem: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Voltar',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            ),
            AvatarDeUsuario(
              iniciais: conversa.iniciais,
              usuarioId: conversa.usuarioId,
              tamanho: 48,
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversa.nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TipografiaTrato.tituloCartao,
                  ),
                  Text(
                    'Pedido ${conversa.numeroPedido} · ${conversa.situacao}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: CoresTrato.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: EspacosTrato.x4),
          ],
        ),
      ),
    );
  }
}

class _AvisoPrivacidade extends StatelessWidget {
  const _AvisoPrivacidade();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: CoresTrato.azulSuave,
      padding: const EdgeInsets.symmetric(
        horizontal: EspacosTrato.margemTela,
        vertical: EspacosTrato.x3,
      ),
      child: ConteudoResponsivo(
        comMargem: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined,
                size: 20, color: CoresTrato.azulTexto),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: Text(
                'As mensagens ficam guardadas e servem de prova. '
                'Antes de contratar, telefones e e-mails ficam ocultos.',
                style: TipografiaTrato.corpoPequeno
                    .copyWith(color: CoresTrato.azulTexto),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaMensagem extends StatelessWidget {
  const _LinhaMensagem({required this.mensagem, this.aoAceitarContraproposta});

  final MensagemChat mensagem;
  final Future<void> Function(ContrapropostaChat)? aoAceitarContraproposta;

  @override
  Widget build(BuildContext context) {
    final legendaHora =
        TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario);
    if (mensagem.tipo == TipoMensagem.sistema) {
      return Padding(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
        child: Column(
          children: [
            Text(
              mensagem.texto ?? '',
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpoPequeno
                  .copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x1),
            Text(mensagem.hora, style: legendaHora),
          ],
        ),
      );
    }

    final minha = mensagem.minha;
    final larguraMaxima = MediaQuery.sizeOf(context).width * 0.72;
    final Widget corpo = mensagem.tipo == TipoMensagem.foto
        ? EspacoFoto(
            rotulo: mensagem.texto ?? '[Foto]', largura: 220, altura: 180)
        : Container(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x4,
              vertical: EspacosTrato.x3,
            ),
            decoration: BoxDecoration(
              color: minha ? CoresTrato.petroleo : CoresTrato.superficie,
              borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
              border: minha ? null : Border.all(color: CoresTrato.borda),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mensagem.contraproposta != null) ...[
                  Text(
                    'Contraproposta',
                    style: TipografiaTrato.sobretitulo.copyWith(
                      color:
                          minha ? CoresTrato.creme : CoresTrato.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                ],
                Text(
                  mensagem.texto ?? '',
                  style: TipografiaTrato.corpo.copyWith(
                    color: minha ? CoresTrato.creme : CoresTrato.petroleo,
                  ),
                ),
                if (mensagem.contraproposta != null &&
                    !minha &&
                    aoAceitarContraproposta != null) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  FilledButton(
                    onPressed: () =>
                        aoAceitarContraproposta!(mensagem.contraproposta!),
                    child: const Text('Aceitar e atualizar orçamento'),
                  ),
                ],
              ],
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment:
            minha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
              constraints: BoxConstraints(maxWidth: larguraMaxima),
              child: corpo),
          const SizedBox(height: EspacosTrato.x1),
          if (!minha)
            Text(mensagem.hora, style: legendaHora)
          else
            // Pinzinho de quem mandou: ✓ enviada · ✓✓ cinza recebida · ✓✓ azul visualizada.
            Semantics(
              label: mensagem.lida
                  ? 'Enviada às ${mensagem.hora}, visualizada'
                  : mensagem.recebida
                      ? 'Enviada às ${mensagem.hora}, recebida'
                      : 'Enviada às ${mensagem.hora}',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(mensagem.hora, style: legendaHora),
                  const SizedBox(width: EspacosTrato.x1),
                  Icon(
                    mensagem.lida || mensagem.recebida ? Icons.done_all : Icons.done,
                    key: ValueKey(
                      mensagem.lida
                          ? 'pino-visualizada'
                          : mensagem.recebida
                              ? 'pino-recebida'
                              : 'pino-enviada',
                    ),
                    size: 16,
                    color: mensagem.lida
                        ? CoresTrato.azulTexto
                        : CoresTrato.textoSecundario,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RespostasRapidas extends StatelessWidget {
  const _RespostasRapidas({required this.respostas, required this.aoTocar});

  final List<String> respostas;
  final ValueChanged<String> aoTocar;

  @override
  Widget build(BuildContext context) {
    if (respostas.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: EspacosTrato.margemTela),
        itemCount: respostas.length,
        separatorBuilder: (_, __) => const SizedBox(width: EspacosTrato.x2),
        itemBuilder: (_, i) => Material(
          color: CoresTrato.superficie,
          shape: const StadiumBorder(side: BorderSide(color: CoresTrato.borda)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => aoTocar(respostas[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
              child: Center(
                  child:
                      Text(respostas[i], style: TipografiaTrato.corpoPequeno)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CampoEnvio extends StatelessWidget {
  const _CampoEnvio({
    required this.controlador,
    required this.aoEnviar,
    required this.aoTocarCamera,
  });

  final TextEditingController controlador;
  final VoidCallback aoEnviar;
  final VoidCallback? aoTocarCamera;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CoresTrato.superficie,
        border: Border(top: BorderSide(color: CoresTrato.borda)),
      ),
      child: ConteudoResponsivo(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x3),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Enviar foto',
                onPressed: aoTocarCamera ?? () {},
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: controlador,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => aoEnviar(),
                  style: TipografiaTrato.corpo,
                  decoration: const InputDecoration(
                    hintText: 'Escreva uma mensagem',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: EspacosTrato.x5,
                      vertical: EspacosTrato.x3,
                    ),
                    border: _borda,
                    enabledBorder: _borda,
                    focusedBorder: _borda,
                  ),
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: aoEnviar,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _borda = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(EspacosTrato.raioPilula)),
    borderSide: BorderSide(color: CoresTrato.borda),
  );
}
