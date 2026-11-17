import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/erros.dart';
import '../dados/servico_cep.dart';
import 'campo.dart';

/// Campo de CEP com busca automática ao completar 8 dígitos (ou pelo ícone de busca).
class CampoCepAutoPreenchimento extends StatefulWidget {
  const CampoCepAutoPreenchimento({
    super.key,
    required this.controlador,
    required this.servico,
    required this.aoEncontrar,
    this.rotulo = 'CEP',
    this.dica = '00000-000',
    this.erro,
    this.foco,
    this.proximoFoco,
    this.aoAlterar,
  });

  final TextEditingController controlador;
  final ServicoCep? servico;
  final void Function(EnderecoPorCep endereco) aoEncontrar;
  final String rotulo;
  final String? dica;
  final String? erro;
  final FocusNode? foco;
  final FocusNode? proximoFoco;
  final VoidCallback? aoAlterar;

  @override
  State<CampoCepAutoPreenchimento> createState() =>
      _CampoCepAutoPreenchimentoState();
}

class _CampoCepAutoPreenchimentoState extends State<CampoCepAutoPreenchimento> {
  Timer? _debounce;
  bool _buscando = false;
  String? _aviso;
  String _ultimoCepConsultado = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _digitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

  void _aoMudar(String valor) {
    widget.aoAlterar?.call();
    if (_aviso != null) setState(() => _aviso = null);
    final cep = _digitos(valor);
    _debounce?.cancel();
    if (cep.length != 8 || widget.servico == null) return;
    if (cep == _ultimoCepConsultado) return;
    _debounce = Timer(const Duration(milliseconds: 280), () => _buscar(cep));
  }

  Future<void> _buscar([String? cepForcado]) async {
    final servico = widget.servico;
    if (servico == null) return;
    final cep = cepForcado ?? _digitos(widget.controlador.text);
    if (cep.length != 8) {
      setState(() => _aviso = 'Digite os 8 números do CEP.');
      return;
    }
    if (_buscando) return;
    _ultimoCepConsultado = cep;
    setState(() {
      _buscando = true;
      _aviso = null;
    });
    try {
      final endereco = await servico.consultar(cep);
      if (!mounted) return;
      widget.aoEncontrar(endereco);
      if (widget.proximoFoco != null && widget.proximoFoco!.canRequestFocus) {
        widget.proximoFoco!.requestFocus();
      }
      setState(() => _buscando = false);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _aviso = e is ErroTrato
            ? e.mensagem
            : 'Não encontramos o CEP. Você pode preencher o endereço abaixo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CampoTrato(
          rotulo: widget.rotulo,
          controlador: widget.controlador,
          dica: widget.dica,
          erro: widget.erro ?? _aviso,
          foco: widget.foco,
          teclado: TextInputType.number,
          acaoTeclado: TextInputAction.search,
          aoEnviarTeclado: (_) => _buscar(),
          formatadores: [
            _FormatadorCep(),
          ],
          textoAcao: _buscando
              ? 'Buscando...'
              : (widget.servico != null ? 'Buscar CEP' : null),
          aoTocarAcao: _buscando || widget.servico == null ? null : _buscar,
          ajuda: widget.servico == null
              ? null
              : 'Digite o CEP para preencher rua, bairro e cidade.',
          aoMudar: _aoMudar,
        ),
      ],
    );
  }
}

class _FormatadorCep extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antigo,
    TextEditingValue novo,
  ) {
    final d = novo.text.replaceAll(RegExp(r'\D'), '');
    final lim = d.length > 8 ? d.substring(0, 8) : d;
    final texto = lim.length > 5 ? '${lim.substring(0, 5)}-${lim.substring(5)}' : lim;
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

