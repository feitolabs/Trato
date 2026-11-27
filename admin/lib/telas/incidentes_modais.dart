import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';
import 'incidentes_tela.dart';

Future<void> abrirRegistroDeIncidente(BuildContext context) =>
    mostrarModal<void>(context, largura: 560, construir: (_) => const _ModalRegistro());

/// Devolve true se o backend aceitou.
Future<bool> abrirMedidaDeIncidente(BuildContext context, Incidente i) async =>
    await mostrarModal<bool>(context, construir: (_) => _ModalMedida(i)) ?? false;

Future<bool> abrirEncerramentoDeIncidente(BuildContext context, Incidente i) async =>
    await mostrarModal<bool>(context, construir: (_) => _ModalEncerrar(i)) ?? false;

/// Envio: trava o segundo clique e deixa o erro no modal, com o texto mantido.
mixin _Envio<T extends StatefulWidget> on State<T> {
  bool enviando = false;
  bool revisando = false;
  String? erro;

  Future<void> enviar(Future<String> Function() chamada, Object? resultado) async {
    if (enviando) return;
    setState(() {
      enviando = true;
      erro = null;
    });
    try {
      final aviso = await chamada();
      if (!mounted) return;
      mostrarAviso(context, aviso);
      Navigator.of(context).pop(resultado);
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
                : () => revisando ? setState(() => revisando = false) : Navigator.of(context).pop(),
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

  Widget texto(String rotulo, TextEditingController c, {int maximo = 4000, int linhas = 1, String? ajuda, String? falha}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration:
              InputDecoration(labelText: rotulo, helperText: ajuda, helperMaxLines: 2, errorText: falha, counterText: ''),
        ),
      );

  Widget escolha(String rotulo, String valor, Map<String, String> opcoes, ValueChanged<String> aoMudar) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: DropdownButtonFormField<String>(
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo),
          items: [for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => aoMudar(v ?? valor)),
        ),
      );
}

class _ModalRegistro extends StatefulWidget {
  const _ModalRegistro();

  @override
  State<_ModalRegistro> createState() => _ModalRegistroState();
}

class _ModalRegistroState extends State<_ModalRegistro> with _Envio {
  String _tipo = 'outro';
  String _canal = 'telefone';
  final _descricao = TextEditingController();
  final _contato = TextEditingController();
  final _pedido = TextEditingController();

  @override
  void dispose() {
    _descricao.dispose();
    _contato.dispose();
    _pedido.dispose();
    super.dispose();
  }

  bool get _exigePedido => _tipo == 'pessoa_diferente';

  @override
  Widget build(BuildContext context) {
    final pedido = _pedido.text.trim();
    return montar(
      titulo: revisando ? 'Confirmar o registro?' : 'Registrar incidente',
      consequencia: 'O prazo de 24 horas para a cautela começa no registro. Em risco imediato, oriente ligar '
          'para a polícia ou emergência.',
      verbo: 'Confirmar registro',
      valido: _descricao.text.trim().isNotEmpty &&
          _contato.text.trim().isNotEmpty &&
          (!_exigePedido || pedido.isNotEmpty),
      confirmar: () => enviar(() async {
        final r = await context.api.registrarIncidente(
          tipo: _tipo,
          descricao: _descricao.text.trim(),
          contato: _contato.text.trim(),
          canal: _canal,
          pedidoId: pedido.isEmpty ? null : pedido,
        );
        final protocolo = r.incidente.protocolo;
        return r.repetido
            ? 'Este relato já tinha sido registrado há pouco ($protocolo). Nada novo foi criado.'
            : 'Incidente registrado. Protocolo $protocolo: informe a quem relatou.';
      }, true),
      formulario: [
        escolha('Tipo', _tipo, kTiposIncidente, (v) => _tipo = v),
        escolha('Canal', _canal, {
          for (final e in kCanaisIncidente.entries)
            if (e.key != 'app') e.key: e.value,
        }, (v) => _canal = v),
        texto('O que aconteceu', _descricao, linhas: 3),
        texto('Contato de quem relatou', _contato, maximo: 320),
        texto(_exigePedido ? 'Código do pedido' : 'Código do pedido (opcional)', _pedido,
            maximo: 64, falha: _exigePedido && pedido.isEmpty ? 'Pessoa diferente exige o pedido' : null),
      ],
      revisao: [
        Linha('Tipo', rotuloDe(kTiposIncidente, _tipo)),
        Linha('Canal', rotuloDe(kCanaisIncidente, _canal)),
        Linha('Relato', _descricao.text.trim()),
        Linha('Contato', _contato.text.trim()),
        Linha('Pedido', pedido.isEmpty ? 'Sem pedido' : pedido),
      ],
    );
  }
}

class _ModalMedida extends StatefulWidget {
  const _ModalMedida(this.incidente);
  final Incidente incidente;

  @override
  State<_ModalMedida> createState() => _ModalMedidaState();
}

class _ModalMedidaState extends State<_ModalMedida> with _Envio {
  String _tipo = 'preservar_registros';
  final _descricao = TextEditingController();

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cancela = medidaCancelaDeVerdade(widget.incidente, _tipo);
    final efeito = BannerInfo(
      efeitoDaMedida(widget.incidente, _tipo),
      titulo: cancela ? 'Atenção: cancela e reembolsa.' : 'Efeito da medida.',
      tom: cancela ? Tom.erro : Tom.alerta,
    );
    return montar(
      titulo: revisando ? (cancela ? 'Cancelar o pedido com reembolso integral?' : 'Confirmar a medida?') : 'Adicionar medida',
      consequencia: 'O registro não pode ser apagado. Para suspender a conta, use "Medidas de conta".',
      verbo: cancela ? 'Cancelar e reembolsar' : 'Confirmar medida',
      destrutivo: cancela,
      valido: _descricao.text.trim().isNotEmpty,
      confirmar: () => enviar(() async {
        await context.api
            .adicionarMedidaIncidente(widget.incidente.id, tipo: _tipo, descricao: _descricao.text.trim());
        return cancela
            ? 'Medida registrada. Se o pedido ainda não estava cancelado, foi cancelado com reembolso integral.'
            : 'Medida registrada.';
      }, true),
      formulario: [
        escolha('Medida', _tipo, kMedidasIncidente, (v) => _tipo = v),
        const SizedBox(height: EspacosTrato.x3),
        efeito,
        texto('O que foi feito', _descricao, linhas: 3, maximo: 1000),
      ],
      revisao: [
        Linha('Medida', rotuloDe(kMedidasIncidente, _tipo)),
        Linha('O que foi feito', _descricao.text.trim()),
        const SizedBox(height: EspacosTrato.x3),
        efeito,
      ],
    );
  }
}

class _ModalEncerrar extends StatefulWidget {
  const _ModalEncerrar(this.incidente);
  final Incidente incidente;

  @override
  State<_ModalEncerrar> createState() => _ModalEncerrarState();
}

class _ModalEncerrarState extends State<_ModalEncerrar> with _Envio {
  final _desfecho = TextEditingController();

  @override
  void dispose() {
    _desfecho.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aviso = BannerInfo(
      'Encerrar pode soltar a retenção do dinheiro do pedido. Confira antes se o valor ainda precisa ficar retido. '
      'Incidente encerrado não reabre.',
      titulo: 'Atenção ao dinheiro.',
      tom: Tom.erro,
      icone: Icons.warning_amber_outlined,
    );
    final libera = liberadoAoEncerrar(widget.incidente);
    final avisos = [
      aviso,
      if (libera != null) ...[
        const SizedBox(height: EspacosTrato.x3),
        BannerInfo(libera, titulo: 'O que o encerramento libera.', tom: Tom.alerta),
      ],
    ];
    return montar(
      titulo: revisando ? 'Confirmar o encerramento?' : 'Encerrar o incidente ${widget.incidente.protocolo}',
      consequencia: 'Registre o desfecho da apuração.',
      verbo: 'Encerrar incidente',
      destrutivo: true,
      valido: _desfecho.text.trim().length >= kMotivoMinimo,
      confirmar: () => enviar(() async {
        await context.api.encerrarIncidente(widget.incidente.id, desfecho: _desfecho.text.trim());
        return 'Incidente encerrado.';
      }, true),
      formulario: [...avisos, texto('Desfecho', _desfecho, linhas: 3, ajuda: 'Pelo menos $kMotivoMinimo caracteres')],
      revisao: [...avisos, const SizedBox(height: EspacosTrato.x3), Linha('Desfecho', _desfecho.text.trim())],
    );
  }
}
