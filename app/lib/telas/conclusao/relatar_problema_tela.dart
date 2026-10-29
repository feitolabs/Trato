import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'apoio_conclusao.dart';
import 'campo_longo.dart';
import 'dados_exemplo.dart';

/// Tela 20: relatar problema (abre a disputa). O valor fica congelado; o app só avisa.
class RelatarProblemaTela extends StatefulWidget {
  const RelatarProblemaTela({
    super.key,
    this.dados = dadosRelatoExemplo,
    this.motivoInicial,
    this.descricaoInicial,
    this.aoEnviar,
    this.aoAdicionarMidia,
  });

  final DadosRelatoProblema dados;
  final String? motivoInicial;
  final String? descricaoInicial;
  final ValueChanged<EnvioRelato>? aoEnviar;
  final VoidCallback? aoAdicionarMidia;

  @override
  State<RelatarProblemaTela> createState() => _RelatarProblemaTelaState();
}

class _RelatarProblemaTelaState extends State<RelatarProblemaTela> {
  late String? _motivo = widget.motivoInicial;
  late String _solucao = widget.dados.solucoes.first;
  late final _descricao = TextEditingController(text: widget.descricaoInicial);

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  bool get _pode => _motivo != null && _descricao.text.trim().isNotEmpty;

  void _enviar() {
    widget.aoEnviar?.call(
      EnvioRelato(motivo: _motivo!, descricao: _descricao.text.trim(), solucao: _solucao),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    return EstruturaConclusao(
      tituloBarra: dados.titulo,
      rodape: BotaoPrimario(
        texto: 'Enviar relato',
        aoTocar: _pode ? _enviar : null,
      ),
      children: [
        Text('Relatar problema', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x4),
        _AvisoCongelado(valorCentavos: dados.valorCongeladoCentavos),
        const SizedBox(height: EspacosTrato.x5),
        Text('O que aconteceu?', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x3),
        for (final motivo in dados.motivos) ...[
          _OpcaoMotivo(
            texto: motivo,
            selecionado: motivo == _motivo,
            aoTocar: () => setState(() => _motivo = motivo),
          ),
          const SizedBox(height: EspacosTrato.x2),
        ],
        const SizedBox(height: EspacosTrato.x3),
        CampoLongo(
          rotulo: 'Descreva',
          controlador: _descricao,
          linhas: 3,
          aoMudar: (_) => setState(() {}),
        ),
        const SizedBox(height: EspacosTrato.x5),
        Text('Fotos ou vídeo', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          children: [
            const EspacoFoto(legenda: '[Foto]', altura: 100, largura: 100),
            const SizedBox(width: EspacosTrato.x2),
            _AdicionarMidia(aoTocar: widget.aoAdicionarMidia ?? () {}),
          ],
        ),
        const SizedBox(height: EspacosTrato.x5),
        Text('O que resolveria para você?', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x2),
        DropdownButtonFormField<String>(
          initialValue: _solucao,
          isExpanded: true,
          style: TipografiaTrato.corpo,
          items: [
            for (final s in dados.solucoes) DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (s) => setState(() => _solucao = s ?? _solucao),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text(
          '${dados.nomeProfissional} tem ${dados.prazoRespostaHoras} horas para responder. '
          'Sem acordo, nossa equipe de mediação decide com base no chat, nas fotos e no orçamento.',
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
      ],
    );
  }
}

class _AvisoCongelado extends StatelessWidget {
  const _AvisoCongelado({required this.valorCentavos});

  final int valorCentavos;

  @override
  Widget build(BuildContext context) {
    final base = TipografiaTrato.corpo.copyWith(color: CoresTrato.ambarTexto);
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: CoresTrato.ambarSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: CoresTrato.ambarTexto),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Valor congelado até a decisão. ',
                    style: base.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        '${formatarReais(valorCentavos)} ficam retidos enquanto o problema é resolvido.',
                  ),
                ],
                style: base,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpcaoMotivo extends StatelessWidget {
  const _OpcaoMotivo({required this.texto, required this.selecionado, required this.aoTocar});

  final String texto;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selecionado,
      child: Material(
        color: selecionado ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: selecionado ? CoresTrato.petroleo : CoresTrato.borda,
            width: selecionado ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          onTap: aoTocar,
          borderRadius: raio,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x4,
              vertical: EspacosTrato.x4,
            ),
            child: Row(
              children: [
                Icon(
                  selecionado ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: CoresTrato.petroleo,
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Text(
                    texto,
                    style: TipografiaTrato.corpo.copyWith(
                      color: CoresTrato.petroleo,
                      fontWeight: selecionado ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Caixa tracejada "Adicionar" (foto ou vídeo).
class _AdicionarMidia extends StatelessWidget {
  const _AdicionarMidia({required this.aoTocar});

  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Adicionar foto ou vídeo',
      excludeSemantics: true,
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        child: CustomPaint(
          painter: _BordaTracejada(),
          child: SizedBox(
            width: 100,
            height: 100,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(EspacosTrato.x2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Adicionar', style: TipografiaTrato.corpoForte, maxLines: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BordaTracejada extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = CoresTrato.textoDica
      ..style = PaintingStyle.stroke
      ..strokeWidth = EspacosTrato.bordaFina;
    final caixa = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(EspacosTrato.raio),
    );
    final caminho = Path()..addRRect(caixa);
    for (final trecho in caminho.computeMetrics()) {
      var pos = 0.0;
      while (pos < trecho.length) {
        canvas.drawPath(trecho.extractPath(pos, pos + 5), pincel);
        pos += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter antigo) => false;
}
