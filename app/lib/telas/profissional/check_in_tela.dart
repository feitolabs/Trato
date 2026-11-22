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

/// Tela 26: "Check-in". Três passos: foto de chegada, localização e código de início.
/// O app só captura e envia; quem confere o código e a prova é o backend ([ServicoCheckIn]).
class CheckInTela extends StatefulWidget {
  const CheckInTela({
    super.key,
    required this.servico,
    required this.tituloBarra,
    this.fotoInicial,
    this.distanciaInicialMetros,
    this.mensagensRapidas = const ['Cheguei', 'Estou na portaria', 'Preciso de 15 minutos'],
    this.aoIniciar,
    this.permissao,
    this.avisoDistanciaMetros = 300,
    this.remoto = false,
  });

  /// Serviço remoto: sem foto de chegada nem localização; só o código que o cliente informa.
  final bool remoto;

  final ServicoCheckIn servico;

  /// Ex.: "Mariana · hoje, 14h".
  final String tituloBarra;
  final FotoChegada? fotoInicial;
  final int? distanciaInicialMetros;
  final List<String> mensagensRapidas;

  /// Chamado quando o backend aceitou o código e o serviço começou.
  final VoidCallback? aoIniciar;

  /// Se vier, a tela explica e pede câmera e localização só na hora de usar. Sem ele (testes
  /// antigos e demonstração), assume que o serviço cuida disso.
  final ServicoPermissao? permissao;

  /// Acima disso a tela só mostra um aviso de "você parece longe". Não bloqueia: quem confere
  /// a presença no local é o backend.
  final int avisoDistanciaMetros;

  @override
  State<CheckInTela> createState() => _CheckInTelaState();
}

class _CheckInTelaState extends State<CheckInTela> with WidgetsBindingObserver {
  final _codigo = TextEditingController();
  final _justificativa = TextEditingController();
  late FotoChegada? _foto = widget.fotoInicial;
  late int? _distancia = widget.distanciaInicialMetros;
  bool _semCodigo = false;
  bool _iniciando = false;
  String? _erroCodigo;
  String? _aviso;
  String? _erroPasso;
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
    if (!mounted || _iniciando || _reenviandoOffline) return;
    final servico = widget.servico;
    if (servico is! ReenvioOffline) return;
    _reenviandoOffline = true;
    try {
      final enviadas = await (servico as ReenvioOffline).reenviarPendentes();
      if (enviadas > 0 && mounted) {
        _timerOffline?.cancel();
        _timerOffline = null;
        setState(() => _aviso = null);
        widget.aoIniciar?.call();
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

  bool get _podeIniciar {
    final provaOk = widget.remoto || (_foto != null && _distancia != null);
    if (!provaOk) return false;
    return _semCodigo ? _justificativa.text.trim().isNotEmpty : _codigo.text.length == 4;
  }

  Future<bool> _permitido(TipoPermissao tipo, TextoPermissao texto) async {
    final p = widget.permissao;
    return p == null || await garantirPermissao(context, p, tipo, texto);
  }

  Future<void> _tirarFoto() async {
    setState(() {
      _erroPasso = null;
      _aviso = null;
    });
    if (!await _permitido(TipoPermissao.camera, TextoPermissao.cameraCheckIn)) {
      return;
    }
    try {
      final foto = await widget.servico.tirarFoto();
      if (mounted && foto != null) setState(() => _foto = foto);
    } on ErroTrato catch (erro) {
      if (mounted) setState(() => _erroPasso = erro.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erroPasso = 'Não deu para tirar a foto agora. Tente de novo.');
      }
    }
  }

  Future<void> _localizar() async {
    setState(() {
      _erroPasso = null;
      _aviso = null;
    });
    if (!await _permitido(TipoPermissao.localizacao, TextoPermissao.localizacao)) {
      if (mounted) {
        setState(() => _erroPasso = 'Ative a localização nas configurações para fazer o check-in.');
      }
      return;
    }
    try {
      final metros = await widget.servico.localizar();
      if (mounted && metros != null) setState(() => _distancia = metros);
    } on ErroTrato catch (erro) {
      if (mounted) setState(() => _erroPasso = erro.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erroPasso = 'Não deu para pegar sua localização agora. Tente de novo.');
      }
    }
  }

  Future<void> _enviarMensagem(String mensagem) async {
    setState(() {
      _erroPasso = null;
      _aviso = null;
    });
    try {
      await widget.servico.enviarMensagemRapida(mensagem);
      if (mounted) setState(() => _aviso = 'Mensagem enviada: $mensagem');
    } on ErroTrato catch (erro) {
      if (mounted) setState(() => _erroPasso = erro.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erroPasso = 'Não foi possível enviar a mensagem agora.');
      }
    }
  }

  Future<void> _confirmarClienteAusente() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Registrar cliente ausente?'),
        content: const Text(
          'Isso registra formalmente sua chegada no local e envia um aviso ao cliente no chat do pedido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Confirmar ausência'),
          ),
        ],
      ),
    );
    if (confirmar == true && mounted) {
      await _clienteAusente();
    }
  }

  Future<void> _clienteAusente() async {
    setState(() {
      _erroPasso = null;
      _aviso = null;
    });
    try {
      await widget.servico.avisarClienteAusente();
      if (mounted) {
        setState(
          () => _aviso =
              'Ocorrência de cliente ausente registrada com comprovação e aviso ao cliente.',
        );
      }
    } on ErroTrato catch (erro) {
      if (mounted) setState(() => _erroPasso = erro.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erroPasso = 'Não deu para registrar a ausência agora. Tente de novo.');
      }
    }
  }

  Future<void> _iniciar() async {
    if (_iniciando) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _iniciando = true;
      _aviso = null; // nova tentativa: o "Sem internet" antigo sai
      _erroCodigo = null;
    });
    final ResultadoInicio resultado;
    try {
      resultado = await widget.servico.iniciarServico(
        _semCodigo ? '' : _codigo.text,
        semCodigo: _semCodigo,
        justificativa: _semCodigo ? _justificativa.text.trim() : null,
      );
    } on ErroTrato catch (erro) {
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erroPasso = erro.mensagem;
        });
      }
      return;
    } on Object {
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erroPasso = 'Não deu para iniciar agora. Tente de novo.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _iniciando = false;
      if (resultado == ResultadoInicio.codigoIncorreto) {
        _erroCodigo = 'Código incorreto. Peça de novo ao cliente.';
      }
      if (resultado == ResultadoInicio.guardadoOffline) {
        _aviso = 'Sem internet. Guardamos sua chegada e enviamos assim que o sinal voltar. '
            'O serviço só começa quando o Trato confirmar.';
        _iniciarTimerOffline();
      }
    });
    if (resultado == ResultadoInicio.iniciado) {
      _timerOffline?.cancel();
      _timerOffline = null;
      widget.aoIniciar?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    final distancia = _distancia;
    return EstruturaAuth(
      tituloBarra: widget.tituloBarra,
      rodape: BotaoPrimario(
        texto: widget.remoto ? 'Iniciar atendimento' : 'Iniciar serviço',
        carregando: _iniciando,
        aoTocar: _podeIniciar ? _iniciar : null,
      ),
      children: [
        Text(widget.remoto ? 'Iniciar atendimento' : 'Check-in',
            style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          widget.remoto
              ? 'Atendimento remoto: peça ao cliente o código de início e digite abaixo. '
                  'Não precisa de foto nem de localização.'
              : 'Três passos para começar o serviço.',
          style: TipografiaTrato.corpo,
        ),
        const SizedBox(height: EspacosTrato.x5),
        if (!widget.remoto) ...[
          _CartaoPasso(
            miniatura: foto == null
                ? ColoredBox(color: context.cores.azulSuave)
                : ToquePreviewImagem(
                    referencia: foto.referencia ?? 'Foto de chegada · ${foto.hora}',
                    legenda: 'Foto de chegada · ${foto.hora}',
                    child: construirImagemReal(foto.referencia) ??
                        ColoredBox(
                          color: context.cores.azulSuave,
                          child: Center(
                            child: Icon(Icons.zoom_in, size: 20, color: context.cores.petroleo),
                          ),
                        ),
                  ),
            titulo: 'Foto de chegada',
            detalhe:
                foto == null ? 'Tire uma foto do local' : '${foto.hora} · toque na foto para ver',
            feito: foto != null,
            textoAcao: 'Tirar foto',
            aoTocarAcao: _tirarFoto,
          ),
          const SizedBox(height: EspacosTrato.x3),
          _CartaoPasso(
            miniatura: ColoredBox(
              color: context.cores.azulSuave,
              child: Icon(Icons.location_on_outlined, color: context.cores.azulTexto),
            ),
            titulo: 'Localização',
            detalhe: distancia == null
                ? 'Confirme que você chegou'
                : distancia == distanciaDesconhecidaMetros
                    ? 'Localização registrada'
                    : 'A $distancia m do endereço',
            feito: distancia != null,
            textoAcao: 'Localizar',
            aoTocarAcao: _localizar,
          ),
        ],
        if (!widget.remoto &&
            distancia != null &&
            distancia != distanciaDesconhecidaMetros &&
            distancia > widget.avisoDistanciaMetros) ...[
          const SizedBox(height: EspacosTrato.x3),
          const AvisoFaixa(
            texto: 'Você parece estar longe do endereço. Confira se está no lugar certo; '
                'o Trato confere de novo ao iniciar.',
            tipo: TipoStatus.alerta,
            icone: Icons.location_off_outlined,
          ),
        ],
        if (_erroPasso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          AvisoFaixa(texto: _erroPasso!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
        ],
        const SizedBox(height: EspacosTrato.x3),
        if (_semCodigo)
          _CartaoSemCodigo(
            titulo: 'Iniciar sem código',
            subtitulo: 'Use apenas se o cliente estiver sem bateria ou sinal na porta.',
            controlador: _justificativa,
            aoMudar: () => setState(() {}),
            aoVoltarCodigo: () => setState(() {
              _semCodigo = false;
              _erroCodigo = null;
            }),
          )
        else
          _CartaoCodigo(
            controlador: _codigo,
            erro: _erroCodigo,
            aoMudar: () => setState(() => _erroCodigo = null),
            aoSemCodigo: () => setState(() {
              _semCodigo = true;
              _erroCodigo = null;
            }),
          ),
        if (!widget.remoto) ...[
          const SizedBox(height: EspacosTrato.x4),
          Text('Mensagem rápida', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final mensagem in widget.mensagensRapidas)
                _ChipMensagem(texto: mensagem, aoTocar: () => _enviarMensagem(mensagem)),
            ],
          ),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_aviso!, style: TipografiaTrato.legenda),
        ],
        if (!widget.remoto) ...[
          const SizedBox(height: EspacosTrato.x8),
          const Divider(),
          const SizedBox(height: EspacosTrato.x3),
          Center(
            child: TextButton(
              key: const Key('cliente-ausente'),
              onPressed: _confirmarClienteAusente,
              style: TextButton.styleFrom(foregroundColor: context.cores.textoSecundario),
              child: const Text('Cliente não está no local'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CartaoPasso extends StatelessWidget {
  const _CartaoPasso({
    required this.miniatura,
    required this.titulo,
    required this.detalhe,
    required this.feito,
    required this.textoAcao,
    required this.aoTocarAcao,
  });

  final Widget miniatura;
  final String titulo;
  final String detalhe;
  final bool feito;
  final String textoAcao;
  final VoidCallback aoTocarAcao;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
            child: SizedBox.square(dimension: EspacosTrato.x12 + EspacosTrato.x2, child: miniatura),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TipografiaTrato.tituloCartao),
                Text(detalhe, style: TipografiaTrato.legenda),
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x2),
          // Em tela estreita com fonte grande, a ação encolhe em vez de estourar.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: EspacosTrato.x12 * 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: feito
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
                        BotaoLink(texto: 'Refazer', aoTocar: aoTocarAcao),
                      ],
                    )
                  : BotaoLink(texto: textoAcao, aoTocar: aoTocarAcao),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão com contorno petróleo: é o passo em destaque do protótipo.
class _CartaoCodigo extends StatelessWidget {
  const _CartaoCodigo({
    required this.controlador,
    required this.aoMudar,
    required this.aoSemCodigo,
    this.erro,
  });

  final TextEditingController controlador;
  final VoidCallback aoMudar;
  final VoidCallback aoSemCodigo;
  final String? erro;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.cores.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: context.cores.petroleo, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Código de início', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text('Peça os 4 números ao cliente.', style: TipografiaTrato.legenda),
            const SizedBox(height: EspacosTrato.x4),
            TextField(
              controller: controlador,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => aoMudar(),
              style: TipografiaTrato.tituloGrande.copyWith(letterSpacing: 12),
              decoration: InputDecoration(counterText: '', errorText: erro, hintText: '— — — —'),
            ),
            const SizedBox(height: EspacosTrato.x1),
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoLink(
                texto: 'Cliente sem bateria ou sinal?',
                aoTocar: aoSemCodigo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoSemCodigo extends StatelessWidget {
  const _CartaoSemCodigo({
    required this.titulo,
    required this.subtitulo,
    required this.controlador,
    required this.aoMudar,
    required this.aoVoltarCodigo,
  });

  final String titulo;
  final String subtitulo;
  final TextEditingController controlador;
  final VoidCallback aoMudar;
  final VoidCallback aoVoltarCodigo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.cores.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: context.cores.petroleo, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(subtitulo, style: TipografiaTrato.legenda),
            const SizedBox(height: EspacosTrato.x4),
            TextField(
              controller: controlador,
              maxLines: 2,
              onChanged: (_) => aoMudar(),
              decoration: const InputDecoration(
                labelText: 'Justificativa',
                hintText: 'Ex.: Cliente sem bateria ou sinal na porta',
              ),
            ),
            const SizedBox(height: EspacosTrato.x1),
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoLink(
                texto: 'Voltar para código de 4 dígitos',
                aoTocar: aoVoltarCodigo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipMensagem extends StatelessWidget {
  const _ChipMensagem({required this.texto, required this.aoTocar});

  final String texto;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cores.superficie,
      shape: StadiumBorder(side: BorderSide(color: context.cores.petroleo)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x4,
            vertical: EspacosTrato.x3,
          ),
          child: Text(texto, style: TipografiaTrato.corpo),
        ),
      ),
    );
  }
}
