import 'package:flutter/material.dart';

void main() {
  runApp(const TratoApp());
}

/// Raiz do app. O tema definitivo (cores e fontes do protótipo) entra na Fase 2,
/// em `lib/tema/`.
class TratoApp extends StatelessWidget {
  const TratoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Trato',
      debugShowCheckedModeBanner: false,
      home: TelaInicial(),
    );
  }
}

class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Trato', style: textos.displayMedium),
              const SizedBox(height: 8),
              Text('Serviço feito, dinheiro liberado.', style: textos.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
