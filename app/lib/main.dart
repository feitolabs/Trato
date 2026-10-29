import 'package:flutter/material.dart';

import 'tema/tema.dart';

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
      home: const TelaInicial(),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Trato',
                style: TipografiaTrato.marca.copyWith(color: CoresTrato.creme),
              ),
              const SizedBox(height: EspacosTrato.x4),
              Text(
                'Serviço feito, dinheiro liberado.',
                style: TipografiaTrato.lema.copyWith(color: CoresTrato.logoAzulClaro),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
