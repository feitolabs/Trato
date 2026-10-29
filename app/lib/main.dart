import 'package:flutter/material.dart';

import 'galeria/galeria_componentes.dart';
import 'tema/tema.dart';

/// `--dart-define=GALERIA=true` abre a vitrine de componentes no lugar da splash.
const _mostrarGaleria = bool.fromEnvironment('GALERIA');

void main() {
  runApp(const TratoApp());
}

class TratoApp extends StatelessWidget {
  const TratoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trato',
      debugShowCheckedModeBanner: false,
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: _mostrarGaleria ? const GaleriaComponentes() : const TelaInicial(),
    );
  }
}

/// Provisória: reproduz a splash do protótipo até a F5.1 (onboarding completo).
class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresTrato.petroleo,
      body: SafeArea(
        child: Center(
          child: ConteudoResponsivo(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Trato',
                    style: TipografiaTrato.marca.copyWith(color: CoresTrato.creme),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x4),
                Text(
                  'Serviço feito, dinheiro liberado.',
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.lema.copyWith(color: CoresTrato.logoAzulClaro),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
