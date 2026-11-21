import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/login_tela.dart';
import 'package:trato_admin/telas/verificacao_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

class _ApiQa5Espiao extends ApiFake {
  _ApiQa5Espiao({
    super.vazio,
    // ignore: unused_element_parameter
    super.erro,
    this.verificacoesFixas,
    this.aoDecidir,
    this.aoAssumir,
    // ignore: unused_element_parameter
    this.aoListarVerificacoes,
    this.aoVerificarCadeia,
    this.aoSolicitarRelatorio,
  });

  final List<Verificacao>? verificacoesFixas;
  Future<void> Function(String id, bool aprovar, String motivo)? aoDecidir;
  Future<void> Function(String id, String motivo, bool substituir)? aoAssumir;
  Future<PaginaRemota<Verificacao>> Function(
    int chamada,
    List<StatusVerificacao> status,
    String busca,
    int deslocamento,
    int limite,
  )? aoListarVerificacoes;
  Future<ResultadoCadeia> Function()? aoVerificarCadeia;
  Future<RelatorioPronto> Function()? aoSolicitarRelatorio;

  int chamadasDecidir = 0;
  int chamadasAssumir = 0;
  int chamadasListarVerificacoes = 0;
  int chamadasCadeia = 0;
  int chamadasRelatorio = 0;

  @override
  Future<PaginaRemota<Verificacao>> listarVerificacoes({
    List<StatusVerificacao> status = const [],
    String busca = '',
    int deslocamento = 0,
    int limite = 50,
  }) async {
    chamadasListarVerificacoes++;
    if (aoListarVerificacoes != null) {
      return aoListarVerificacoes!(chamadasListarVerificacoes, status, busca, deslocamento, limite);
    }
    if (verificacoesFixas != null) {
      final achadas = [
        for (final v in verificacoesFixas!)
          if (status.isEmpty || status.contains(v.status)) v,
      ];
      return PaginaRemota(achadas, achadas.length);
    }
    return super.listarVerificacoes(
      status: status,
      busca: busca,
      deslocamento: deslocamento,
      limite: limite,
    );
  }

  @override
  Future<Map<StatusVerificacao, int>> contarVerificacoes() async {
    if (verificacoesFixas != null) {
      return {
        for (final s in StatusVerificacao.values)
          s: verificacoesFixas!.where((v) => v.status == s).length,
      };
    }
    return super.contarVerificacoes();
  }

  @override
  Future<void> decidirVerificacao(
    String id, {
    required bool aprovar,
    required String motivo,
  }) async {
    chamadasDecidir++;
    if (aoDecidir != null) {
      await aoDecidir!(id, aprovar, motivo);
      return;
    }
    await super.decidirVerificacao(id, aprovar: aprovar, motivo: motivo);
  }

  @override
  Future<void> assumirVerificacao(
    String id, {
    required String motivo,
    bool substituir = false,
  }) async {
    chamadasAssumir++;
    if (aoAssumir != null) {
      await aoAssumir!(id, motivo, substituir);
      return;
    }
    await super.assumirVerificacao(id, motivo: motivo, substituir: substituir);
  }

  @override
  Future<ResultadoCadeia> verificarCadeia() async {
    chamadasCadeia++;
    if (aoVerificarCadeia != null) return aoVerificarCadeia!();
    return super.verificarCadeia();
  }

  @override
  Future<RelatorioPronto> solicitarRelatorio(
    String tipo, {
    DateTime? inicio,
    DateTime? fim,
    String? cidadeId,
    String formato = 'excel_br',
    required String motivo,
  }) async {
    chamadasRelatorio++;
    if (aoSolicitarRelatorio != null) return aoSolicitarRelatorio!();
    return super.solicitarRelatorio(
      tipo,
      inicio: inicio,
      fim: fim,
      cidadeId: cidadeId,
      formato: formato,
      motivo: motivo,
    );
  }
}

void main() {
  // ---- Teste pré-existente preservado ----
  group('QA5 Admin — LoginTela', () {
    testWidgets('renderiza em desktop e mobile sem overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(360, 740)),
            child: LoginTela(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ---- QA5-P: VerificacaoTela ----
  group('QA5 Admin — VerificacaoTela', () {
    testWidgets('duplo clique ao aprovar durante envio desabilita botoes e envia apenas 1 chamada',
        (tester) async {
      final completer = Completer<void>();
      final api = _ApiQa5Espiao(
        aoDecidir: (id, aprovar, motivo) => completer.future,
      );
      await abrirPainel(tester, papel: 'cadastro', api: api);

      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar profissional'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Motivo'),
        'Documentos legiveis e conferidos para aprovacao',
      );
      await tester.pump();

      final confirmarNoModal = find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(FilledButton, 'Aprovar profissional'),
      );
      await tester.tap(confirmarNoModal);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.chamadasDecidir, 1);

      // Enquanto a requisicao esta em andamento, aprovar e recusar ficam desabilitados.
      final btnRecusar = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Recusar cadastro'),
      );
      expect(btnRecusar.onPressed, isNull);
      final btnEnviando = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enviando'),
      );
      expect(btnEnviando.onPressed, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Enviando'), warnIfMissed: false);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar cadastro'), warnIfMissed: false);
      await tester.pump();
      expect(api.chamadasDecidir, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplo clique rapido no botao Aprovar antes de abrir modal nao abre dois modais',
        (tester) async {
      final api = _ApiQa5Espiao();
      await abrirPainel(tester, papel: 'cadastro', api: api);

      final btn = find.widgetWithText(FilledButton, 'Aprovar profissional');
      await tester.tap(btn);
      await tester.tap(btn, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Apenas 1 modal de motivo deve estar aberto.
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('duplo clique rapido ao confirmar no modal nao fecha duas rotas nem quebra',
        (tester) async {
      final api = _ApiQa5Espiao();
      await abrirPainel(tester, papel: 'cadastro', api: api);

      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar profissional'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Motivo'),
        'Documentos conferidos no sistema de cadastro',
      );
      await tester.pump();

      final confirmar = find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(FilledButton, 'Aprovar profissional'),
      );
      await tester.tap(confirmar);
      await tester.tap(confirmar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.chamadasDecidir, 1);
      expect(find.byType(VerificacaoTela), findsOneWidget);
    });

    testWidgets('botoes de decisao permanecem travados enquanto fila recarrega apos aprovar',
        (tester) async {
      final recarga = Completer<PaginaRemota<Verificacao>>();
      var pausarRecarga = false;
      final api = _ApiQa5Espiao();
      api.aoDecidir = (id, aprovar, motivo) async {
        pausarRecarga = true;
      };
      api.aoListarVerificacoes = (chamada, status, busca, deslocamento, limite) {
        if (pausarRecarga) return recarga.future;
        return ApiFake().listarVerificacoes(
          status: status,
          busca: busca,
          deslocamento: deslocamento,
          limite: limite,
        );
      };

      await abrirPainel(tester, papel: 'cadastro', api: api);

      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar profissional'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Motivo'),
        'Documentos conferidos e aprovados no teste',
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, 'Aprovar profissional'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // decidirVerificacao ja retornou ok, mas aoMudar() (recarregar fila) ainda esta pendente.
      // Os botoes nao deveriam reabilitar no cadastro ja decidido enquanto recarrega.
      final btnAprovar = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enviando'),
      );
      expect(btnAprovar.onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Recusar cadastro')).onPressed,
        isNull,
      );

      recarga.complete(const PaginaRemota([], 0));
      await tester.pumpAndSettle();
    });

    testWidgets('duplo clique ao recusar durante envio desabilita botoes e envia apenas 1 chamada',
        (tester) async {
      final completer = Completer<void>();
      final api = _ApiQa5Espiao(
        aoDecidir: (id, aprovar, motivo) => completer.future,
      );
      await abrirPainel(tester, papel: 'cadastro', api: api);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar cadastro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motivo da lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selfie não confere com o documento').last);
      await tester.pumpAndSettle();

      final confirmarRecusa = find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(OutlinedButton, 'Recusar cadastro'),
      );
      await tester.tap(confirmarRecusa);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.chamadasDecidir, 1);
      final btnRecusar = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Recusar cadastro'),
      );
      expect(btnRecusar.onPressed, isNull);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar cadastro'), warnIfMissed: false);
      await tester.pump();
      expect(api.chamadasDecidir, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplo clique em Assumir analise durante envio desabilita botao', (tester) async {
      final completer = Completer<void>();
      final api = _ApiQa5Espiao(
        aoAssumir: (id, motivo, substituir) => completer.future,
      );
      await abrirPainel(tester, papel: 'cadastro', api: api);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Assumir análise'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Motivo'),
        'Assumindo analise do cadastro pendente',
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, 'Assumir análise'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.chamadasAssumir, 1);
      final btnAssumir = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Assumir análise'),
      );
      expect(btnAssumir.onPressed, isNull);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('timeout e erro de rede ao aprovar e ao recusar exibem erro e destravam botoes',
        (tester) async {
      var tentativa = 0;
      final api = _ApiQa5Espiao();
      api.aoDecidir = (id, aprovar, motivo) async {
        tentativa++;
        if (tentativa == 1) throw TimeoutException('tempo esgotado no servidor');
        if (tentativa == 2) throw const ErroApi('Falha temporaria ao gravar decisao.');
        // 3a tentativa: sucesso
      };

      await abrirPainel(tester, papel: 'cadastro', api: api);

      // 1) Aprovar falha com TimeoutException
      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar profissional'));
      await tester.pumpAndSettle();
      await confirmarMotivo(tester, 'Aprovar profissional');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Código ERR-'), findsOneWidget);

      // Botoes continuam destravados apos falha
      final btnAprovarPosErro = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Aprovar profissional'),
      );
      expect(btnAprovarPosErro.onPressed, isNotNull);

      // 2) Recusar falha com ErroApi
      await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar cadastro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motivo da lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documento vencido ou inválido').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(OutlinedButton, 'Recusar cadastro'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Falha temporaria ao gravar decisao.'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Recusar cadastro')).onPressed,
        isNotNull,
      );

      // 3) Nova tentativa de aprovar funciona
      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar profissional'));
      await tester.pumpAndSettle();
      await confirmarMotivo(tester, 'Aprovar profissional');
      expect(find.text('Profissional aprovado.'), findsOneWidget);
      expect(api.chamadasDecidir, 3);
    });

    testWidgets('lista vazia renderiza estado vazio sem overflow em desktop e mobile 1.3x',
        (tester) async {
      await abrirPainel(tester, papel: 'cadastro', api: _ApiQa5Espiao(vazio: true));
      expect(find.text('Nenhum cadastro esperando análise.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lista vazia em mobile 400x700 com fonte 1.3x sem overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await abrirPainel(
        tester,
        papel: 'cadastro',
        api: _ApiQa5Espiao(vazio: true),
        largura: 400,
        altura: 700,
      );
      expect(find.text('Nenhum cadastro esperando análise.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('texto hostil longo em desktop com fonte 1.3x sem overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final hostil = Verificacao(
        id: 'ver-hostil-1',
        profissionalId: 'prof-hostil-1',
        idPublico: 'PROF-999999999999',
        profissional:
            'NomeSuperExtensoSemEspacosParaTestarQuebraDeTextoNaListaENoDetalhe<script>alert(1)</script>123456',
        cidade: 'São José dos Campos dos Goytacazes da Serra Dourada',
        nivel: 'Identidade e antecedentes conferidos com validação reforçada',
        categorias: const [
          'Eletricista Industrial Predial Residencial Alta Tensao',
          'Hidraulica Completa e Desentupimento de Esgoto',
        ],
        enviadaEm: DateTime(2026, 10, 29, 10, 30),
        documentos: const [
          'RG_frente_e_verso_alta_resolucao_muito_longo_sem_espacos_1234567890.png',
          'Selfie com documento segurado ao lado do rosto',
        ],
        enviosAnteriores: [
          EnvioVerificacao(
            enviadoEm: DateTime(2026, 10, 20, 14),
            aprovado: false,
            motivo:
                'Recusa anterior com descrição extensa sem quebras aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ],
      );

      await abrirPainel(
        tester,
        papel: 'cadastro',
        api: _ApiQa5Espiao(verificacoesFixas: [hostil]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('texto hostil longo em mobile 400x700 com fonte 1.3x sem overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final hostil = Verificacao(
        id: 'ver-hostil-mob',
        profissionalId: 'prof-hostil-mob',
        idPublico: 'PROF-888888',
        profissional:
            'NomeSuperExtensoSemEspacosParaTestarQuebraDeTextoNoCelular12345678901234567890',
        cidade: 'Belo Horizonte',
        nivel: 'Verificação básica',
        categorias: const ['Eletricista Residencial e Predial', 'Encanador'],
        enviadaEm: DateTime(2026, 10, 29, 10, 30),
        documentos: const ['RG frente', 'Selfie com documento'],
      );

      await abrirPainel(
        tester,
        papel: 'cadastro',
        api: _ApiQa5Espiao(verificacoesFixas: [hostil]),
        largura: 400,
        altura: 700,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Abre o detalhe no celular (rola para baixo se o topo ocupar a tela)
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('NomeSuperExtenso').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ---- QA5-P (extra): AuditoriaTela duplo clique e timeout ----
  group('QA5 Admin — AuditoriaTela', () {
    testWidgets('duplo clique rapido em Verificar cadeia de hash dispara apenas uma chamada',
        (tester) async {
      final completer = Completer<ResultadoCadeia>();
      final api = _ApiQa5Espiao(aoVerificarCadeia: () => completer.future);
      await abrirPainel(tester, papel: 'administrador', api: api, secao: 'auditoria');

      final btn = find.widgetWithText(FilledButton, 'Verificar cadeia de hash');
      await tester.tap(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(api.chamadasCadeia, 1);

      completer.complete(const ResultadoCadeia(ok: true, verificadas: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('timeout ao verificar cadeia e ao exportar CSV exibe erro e destrava botoes',
        (tester) async {
      final api = _ApiQa5Espiao(
        aoVerificarCadeia: () async => throw TimeoutException('timeout cadeia'),
        aoSolicitarRelatorio: () async => throw TimeoutException('timeout export'),
      );
      await abrirPainel(tester, papel: 'administrador', api: api, secao: 'auditoria');

      await tester.tap(find.widgetWithText(FilledButton, 'Verificar cadeia de hash'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('TimeoutException'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Verificar cadeia de hash'))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Exportar CSV'));
      await tester.pumpAndSettle();
      await confirmarMotivo(tester, 'Exportar CSV');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Código ERR-'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Exportar CSV')).onPressed,
        isNotNull,
      );
    });
  });
}
