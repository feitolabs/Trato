import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'materiais_contestacao_tela.dart';

Future<bool> abrirDecidirContestacaoMaterial(BuildContext context, ContestacaoMaterial c) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalDecidirMaterial(c)) ?? false;

class _ModalDecidirMaterial extends StatefulWidget {
  const _ModalDecidirMaterial(this.contestacao);
  final ContestacaoMaterial contestacao;

  @override
  State<_ModalDecidirMaterial> createState() => _ModalDecidirMaterialState();
}

class _ModalDecidirMaterialState extends State<_ModalDecidirMaterial> {
  String? _decisao;
  final _resposta = TextEditingController();
  final _valor = TextEditingController();
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _resposta.dispose();
    _valor.dispose();
    super.dispose();
  }

  bool get _parcial => _decisao == 'parcial';

  /// Só confere se o texto é um valor em reais. A faixa aceita quem decide é o backend.
  int? get _centavos => _parcial ? lerReaisEmCentavos(_valor.text) : null;

  bool get _valido =>
      _decisao != null && _resposta.text.trim().length >= kMotivoMinimo && (!_parcial || _centavos != null);

  Future<void> _confirmar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.decidirContestacaoMaterial(
        widget.contestacao.id,
        status: _decisao!,
        resposta: _resposta.text.trim(),
        valorReconhecidoCentavos: _centavos,
      );
      if (!mounted) return;
      mostrarAviso(context, 'Decisão registrada.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  String get _resumoValor => switch (_decisao) {
        'procedente' => 'Todo o valor contestado (${formatarReais(widget.contestacao.valorContestadoCentavos)})',
        'parcial' => formatarReais(_centavos!),
        _ => formatarReais(0),
      };

  List<Widget> _formulario() => [
        Linha('Valor contestado', formatarReais(widget.contestacao.valorContestadoCentavos)),
        Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x3),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('material-decisao'),
            initialValue: _decisao,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Decisão'),
            items: [
              for (final s in const ['procedente', 'parcial', 'improcedente'])
                DropdownMenuItem(value: s, child: Text(kStatusContestacaoMaterial[s]!)),
            ],
            onChanged: (v) => setState(() => _decisao = v),
          ),
        ),
        if (_parcial)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x3),
            child: TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Valor reconhecido (R\$)',
                helperText: 'Maior que zero e menor que o contestado. Exemplo: 50,00',
                helperMaxLines: 2,
                errorText: _valor.text.trim().isEmpty || _centavos != null
                    ? null
                    : 'Valor inválido. Use vírgula nos centavos.',
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x3),
          child: TextField(
            controller: _resposta,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Resposta',
              helperText: 'Pelo menos $kMotivoMinimo caracteres',
              counterText: '',
            ),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar decisão?' : 'Decidir ${widget.contestacao.protocolo}',
        consequencia: 'A decisão não pode ser mudada depois. Ela não movimenta dinheiro.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_revisando) ...[
            Linha('Decisão', kStatusContestacaoMaterial[_decisao]!),
            Linha('Valor reconhecido na análise', _resumoValor),
            Linha('Resposta', _resposta.text.trim()),
          ] else
            ..._formulario(),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          if (!_revisando)
            BotaoTrato.primario('Revisar', aoPressionar: _valido ? () => setState(() => _revisando = true) : null)
          else
            BotaoTrato.primario(
              'Confirmar decisão',
              carregando: _enviando,
              rotuloCarregando: 'Enviando',
              aoPressionar: _enviando ? null : _confirmar,
            ),
        ],
      ),
    );
  }
}
