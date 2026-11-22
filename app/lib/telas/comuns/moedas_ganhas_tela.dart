import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tema/tema.dart';
import 'desconto_moedas.dart';
import 'moeda_trato.dart';

/// Recompensa depois de avaliar: Tratinho que salta, número que sobe e confete.
/// Só mostra o que o backend já creditou (`moedas`); nenhuma conta roda aqui.
/// Respeita "reduzir animações": nesse caso já abre no estado final.
class MoedasGanhasTela extends StatefulWidget {
  const MoedasGanhasTela({
    super.key,
    required this.moedas,
    required this.aoContinuar,
    this.pendentes = 0,
    this.proximaLiberacao,
    this.valorMoedaCentavos,
    this.acaoExtra,
  });

  /// Botão opcional acima de "Continuar" (ex.: "Salvar como de confiança").
  final Widget? acaoExtra;

  final int moedas;

  /// Tratinhos de avaliação ainda em espera, quando houver (backend antigo: 0, sem linha).
  final int pendentes;
  final DateTime? proximaLiberacao;
  final int? valorMoedaCentavos;
  final VoidCallback aoContinuar;

  @override
  State<MoedasGanhasTela> createState() => _MoedasGanhasTelaState();
}

class _MoedasGanhasTelaState extends State<MoedasGanhasTela>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _iniciou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    if (MediaQuery.of(context).disableAnimations) {
      _ctl.value = 1;
    } else {
      HapticFeedback.mediumImpact();
      _ctl.forward().whenComplete(HapticFeedback.lightImpact);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.aoContinuar();
      },
      child: Scaffold(
        backgroundColor: context.cores.petroleo,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _ctl,
                  builder: (context, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _Confete(_ctl.value)),
                      ),
                      _Conteudo(
                        progresso: _ctl.value,
                        moedas: widget.moedas,
                        pendentes: widget.pendentes,
                        proximaLiberacao: widget.proximaLiberacao,
                        valorMoedaCentavos: widget.valorMoedaCentavos,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(EspacosTrato.x4),
                child: ConteudoResponsivo(
                  // Botão claro: o primário do tema é petróleo e sumiria neste fundo.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.acaoExtra != null) widget.acaoExtra!,
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: widget.aoContinuar,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.cores.fundo,
                            foregroundColor: context.cores.petroleo,
                            minimumSize: const Size.fromHeight(52),
                            textStyle: TipografiaTrato.corpoForte,
                          ),
                          child: const Text('Continuar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  const _Conteudo({
    required this.progresso,
    required this.moedas,
    required this.pendentes,
    required this.proximaLiberacao,
    required this.valorMoedaCentavos,
  });

  final double progresso;
  final int moedas;
  final int pendentes;
  final DateTime? proximaLiberacao;
  final int? valorMoedaCentavos;

  @override
  Widget build(BuildContext context) {
    // 0–35%: a moeda salta; 20–65%: o número sobe; 55–100%: textos aparecem.
    final moeda =
        Curves.elasticOut.transform((progresso / 0.35).clamp(0.0, 1.0));
    final giro =
        Curves.easeOutCubic.transform((progresso / 0.5).clamp(0.0, 1.0));
    final contagem = Curves.easeOutCubic.transform(
      ((progresso - 0.2) / 0.45).clamp(0.0, 1.0),
    );
    final textos =
        Curves.easeOut.transform(((progresso - 0.55) / 0.3).clamp(0.0, 1.0));
    final valor = (moedas * contagem).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.4 + 0.6 * moeda,
          // Giro de moeda de verdade (2 voltas) que termina de frente.
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY((1 - giro) * math.pi * 4),
            child: MoedaTrato(tamanho: 156, brilho: progresso),
          ),
        ),
        const SizedBox(height: EspacosTrato.x6),
        Text(
          '+$valor',
          style: TipografiaTrato.marca
              .copyWith(color: context.cores.sobrePetroleo, fontSize: 80),
        ),
        Opacity(
          opacity: textos,
          child: Transform.translate(
            offset: Offset(0, (1 - textos) * 12),
            child: Column(
              children: [
                Text(
                  pendentes > 0
                      ? (proximaLiberacao != null
                          ? '${moedas == 1 ? 'Tratinho reservado' : 'Tratinhos reservados'} — liberam em ${formatarDiaMes(proximaLiberacao!)}'
                          : (moedas == 1
                              ? 'Tratinho reservado'
                              : 'Tratinhos reservados'))
                      : (moedas == 1 ? 'Tratinho' : 'Tratinhos'),
                  style: TipografiaTrato.titulo
                      .copyWith(color: context.cores.azulSuave),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EspacosTrato.x4),
                Text(
                  'Valeu pela avaliação!',
                  style: TipografiaTrato.tituloGrande
                      .copyWith(color: context.cores.sobrePetroleo),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: EspacosTrato.x5),
                  child: Text(
                    'Quem vem depois vai escolher com mais segurança por causa de você. '
                    '${pendentes > 0 ? 'Seus Tratinhos ficam guardados até a liberação.' : 'Os Tratinhos já estão na sua conta.'}',
                    style:
                        TipografiaTrato.corpo.copyWith(color: context.cores.sobrePetroleo),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (valorMoedaCentavos != null) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    textoTratinhosEmReais(moedas, valorMoedaCentavos),
                    key: const Key('tratinhos-em-reais'),
                    style: TipografiaTrato.corpoPequeno
                        .copyWith(color: context.cores.azulSuave),
                  ),
                ],
                if (pendentes > 0) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    textoTratinhosPendentes(
                        pendentes, proximaLiberacao, valorMoedaCentavos)!,
                    key: const Key('tratinhos-pendentes'),
                    style: TipografiaTrato.corpoPequeno
                        .copyWith(color: context.cores.azulSuave),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Confete: pontos que saem do centro, abrem em leque e caem, sumindo no fim.
class _Confete extends CustomPainter {
  _Confete(this.t);

  final double t;

  static const _cores = [
    CoresTrato.laranja,
    CoresTrato.azulClaro,
    CoresTrato.ambarSuave,
    CoresTrato.creme,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final aleatorio = math.Random(7);
    final centro = Offset(size.width / 2, size.height * 0.40);
    final fase = ((t - 0.05) / 0.9).clamp(0.0, 1.0);
    if (fase <= 0) return;
    for (var i = 0; i < 36; i++) {
      final angulo = aleatorio.nextDouble() * math.pi * 2;
      final alcance = 90 + aleatorio.nextDouble() * (size.width * 0.55);
      final tamanho = 4 + aleatorio.nextDouble() * 6;
      final cor = _cores[i % _cores.length];
      final sobe = Curves.easeOutCubic.transform(fase);
      final cai = fase * fase * 90;
      final pos = centro +
          Offset(math.cos(angulo) * alcance * sobe,
              math.sin(angulo) * alcance * sobe + cai);
      final alfa = (1 - ((fase - 0.6) / 0.4).clamp(0.0, 1.0));
      final pincel = Paint()..color = cor.withValues(alpha: alfa);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angulo + fase * 6);
      if (i.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: tamanho * 1.8, height: tamanho),
            const Radius.circular(2),
          ),
          pincel,
        );
      } else {
        canvas.drawCircle(Offset.zero, tamanho / 2, pincel);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confete antigo) => antigo.t != t;
}
