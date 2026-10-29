import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';
import 'pecas.dart';

/// Tela 17 — Chat do pedido. Mensagens novas ficam só na memória da tela (provisório):
/// o envio real, a guarda como prova e a ocultação de telefones são do backend.
class ChatPedidoTela extends StatefulWidget {
  const ChatPedidoTela({
    super.key,
    this.conversa = DadosExemplo.conversa,
    this.aoEnviar,
    this.aoTocarCamera,
    this.horaAgora = _horaPadrao,
  });

  final ConversaPedido conversa;
  final ValueChanged<String>? aoEnviar;
  final VoidCallback? aoTocarCamera;

  /// Hora mostrada na mensagem recém-enviada (injetável nos testes).
  final String Function() horaAgora;

  static String _horaPadrao() {
    final agora = DateTime.now();
    return '${agora.hour}h${agora.minute.toString().padLeft(2, '0')}';
  }

  @override
  State<ChatPedidoTela> createState() => _ChatPedidoTelaState();
}

class _ChatPedidoTelaState extends State<ChatPedidoTela> {
  final _controlador = TextEditingController();
  late final List<MensagemChat> _mensagens = [...widget.conversa.mensagens];

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _enviar([String? texto]) {
    final conteudo = (texto ?? _controlador.text).trim();
    if (conteudo.isEmpty) return;
    setState(() {
      _mensagens.add(
        MensagemChat(
            tipo: TipoMensagem.texto, texto: conteudo, hora: widget.horaAgora(), minha: true),
      );
      _controlador.clear();
    });
    widget.aoEnviar?.call(conteudo);
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
                  padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  children: [
                    // reverse: a lista começa colada embaixo, perto do campo de envio.
                    for (final m in _mensagens.reversed) _LinhaMensagem(mensagem: m),
                  ],
                ),
              ),
            ),
            _RespostasRapidas(respostas: conversa.respostasRapidas, aoTocar: _enviar),
            _CampoEnvio(
              controlador: _controlador,
              aoEnviar: _enviar,
              aoTocarCamera: widget.aoTocarCamera,
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
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: CoresTrato.azulClaro, shape: BoxShape.circle),
              child: Text(conversa.iniciais, style: TipografiaTrato.corpoForte),
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
            const Icon(Icons.shield_outlined, size: 20, color: CoresTrato.azulTexto),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: Text(
                'As mensagens ficam guardadas e servem de prova. '
                'Telefones e e-mails são ocultados.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaMensagem extends StatelessWidget {
  const _LinhaMensagem({required this.mensagem});

  final MensagemChat mensagem;

  @override
  Widget build(BuildContext context) {
    final legendaHora = TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario);
    if (mensagem.tipo == TipoMensagem.sistema) {
      return Padding(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
        child: Column(
          children: [
            Text(
              mensagem.texto ?? '',
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
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
        ? EspacoFoto(rotulo: mensagem.texto ?? '[Foto]', largura: 220, altura: 180)
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
            child: Text(
              mensagem.texto ?? '',
              style: TipografiaTrato.corpo.copyWith(
                color: minha ? CoresTrato.creme : CoresTrato.petroleo,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment: minha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(constraints: BoxConstraints(maxWidth: larguraMaxima), child: corpo),
          const SizedBox(height: EspacosTrato.x1),
          Text(mensagem.lida ? '${mensagem.hora} · lida' : mensagem.hora, style: legendaHora),
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
        padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.margemTela),
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
              child: Center(child: Text(respostas[i], style: TipografiaTrato.corpoPequeno)),
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
