import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/busca/modelos.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/tema/tema.dart';

class _BuscaGravando implements ServicoBusca {
  _BuscaGravando(this.resultados);

  final List<Profissional> resultados;
  final List<({String termo, bool disponivelAgora})> consultas = [];

  @override
  Future<List<Profissional>> buscar(String termo, {bool disponivelAgora = false}) async {
    consultas.add((termo: termo, disponivelAgora: disponivelAgora));
    // Como o backend: com o filtro ligado, só quem está disponível.
    return disponivelAgora ? const <Profissional>[] : resultados;
  }
}

const _ana = Profissional(
  nome: 'Ana S.',
  iniciais: 'AS',
  verificacao: 'Verificado',
  especialidade: 'Eletricista',
  servicosConcluidos: 10,
  nota: 4.9,
  distanciaKm: 2,
  atendeHoje: true,
);

void main() {
  testWidgets('chip "Disponíveis agora" liga e desliga e refaz a busca com o parâmetro',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final servico = _BuscaGravando(const [_ana]);
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: BuscaProfissionaisTela(servico: servico, termoInicial: 'eletricista'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disponíveis agora'), findsOneWidget);
    expect(servico.consultas.last, (termo: 'eletricista', disponivelAgora: false));
    expect(find.text('Ana S.'), findsOneWidget);

    // Liga: nova busca com disponivel_agora; sem resultados o chip continua para poder desligar.
    await tester.ensureVisible(find.text('Disponíveis agora'));
    await tester.tap(find.text('Disponíveis agora'));
    await tester.pumpAndSettle();
    expect(servico.consultas.last, (termo: 'eletricista', disponivelAgora: true));
    expect(find.text('Nada encontrado'), findsOneWidget);
    expect(find.text('Disponíveis agora'), findsOneWidget);

    // Desliga: volta a busca sem o filtro e os resultados.
    await tester.ensureVisible(find.text('Disponíveis agora'));
    await tester.tap(find.text('Disponíveis agora'));
    await tester.pumpAndSettle();
    expect(servico.consultas.last, (termo: 'eletricista', disponivelAgora: false));
    expect(find.text('Ana S.'), findsOneWidget);
  });
}
