import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
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
      itens: const [ItemOrcamento(descricao: 'Tinta', centavos: 4000)],
      notaMaterial: '',
      agendaTitulo: '',
      agendaDetalhe: '',
      garantiaTitulo: '',
      garantiaDetalhe: '',
      foraDoEscopo: fora,
      cancelamento: '',
      tiposDosItens: tipos,
    );

Orcamento _orc(DetalheOrcamento detalhe) => Orcamento(
      id: 'o1',
      profissional: 'Ana Lima',
      iniciais: 'AL',
      verificacao: '',
      totalCentavos: 14000,
      nota: 4.8,
      notaResumo: '4,8 · 10 avaliações',
      servicosResumo: '10',
      servicosConcluidos: 10,
      quando: 'Sáb, 31/10 · 2 h',
      inicio: DateTime(2026, 10, 31, 10),
      garantia: '90 dias',
      observacao: 'Observação',
      detalhe: detalhe,
    );

void main() {
  group('F45 · sem contradição de Material', () {
    test('conflito exato (case-insensitive) ajusta Inclui e Não inclui; sem conflito mantém igual',
        () {
      final conflito = _detalhe(
        tipos: ['horas', 'material'],
        fora: 'Material, Limpeza e retirada de entulho',
      );
      expect(textoInclui(conflito), 'Mão de obra, Material listado');
      expect(textoNaoInclui(conflito), 'Demais materiais, Limpeza e retirada de entulho');

      final conflitoMinusculo = _detalhe(tipos: ['material'], fora: 'material');
      expect(textoInclui(conflitoMinusculo), 'Material listado');
      expect(textoNaoInclui(conflitoMinusculo), 'Demais materiais');

      // Sem item de material em Inclui: não muda.
      final semMaterialInclui = _detalhe(tipos: ['horas'], fora: 'Material');
      expect(textoInclui(semMaterialInclui), 'Mão de obra');
      expect(textoNaoInclui(semMaterialInclui), 'Material');

      // Item não exato ("Material de acabamento"): não muda.
      final textoParcial = _detalhe(tipos: ['material'], fora: 'Material de acabamento');
      expect(textoInclui(textoParcial), 'Material');
      expect(textoNaoInclui(textoParcial), 'Material de acabamento');
    });

    testWidgets('calculadora troca chip Material por Demais materiais quando há item de material',
        (tester) async {
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: ServicoOrcamentoFake(),
          tituloPedido: 'Pintura de quarto',
          itensIniciais: const [ItemMaterial(nome: 'Tinta', centavos: 4000)],
        ),
      );
      expect(find.byKey(const ValueKey('sugestao-nao-incluso-Material')), findsNothing);
      final chipDemais = find.byKey(const ValueKey('sugestao-nao-incluso-Demais materiais'));
      expect(chipDemais, findsOneWidget);

      await tester.tap(chipDemais);
      await tester.pumpAndSettle();
      expect(chipDemais, findsNothing);
      expect(find.text('Demais materiais'), findsOneWidget);
    });

    testWidgets('comparador e detalhe mostram Material listado e Demais materiais sem contradição',
        (tester) async {
      final orc = _orc(_detalhe(tipos: ['horas', 'material'], fora: 'Material'));

      await _abrir(
        tester,
        OrcamentosRecebidosTela(
          pedido: const ResumoPedido(
            numero: '#FDDA',
            titulo: 'Pintura',
            recebidos: 1,
            limite: 5,
            tempoRestante: '20h',
          ),
          orcamentos: [orc],
        ),
      );
      expect(find.text('Mão de obra, Material listado'), findsOneWidget);
      expect(find.text('Demais materiais'), findsOneWidget);

      await _abrir(tester, DetalheOrcamentoTela(orcamento: orc));
      expect(find.text('Mão de obra, Material listado'), findsOneWidget);
      expect(find.text('Demais materiais'), findsOneWidget);
    });
  });

  group('F45 · banner de 1º orçamento no detalhe do pedido do cliente', () {
    Widget telaPedido(int orcamentosRecebidos) => PedidoAbertoTela(
          numero: 'FDDA',
          dados: DadosDoPedido(
            categoriaNome: 'Pintura',
            titulo: 'Pintar quarto',
            descricao: 'Pintura interna',
            orcamentosRecebidos: orcamentosRecebidos,
          ),
          aoVerOrcamentos: () {},
          aoSalvar: ({
            required String descricao,
            required int faixaMaxCentavos,
            required String logradouro,
            required String numero,
            required String bairro,
            String? cep,
          }) async =>
              null,
        );

    testWidgets('mostra banner com 0 orçamentos e oculta com 1 ou mais', (tester) async {
      await _abrir(tester, telaPedido(0));
      expect(find.textContaining('avisaremos quando chegar o 1º orçamento'), findsOneWidget);

      await _abrir(tester, telaPedido(1));
      expect(find.textContaining('avisaremos quando chegar o 1º orçamento'), findsNothing);
    });

    test(
        'RepositorioPedidosApi.dados preenche orcamentosRecebidos via /orcamentos quando /dados omite',
        () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('token'),
        cliente: MockClient((r) async {
          if (r.url.path == '/v1/pedidos/p1/dados') {
            return http.Response(
              jsonEncode({
                'categoria_nome': 'Pintura',
                'titulo': 'Pintar quarto',
                'descricao': 'Pintura interna',
                'estado': 'aberto',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path == '/v1/pedidos/p1/orcamentos') {
            return http.Response(
              jsonEncode([
                {'id': 'o1', 'valor_centavos': 14000},
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('null', 200, headers: {'content-type': 'application/json'});
        }),
      );
      final dados = await RepositorioPedidosApi(api).dados('p1');
      expect(dados.orcamentosRecebidos, 1);
    });
  });
}
