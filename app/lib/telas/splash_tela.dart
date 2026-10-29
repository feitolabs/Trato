import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../tema/tema.dart';
import 'onboarding/onboarding_tela.dart';

/// Tela 1 do protótipo: logo Feito Labs, "Trato" e o lema. Toque em qualquer lugar para começar.
class SplashTela extends StatelessWidget {
  const SplashTela({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresTrato.petroleo,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const OnboardingTela()),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              const LogoFeitoLabs(),
              const SizedBox(height: EspacosTrato.x6),
              Text(
                'FEITO LABS APRESENTA',
                style: TipografiaTrato.sobretitulo.copyWith(color: CoresTrato.creme),
              ),
              const Spacer(flex: 6),
              ConteudoResponsivo(
                child: Column(
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
              const Spacer(flex: 7),
              const IndicadorPaginas(
                total: 3,
                atual: 0,
                pilula: false,
                corAtiva: CoresTrato.creme,
                corInativa: CoresTrato.pontoSobrePetroleo,
              ),
              const SizedBox(height: EspacosTrato.x4),
              Text(
                'Toque para começar',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulClaro),
              ),
              const SizedBox(height: EspacosTrato.x8),
            ],
          ),
        ),
      ),
    );
  }
}
