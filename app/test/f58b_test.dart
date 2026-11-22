import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/cliente/avatar_iniciais.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child, {ThemeData? tema}) =>
    MaterialApp(theme: tema ?? TemaTrato.claro, home: child);

class _ServicoCadastroF58bFake implements ServicoCadastroProfissional {
  @override
  Future<OpcoesCadastro> carregarOpcoes() async => opcoesCadastroPadrao;

  @override
  Future<DadosCadastroProfissional?> carregarAtual() async => null;

  @override
  Future<void> salvar(DadosCadastroProfissional dados) async {}
}

void main() {
  group('F58b — Correções visuais do emulador e Modo Dark', () {
    testWidgets('1. FAB "+ Novo pedido" na aba Pedidos fica acima da BarraAbasFlutuante',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _envolver(
          Scaffold(
            extendBody: true,
            body: RotasTrato.abaPedidos(),
            bottomNavigationBar: BarraAbasFlutuante(
              abas: abasCliente,
              indiceAtual: 2,
              aoSelecionar: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const ValueKey('fab-novo-pedido'));
      final barraFinder = find.byType(BarraAbasFlutuante);
      expect(fabFinder, findsOneWidget);
      expect(barraFinder, findsOneWidget);

      final fabRect = tester.getRect(fabFinder);
      final barraRect = tester.getRect(barraFinder);

      // A base do FAB não pode sobrepor o topo da barra flutuante.
      expect(fabRect.bottom, lessThanOrEqualTo(barraRect.top + 4));
    });

    testWidgets('2. Toque na foto do cabeçalho do chat abre o perfil e NÃO abre ampliação da foto',
        (tester) async {
      var abriuPerfil = 0;
      const conversa = ConversaPedido(
        nome: 'Carlos Silva',
        iniciais: 'CS',
        numeroPedido: '#42',
        situacao: 'Em andamento',
        mensagens: [],
        respostasRapidas: [],
        usuarioId: 'pro-com-foto',
        pedidoId: 'p42',
      );

      await tester.pumpWidget(
        _envolver(
          ChatPedidoTela(
            conversa: conversa,
            aoAbrirPerfil: () => abriuPerfil++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Garante que o AvatarIniciais no cabeçalho tem ampliação desligada e sem ToquePreviewImagem.
      final avatar = tester.widget<AvatarIniciais>(find.byType(AvatarIniciais).first);
      expect(avatar.permitirAmpliacao, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cabecalho-chat-perfil')),
          matching: find.byType(ToquePreviewImagem),
        ),
        findsNothing,
      );

      // Tocar diretamente sobre o avatar dispara apenas aoAbrirPerfil.
      await tester.tap(find.byType(AvatarIniciais).first);
      await tester.pumpAndSettle();
      expect(abriuPerfil, 1);
      // Nenhum modal de foto aberto.
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('3. CadastroProfissionalTela mostra o novo texto "Sem taxa de serviço."',
        (tester) async {
      await tester.pumpWidget(
        _envolver(CadastroProfissionalTela(servico: _ServicoCadastroF58bFake())),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sem taxa de serviço. Receba pedidos direto no celular.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('0% de taxa enquanto crescemos'),
        findsNothing,
      );
    });

    testWidgets('4. SeusPedidosTela e ChatPedidoTela renderizam sem erro com cores de CoresTratoEscuro',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          const SeusPedidosTela(
            emAndamento: [
              PedidoResumo(
                id: 'p1',
                titulo: 'Instalar chuveiro',
                subtitulo: 'Carlos · #01',
                statusTexto: 'Em execução',
                statusTipo: TipoStatus.info,
                profissionalNome: 'Carlos',
              ),
            ],
            finalizados: [],
          ),
          tema: TemaTrato.escuro,
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('Seus pedidos'));
      expect(Theme.of(ctx).scaffoldBackgroundColor, CoresTratoEscuro.fundo);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _envolver(
          const ChatPedidoTela(
            conversa: ConversaPedido(
              nome: 'Carlos Silva',
              iniciais: 'CS',
              numeroPedido: '#42',
              situacao: 'Em andamento',
              mensagens: [],
              respostasRapidas: ['Pode vir às 14h'],
              usuarioId: 'pro1',
              pedidoId: 'p42',
            ),
          ),
          tema: TemaTrato.escuro,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
