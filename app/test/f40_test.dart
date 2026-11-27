import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

DetalheOrcamento _detalhe({List<String> tipos = const [], String fora = ''}) => DetalheOrcamento(
      validoAte: '31/10',
      itens: const [ItemOrcamento(descricao: 'Serviço', centavos: 10000)],
      notaMaterial: '',
      agendaTitulo: '',
      agendaDetalhe: '',
      garantiaTitulo: '',
      garantiaDetalhe: '',
      foraDoEscopo: fora,
      cancelamento: '',
      tiposDosItens: tipos,
    );

Orcamento _orc(String id, String nome, DetalheOrcamento? detalhe) => Orcamento(
      id: id,
      profissional: nome,
      iniciais: nome.substring(0, 2).toUpperCase(),
      verificacao: '',
      totalCentavos: 10000,
      nota: 4.5,
      notaResumo: '4,5 · 10 avaliações',
      servicosResumo: '10',
      servicosConcluidos: 10,
      quando: 'Sáb, 31/10 · 2 h',
      inicio: DateTime(2026, 10, 31, 10),
      garantia: '90 dias',
      observacao: 'Observação',
      detalhe: detalhe,
    );

void main() {
  group('F40 · textos Inclui / Não inclui', () {
    test('Inclui: rótulos e ordem fixos, só o que existe', () {
      expect(
        textoInclui(_detalhe(tipos: ['material', 'horas', 'deslocamento', 'material'])),
        'Deslocamento, Mão de obra, Material',
      );
      expect(textoInclui(_detalhe(tipos: ['outro', 'horas'])), 'Mão de obra, Outros');
      expect(textoInclui(_detalhe(tipos: ['algo_novo'])), 'Outros'); // tipo desconhecido
      expect(textoInclui(_detalhe()), 'Valor combinado');
      expect(textoInclui(null), 'Valor combinado');
    });

    test('Não inclui: texto de fora_do_escopo ou "Nada informado"', () {
      expect(textoNaoInclui(_detalhe(fora: ' Pintura e reboco ')), 'Pintura e reboco');
      expect(textoNaoInclui(_detalhe()), 'Nada informado');
      expect(textoNaoInclui(_detalhe(fora: '   ')), 'Nada informado');
      expect(textoNaoInclui(null), 'Nada informado');
    });

    test('a API alimenta o Inclui com o tipo de TODOS os itens (mesmo item de R\$ 0)', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('valor-de-teste'),
        cliente: MockClient((r) async {
          Object corpo = {'detail': 'não'};
          var status = 404;
          if (r.url.path == '/v1/pedidos/p1') {
            status = 200;
            corpo = {
              'id': 'p1',
              'estado': 'aberto',
              'estado_nome': 'Aberto',
              'cliente_id': 'c1',
              'aberto_em': DateTime.now().toUtc().toIso8601String(),
              'acoes_permitidas': <String>[],
            };
          } else if (r.url.path == '/v1/pedidos/p1/orcamentos') {
            status = 200;
            corpo = [
              {
                'id': 'o1',
                'profissional_id': 'pro1',
                'profissional_nome': 'Ana L.',
                'valor_centavos': 15000
              },
            ];
          } else if (r.url.path == '/v1/orcamentos/o1') {
            status = 200;
            corpo = {
              'id': 'o1',
              'fora_do_escopo': 'Pintura',
              'itens': [
                {
                  'tipo': 'deslocamento',
                  'descricao': 'Ida',
                  'quantidade': '1',
                  'total_centavos': 0
                },
                {
                  'tipo': 'horas',
                  'descricao': 'Mão de obra',
                  'quantidade': '2',
                  'total_centavos': 12000
                },
                {
                  'tipo': 'material',
                  'descricao': 'Tomada',
                  'quantidade': '1',
                  'total_centavos': 3000
                },
              ],
            };
          }
          return http.Response(
            jsonEncode(corpo),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final r = await RepositorioOrcamentosApi(api).listar('p1');
      final d = r.orcamentos.single.detalhe!;
      expect(d.tiposDosItens, ['deslocamento', 'horas', 'material']);
      expect(textoInclui(d), 'Deslocamento, Mão de obra, Material');
      expect(textoNaoInclui(d), 'Pintura');
    });
  });

  group('F40 · cliente vê Inclui / Não inclui', () {
    final completo = _orc(
      'a',
      'Ana Lima',
      _detalhe(tipos: ['material', 'horas', 'deslocamento'], fora: 'Pintura e reboco'),
    );
    final vazio = _orc('b', 'Beto Souza', _detalhe());

    testWidgets('comparador: cada orçamento tem as duas colunas; vazios mostram o texto padrão',
        (tester) async {
      await _abrir(
        tester,
        OrcamentosRecebidosTela(
          pedido: const ResumoPedido(
            numero: 'AB12',
            titulo: 'Tomada',
            recebidos: 2,
            limite: 5,
            tempoRestante: '30 horas',
          ),
          orcamentos: [completo, vazio],
        ),
      );
      expect(find.text('Inclui:'), findsNWidgets(2));
      expect(find.text('Não inclui:'), findsNWidgets(2));
      expect(find.text('Deslocamento, Mão de obra, Material'), findsOneWidget);
      expect(find.text('Pintura e reboco'), findsOneWidget);
      expect(find.text('Valor combinado'), findsOneWidget);
      expect(find.text('Nada informado'), findsOneWidget);
    });

    Text naoInclui(WidgetTester tester) => tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('orcamento-nao-inclui')),
                matching: find.byType(Text),
              )
              .last,
        );

    testWidgets('comparador limita o "Não inclui" a 2 linhas; o detalhe mostra completo',
        (tester) async {
      const longo = 'Troca de fiação embutida, quebra de parede, pintura, reboco e retirada de '
          'entulho. Se for preciso, o profissional propõe um aditivo e você aprova antes.';
      final longoOrc = _orc('c', 'Carla Dias', _detalhe(fora: longo));
      await _abrir(
        tester,
        OrcamentosRecebidosTela(
          pedido: const ResumoPedido(
            numero: 'AB12',
            titulo: 'Tomada',
            recebidos: 1,
            limite: 5,
            tempoRestante: '30 horas',
          ),
          orcamentos: [longoOrc],
        ),
      );
      final noComparador = naoInclui(tester);
      expect(noComparador.data, longo); // o texto inteiro está lá; só a exibição é cortada
      expect(noComparador.maxLines, 2);
      expect(noComparador.overflow, TextOverflow.ellipsis);

      await _abrir(tester, DetalheOrcamentoTela(orcamento: longoOrc));
      final noDetalhe = naoInclui(tester);
      expect(noDetalhe.maxLines, isNull);
      expect(noDetalhe.data, longo);
    });

    testWidgets('detalhe: mesmo rótulo e mesma ordem', (tester) async {
      await _abrir(tester, DetalheOrcamentoTela(orcamento: completo));
      expect(find.byKey(const Key('orcamento-inclui')), findsOneWidget);
      expect(find.text('Inclui:'), findsOneWidget);
      expect(find.text('Deslocamento, Mão de obra, Material'), findsOneWidget);
      expect(find.text('Não inclui:'), findsOneWidget);
      expect(find.text('Pintura e reboco'), findsWidgets);
    });

    testWidgets('detalhe sem itens e sem fora_do_escopo: textos padrão', (tester) async {
      await _abrir(tester, DetalheOrcamentoTela(orcamento: vazio));
      expect(find.text('Valor combinado'), findsOneWidget);
      expect(find.text('Nada informado'), findsOneWidget);
    });
  });

  group('F40 · calculadora: sugestões do "não incluso"', () {
    Future<void> abrirCalculadora(WidgetTester tester, {String? inicial}) => _abrir(
          tester,
          CalculadoraOrcamentoTela(
            servico: ServicoOrcamentoFake(),
            tituloPedido: 'Trocar tomada',
            foraDoEscopoInicial: inicial,
          ),
        );

    String campo(WidgetTester tester) => tester
        .widget<TextField>(find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text('O que não está incluído'),
                    matching: find.byType(Column),
                  )
                  .first,
              matching: find.byType(TextField),
            )
            .first)
        .controller!
        .text;

    testWidgets('mostra as 4 sugestões; tocar acrescenta ao campo e o chip some', (tester) async {
      await abrirCalculadora(tester);
      for (final s in sugestoesNaoInclui) {
        expect(find.byKey(ValueKey('sugestao-nao-incluso-$s')), findsOneWidget);
      }
      final material = find.byKey(const ValueKey('sugestao-nao-incluso-Material'));
      await tester.ensureVisible(material);
      await tester.tap(material);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sugestao-nao-incluso-Material')), findsNothing);
      expect(campo(tester), 'Material');

      final limpeza =
          find.byKey(const ValueKey('sugestao-nao-incluso-Limpeza e retirada de entulho'));
      await tester.ensureVisible(limpeza);
      await tester.tap(limpeza);
      await tester.pumpAndSettle();
      expect(campo(tester), 'Material, Limpeza e retirada de entulho');
    });

    testWidgets('acrescenta ao que o profissional já escreveu (campo editável)', (tester) async {
      await abrirCalculadora(tester, inicial: 'Pintura');
      final reparos = find.byKey(const ValueKey('sugestao-nao-incluso-Reparos além do combinado'));
      await tester.ensureVisible(reparos);
      await tester.tap(reparos);
      await tester.pumpAndSettle();
      expect(campo(tester), 'Pintura, Reparos além do combinado');
    });

    testWidgets('usadas as 4, a faixa some', (tester) async {
      await abrirCalculadora(tester);
      for (final s in sugestoesNaoInclui) {
        final chip = find.byKey(ValueKey('sugestao-nao-incluso-$s'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('sugestoes-nao-incluso')), findsNothing);
    });
  });
}
