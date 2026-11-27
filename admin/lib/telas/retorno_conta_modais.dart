import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';

Future<bool> abrirAprovarRetorno(BuildContext context, PedidoRetornoConta r) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalAprovarRetorno(r)) ?? false;

Future<bool> abrirRecusarRetorno(BuildContext context, PedidoRetornoConta r) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalRecusarRetorno(r)) ?? false;

Future<bool> abrirRevogarImpedimento(BuildContext context, ImpedimentoCadastro i) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalRevogarImpedimento(i)) ?? false;

mixin _EnvioRetorno<T extends StatefulWidget> on State<T> {
  bool enviando = false;
  bool revisando = false;
  String? erro;

  Future<void> enviar(Future<String> Function() chamada) async {
    if (enviando) return;
    setState(() {
      enviando = true;
      erro = null;
    });
    try {
      final aviso = await chamada();
      if (!mounted) return;
      mostrarAviso(context, aviso);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          erro = e.toString();
          enviando = false;
          revisando = false;
        });
      }
    }
  }

  Widget montar({
    required String titulo,
    required String consequencia,
    required List<Widget> formulario,
    required List<Widget> revisao,
    required bool valido,
    required String verbo,
    required VoidCallback confirmar,
    bool destrutivo = false,
  }) {
    final aoConfirmar = enviando ? null : confirmar;
    return PopScope(
      canPop: !enviando,
      child: CorpoModal(
        titulo: titulo,
        consequencia: consequencia,
        filhos: [
          if (erro != null) ...[
            BannerInfo(erro!, titulo: 'Não foi feito.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(revisando ? revisao : formulario),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: enviando
                ? null
                : () => revisando ? setState(() => revisando = false) : Navigator.of(context).pop(false),
          ),
          if (!revisando)
            BotaoTrato.primario('Revisar', aoPressionar: valido ? () => setState(() => revisando = true) : null)
          else if (destrutivo)
            BotaoTrato.destrutivo(verbo, carregando: enviando, rotuloCarregando: 'Enviando', aoPressionar: aoConfirmar)
          else
            BotaoTrato.primario(verbo, carregando: enviando, rotuloCarregando: 'Enviando', aoPressionar: aoConfirmar),
        ],
      ),
    );
  }

  Widget campoMotivo(String rotulo, TextEditingController c, {int maximo = 2000}) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: 3,
          maxLines: 6,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: 'Pelo menos $kMotivoMinimo caracteres',
            counterText: '',
          ),
        ),
      );
}

class _ModalAprovarRetorno extends StatefulWidget {
  const _ModalAprovarRetorno(this.retorno);
  final PedidoRetornoConta retorno;

  @override
  State<_ModalAprovarRetorno> createState() => _ModalAprovarRetornoState();
}

class _ModalAprovarRetornoState extends State<_ModalAprovarRetorno> with _EnvioRetorno {
  final _motivo = TextEditingController();
  bool _semRiscoConfirmado = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mot = _motivo.text.trim();
    return montar(
      titulo: revisando ? 'Confirmar aprovação?' : 'Aprovar retorno ${widget.retorno.protocolo}',
      consequencia: 'Aprovar o retorno só é permitido sem risco identificado (Termos 20.9).',
      verbo: 'Confirmar aprovação',
      valido: _semRiscoConfirmado && mot.length >= kMotivoMinimo,
      confirmar: () => enviar(() async {
        await context.api.aprovarRetornoConta(widget.retorno.id, motivo: mot);
        return 'Pedido de retorno aprovado.';
      }),
      formulario: [
        campoMotivo('Motivo da aprovação', _motivo),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Confirmo que não há risco identificado (Termos 20.9)', style: TipografiaTrato.corpo),
            value: _semRiscoConfirmado,
            onChanged: (v) => setState(() => _semRiscoConfirmado = v ?? false),
          ),
        ),
      ],
      revisao: [
        Linha('Motivo', mot),
        const Linha('Risco identificado', 'Não (confirmado)'),
      ],
    );
  }
}

class _ModalRecusarRetorno extends StatefulWidget {
  const _ModalRecusarRetorno(this.retorno);
  final PedidoRetornoConta retorno;

  @override
  State<_ModalRecusarRetorno> createState() => _ModalRecusarRetornoState();
}

class _ModalRecusarRetornoState extends State<_ModalRecusarRetorno> with _EnvioRetorno {
  final _motivo = TextEditingController();
  bool _riscoIdentificado = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mot = _motivo.text.trim();
    return montar(
      titulo: revisando ? 'Confirmar recusa?' : 'Recusar retorno ${widget.retorno.protocolo}',
      consequencia: 'O pedido de retorno será recusado e a decisão ficará registrada na auditoria.',
      verbo: 'Confirmar recusa',
      destrutivo: true,
      valido: mot.length >= kMotivoMinimo,
      confirmar: () => enviar(() async {
        await context.api.recusarRetornoConta(
          widget.retorno.id,
          motivo: mot,
          riscoIdentificado: _riscoIdentificado,
        );
        return 'Pedido de retorno recusado.';
      }),
      formulario: [
        campoMotivo('Motivo da recusa', _motivo),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Risco identificado', style: TipografiaTrato.corpo),
            value: _riscoIdentificado,
            onChanged: (v) => setState(() => _riscoIdentificado = v ?? false),
          ),
        ),
      ],
      revisao: [
        Linha('Motivo', mot),
        Linha('Risco identificado', _riscoIdentificado ? 'Sim' : 'Não'),
      ],
    );
  }
}

class _ModalRevogarImpedimento extends StatefulWidget {
  const _ModalRevogarImpedimento(this.impedimento);
  final ImpedimentoCadastro impedimento;

  @override
  State<_ModalRevogarImpedimento> createState() => _ModalRevogarImpedimentoState();
}

class _ModalRevogarImpedimentoState extends State<_ModalRevogarImpedimento> with _EnvioRetorno {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mot = _motivo.text.trim();
    return montar(
      titulo: revisando ? 'Confirmar revogação?' : 'Revogar impedimento',
      consequencia: 'Revogar libera o identificador para novo cadastro e registra na auditoria.',
      verbo: 'Confirmar revogação',
      destrutivo: true,
      valido: mot.length >= kMotivoMinimo,
      confirmar: () => enviar(() async {
        await context.api.revogarImpedimentoConta(widget.impedimento.id, motivo: mot);
        return 'Impedimento revogado.';
      }),
      formulario: [campoMotivo('Motivo da revogação', _motivo, maximo: 1000)],
      revisao: [Linha('Motivo', mot)],
    );
  }
}
