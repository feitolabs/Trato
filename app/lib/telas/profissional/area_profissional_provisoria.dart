import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'calculadora_orcamento_tela.dart';
import 'check_in_tela.dart';
import 'servico_check_in_fake.dart';
import 'servico_orcamento_fake.dart';

/// PROVISÓRIA: o app do profissional (início, pedidos abertos, carteira) ainda não existe
/// (F6.1, F6.2, F6.6). Esta tela só dá acesso às telas prontas, com serviços de teste.
class AreaProfissionalProvisoria extends StatelessWidget {
  const AreaProfissionalProvisoria({super.key});

  /// Percentual só de demonstração: a taxa real é decidida pelo backend (P2).
  static const _taxaDemonstracaoBps = 750;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Área do profissional')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConteudoResponsivo(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Em construção', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  'O app do profissional ainda não está pronto. Estas são as telas já feitas, '
                  'com dados e serviços de teste.',
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                ),
                const SizedBox(height: EspacosTrato.x6),
                BotaoPrimario(
                  texto: 'Fazer orçamento',
                  aoTocar: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CalculadoraOrcamentoTela(
                        servico: ServicoOrcamentoFake(taxaBps: _taxaDemonstracaoBps),
                        tituloPedido: 'Troca de tomadas e chuveiro',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x3),
                BotaoSecundario(
                  texto: 'Fazer check-in',
                  aoTocar: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CheckInTela(
                        servico: ServicoCheckInFake(),
                        tituloBarra: 'Mariana · hoje, 14h',
                      ),
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
