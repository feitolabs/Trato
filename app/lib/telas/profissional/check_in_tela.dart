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
  });

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

class _CheckInTelaState extends State<CheckInTela> {
  final _codigo = TextEditingController();
  late FotoChegada? _foto = widget.fotoInicial;
  late int? _distancia = widget.distanciaInicialMetros;
  bool _iniciando = false;
  String? _erroCodigo;
  String? _aviso;
  String? _erroPasso;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  bool get _podeIniciar => _foto != null && _distancia != null && _codigo.text.length == 4;

  Future<bool> _permitido(TipoPermissao tipo, TextoPermissao texto) async {
    final p = widget.permissao;
    return p == null || await garantirPermissao(context, p, tipo, texto);
  }

  Future<void> _tirarFoto() async {
    setState(() => _erroPasso = null);
    if (!await _permitido(TipoPermissao.camera, TextoPermissao.cameraCheckIn)) return;
    try {
      final foto = await widget.servico.tirarFoto();
      if (mounted && foto != null) setState(() => _foto = foto);
    } on ErroTrato catch (erro) {
      if (mounted) setState(() => _erroPasso = erro.mensagem);
    }
  }

  Future<void> _localizar() async {
    setState(() => _erroPasso = null);
    if (!await _permitido(TipoPermissao.localizacao, TextoPermissao.localizacao)) return;
    try {
      final metros = await widget.servico.localizar();
      if (mounted && metros != null) setState(() => _distancia = metros);
    } on ErroTrato catch (erro) {
      if (mounted) setState(() => _erroPasso = erro.mensagem);
    }
  }

  Future<void> _enviarMensagem(String mensagem) async {
    await widget.servico.enviarMensagemRapida(mensagem);
    if (mounted) setState(() => _aviso = 'Mensagem enviada: $mensagem');
  }

  Future<void> _clienteAusente() async {
    await widget.servico.avisarClienteAusente();
    if (mounted) setState(() => _aviso = 'Avisamos o cliente e a central.');
  }

  Future<void> _iniciar() async {
    setState(() {
      _iniciando = true;
      _erroCodigo = null;
    });
    final ResultadoInicio resultado;
    try {
      resultado = await widget.servico.iniciarServico(_codigo.text);
    } on ErroTrato catch (erro) {
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erroPasso = erro.mensagem;
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
      }
    });
    if (resultado == ResultadoInicio.iniciado) widget.aoIniciar?.call();
  }

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    final distancia = _distancia;
    return EstruturaAuth(
      tituloBarra: widget.tituloBarra,
      rodape: BotaoPrimario(
        texto: 'Iniciar serviço',
        carregando: _iniciando,
        aoTocar: _podeIniciar ? _iniciar : null,
      ),
      children: [
        Text('Check-in', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text('Três passos para começar o serviço.', style: TipografiaTrato.corpo),
        const SizedBox(height: EspacosTrato.x5),
        _CartaoPasso(
          miniatura: const ColoredBox(color: CoresTrato.azulClaro),
          titulo: 'Foto de chegada',
          detalhe: foto?.hora ?? 'Tire uma foto do local',
          feito: foto != null,
          textoAcao: 'Tirar foto',
          aoTocarAcao: _tirarFoto,
        ),
        const SizedBox(height: EspacosTrato.x3),
        _CartaoPasso(
          miniatura: const ColoredBox(
            color: CoresTrato.azulSuave,
            child: Icon(Icons.location_on_outlined, color: CoresTrato.azulTexto),
          ),
          titulo: 'Localização',
          detalhe: distancia == null ? 'Confirme que você chegou' : 'A $distancia m do endereço',
          feito: distancia != null,
          textoAcao: 'Localizar',
          aoTocarAcao: _localizar,
        ),
        if (distancia != null && distancia > widget.avisoDistanciaMetros) ...[
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
        _CartaoCodigo(
          controlador: _codigo,
          erro: _erroCodigo,
          aoMudar: () => setState(() => _erroCodigo = null),
        ),
        const SizedBox(height: EspacosTrato.x5),
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
        if (_aviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_aviso!, style: TipografiaTrato.legenda),
        ],
        const SizedBox(height: EspacosTrato.x5),
        Center(child: BotaoLink(texto: 'Cliente não está no local', aoTocar: _clienteAusente)),
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
                  ? const ChipStatus(texto: 'Feito', tipo: TipoStatus.sucesso, icone: Icons.check)
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
  const _CartaoCodigo({required this.controlador, required this.aoMudar, this.erro});

  final TextEditingController controlador;
  final VoidCallback aoMudar;
  final String? erro;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CoresTrato.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: CoresTrato.petroleo, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Código de início', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text('Peça os 4 números para a cliente.', style: TipografiaTrato.legenda),
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
      color: CoresTrato.superficie,
      shape: const StadiumBorder(side: BorderSide(color: CoresTrato.petroleo)),
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
