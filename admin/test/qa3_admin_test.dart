// QA3-B: Testes adversariais do Painel Admin (em memoria; sem tocar producao).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/recuperacao_senha.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

class _ApiAdversarial extends ApiFake {
  _ApiAdversarial({
    super.erro,
    this.lentoDecidir = false,
    this.muitosItens = false,
  });

  final bool lentoDecidir;
  final bool muitosItens;
  int chamadasDecidir = 0;
  final completerDecidir = Completer<ResultadoDecisao>();

  @override
  Future<ResultadoDecisao> decidirDisputa(
    String id, {
    required DecisaoDisputa decisao,
    int? valorReembolsoCentavos,
    required String justificativa,
    StatusDisputa? estadoEsperado,
  }) {
    chamadasDecidir++;
    if (lentoDecidir) return completerDecidir.future;
    return super.decidirDisputa(
      id,
      decisao: decisao,
      valorReembolsoCentavos: valorReembolsoCentavos,
      justificativa: justificativa,
      estadoEsperado: estadoEsperado,
    );
  }

  @override
  Future<List<UsuarioBusca>> buscarUsuarios(String termo) async {
    if (erro) throw const ErroApi('Falha de rede');
    if (muitosItens) {
      return [
        for (var i = 0; i < 500; i++)
          UsuarioBusca(
            id: 'u-$i',
            nome: 'Usuário $i 🔧',
            tipo: i.isEven ? 'cliente' : 'profissional',
            status: 'ativo',
            cidade: 'Belo Horizonte',
            emailMascarado: 'u$i***@teste.local',
            telefoneMascarado: '(31) 9****-${i.toString().padLeft(4, '0')}',
          ),
      ];
    }
    return super.buscarUsuarios(termo);
  }

  @override
  Future<List<LancamentoEspelho>> extrato({int? dias}) async {
    if (erro) throw const ErroApi('Falha de rede');
    if (muitosItens) {
      return [
        for (var i = 0; i < 500; i++)
          LancamentoEspelho(
            id: 'l-$i',
            pedido: 'PED-$i',
            data: DateTime.now().subtract(Duration(minutes: i)),
            descricao: 'Pagamento $i',
            valorCentavos: 10000,
            refProvedor: 'pi_$i',
            status: StatusProvedor.confirmado,
          ),
      ];
    }
    return super.extrato(dias: dias);
  }

  @override
  Future<PaginaAuditoria> listarAuditoria({
    String? acao,
    String? ator,
    String? entidade,
    DateTime? desde,
    DateTime? ate,
    int limite = 25,
    int deslocamento = 0,
  }) async {
    if (erro) throw const ErroApi('Falha de rede');
    if (muitosItens) {
      final todos = [
        for (var i = 1; i <= 500; i++)
          EntradaAuditoria(
            id: i,
            ocorridaEm: DateTime(2026, 11, 20, 10).subtract(Duration(minutes: i)),
            ator: 'admin@teste.local',
            atorNome: 'Admin',
            acao: 'acao.teste',
            entidade: 'entidade:$i',
            motivo: 'Motivo $i',
            hash: 'h$i',
          ),
      ];
      return PaginaAuditoria(
        itens: todos.skip(deslocamento).take(limite).toList(),
        total: 500,
      );
    }
    return super.listarAuditoria(
      acao: acao,
      ator: ator,
      entidade: entidade,
      desde: desde,
      ate: ate,
      limite: limite,
      deslocamento: deslocamento,
    );
  }
}

void main() {
  group('Login, Esqueci a senha e Nova senha', () {
    testWidgets('login vazio / espacos / senha curta', (tester) async {
      await abrirPainelSemEntrar(tester);
      await tester.enterText(find.widgetWithText(TextField, 'E-mail da equipe'), '   ');
      await tester.enterText(find.widgetWithText(TextField, 'Senha'), '');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Preencha e-mail e senha.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'E-mail da equipe'), 'admin@teste.local');
      await tester.enterText(find.widgetWithText(TextField, 'Senha'), '123');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('incorretos'), findsOneWidget);
    });

    testWidgets('Esqueci a senha com e-mail invalido nao envia e valido envia', (tester) async {
      final api = ApiFake();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(PainelApp(key: UniqueKey(), api: api));
      await tester.tap(find.text('Esqueci a senha'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '<script>invalido</script>');
      await tester.pump();
      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();
      expect(api.recuperacoesPedidas, isEmpty);

      await tester.enterText(find.byType(TextField).last, 'equipe@feitolabs.com.br');
      await tester.pump();
      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();
      expect(api.recuperacoesPedidas, ['equipe@feitolabs.com.br']);
    });

    testWidgets('NovaSenhaTela: token expirado, vencido no backend e senha curta', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final linkExpirado = LinkRecuperacao.deUri(
        Uri.parse('https://painel.teste/#error=access_denied&error_code=otp_expired'),
      );
      await tester.pumpWidget(PainelApp(key: UniqueKey(), api: ApiFake(), linkRecuperacao: linkExpirado));
      await tester.pumpAndSettle();
      expect(find.textContaining('expirou'), findsOneWidget);

      final linkVencidoBackend = LinkRecuperacao.deUri(
        Uri.parse('https://painel.teste/#access_token=token-vencido&type=recovery'),
      );
      await tester.pumpWidget(PainelApp(key: UniqueKey(), api: ApiFake(), linkRecuperacao: linkVencidoBackend));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nova-senha')), 'curta');
      await tester.pump();
      expect(find.textContaining('Mínimo'), findsWidgets);

      await tester.enterText(find.byKey(const ValueKey('nova-senha')), 'SenhaForte123');
      await tester.enterText(find.byKey(const ValueKey('confirmar-senha')), 'SenhaForte123');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Definir senha'));
      await tester.pumpAndSettle();
      expect(find.textContaining('expirou'), findsOneWidget);
    });
  });

  group('Papeis sem permissao', () {
    testWidgets('atendenteN1 nao ve menus de equipe, config, auditoria, disputas nem pagamentos', (tester) async {
      await abrirPainel(tester, papel: 'atendente_n1');
      expect(find.byKey(const ValueKey('menu-equipe')), findsNothing);
      expect(find.byKey(const ValueKey('menu-config')), findsNothing);
      expect(find.byKey(const ValueKey('menu-auditoria')), findsNothing);
      expect(find.byKey(const ValueKey('menu-pagamentos')), findsNothing);
      expect(find.byKey(const ValueKey('menu-disputas')), findsNothing);
    });
  });

  group('Disputas e Reembolso por alcada', () {
    testWidgets('valor 0, negativo, acima da alcada, motivo curto e duplo clique', (tester) async {
      final api = _ApiAdversarial(lentoDecidir: true);
      await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas');

      await rolarListaAte(tester, find.text('Reembolso parcial'));
      await tester.tap(find.text('Reembolso parcial'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Valor do reembolso (R\$)'), '0');
      await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'curto');
      await tester.pumpAndSettle();
      await rolarListaAte(tester, find.text('Reembolsar em parte'));
      await tester.tap(find.text('Reembolsar em parte'));
      await tester.pumpAndSettle();
      expect(api.chamadasDecidir, 0);

      await tester.enterText(find.widgetWithText(TextField, 'Valor do reembolso (R\$)'), '-50');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reembolsar em parte'));
      await tester.pumpAndSettle();
      expect(api.chamadasDecidir, 0);

      // Mediador tem alcada de R$ 500,00 e a disputa d-1 tem R$ 2.400,00: R$ 600,00 exige segunda aprovacao
      await tester.enterText(find.widgetWithText(TextField, 'Valor do reembolso (R\$)'), '600,00');
      await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'Justificativa valida para o reembolso.');
      await tester.pumpAndSettle();
      await rolarListaAte(tester, find.text('Enviar para aprovação'));
      await tester.tap(find.text('Enviar para aprovação'));
      await tester.pump();
      await tester.tap(find.text('Registrando'));
      await tester.pump();
      expect(api.chamadasDecidir, 1);
      api.completerDecidir.complete(
        const ResultadoDecisao(status: StatusDisputa.aguardandoSegundaPessoa, mensagem: 'Enviado'),
      );
      await tester.pumpAndSettle();
    });
  });

  group('Configuracoes, Equipe, Busca, Pagamentos, Verificacao e Auditoria', () {
    testWidgets('ConfigTela: valor vazio desabilita Propor, texto e fora da faixa mostram erro', (tester) async {
      await abrirPainel(tester, papel: 'administrador', secao: 'config');
      final campo = find.byKey(const ValueKey('campo-adiantamento_bps'));
      await tester.enterText(campo, '');
      await tester.pumpAndSettle();
      // Campo vazio: mostra a dica e continua sem permitir propor.
      expect(find.text('Digite um número'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Propor').first).onPressed, isNull);

      await tester.enterText(campo, 'abc');
      await tester.pumpAndSettle();
      expect(find.textContaining('Percentual inválido'), findsOneWidget);

      await tester.enterText(campo, '999');
      await tester.pumpAndSettle();
      expect(find.textContaining('Fora da faixa'), findsOneWidget);
    });

    testWidgets('EquipeTela: email invalido, alcada acima do teto e motivo curto', (tester) async {
      await abrirPainel(tester, papel: 'administrador', secao: 'equipe');
      await tester.tap(find.text('Conceder acesso'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Maria Silva');
      await tester.enterText(find.widgetWithText(TextField, 'E-mail corporativo'), 'email-invalido');
      await tester.enterText(find.widgetWithText(TextField, 'Alçada'), '9999999');
      await tester.pumpAndSettle();
      expect(find.text('Informe um e-mail válido'), findsOneWidget);
      expect(find.textContaining('Passa do teto'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'E-mail corporativo'), 'maria@feitolabs.com.br');
      await tester.enterText(find.widgetWithText(TextField, 'Alçada'), '0');
      await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'curto');
      await tester.pumpAndSettle();
      final modal = find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);
      final btn = tester.widget<FilledButton>(
        find.descendant(of: modal, matching: find.widgetWithText(FilledButton, 'Conceder acesso')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('Busca, Pagamentos e Auditoria com 500 itens', (tester) async {
      final api500 = _ApiAdversarial(muitosItens: true);
      await abrirPainel(tester, papel: 'administrador', api: api500, secao: 'busca');
      await tester.enterText(find.byType(TextField).first, '<script>alert(1)</script>');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await irPara(tester, 'pagamentos');
      expect(tester.takeException(), isNull);

      await irPara(tester, 'auditoria');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Verificacao com erro de rede mostra falha tratada', (tester) async {
      final apiErro = _ApiAdversarial(erro: true);
      await abrirPainel(tester, papel: 'administrador', api: apiErro, secao: 'verificacao');
      expect(find.textContaining('Não foi possível'), findsWidgets);
    });

    testWidgets('Auditoria detecta cadeia quebrada', (tester) async {
      final apiQuebrada = ApiFake(cadeiaQuebradaEm: 3);
      await abrirPainel(tester, papel: 'administrador', api: apiQuebrada, secao: 'auditoria');
      await tester.tap(find.text('Verificar cadeia de hash'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cadeia de hash quebrada a partir do registro nº 3'), findsOneWidget);
    });

    testWidgets('Layout celular 400x700 abre Auditoria via Mais sem overflow', (tester) async {
      await abrirPainel(tester, papel: 'administrador', largura: 400, altura: 700);
      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('menu-auditoria')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('menu-auditoria')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
