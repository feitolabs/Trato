import 'package:flutter/material.dart';

import '../tema/tema.dart';
import 'botoes.dart';
import 'icones.dart';

/// Tamanho mínimo do motivo (só orientação de tela; o backend também exige motivo).
const kMotivoMinimo = 10;

const kTextoAuditoria = 'Esta ação fica registrada na auditoria com seu nome e o motivo.';

/// Abre [construir] como modal: caixa centralizada com cantos de 24 px no desktop e no tablet;
/// sobe da base da tela (RNF-01) no celular. Atrás vai a camada escura translúcida.
Future<T?> mostrarModal<T>(BuildContext context, {required WidgetBuilder construir, double largura = 480}) {
  if (FaixaPainel.de(context).ehCelular) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(child: construir(ctx)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(EspacosTrato.x4),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largura),
        child: SingleChildScrollView(child: construir(ctx)),
      ),
    ),
  );
}

/// Esqueleto de um modal do DS: título, consequência em uma frase, corpo e ações à direita.
class CorpoModal extends StatelessWidget {
  const CorpoModal({
    super.key,
    required this.titulo,
    this.consequencia,
    this.filhos = const [],
    required this.acoes,
  });

  final String titulo;
  final String? consequencia;
  final List<Widget> filhos;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(titulo, style: TipografiaTrato.secao)),
          if (consequencia != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(consequencia!, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo)),
          ],
          if (filhos.isNotEmpty) const SizedBox(height: EspacosTrato.x4),
          ...filhos,
          const SizedBox(height: EspacosTrato.x6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            children: acoes,
          ),
        ],
      ),
    );
  }
}

/// Aviso fixo de que a ação vira linha na trilha de auditoria.
class AvisoAuditoria extends StatelessWidget {
  const AvisoAuditoria({super.key, this.texto = kTextoAuditoria});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(IconesTrato.auditoria, size: 16, color: CoresTrato.textoMudo),
        ),
        const SizedBox(width: EspacosTrato.x2),
        Expanded(child: Text(texto, style: TipografiaTrato.legenda)),
      ],
    );
  }
}

/// Pede o motivo antes de uma ação sensível (padrão de interação 1 do DS):
/// consequência descrita, campo Motivo (mín. 10), aviso de auditoria, Cancelar e o verbo da ação.
/// O botão de confirmação fica desabilitado até o motivo ser válido. Devolve o motivo, ou null.
///
/// [motivosPadrao]: lista padronizada (RF-VER-04); a pessoa escolhe um e pode somar texto livre.
Future<String?> pedirMotivo(
  BuildContext context, {
  required String titulo,
  String? descricao,
  String rotuloConfirmar = 'Confirmar',
  bool destrutivo = false,
  List<String>? motivosPadrao,
}) {
  return mostrarModal<String>(
    context,
    construir: (_) => _ModalMotivo(
      titulo: titulo,
      descricao: descricao,
      rotuloConfirmar: rotuloConfirmar,
      destrutivo: destrutivo,
      motivosPadrao: motivosPadrao,
    ),
  );
}

class _ModalMotivo extends StatefulWidget {
  const _ModalMotivo({
    required this.titulo,
    required this.descricao,
    required this.rotuloConfirmar,
    required this.destrutivo,
    required this.motivosPadrao,
  });

  final String titulo;
  final String? descricao;
  final String rotuloConfirmar;
  final bool destrutivo;
  final List<String>? motivosPadrao;

  @override
  State<_ModalMotivo> createState() => _ModalMotivoState();
}

class _ModalMotivoState extends State<_ModalMotivo> {
  final _controle = TextEditingController();
  final _foco = FocusNode();
  String? _padrao;
  bool _saiuDoCampo = false;

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (!_foco.hasFocus && _controle.text.isNotEmpty) setState(() => _saiuDoCampo = true);
    });
  }

  @override
  void dispose() {
    _controle.dispose();
    _foco.dispose();
    super.dispose();
  }

  int get _tamanho => _controle.text.trim().length;
  bool get _usaLista => widget.motivosPadrao != null;
  bool get _valido => _usaLista ? _padrao != null : _tamanho >= kMotivoMinimo;

  String get _motivoFinal {
    final livre = _controle.text.trim();
    if (!_usaLista) return livre;
    return livre.isEmpty ? _padrao! : '${_padrao!}: $livre';
  }

  @override
  Widget build(BuildContext context) {
    final erro = !_usaLista && _saiuDoCampo && _tamanho < kMotivoMinimo;
    final ajuda = _usaLista
        ? 'Detalhes são opcionais'
        : (_tamanho == 0 ? 'Pelo menos $kMotivoMinimo caracteres' : '$_tamanho de $kMotivoMinimo caracteres mínimos');
    final confirmar = _valido ? () => Navigator.of(context).pop(_motivoFinal) : null;

    return CorpoModal(
      titulo: widget.titulo,
      consequencia: widget.descricao,
      filhos: [
        if (_usaLista) ...[
          DropdownButtonFormField<String>(
            initialValue: _padrao,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Motivo da lista'),
            items: [
              for (final m in widget.motivosPadrao!) DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _padrao = v),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        TextField(
          controller: _controle,
          focusNode: _foco,
          autofocus: !_usaLista,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _usaLista ? 'Motivo (detalhes)' : 'Motivo',
            helperText: erro ? null : ajuda,
            errorText: erro ? 'Escreva ao menos $kMotivoMinimo caracteres' : null,
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        const AvisoAuditoria(),
      ],
      acoes: [
        BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop()),
        widget.destrutivo
            ? BotaoTrato.destrutivo(widget.rotuloConfirmar, aoPressionar: confirmar)
            : BotaoTrato.primario(widget.rotuloConfirmar, aoPressionar: confirmar),
      ],
    );
  }
}

/// Campo Motivo do DS: rótulo flutuante "Motivo", ajuda "Pelo menos 10 caracteres", contagem
/// "14 de 10 caracteres mínimos" e erro só depois que a pessoa sai do campo com texto curto.
class CampoMotivo extends StatefulWidget {
  const CampoMotivo({super.key, required this.controle, required this.aoMudar, this.rotulo = 'Motivo'});

  final TextEditingController controle;
  final VoidCallback aoMudar;
  final String rotulo;

  @override
  State<CampoMotivo> createState() => _CampoMotivoState();
}

class _CampoMotivoState extends State<CampoMotivo> {
  final _foco = FocusNode();
  bool _saiu = false;

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (!_foco.hasFocus && widget.controle.text.isNotEmpty) setState(() => _saiu = true);
    });
  }

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.controle.text.trim().length;
    final erro = _saiu && n < kMotivoMinimo;
    return TextField(
      controller: widget.controle,
      focusNode: _foco,
      minLines: 2,
      maxLines: 4,
      onChanged: (_) {
        setState(() {});
        widget.aoMudar();
      },
      decoration: InputDecoration(
        labelText: widget.rotulo,
        helperText: erro ? null : (n == 0 ? 'Pelo menos $kMotivoMinimo caracteres' : '$n de $kMotivoMinimo caracteres mínimos'),
        errorText: erro ? 'Escreva ao menos $kMotivoMinimo caracteres' : null,
      ),
    );
  }
}

/// Modal de ação sensível com campos próprios (padrão de interação 1 do DS): consequência,
/// campos, Motivo, aviso de auditoria, Cancelar e o verbo da ação. O botão só habilita com os
/// campos válidos e o motivo de pelo menos 10 caracteres. Devolve [resultado] ou null.
class ModalFormulario<T> extends StatefulWidget {
  const ModalFormulario({
    super.key,
    required this.titulo,
    required this.rotuloConfirmar,
    required this.campos,
    required this.camposValidos,
    required this.resultado,
    this.consequencia,
    this.destrutivo = false,
  });

  final String titulo;
  final String? consequencia;
  final String rotuloConfirmar;
  final bool destrutivo;

  /// Constrói os campos; chame o `rebuild` quando algum mudar, para o botão reavaliar.
  final Widget Function(BuildContext context, VoidCallback rebuild) campos;
  final bool Function() camposValidos;
  final T Function(String motivo) resultado;

  @override
  State<ModalFormulario<T>> createState() => _ModalFormularioState<T>();
}

class _ModalFormularioState<T> extends State<ModalFormulario<T>> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido = widget.camposValidos() && _motivo.text.trim().length >= kMotivoMinimo;
    final confirmar = valido ? () => Navigator.of(context).pop(widget.resultado(_motivo.text.trim())) : null;
    return CorpoModal(
      titulo: widget.titulo,
      consequencia: widget.consequencia,
      filhos: [
        widget.campos(context, () => setState(() {})),
        const SizedBox(height: EspacosTrato.x3),
        CampoMotivo(controle: _motivo, aoMudar: () => setState(() {})),
        const SizedBox(height: EspacosTrato.x3),
        const AvisoAuditoria(),
      ],
      acoes: [
        BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop()),
        widget.destrutivo
            ? BotaoTrato.destrutivo(widget.rotuloConfirmar, aoPressionar: confirmar)
            : BotaoTrato.primario(widget.rotuloConfirmar, aoPressionar: confirmar),
      ],
    );
  }
}

/// Abre um [ModalFormulario].
Future<T?> pedirFormulario<T>(
  BuildContext context, {
  required String titulo,
  required String rotuloConfirmar,
  required Widget Function(BuildContext context, VoidCallback rebuild) campos,
  required bool Function() camposValidos,
  required T Function(String motivo) resultado,
  String? consequencia,
  bool destrutivo = false,
}) {
  return mostrarModal<T>(
    context,
    construir: (_) => ModalFormulario<T>(
      titulo: titulo,
      consequencia: consequencia,
      rotuloConfirmar: rotuloConfirmar,
      destrutivo: destrutivo,
      campos: campos,
      camposValidos: camposValidos,
      resultado: resultado,
    ),
  );
}

/// Campo de data (DD/MM/AAAA) que abre o seletor. Vazio = sem data.
class CampoData extends StatelessWidget {
  const CampoData({super.key, required this.rotulo, required this.valor, required this.aoMudar, this.erro, this.ajuda});

  final String rotulo;
  final DateTime? valor;
  final ValueChanged<DateTime?> aoMudar;
  final String? erro;
  final String? ajuda;

  @override
  Widget build(BuildContext context) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return InkWell(
      borderRadius: BorderRadius.circular(EspacosTrato.raio),
      onTap: () async {
        final agora = DateTime.now();
        final r = await showDatePicker(
          context: context,
          initialDate: valor ?? agora,
          firstDate: DateTime(agora.year - 1),
          lastDate: DateTime(agora.year + 5),
          locale: const Locale('pt', 'BR'),
        );
        if (r != null) aoMudar(r);
      },
      child: InputDecorator(
        isEmpty: valor == null,
        decoration: InputDecoration(
          labelText: rotulo,
          helperText: ajuda,
          errorText: erro,
          suffixIcon: valor == null
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  icon: const Icon(IconesTrato.fechar, size: 18),
                  tooltip: 'Limpar $rotulo',
                  onPressed: () => aoMudar(null),
                ),
        ),
        child: Text(valor == null ? '' : fmt(valor!), style: TipografiaTrato.corpo),
      ),
    );
  }
}
