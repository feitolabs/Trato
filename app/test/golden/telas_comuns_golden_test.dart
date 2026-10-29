import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_fake.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/busca/servico_fake.dart';
import 'package:trato/telas/lgpd/central_privacidade_tela.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'package:trato/telas/lgpd/servico_fake.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/servico_fake.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/notificacoes/servico_fake.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas comuns (F5.12, F5.13, F5.4) em celular pequeno, protótipo e tablet.
/// Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };

  final telas = <String, Widget Function()>{
    'notificacoes': () => NotificacoesTela(servico: ServicoNotificacoesFake()),
    'notificacoes_vazio': () =>
        NotificacoesTela(servico: ServicoNotificacoesFake(itens: const [])),
    'notificacoes_erro': () => NotificacoesTela(servico: ServicoNotificacoesFake(falhar: true)),
    'mensagens': () => const MensagensTela(servico: ServicoMensagensFake()),
    'mensagens_vazio': () => const MensagensTela(servico: ServicoMensagensFake(itens: [])),
    'privacidade': () => CentralPrivacidadeTela(servico: ServicoPrivacidadeFake()),
    'excluir_conta': () => ExcluirContaTela(servico: ServicoPrivacidadeFake()),
    'ajuda': () => const AjudaTela(servico: ServicoAjudaFake()),
    'busca': () => const BuscaProfissionaisTela(servico: ServicoBuscaFake()),
    'busca_resultados': () =>
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(), termoInicial: 'elétrica'),
    'busca_vazio': () =>
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(), termoInicial: 'zzzz'),
  };

  for (final MapEntry(key: tela, value: criar) in telas.entries) {
    for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
      testWidgets('$tela — $nome', (tester) async {
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            debugShowCheckedModeBanner: false,
            builder: (context, filho) => EscalaFonteLimitada(child: filho!),
            home: criar(),
          ),
        );
        await tester.pump();
        await tester.pump();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('comuns_${tela}_$nome.png'),
        );
      });
    }
  }
}
