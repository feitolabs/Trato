@Tags(['lento'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_fake.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/tema/tema.dart';

/// Percorre os caminhos de toque do app e falha se alguma tela mostrar o texto do placeholder
/// "Esta tela chega nas próximas etapas". É um explorador: em cada tela, toca em cada alvo
/// tocável (um de cada vez, a partir de uma árvore nova), confere a tela aberta e, se for uma
/// tela nova, entra nela até [_profundidade] toques. Telas com o mesmo conteúdo contam uma vez.
///
/// Fora do escopo desta passada: tudo o que vem depois de "Sair" (tela de login), que é do
/// fluxo de cadastro e acesso.
const _placeholder = 'chega nas próximas etapas';
const _profundidade = 3;
const _limiteDeTelas = 45;

class _Explorador {
  _Explorador(this.tester, this.raiz);

  final WidgetTester tester;
  final Widget Function() raiz;
  final visitadas = <String>{};
  final log = <String>[];

  Future<void> _assentar() async {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 4),
      );
    } on Object {
      // Animação infinita (ex.: espera de pagamento): segue com o quadro atual.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> _montar() async {
    RotasTrato.repos = RepositoriosTrato.demo();
    ServicoAuthPadrao.atual = ServicoAuthFake();
    // Solta a árvore anterior antes de montar a nova (a memória cresce com muitas montagens).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(key: UniqueKey(), theme: TemaTrato.claro, home: raiz()),
    );
    await _assentar();
  }

  /// Posições (centros) dos alvos tocáveis visíveis, de cima para baixo.
  List<Offset> _alvos() {
    final achados = find.byWidgetPredicate(
      (w) =>
          (w is InkWell && w.onTap != null) ||
          (w is GestureDetector && w.onTap != null) ||
          (w is ButtonStyleButton && w.onPressed != null) ||
          (w is IconButton && w.onPressed != null),
    );
    final tela = tester.view.physicalSize / tester.view.devicePixelRatio;
    final centros = <Offset>[];
    final vistos = <String>{};
    for (var i = 0; i < achados.evaluate().length; i++) {
      final centro = tester.getCenter(achados.at(i));
      final dentro = centro.dx > 0 && centro.dy > 0 && centro.dx < tela.width && centro.dy < tela.height;
      if (!dentro) continue;
      if (vistos.add('${centro.dx.round() ~/ 4}:${centro.dy.round() ~/ 4}')) centros.add(centro);
    }
    centros.sort((a, b) => a.dy != b.dy ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx));
    return centros;
  }

  String _assinatura() {
    final textos = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final dado = (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText();
      if (dado != null) textos.add(dado);
    }
    final modais = find.byType(BottomSheet).evaluate().length + find.byType(Dialog).evaluate().length;
    return '${textos.join('|')}#$modais';
  }

  void _conferir(List<int> caminho) {
    expect(
      find.textContaining(_placeholder, findRichText: true),
      findsNothing,
      reason: 'Placeholder na tela alcançada pelo caminho $caminho:\n${log.join('\n')}',
    );
  }

  Future<void> visitar(List<int> caminho) async {
    if (visitadas.length >= _limiteDeTelas) return;
    await _montar();
    for (final indice in caminho) {
      final alvos = _alvos();
      if (indice >= alvos.length) return;
      await tester.tapAt(alvos[indice]);
      await _assentar();
    }
    _conferir(caminho);
    if (find.byType(LoginTela).evaluate().isNotEmpty) return; // depois de "Sair"
    if (!visitadas.add(_assinatura())) return;
    log.add('tela ${visitadas.length}: caminho $caminho');
    if (caminho.length >= _profundidade) return;
    final quantos = _alvos().length;
    for (var i = 0; i < quantos; i++) {
      await visitar([...caminho, i]);
    }
  }
}

void main() {
  void explorar(String nome, Widget Function() raiz) {
    testWidgets('nenhum caminho de toque termina em placeholder — $nome', (tester) async {
      tester.view.physicalSize = const Size(390, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final explorador = _Explorador(tester, raiz);
      await explorador.visitar(const []);
      // ignore: avoid_print
      print('$nome: ${explorador.visitadas.length} telas distintas');
      expect(explorador.visitadas.length, greaterThan(3), reason: 'o explorador não entrou em nenhuma tela');
    }, timeout: const Timeout(Duration(minutes: 8)));
  }

  const abasCliente = ['Início', 'Buscar', 'Pedidos', 'Mensagens', 'Perfil'];
  const abasProfissional = ['Início', 'Pedidos', 'Agenda', 'Carteira', 'Perfil'];
  for (final (i, nome) in abasCliente.indexed) {
    explorar('cliente / $nome', () => CascaClienteTela(abaInicial: i));
  }
  for (final (i, nome) in abasProfissional.indexed) {
    explorar('profissional / $nome', () => RotasTrato.cascaProfissionalParaTeste(abaInicial: i));
  }
}
