import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/aditivo/aditivo.dart';
import 'package:trato/telas/aditivo/criar_aditivo_tela.dart';
import 'package:trato/telas/aditivo/responder_aditivo_tela.dart';
import 'package:trato/telas/disputa_profissional/atender_retrabalho_tela.dart';
import 'package:trato/telas/disputa_profissional/disputa.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/telas/nota_material/enviar_nota_tela.dart';
import 'package:trato/telas/nota_material/nota_material.dart';
import 'package:trato/telas/nota_material/ver_nota_tela.dart';
import 'package:trato/telas/perfil_publico/avaliacoes_recebidas_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/telas/profissional/servico_orcamento_fake.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/telas/verificacao/verificacao.dart';
import 'package:trato/telas/verificacao/verificacao_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas do profissional (cadastro, verificação, nota, aditivo, disputa, perfil) em 3 tamanhos.
/// Atualizar: flutter test --update-goldens test/golden/telas_profissional_golden_test.dart
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 1100),
    'tablet': Size(768, 1024),
  };

  final telas = <String, Widget Function()>{
    'cadastro': () => CadastroProfissionalTela(servico: ServicoCadastroProfissionalFake()),
    'verificacao_nova': () => VerificacaoTela(servico: ServicoVerificacaoFake()),
    'verificacao_pendente': () => VerificacaoTela(
          servico: ServicoVerificacaoFake(
            situacao: const SituacaoVerificacao(
              status: StatusVerificacao.pendente,
              motivo: 'Foto do documento ficou desfocada',
            ),
          ),
        ),
    'verificacao_em_analise': () => VerificacaoTela(
          servico: ServicoVerificacaoFake(
            situacao: const SituacaoVerificacao(status: StatusVerificacao.emAnalise),
          ),
        ),
    'enviar_nota': () => EnviarNotaTela(
          servico: ServicoNotaMaterialFake(),
          pedidoId: 'p1',
          tituloPedido: 'Troca de tomadas e chuveiro',
        ),
    'ver_nota': () => VerNotaTela(
          servico: ServicoNotaMaterialFake(nota: notaMaterialExemplo),
          pedidoId: 'p1',
        ),
    'ver_nota_vazia': () => VerNotaTela(servico: ServicoNotaMaterialFake(), pedidoId: 'p1'),
    'criar_aditivo': () => CriarAditivoTela(
          servico: ServicoAditivoFake(),
          servicoLiquido: ServicoOrcamentoFake(taxaBps: 750),
          pedidoId: 'p1',
          tituloPedido: 'Troca de tomadas e chuveiro',
        ),
    'responder_aditivo': () =>
        ResponderAditivoTela(servico: ServicoAditivoFake(detalhe: aditivoExemplo), aditivoId: 'ad-1'),
    'responder_disputa': () => ResponderDisputaTela(
          servico: ServicoDisputaProfissionalFake(disputa: disputaExemplo),
          disputaId: 'disp-1',
        ),
    'atender_retrabalho': () => AtenderRetrabalhoTela(
          servico: ServicoDisputaProfissionalFake(retrabalho: retrabalhoExemplo),
          disputaId: 'disp-1',
        ),
    'perfil_publico': () => PerfilPublicoTela(servico: ServicoPerfilPublicoFake()),
    'avaliacoes_recebidas': () => AvaliacoesRecebidasTela(servico: ServicoPerfilPublicoFake()),
    'avaliacoes_erro': () =>
        AvaliacoesRecebidasTela(servico: ServicoPerfilPublicoFake(falharAoCarregar: true)),
  };

  for (final MapEntry(key: variante, value: criar) in telas.entries) {
    for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
      testWidgets('profissional $variante — $nome', (tester) async {
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
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('profissional_${variante}_$nome.png'),
        );
      });
    }
  }
}
