import 'dart:async';

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

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 2400),
  double fonte = 1.0,
  bool assentar = true,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fonte)),
        child: EscalaFonteLimitada(child: filho!),
      ),
      home: KeyedSubtree(key: UniqueKey(), child: tela),
    ),
  );
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

/// Serviço que nunca responde: segura a tela em "carregando".
class _Pendente {
  static Future<T> _nunca<T>() => Completer<T>().future;
}

class _CadastroPendente extends ServicoCadastroProfissionalFake {
  @override
  Future<OpcoesCadastro> carregarOpcoes() => _Pendente._nunca();
}

void main() {
  group('Estados comuns (carregando / erro / vazio)', () {
    testWidgets('carregando mostra o indicador', (t) async {
      await _abrir(t, CadastroProfissionalTela(servico: _CadastroPendente()), assentar: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('erro mostra mensagem simples e "Tentar de novo" recarrega', (t) async {
      final fake = ServicoPerfilPublicoFake(falharAoCarregar: true);
      await _abrir(t, PerfilPublicoTela(servico: fake));
      expect(find.text('Não foi possível carregar'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      await _tocar(t, find.text('Tentar de novo'));
      expect(find.text('Não foi possível carregar'), findsOneWidget);
    });

    testWidgets('vazio: avaliações, nota, aditivo, disputa e retrabalho', (t) async {
      await _abrir(t, AvaliacoesRecebidasTela(servico: ServicoPerfilPublicoFake(avaliacoes: const [])));
      expect(find.text('Nenhuma avaliação ainda'), findsOneWidget);
      await _abrir(t, VerNotaTela(servico: ServicoNotaMaterialFake(), pedidoId: 'p'));
      expect(find.text('Nenhuma nota enviada'), findsOneWidget);
      await _abrir(t, ResponderAditivoTela(servico: ServicoAditivoFake(), aditivoId: 'a'));
      expect(find.text('Nenhum aditivo'), findsOneWidget);
      await _abrir(t, ResponderDisputaTela(servico: ServicoDisputaProfissionalFake(), disputaId: 'd'));
      expect(find.text('Nenhum problema aberto'), findsOneWidget);
      await _abrir(t, AtenderRetrabalhoTela(servico: ServicoDisputaProfissionalFake(), disputaId: 'd'));
      expect(find.text('Sem retrabalho para agendar'), findsOneWidget);
      await _abrir(
        t,
        CadastroProfissionalTela(
          servico: ServicoCadastroProfissionalFake(
            opcoes: const OpcoesCadastro(categorias: [], raiosKm: [], dias: [], periodos: []),
          ),
        ),
      );
      expect(find.text('Cadastro indisponível agora'), findsOneWidget);
    });
  });

  group('Cadastro do profissional', () {
    testWidgets('valida, salva e chama aoConcluir', (t) async {
      final fake = ServicoCadastroProfissionalFake();
      var concluiu = false;
      await _abrir(
        t,
        CadastroProfissionalTela(
          servico: fake,
          aoAdicionarFoto: () async => 'foto-1',
          aoConcluir: () => concluiu = true,
        ),
      );
      await _tocar(t, find.text('Salvar e continuar'));
      expect(find.text('Informe seu nome completo'), findsOneWidget);
      expect(find.text('Escolha pelo menos uma categoria'), findsOneWidget);
      expect(fake.salvos, isEmpty);

      await t.enterText(find.byType(TextField).first, 'Carlos Almeida');
      await t.enterText(find.widgetWithText(TextField, '').at(1), 'x'); // sobre (ignorado)
      await _tocar(t, find.text('Eletricista'));
      await _tocar(t, find.text('Seg'));
      await _tocar(t, find.text('Manhã'));
      await t.enterText(find.byType(TextField).at(2), 'Belo Horizonte');
      await _tocar(t, find.text('20 km'));
      await _tocar(t, find.text('Adicionar foto'));
      await _tocar(t, find.text('Salvar e continuar'));

      expect(fake.salvos, hasLength(1));
      final d = fake.salvos.single;
      expect(d.categorias, {'Eletricista'});
      expect(d.raioKm, 20);
      expect(d.portfolio, ['foto-1']);
      expect(concluiu, isTrue);
    });

    testWidgets('falha ao salvar mostra aviso e deixa tentar de novo', (t) async {
      final fake = ServicoCadastroProfissionalFake(falharAoSalvar: true);
      await _abrir(t, CadastroProfissionalTela(servico: fake));
      await t.enterText(find.byType(TextField).first, 'Carlos Almeida');
      await t.enterText(find.byType(TextField).at(2), 'BH');
      await _tocar(t, find.text('Eletricista'));
      await _tocar(t, find.text('Seg'));
      await _tocar(t, find.text('Manhã'));
      await _tocar(t, find.text('Salvar e continuar'));
      expect(find.text('Não foi possível salvar. Tente de novo.'), findsOneWidget);
    });
  });

  group('Verificação', () {
    testWidgets('mostra finalidade e retenção; só envia com 2 fotos e ciência', (t) async {
      final fake = ServicoVerificacaoFake();
      var concluiu = false;
      await _abrir(
        t,
        VerificacaoTela(
          servico: fake,
          aoCapturarDocumento: () async => 'doc',
          aoCapturarSelfie: () async => 'selfie',
          aoConcluir: () => concluiu = true,
        ),
      );
      expect(find.text('Para que usamos'), findsOneWidget);
      expect(find.text('Por quanto tempo guardamos'), findsOneWidget);
      expect(find.textContaining('Não é garantia'), findsNothing);
      expect(find.textContaining('não garante'), findsOneWidget);
      expect(find.textContaining('seguro'), findsNothing);

      FilledButton botao() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar para análise'));
      expect(botao().onPressed, isNull);
      await _tocar(t, find.text('Foto do documento'));
      await _tocar(t, find.text('Selfie segurando o rosto'));
      expect(botao().onPressed, isNull);
      await _tocar(t, find.byKey(const Key('ciente_lgpd')));
      expect(botao().onPressed, isNotNull);
      await _tocar(t, find.text('Enviar para análise'));
      expect(fake.enviados.single.documento, 'doc');
      expect(fake.enviados.single.selfie, 'selfie');
      expect(concluiu, isTrue);
      expect(find.text('Em análise'), findsOneWidget);
    });

    testWidgets('status em análise, aprovada e pendente com motivo', (t) async {
      await _abrir(
        t,
        VerificacaoTela(
          servico: ServicoVerificacaoFake(
            situacao: const SituacaoVerificacao(status: StatusVerificacao.emAnalise),
          ),
        ),
      );
      expect(find.text('Em análise'), findsOneWidget);
      expect(find.text('Enviar para análise'), findsNothing);

      await _abrir(
        t,
        VerificacaoTela(
          servico: ServicoVerificacaoFake(
            situacao: const SituacaoVerificacao(status: StatusVerificacao.aprovada),
          ),
        ),
      );
      expect(find.text('Aprovada'), findsOneWidget);

      await _abrir(
        t,
        VerificacaoTela(
          servico: ServicoVerificacaoFake(
            situacao: const SituacaoVerificacao(
              status: StatusVerificacao.pendente,
              motivo: 'Foto do documento ficou desfocada',
            ),
          ),
        ),
      );
      expect(find.text('Pendente'), findsOneWidget);
      expect(find.text('Motivo: Foto do documento ficou desfocada'), findsOneWidget);
      expect(find.text('Enviar para análise'), findsOneWidget);
    });
  });

  group('Nota dos materiais', () {
    testWidgets('profissional envia foto + itens', (t) async {
      final fake = ServicoNotaMaterialFake();
      await _abrir(
        t,
        EnviarNotaTela(
          servico: fake,
          pedidoId: 'p1',
          tituloPedido: 'Troca de tomadas',
          aoCapturarFoto: () async => 'nota-1',
        ),
      );
      FilledButton botao() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar nota ao cliente'));
      expect(botao().onPressed, isNull);

      await _tocar(t, find.text('Adicionar item'));
      expect(find.text('Diga o que é o item'), findsOneWidget);

      await t.enterText(find.byType(TextField).at(0), '2 tomadas');
      await t.enterText(find.byType(TextField).at(1), '46,50');
      await _tocar(t, find.text('Adicionar item'));
      expect(find.text('R\$ 46,50'), findsWidgets);
      await _tocar(t, find.text('Foto da nota'));
      expect(botao().onPressed, isNotNull);
      await _tocar(t, find.text('Enviar nota ao cliente'));

      final envio = fake.enviados.single;
      expect(envio.pedidoId, 'p1');
      expect(envio.fotoNota, 'nota-1');
      expect(envio.itens.single.centavos, 4650);
      expect(find.text('Nota enviada ao cliente.'), findsOneWidget);
    });

    testWidgets('cliente vê itens e soma', (t) async {
      await _abrir(
        t,
        VerNotaTela(servico: ServicoNotaMaterialFake(nota: notaMaterialExemplo), pedidoId: 'p1'),
      );
      expect(find.text('2 tomadas 20 A'), findsOneWidget);
      expect(find.text('R\$ 119,00'), findsOneWidget);
    });
  });

  group('Aditivo', () {
    testWidgets('profissional: líquido vem do serviço e envia em centavos', (t) async {
      final fake = ServicoAditivoFake();
      final liquido = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(
        t,
        CriarAditivoTela(
          servico: fake,
          servicoLiquido: liquido,
          pedidoId: 'p1',
          tituloPedido: 'Troca de tomadas',
        ),
      );
      expect(find.textContaining('só vale se o cliente aprovar'), findsOneWidget);
      await _tocar(t, find.text('Enviar aditivo ao cliente'));
      expect(fake.criados, isEmpty);
      expect(find.text('Informe o valor, ex.: 45,00'), findsOneWidget);

      await t.enterText(find.byType(TextField).at(0), 'Cabo trocado por desgaste');
      await t.enterText(find.byType(TextField).at(1), '100');
      await t.pumpAndSettle();
      expect(liquido.pedidos, contains(10000));
      expect(find.text('R\$ 92,50'), findsOneWidget);

      await _tocar(t, find.text('Enviar aditivo ao cliente'));
      expect(fake.criados.single.valorCentavos, 10000);
      expect(find.textContaining('Aguardando a resposta do cliente'), findsOneWidget);
    });

    testWidgets('cliente aprova', (t) async {
      final fake = ServicoAditivoFake(detalhe: aditivoExemplo);
      bool? resposta;
      await _abrir(
        t,
        ResponderAditivoTela(servico: fake, aditivoId: 'ad-1', aoResponder: (a) => resposta = a),
      );
      expect(find.text('R\$ 45,00'), findsOneWidget);
      expect(find.textContaining('pago'), findsNothing);
      await _tocar(t, find.text('Aprovar aditivo'));
      expect(fake.respostas.single, ('ad-1', true));
      expect(resposta, isTrue);
      expect(find.text('Aditivo aprovado'), findsOneWidget);
    });

    testWidgets('cliente recusa depois de confirmar', (t) async {
      final fake = ServicoAditivoFake(detalhe: aditivoExemplo);
      await _abrir(t, ResponderAditivoTela(servico: fake, aditivoId: 'ad-1'));
      await _tocar(t, find.text('Recusar'));
      expect(fake.respostas, isEmpty);
      await _tocar(t, find.widgetWithText(TextButton, 'Recusar'));
      expect(fake.respostas.single, ('ad-1', false));
      expect(find.text('Aditivo recusado'), findsOneWidget);
    });

    testWidgets('falha ao responder mostra aviso e mantém os botões', (t) async {
      final fake = ServicoAditivoFake(detalhe: aditivoExemplo, falharAoEnviar: true);
      await _abrir(t, ResponderAditivoTela(servico: fake, aditivoId: 'ad-1'));
      await _tocar(t, find.text('Aprovar aditivo'));
      expect(find.textContaining('Não foi possível enviar sua resposta'), findsOneWidget);
      expect(find.text('Aprovar aditivo'), findsOneWidget);
    });
  });

  group('Disputa e retrabalho', () {
    testWidgets('responde com reembolso parcial em centavos', (t) async {
      final fake = ServicoDisputaProfissionalFake(disputa: disputaExemplo);
      TipoRespostaDisputa? tipo;
      await _abrir(
        t,
        ResponderDisputaTela(
          servico: fake,
          disputaId: 'disp-1',
          aoAdicionarEvidencia: () async => 'prova-1',
          aoRespondida: (x) => tipo = x,
        ),
      );
      expect(find.text('Responder em até 48 h'), findsOneWidget);
      await _tocar(t, find.text('Propor reembolso parcial'));
      await _tocar(t, find.text('Enviar resposta'));
      expect(fake.respostas, isEmpty);
      expect(find.text('Escreva uma resposta curta'), findsOneWidget);

      await t.enterText(find.byType(TextField).at(0), '50');
      await t.enterText(find.byType(TextField).at(1), 'Aceito devolver parte do valor');
      await _tocar(t, find.text('Anexar foto'));
      await _tocar(t, find.text('Enviar resposta'));
      final r = fake.respostas.single;
      expect(r.tipo, TipoRespostaDisputa.proporReembolsoParcial);
      expect(r.reembolsoParcialCentavos, 5000);
      expect(r.evidencias, ['prova-1']);
      expect(tipo, TipoRespostaDisputa.proporReembolsoParcial);
    });

    testWidgets('atender retrabalho: escolhe horário e confirma', (t) async {
      final fake = ServicoDisputaProfissionalFake(retrabalho: retrabalhoExemplo);
      String? agendado;
      await _abrir(
        t,
        AtenderRetrabalhoTela(servico: fake, disputaId: 'disp-1', aoAgendado: (h) => agendado = h),
      );
      FilledButton botao() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar horário'));
      expect(botao().onPressed, isNull);
      await _tocar(t, find.text('Sex, 06/11 · manhã'));
      await _tocar(t, find.text('Confirmar horário'));
      expect(fake.agendamentos.single.horario, 'Sex, 06/11 · manhã');
      expect(agendado, 'Sex, 06/11 · manhã');
    });
  });

  group('Perfil público e avaliações', () {
    testWidgets('mostra perfil, avaliações e dispara os atalhos', (t) async {
      var verAvaliacoes = false;
      await _abrir(
        t,
        PerfilPublicoTela(
          servico: ServicoPerfilPublicoFake(),
          aoVerAvaliacoes: () => verAvaliacoes = true,
        ),
      );
      expect(find.text('Carlos Almeida'), findsOneWidget);
      expect(find.text('Identidade conferida'), findsOneWidget);
      await _tocar(t, find.text('Ver todas as avaliações'));
      expect(verAvaliacoes, isTrue);
    });

    testWidgets('lista de avaliações recebidas', (t) async {
      await _abrir(t, AvaliacoesRecebidasTela(servico: ServicoPerfilPublicoFake()));
      expect(find.text('2 avaliações'), findsOneWidget);
      expect(find.textContaining('Mariana S.'), findsOneWidget);
    });
  });

  group('Fonte grande e tela pequena não estouram', () {
    final telas = <String, Widget Function()>{
      'cadastro': () => CadastroProfissionalTela(servico: ServicoCadastroProfissionalFake()),
      'verificacao': () => VerificacaoTela(servico: ServicoVerificacaoFake()),
      'enviar nota': () => EnviarNotaTela(
          servico: ServicoNotaMaterialFake(), pedidoId: 'p', tituloPedido: 'Troca de tomadas e chuveiro'),
      'ver nota': () => VerNotaTela(
          servico: ServicoNotaMaterialFake(nota: notaMaterialExemplo), pedidoId: 'p'),
      'criar aditivo': () => CriarAditivoTela(
            servico: ServicoAditivoFake(),
            servicoLiquido: ServicoOrcamentoFake(taxaBps: 750),
            pedidoId: 'p',
            tituloPedido: 'Troca de tomadas e chuveiro',
          ),
      'responder aditivo': () =>
          ResponderAditivoTela(servico: ServicoAditivoFake(detalhe: aditivoExemplo), aditivoId: 'a'),
      'responder disputa': () => ResponderDisputaTela(
          servico: ServicoDisputaProfissionalFake(disputa: disputaExemplo), disputaId: 'd'),
      'retrabalho': () => AtenderRetrabalhoTela(
          servico: ServicoDisputaProfissionalFake(retrabalho: retrabalhoExemplo), disputaId: 'd'),
      'perfil público': () => PerfilPublicoTela(servico: ServicoPerfilPublicoFake()),
      'avaliações': () => AvaliacoesRecebidasTela(servico: ServicoPerfilPublicoFake()),
    };
    for (final MapEntry(key: nome, value: criar) in telas.entries) {
      testWidgets('$nome em 320 dp com fonte 2.0 (limitada em 1.3)', (t) async {
        await _abrir(t, criar(), tamanho: const Size(320, 640), fonte: 2.0);
        expect(t.takeException(), isNull);
      });
    }
  });
}
