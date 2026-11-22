import '../cliente/avatar_de_usuario.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../dados/repositorios.dart' show ResumoPerfilCliente;
import '../../tema/tema.dart';
import '../comuns/formato_aparelho.dart';
import 'modelos.dart';
import 'pecas.dart';
import 'sugestoes_chat.dart';

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
    this.aoAceitarProposta,
    this.aoProporNovaCondicao,
    this.aoAceitarAgenda,
    this.aoSugerirAgenda,
    this.aoAbrirPerfil,
    this.intervaloAtualizacao = const Duration(seconds: 4),
    this.horaAgora = _horaPadrao,
  });

  final ConversaPedido conversa;
  final FutureOr<void> Function(String)? aoEnviar;
  final VoidCallback? aoTocarCamera;
  final Future<String?> Function()? aoCapturarFoto;
  final FutureOr<void> Function(String)? aoEnviarFoto;
  final Future<ConversaPedido> Function()? aoRecarregar;

  /// Profissional aceita a contraproposta do cliente (só aparece nas mensagens que ele recebe).
  final Future<void> Function(ContrapropostaChat)? aoAceitarContraproposta;

  /// Cliente aceita a nova proposta do profissional e segue direto para o pagamento.
  final Future<void> Function(ContrapropostaChat)? aoAceitarProposta;

  /// Profissional abre o modal para propor novo valor/prazo direto pela conversa.
  final Future<void> Function()? aoProporNovaCondicao;

  /// Aceita uma sugestão de dia e horário da visita enviada no chat.
  final Future<void> Function(MensagemChat)? aoAceitarAgenda;

  /// Abre seletor de data/horário para sugerir ou remarcar visita pelo chat.
  final Future<void> Function()? aoSugerirAgenda;

  /// Abre o perfil da outra parte ao tocar no avatar/nome no cabeçalho do chat.
  final VoidCallback? aoAbrirPerfil;
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
  final _sugestoesUsadas = <String>{};
  var _sugestoesOcultas = true; // até ler a preferência do aparelho
  String? _preferenciaLidaPara;
  late ConversaPedido _conversa = widget.conversa;
  late List<MensagemChat> _mensagens = [...widget.conversa.mensagens];
  int _enviosPendentes = 0;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _garantirPreferenciaSugestoes();
    if (widget.aoRecarregar != null) {
      unawaited(_sincronizar());
      _relogio = Timer.periodic(widget.intervaloAtualizacao, (_) => _sincronizar());
    }
  }

  @override
  void didUpdateWidget(covariant ChatPedidoTela oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversa != widget.conversa) {
      _conversa = widget.conversa;
      if (_conversa.mensagens.length >= _mensagens.length - _enviosPendentes) {
        _mensagens = [..._conversa.mensagens];
      }
      _garantirPreferenciaSugestoes();
    }
  }

  Future<void> _sincronizar() async {
    final recarregar = widget.aoRecarregar;
    if (recarregar == null || !mounted) return;
    try {
      final atualizada = await recarregar();
      if (!mounted) return;
      setState(() {
        _conversa = atualizada;
        if (atualizada.mensagens.length >= _mensagens.length - _enviosPendentes) {
          _mensagens = [...atualizada.mensagens];
        }
      });
      _garantirPreferenciaSugestoes();
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

  Future<void> _enviar([String? texto]) async {
    final conteudo = (texto ?? _controlador.text).trim();
    if (conteudo.isEmpty) return;
    final digitada = texto == null;
    final otimista = MensagemChat(
      tipo: TipoMensagem.texto,
      texto: conteudo,
      hora: widget.horaAgora(),
      minha: true,
    );
    setState(() {
      _mensagens.add(otimista);
      _enviosPendentes++;
      if (digitada) _controlador.clear();
    });
    try {
      await widget.aoEnviar?.call(conteudo);
    } on Object {
      if (mounted) {
        setState(() {
          _mensagens.remove(otimista);
          if (digitada && _controlador.text.isEmpty) {
            _controlador.text = conteudo;
          }
        });
      }
    } finally {
      _enviosPendentes = (_enviosPendentes - 1).clamp(0, 999);
    }
  }

  Future<void> _tocarCamera() async {
    widget.aoTocarCamera?.call();
    if (widget.aoCapturarFoto != null) {
      final ref = await widget.aoCapturarFoto!();
      if (ref != null && mounted) {
        final otimista = MensagemChat(
          tipo: TipoMensagem.foto,
          texto: ref,
          hora: widget.horaAgora(),
          minha: true,
        );
        setState(() {
          _mensagens.add(otimista);
          _enviosPendentes++;
        });
        try {
          await widget.aoEnviarFoto?.call(ref);
        } on Object {
          if (mounted) {
            setState(() => _mensagens.remove(otimista));
          }
        } finally {
          _enviosPendentes = (_enviosPendentes - 1).clamp(0, 999);
        }
      }
    }
  }

  bool _mostrarSugestoes(ConversaPedido c) =>
      !_sugestoesOcultas &&
      chatPermiteSugestoes(c.estadoApi) &&
      _sugestoesUsadas.length <
          sugestoesDoChat(souCliente: c.souCliente, categoria: c.categoriaNome).length;

  /// Tocar numa sugestão só preenche o campo (nunca envia) e a sugestão usada some.
  void _usarSugestao(String texto) {
    final atual = _controlador.text.trim();
    final novo = atual.isEmpty ? texto : '$atual $texto';
    _controlador.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
    setState(() => _sugestoesUsadas.add(texto));
  }

  Future<void> _esconderSugestoes() async {
    setState(() => _sugestoesOcultas = true);
    await PreferenciaSugestoesChat.ocultar(_chaveSugestoes);
  }

  String get _chaveSugestoes => _conversa.pedidoId ?? _conversa.numeroPedido;

  void _garantirPreferenciaSugestoes() {
    if (!chatPermiteSugestoes(_conversa.estadoApi)) return;
    final chave = _chaveSugestoes;
    if (_preferenciaLidaPara == chave) return;
    _preferenciaLidaPara = chave;
    unawaited(_lerPreferenciaSugestoes(chave));
  }

  Future<void> _lerPreferenciaSugestoes(String chave) async {
    final ocultas = await PreferenciaSugestoesChat.ocultas(chave);
    if (mounted && _chaveSugestoes == chave) {
      setState(() => _sugestoesOcultas = ocultas);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversa = _conversa;
    final ultimaPorOrcamento = <String, int>{};
    for (var i = 0; i < _mensagens.length; i++) {
      final c = _mensagens[i].contraproposta;
      if (c != null) ultimaPorOrcamento[c.orcamentoId] = i;
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Cabecalho(
              conversa: conversa,
              aoAbrirPerfil: widget.aoAbrirPerfil,
              aoAtualizar: widget.aoRecarregar == null ? null : _sincronizar,
              aoProporNovaCondicao: conversa.pedidoAberto ? widget.aoProporNovaCondicao : null,
              aoSugerirAgenda: widget.aoSugerirAgenda == null
                  ? null
                  : () async {
                      await widget.aoSugerirAgenda!();
                      await _sincronizar();
                    },
            ),
            const _AvisoPrivacidade(),
            Expanded(
              child: ConteudoResponsivo(
                child: ListView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  children: [
                    // reverse: a lista começa colada embaixo, perto do campo de envio.
                    for (var i = _mensagens.length - 1; i >= 0; i--)
                      _buildLinha(i, _mensagens[i], conversa, ultimaPorOrcamento),
                  ],
                ),
              ),
            ),
            if (_mostrarSugestoes(conversa))
              SugestoesChat(
                sugestoes: [
                  for (final s in sugestoesDoChat(
                    souCliente: conversa.souCliente,
                    categoria: conversa.categoriaNome,
                  ))
                    if (!_sugestoesUsadas.contains(s)) s,
                ],
                aoTocar: _usarSugestao,
                aoEsconder: _esconderSugestoes,
              ),
            _RespostasRapidas(respostas: conversa.respostasRapidas, aoTocar: _enviar),
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

  Widget _buildLinha(
    int indice,
    MensagemChat m,
    ConversaPedido conversa,
    Map<String, int> ultimaPorOrcamento,
  ) {
    final c = m.contraproposta;
    final substituida = c != null && ultimaPorOrcamento[c.orcamentoId] != indice;
    final ativoNoBackend = c == null
        ? true
        : (conversa.pedidoAberto &&
            (conversa.orcamentosAtivos.isEmpty ||
                conversa.orcamentosAtivos.contains(c.orcamentoId)));
    final podeAceitar = !substituida && ativoNoBackend;

    return _LinhaMensagem(
      mensagem: m,
      podeAceitarProposta: podeAceitar,
      aoAceitarContraproposta: widget.aoAceitarContraproposta == null
          ? null
          : (prop) async {
              await widget.aoAceitarContraproposta!(prop);
              await _sincronizar();
            },
      aoAceitarProposta: widget.aoAceitarProposta == null
          ? null
          : (prop) async {
              await widget.aoAceitarProposta!(prop);
              await _sincronizar();
            },
      aoAceitarAgenda: widget.aoAceitarAgenda == null
          ? null
          : (msg) async {
              await widget.aoAceitarAgenda!(msg);
              await _sincronizar();
            },
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.conversa,
    this.aoAbrirPerfil,
    this.aoAtualizar,
    this.aoProporNovaCondicao,
    this.aoSugerirAgenda,
  });

  final ConversaPedido conversa;
  final VoidCallback? aoAbrirPerfil;
  final Future<void> Function()? aoAtualizar;
  final Future<void> Function()? aoProporNovaCondicao;
  final Future<void> Function()? aoSugerirAgenda;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final temAcoesSecundarias = aoProporNovaCondicao != null || aoSugerirAgenda != null;
    return ConteudoResponsivo(
      comMargem: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Voltar',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                ),
                Expanded(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: const ValueKey('cabecalho-chat-perfil'),
                      onTap: aoAbrirPerfil,
                      borderRadius: BorderRadius.circular(EspacosTrato.raio),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: EspacosTrato.x1,
                          vertical: EspacosTrato.x1,
                        ),
                        child: Row(
                          children: [
                            AvatarDeUsuario(
                              iniciais: conversa.iniciais,
                              usuarioId: conversa.usuarioId,
                              tamanho: 48,
                              permitirAmpliacao: false,
                            ),
                            const SizedBox(width: EspacosTrato.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          conversa.nome,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TipografiaTrato.tituloCartao.copyWith(
                                            color: c.texto,
                                          ),
                                        ),
                                      ),
                                      if (aoAbrirPerfil != null) ...[
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 18,
                                          color: c.textoSecundario,
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    'Pedido ${conversa.numeroPedido} · ${conversa.situacao}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TipografiaTrato.corpoPequeno.copyWith(
                                      color: c.textoSecundario,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (aoAtualizar != null)
                  IconButton(
                    tooltip: 'Atualizar conversa',
                    onPressed: aoAtualizar,
                    icon: const Icon(Icons.refresh, size: 20),
                  )
                else
                  const SizedBox(width: EspacosTrato.x4),
              ],
            ),
          ),
          if (temAcoesSecundarias)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EspacosTrato.x4,
                0,
                EspacosTrato.x4,
                EspacosTrato.x2,
              ),
              child: Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x1,
                children: [
                  if (aoProporNovaCondicao != null)
                    TextButton.icon(
                      onPressed: aoProporNovaCondicao,
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Nova proposta'),
                    ),
                  if (aoSugerirAgenda != null)
                    TextButton.icon(
                      key: const Key('botao-sugerir-agenda'),
                      onPressed: aoSugerirAgenda,
                      icon: const Icon(Icons.event_available_outlined, size: 18),
                      label: const Text('Horário'),
                    ),
                ],
              ),
            ),
        ],
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
      color: context.cores.azulSuave,
      padding: const EdgeInsets.symmetric(
        horizontal: EspacosTrato.margemTela,
        vertical: EspacosTrato.x3,
      ),
      child: ConteudoResponsivo(
        comMargem: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 20, color: context.cores.azulTexto),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: Text(
                'As mensagens ficam guardadas e servem de prova. '
                'Antes de contratar, telefones e e-mails ficam ocultos.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.azulTexto),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaMensagem extends StatelessWidget {
  const _LinhaMensagem({
    required this.mensagem,
    required this.podeAceitarProposta,
    this.aoAceitarContraproposta,
    this.aoAceitarProposta,
    this.aoAceitarAgenda,
  });

  final MensagemChat mensagem;
  final bool podeAceitarProposta;
  final Future<void> Function(ContrapropostaChat)? aoAceitarContraproposta;
  final Future<void> Function(ContrapropostaChat)? aoAceitarProposta;
  final Future<void> Function(MensagemChat)? aoAceitarAgenda;

  @override
  Widget build(BuildContext context) {
    final legendaHora = TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario);
    if (mensagem.tipo == TipoMensagem.sistema) {
      return Padding(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
        child: Column(
          children: [
            Text(
              mensagem.texto ?? '',
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x1),
            Text(mensagem.hora, style: legendaHora),
          ],
        ),
      );
    }

    final minha = mensagem.minha;
    final larguraMaxima = MediaQuery.sizeOf(context).width * 0.72;
    final prop = mensagem.contraproposta;
    final agenda = mensagem.propostaAgenda;
    final Widget corpo = mensagem.tipo == TipoMensagem.foto
        ? EspacoFoto(rotulo: mensagem.texto ?? '[Foto]', largura: 220, altura: 180)
        : Container(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x4,
              vertical: EspacosTrato.x3,
            ),
            decoration: BoxDecoration(
              color: minha ? context.cores.petroleo : context.cores.superficie,
              borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
              border: minha ? null : Border.all(color: context.cores.borda),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (prop != null) ...[
                  Text(
                    prop.ehPropostaDoProfissional ? 'Nova proposta' : 'Contraproposta',
                    style: TipografiaTrato.sobretitulo.copyWith(
                      color: minha ? context.cores.sobrePetroleo : context.cores.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    'Valor: ${formatarReais(prop.valorCentavos)}'
                    '${prop.prazoExecucaoDias == null ? '' : ' · Prazo: ${prop.prazoExecucaoDias} ${prop.prazoExecucaoDias == 1 ? 'dia' : 'dias'}'}',
                    style: TipografiaTrato.corpoForte.copyWith(
                      color: minha ? context.cores.sobrePetroleo : context.cores.petroleo,
                    ),
                  ),
                  if ((mensagem.texto ?? '').trim().isNotEmpty)
                    const SizedBox(height: EspacosTrato.x1),
                ],
                if (agenda != null) ...[
                  Text(
                    'Sugestão de visita',
                    style: TipografiaTrato.sobretitulo.copyWith(
                      color: minha ? context.cores.sobrePetroleo : context.cores.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    '${agenda.inicio.day.toString().padLeft(2, '0')}/'
                    '${agenda.inicio.month.toString().padLeft(2, '0')} · '
                    '${agenda.inicio.hour.toString().padLeft(2, '0')}h'
                    '${agenda.inicio.minute.toString().padLeft(2, '0')} às '
                    '${agenda.fim.hour.toString().padLeft(2, '0')}h'
                    '${agenda.fim.minute.toString().padLeft(2, '0')}',
                    style: TipografiaTrato.corpoForte.copyWith(
                      color: minha ? context.cores.sobrePetroleo : context.cores.petroleo,
                    ),
                  ),
                  if ((mensagem.texto ?? '').trim().isNotEmpty)
                    const SizedBox(height: EspacosTrato.x1),
                ],
                if ((mensagem.texto ?? '').trim().isNotEmpty || (prop == null && agenda == null))
                  Text(
                    mensagem.texto ?? '',
                    style: TipografiaTrato.corpo.copyWith(
                      color: minha ? context.cores.sobrePetroleo : context.cores.petroleo,
                    ),
                  ),
                if (agenda != null && !minha && aoAceitarAgenda != null) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  _BotaoProposta(
                    ativo: true,
                    rotuloAtivo: 'Confirmar este horário',
                    rotuloInativo: 'Horário confirmado',
                    aoTocar: () => aoAceitarAgenda!(mensagem),
                  ),
                ],
                if (prop != null && !minha) ...[
                  if (prop.ehPropostaDoProfissional && aoAceitarProposta != null) ...[
                    const SizedBox(height: EspacosTrato.x3),
                    _BotaoProposta(
                      ativo: podeAceitarProposta,
                      rotuloAtivo: 'Aceitar e pagar',
                      rotuloInativo: 'Proposta substituída',
                      aoTocar: () => aoAceitarProposta!(prop),
                    ),
                  ] else if (!prop.ehPropostaDoProfissional && aoAceitarContraproposta != null) ...[
                    const SizedBox(height: EspacosTrato.x3),
                    _BotaoProposta(
                      ativo: podeAceitarProposta,
                      rotuloAtivo: 'Aceitar e atualizar orçamento',
                      rotuloInativo: 'Orçamento atualizado',
                      aoTocar: () => aoAceitarContraproposta!(prop),
                    ),
                  ],
                ],
              ],
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment: minha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(constraints: BoxConstraints(maxWidth: larguraMaxima), child: corpo),
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
                    color: mensagem.lida ? context.cores.azulTexto : context.cores.textoSecundario,
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
        padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.margemTela),
        itemCount: respostas.length,
        separatorBuilder: (_, __) => const SizedBox(width: EspacosTrato.x2),
        itemBuilder: (_, i) => Material(
          color: context.cores.superficie,
          shape: StadiumBorder(side: BorderSide(color: context.cores.borda)),
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
      decoration: BoxDecoration(
        color: context.cores.superficie,
        border: Border(top: BorderSide(color: context.cores.borda)),
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

class _BotaoProposta extends StatefulWidget {
  const _BotaoProposta({
    required this.ativo,
    required this.rotuloAtivo,
    required this.rotuloInativo,
    required this.aoTocar,
  });

  final bool ativo;
  final String rotuloAtivo;
  final String rotuloInativo;
  final Future<void> Function() aoTocar;

  @override
  State<_BotaoProposta> createState() => _BotaoPropostaState();
}

class _BotaoPropostaState extends State<_BotaoProposta> {
  var _enviando = false;
  var _concluido = false;

  Future<void> _executar() async {
    if (_enviando || _concluido || !widget.ativo) return;
    setState(() => _enviando = true);
    try {
      await widget.aoTocar();
      if (mounted) setState(() => _concluido = true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.ativo && !_concluido;
    return FilledButton(
      onPressed: (habilitado && !_enviando) ? _executar : null,
      child: _enviando
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(habilitado ? widget.rotuloAtivo : widget.rotuloInativo),
    );
  }
}

/// Bottom sheet de resumo seguro (LGPD) do cliente aberto pelo profissional no topo do chat.
class FolhaResumoPerfilCliente extends StatefulWidget {
  const FolhaResumoPerfilCliente({
    super.key,
    required this.carregar,
    required this.nomeFallback,
    required this.iniciaisFallback,
  });

  final Future<ResumoPerfilCliente?> Function() carregar;
  final String nomeFallback;
  final String iniciaisFallback;

  @override
  State<FolhaResumoPerfilCliente> createState() => _FolhaResumoPerfilClienteState();
}

class _FolhaResumoPerfilClienteState extends State<FolhaResumoPerfilCliente> {
  late Future<ResumoPerfilCliente?> _futuro = widget.carregar();

  void _tentarDeNovo() => setState(() => _futuro = widget.carregar());

  static String? _formatarMembroDesde(String? iso) {
    final limpo = iso?.trim() ?? '';
    if (limpo.isEmpty) return null;
    final dt = DateTime.tryParse(limpo);
    if (dt == null) return limpo;
    final mes = dt.month.toString().padLeft(2, '0');
    return '$mes/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EspacosTrato.x5,
          EspacosTrato.x5,
          EspacosTrato.x5,
          EspacosTrato.x6,
        ),
        child: FutureBuilder<ResumoPerfilCliente?>(
          future: _futuro,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: EspacosTrato.x6),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Perfil do cliente', style: TipografiaTrato.titulo.copyWith(color: c.texto)),
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    'Não foi possível carregar o resumo agora. Tente de novo.',
                    style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
                  ),
                  const SizedBox(height: EspacosTrato.x4),
                  TextButton(onPressed: _tentarDeNovo, child: const Text('Tentar de novo')),
                ],
              );
            }
            final dados = snap.data;
            final nome =
                (dados?.nome.trim().isNotEmpty ?? false) ? dados!.nome.trim() : widget.nomeFallback;
            final nota = dados?.notaMedia;
            final totalAv = dados?.totalAvaliacoes ?? 0;
            final concluidos = dados?.servicosConcluidos ?? 0;
            final desde = _formatarMembroDesde(dados?.membroDesde);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.azulSuave,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.borda),
                      ),
                      child: Text(
                        widget.iniciaisFallback,
                        style: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nome, style: TipografiaTrato.titulo.copyWith(color: c.texto)),
                          if (desde != null)
                            Text(
                              'No Trato desde $desde',
                              style: TipografiaTrato.corpoPequeno.copyWith(
                                color: c.textoSecundario,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(EspacosTrato.x3),
                        decoration: BoxDecoration(
                          color: c.fundo,
                          borderRadius: BorderRadius.circular(EspacosTrato.raio),
                          border: Border.all(color: c.borda),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Avaliação',
                              style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
                            ),
                            const SizedBox(height: 4),
                            if (nota != null)
                              Text(
                                '★ ${nota.toStringAsFixed(1).replaceAll('.', ',')} ($totalAv)',
                                style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
                              )
                            else
                              Text(
                                'Sem avaliações ainda',
                                style: TipografiaTrato.corpoPequeno.copyWith(
                                  color: c.textoSecundario,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(EspacosTrato.x3),
                        decoration: BoxDecoration(
                          color: c.fundo,
                          borderRadius: BorderRadius.circular(EspacosTrato.raio),
                          border: Border.all(color: c.borda),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Serviços concluídos',
                              style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$concluidos',
                              style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
