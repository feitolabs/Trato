import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dispositivo/explicacao_permissao.dart';
import '../../dispositivo/permissao.dart';
import '../../tema/tema.dart';
import '../auth/estrutura_auth.dart';
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'servico_check_in.dart';
import 'servico_check_out.dart';

/// Check-out: foto final do serviço e código de conclusão que o cliente informa.
/// O app só captura e envia; quem confere o código é o backend ([ServicoCheckOut]).
class CheckOutTela extends StatefulWidget {
  const CheckOutTela({
    super.key,
    required this.servico,
    required this.tituloBarra,
    this.aoConcluir,
    this.permissao,
    this.remoto = false,
  });

  /// Serviço remoto: sem foto final; só o código de conclusão.
  final bool remoto;

  final ServicoCheckOut servico;
  final String tituloBarra;

  /// Chamado quando o backend aceitou o código.
  final VoidCallback? aoConcluir;

  /// Se vier, explica e pede a câmera só na hora de usar.
  final ServicoPermissao? permissao;

  @override
  State<CheckOutTela> createState() => _CheckOutTelaState();
}

class _CheckOutTelaState extends State<CheckOutTela> with WidgetsBindingObserver {
  final _codigo = TextEditingController();
  final _justificativa = TextEditingController();
  FotoChegada? _foto;
  int? _distancia;
  bool _semCodigo = false;
  bool _enviando = false;
  String? _erroCodigo;
  String? _erro;
  String? _aviso;
  Timer? _timerOffline;
  var _reenviandoOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Ao voltar ao primeiro plano o "Sem internet" antigo sai: a conexão pode ter voltado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && mounted) {
      if (_aviso != null) setState(() => _aviso = null);
      if (_timerOffline != null) _tentarReenviarOffline();
    }
  }

  void _iniciarTimerOffline() {
    _timerOffline?.cancel();
    _timerOffline = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _tentarReenviarOffline(),
    );
  }

  Future<void> _tentarReenviarOffline() async {
    if (!mounted || _enviando || _reenviandoOffline) return;
    final servico = widget.servico;
    if (servico is! ReenvioOffline) return;
    _reenviandoOffline = true;
    try {
      final enviadas = await (servico as ReenvioOffline).reenviarPendentes();
      if (enviadas > 0 && mounted) {
        _timerOffline?.cancel();
        _timerOffline = null;
        setState(() => _aviso = null);
        widget.aoConcluir?.call();
      }
    } on Object {
      // Ainda sem sinal: a próxima tentativa do timer resolve.
    } finally {
      _reenviandoOffline = false;
    }
  }

  @override
  void dispose() {
    _timerOffline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _codigo.dispose();
    _justificativa.dispose();
    super.dispose();
  }

  bool get _podeConcluir {
    if (_semCodigo) {
      final provaOk = widget.remoto || (_foto != null && _distancia != null);
      return provaOk && _justificativa.text.trim().isNotEmpty;
    }
    return _codigo.text.length == 4 && (widget.remoto || _foto != null);
  }

  Future<void> _localizar() async {
    setState(() {
      _erro = null;
      _aviso = null;
    });
    final p = widget.permissao;
    if (p != null &&
        !await garantirPermissao(
            context, p, TipoPermissao.localizacao, TextoPermissao.localizacao)) {
      return;
    }
    try {
      final metros = await widget.servico.localizar();
      if (mounted && metros != null) setState(() => _distancia = metros);
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erro = 'Não deu para pegar sua localização agora. Tente de novo.');
      }
    }
  }

  Future<void> _tirarFoto() async {
    setState(() {
      _erro = null;
      _aviso = null;
    });
    final p = widget.permissao;
    if (p != null &&
        !await garantirPermissao(context, p, TipoPermissao.camera, TextoPermissao.cameraCheckIn)) {
      return;
    }
    try {
      final foto = await widget.servico.tirarFotoFinal();
      if (mounted && foto != null) setState(() => _foto = foto);
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erro = 'Não deu para tirar a foto agora. Tente de novo.');
      }
    }
  }

  Future<void> _concluir() async {
    if (_enviando) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _aviso = null; // novo envio: o "Sem internet" antigo sai
      _erro = null;
      _erroCodigo = null;
    });
    final ResultadoFim r;
    try {
      r = await widget.servico.finalizar(
        _semCodigo ? '' : _codigo.text,
        semCodigo: _semCodigo,
        justificativa: _semCodigo ? _justificativa.text.trim() : null,
      );
    } on ErroTrato catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = e.mensagem;
        });
      }
      return;
    } on Object {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = 'Não deu para concluir agora. Tente de novo.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (r == ResultadoFim.codigoIncorreto) {
        _erroCodigo = 'Código incorreto. Peça de novo ao cliente.';
      }
      if (r == ResultadoFim.guardadoOffline) {
        _aviso = 'Sem internet. Guardamos a conclusão e enviamos assim que o sinal voltar. '
            'O Trato ainda vai confirmar.';
        _iniciarTimerOffline();
      }
    });
    if (r == ResultadoFim.concluido) {
      _timerOffline?.cancel();
      _timerOffline = null;
      widget.aoConcluir?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    return EstruturaAuth(
      tituloBarra: widget.tituloBarra,
      rodape: BotaoPrimario(
        texto: 'Concluir serviço',
        carregando: _enviando,
        aoTocar: _podeConcluir ? _concluir : null,
      ),
      children: [
        Text('Check-out', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          widget.remoto
              ? 'Atendimento remoto: digite o código de conclusão que o cliente informar.'
              : 'Foto final e código de conclusão.',
          style: TipografiaTrato.corpo,
        ),
        const SizedBox(height: EspacosTrato.x5),
        if (!widget.remoto)
          CartaoTrato(
            child: Row(
              children: [
                if (foto != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(EspacosTrato.raio),
                    child: SizedBox.square(
                      dimension: EspacosTrato.x12 + EspacosTrato.x2,
                      child: ToquePreviewImagem(
                        referencia: foto.referencia ?? 'Foto final · ${foto.hora}',
                        legenda: 'Foto final · ${foto.hora}',
                        child: construirImagemReal(foto.referencia) ??
                            const ColoredBox(
                              color: CoresTrato.azulClaro,
                              child: Center(
                                child: Icon(Icons.zoom_in, size: 20, color: CoresTrato.petroleo),
                              ),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Foto final', style: TipografiaTrato.tituloCartao),
                      Text(
                        foto == null
                            ? 'Mostre o serviço pronto'
                            : '${foto.hora} · toque na foto para ver',
                        style: TipografiaTrato.legenda,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: EspacosTrato.x2),
                foto != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const ChipStatus(
                            texto: 'Feito',
                            tipo: TipoStatus.sucesso,
                            icone: Icons.check,
                          ),
                          const SizedBox(height: EspacosTrato.x1),
                          BotaoLink(texto: 'Refazer', aoTocar: _tirarFoto),
                        ],
                      )
                    : BotaoLink(texto: 'Tirar foto', aoTocar: _tirarFoto),
              ],
            ),
          ),
        if (!widget.remoto) const SizedBox(height: EspacosTrato.x3),
        if (_semCodigo && !widget.remoto) ...[
          CartaoTrato(
            child: Row(
              children: [
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(EspacosTrato.raio)),
                  child: SizedBox.square(
                    dimension: EspacosTrato.x12 + EspacosTrato.x2,
                    child: ColoredBox(
                      color: CoresTrato.azulSuave,
                      child: Icon(Icons.location_on_outlined, color: CoresTrato.azulTexto),
                    ),
                  ),
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Localização', style: TipografiaTrato.tituloCartao),
                      Text(
                        _distancia == null
                            ? 'Confirme sua localização no encerramento'
                            : 'Localização registrada',
                        style: TipografiaTrato.legenda,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: EspacosTrato.x2),
                _distancia != null
                    ? const ChipStatus(
                        texto: 'Feito',
                        tipo: TipoStatus.sucesso,
                        icone: Icons.check,
                      )
                    : BotaoLink(texto: 'Localizar', aoTocar: _localizar),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_semCodigo) ...[
          TextField(
            controller: _justificativa,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Justificativa',
              hintText: 'Ex.: Cliente sem bateria ou sinal na saída',
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoFaixa(
            texto: 'O pagamento só será liberado após o cliente confirmar no app.',
            tipo: TipoStatus.alerta,
            icone: Icons.info_outline,
          ),
        ] else
          TextField(
            controller: _codigo,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _erroCodigo = null),
            style: TipografiaTrato.tituloGrande.copyWith(letterSpacing: 12),
            decoration: InputDecoration(
              counterText: '',
              errorText: _erroCodigo,
              hintText: '— — — —',
              labelText: 'Código de conclusão',
            ),
          ),
        const SizedBox(height: EspacosTrato.x2),
        Center(
          child: BotaoLink(
            texto: _semCodigo ? 'Voltar para código de 4 dígitos' : 'Cliente sem bateria ou sinal?',
            aoTocar: () => setState(() {
              _semCodigo = !_semCodigo;
              _erroCodigo = null;
            }),
          ),
        ),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_aviso!, style: TipografiaTrato.legenda),
        ],
      ],
    );
  }
}
