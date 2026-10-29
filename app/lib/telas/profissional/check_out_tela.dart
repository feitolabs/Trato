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
  });

  final ServicoCheckOut servico;
  final String tituloBarra;

  /// Chamado quando o backend aceitou o código.
  final VoidCallback? aoConcluir;

  /// Se vier, explica e pede a câmera só na hora de usar.
  final ServicoPermissao? permissao;

  @override
  State<CheckOutTela> createState() => _CheckOutTelaState();
}

class _CheckOutTelaState extends State<CheckOutTela> {
  final _codigo = TextEditingController();
  FotoChegada? _foto;
  bool _enviando = false;
  String? _erroCodigo;
  String? _erro;
  String? _aviso;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  bool get _podeConcluir => _foto != null && _codigo.text.length == 4;

  Future<void> _tirarFoto() async {
    setState(() => _erro = null);
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
    }
  }

  Future<void> _concluir() async {
    setState(() {
      _enviando = true;
      _erro = null;
      _erroCodigo = null;
    });
    final ResultadoFim r;
    try {
      r = await widget.servico.finalizar(_codigo.text);
    } on ErroTrato catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = e.mensagem;
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
      }
    });
    if (r == ResultadoFim.concluido) widget.aoConcluir?.call();
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
        Text('Foto final e código de conclusão.', style: TipografiaTrato.corpo),
        const SizedBox(height: EspacosTrato.x5),
        CartaoTrato(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Foto final', style: TipografiaTrato.tituloCartao),
                    Text(foto?.hora ?? 'Mostre o serviço pronto', style: TipografiaTrato.legenda),
                  ],
                ),
              ),
              foto != null
                  ? const ChipStatus(texto: 'Feito', tipo: TipoStatus.sucesso, icone: Icons.check)
                  : BotaoLink(texto: 'Tirar foto', aoTocar: _tirarFoto),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
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
