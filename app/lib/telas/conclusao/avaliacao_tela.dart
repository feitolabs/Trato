import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'apoio_conclusao.dart';
import 'campo_longo.dart';
import 'dados_exemplo.dart';
import 'estrelas_nota.dart';

/// Tela 19: avaliação em 5 critérios, comentário e gorjeta opcional.
class AvaliacaoTela extends StatefulWidget {
  const AvaliacaoTela({
    super.key,
    this.dados = dadosAvaliacaoExemplo,
    this.notasIniciais,
    this.aoEnviar,
    this.aoAvaliarDepois,
  });

  final DadosAvaliacao dados;

  /// Notas já marcadas ao abrir (o protótipo mostra 5, 5, 4, 5, 0). Sem isso, tudo zerado.
  final List<int>? notasIniciais;
  final ValueChanged<EnvioAvaliacao>? aoEnviar;
  final VoidCallback? aoAvaliarDepois;

  @override
  State<AvaliacaoTela> createState() => _AvaliacaoTelaState();
}

class _AvaliacaoTelaState extends State<AvaliacaoTela> {
  late final List<int> _notas = List.of(
    widget.notasIniciais ?? List.filled(widget.dados.criterios.length, 0),
  );
  final _comentario = TextEditingController();
  final _outraGorjeta = TextEditingController();

  /// null = "Não"; -1 = "Outro"; senão o valor sugerido em centavos.
  int? _gorjeta;

  static const _outro = -1;

  @override
  void dispose() {
    _comentario.dispose();
    _outraGorjeta.dispose();
    super.dispose();
  }

  int get _gorjetaCentavos {
    if (_gorjeta == null) return 0;
    if (_gorjeta == _outro) {
      final digitos = _outraGorjeta.text.replaceAll(RegExp(r'\D'), '');
      return digitos.isEmpty ? 0 : int.parse(digitos) * 100;
    }
    return _gorjeta!;
  }

  void _enviar() {
    widget.aoEnviar?.call(
      EnvioAvaliacao(
        notas: List.unmodifiable(_notas),
        comentario: _comentario.text.trim(),
        gorjetaCentavos: _gorjetaCentavos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    return EstruturaConclusao(
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotaoPrimario(texto: 'Enviar avaliação', aoTocar: _enviar),
          const SizedBox(height: EspacosTrato.x1),
          BotaoLink(texto: 'Avaliar depois', aoTocar: widget.aoAvaliarDepois ?? () {}),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: ChipStatus(
            texto: 'Pagamento liberado · ${formatarReais(dados.valorLiberadoCentavos)}',
            tipo: TipoStatus.sucesso,
            icone: Icons.check,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text('Como foi o serviço do ${dados.nomeProfissional}?', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Sua nota ajuda outros clientes. O ${dados.nomeProfissional} também avalia você.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CartaoTrato(
          child: Column(
            children: [
              for (var i = 0; i < dados.criterios.length; i++) ...[
                if (i > 0) const Divider(height: EspacosTrato.x6),
                _LinhaCriterio(
                  criterio: dados.criterios[i],
                  nota: _notas[i],
                  aoMudar: (n) => setState(() => _notas[i] = n),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoLongo(rotulo: 'Conte como foi (opcional)', controlador: _comentario),
        const SizedBox(height: EspacosTrato.x5),
        Text('Gorjeta (opcional)', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          'Vai inteira para o profissional, sem taxa.',
          style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          children: [
            _OpcaoGorjeta(
              texto: 'Não',
              selecionado: _gorjeta == null,
              aoTocar: () => setState(() => _gorjeta = null),
            ),
            for (final valor in dados.gorjetasCentavos)
              _OpcaoGorjeta(
                texto: formatarReais(valor).replaceAll(',00', ''),
                selecionado: _gorjeta == valor,
                aoTocar: () => setState(() => _gorjeta = valor),
              ),
            _OpcaoGorjeta(
              texto: 'Outro',
              selecionado: _gorjeta == _outro,
              aoTocar: () => setState(() => _gorjeta = _outro),
            ),
          ],
        ),
        if (_gorjeta == _outro) ...[
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(
            rotulo: 'Valor da gorjeta',
            controlador: _outraGorjeta,
            prefixo: 'R\$ ',
            teclado: TextInputType.number,
            formatadores: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ],
    );
  }
}

class _LinhaCriterio extends StatelessWidget {
  const _LinhaCriterio({required this.criterio, required this.nota, required this.aoMudar});

  final String criterio;
  final int nota;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    final rotulo = Text(criterio, style: TipografiaTrato.corpoForte);
    final estrelas = EstrelasNota(rotulo: criterio, nota: nota, aoMudar: aoMudar);
    // Em coluna estreita (320 dp) o rótulo vai para cima das estrelas em vez de encolher.
    return LayoutBuilder(
      builder: (context, caixa) {
        if (caixa.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [rotulo, const SizedBox(height: EspacosTrato.x1), estrelas],
          );
        }
        return Row(
          children: [
            Expanded(child: rotulo),
            const SizedBox(width: EspacosTrato.x2),
            estrelas,
          ],
        );
      },
    );
  }
}

class _OpcaoGorjeta extends StatelessWidget {
  const _OpcaoGorjeta({required this.texto, required this.selecionado, required this.aoTocar});

  final String texto;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x1),
        child: BotaoSecundario(texto: texto, aoTocar: aoTocar, selecionado: selecionado),
      ),
    );
  }
}
