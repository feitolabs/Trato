import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';
import 'apoio/endereco_pedido.dart';

const _formulario = FormularioPedido(
  categoria: 'Eletricista',
  servicos: ['Tomada'],
  servicosIniciais: {'Tomada'},
  perguntaQuantidade: 'Quantas?',
  dicaQuantidade: 'Qtd',
  quantidadeInicial: 1,
  perguntaVoltagem: 'Voltagem',
  voltagens: ['220 V'],
  voltagemInicial: '220 V',
  descricaoInicial: 'Instalação na sala',
  fotos: [],
  prazos: ['Esta semana'],
  faixas: [FaixaPreco(minimoCentavos: 10000, maximoCentavos: 20000)],
  endereco: 'Centro',
  avisoEndereco: '',
  avisoPrazo: '',
  categoriaId: 'cat-1',
  cidades: [CidadeOpcao(id: 'cid-1', nome: 'BH', uf: 'MG')],
  aceitaRemoto: true,
);

/// Percorre a tela real de novo pedido até o POST de verdade (repositório + HTTP simulado) e
/// devolve o corpo enviado.
Future<Map<String, dynamic>> _enviarPelaTela(
  WidgetTester t,
  Future<void> Function() marcar,
) async {
  final corpos = <Map<String, dynamic>>[];
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      corpos.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'id': 'ab12cd34',
          'estado': 'aberto',
          'estado_nome': 'Aberto',
          'cliente_id': 'c1',
          'aberto_em': '2026-11-21T10:00:00Z',
          'acoes_permitidas': <String>[],
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final repo = RepositorioPedidosApi(api);
  t.view.physicalSize = const Size(390, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: NovoPedidoTela(
        formulario: _formulario,
        agora: () => DateTime(2026, 11, 21, 10),
        aoEnviar: (r) async => repo.criar(r),
      ),
    ),
  );
  await t.pumpAndSettle();
  await preencherEnderecoDoPedido(t);
  await marcar();
  await t.ensureVisible(find.text('Enviar pedido'));
  await t.tap(find.text('Enviar pedido'));
  await t.pumpAndSettle();
  return corpos.single;
}

void main() {
  testWidgets('marcar "É urgente (para hoje)" e enviar: o POST leva urgente=true', (t) async {
    final corpo = await _enviarPelaTela(t, () async {
      await t.ensureVisible(find.text('É urgente (para hoje)'));
      await t.tap(find.text('É urgente (para hoje)'));
      await t.pump();
    });
    expect(corpo['urgente'], isTrue);
  });

  testWidgets('urgente depois de trocar de prazo: continua urgente=true',
      (t) async {
    final corpo = await _enviarPelaTela(t, () async {
      await t.ensureVisible(find.text('Tenho data limite'));
      await t.tap(find.text('Tenho data limite'));
      await t.pump();
      await t.ensureVisible(find.text('É urgente (para hoje)'));
      await t.tap(find.text('É urgente (para hoje)'));
      await t.pump();
    });
    expect(corpo['urgente'], isTrue);
  });

  testWidgets('sem marcar urgente, o POST leva urgente=false', (t) async {
    final corpo = await _enviarPelaTela(t, () async {});
    expect(corpo['urgente'], isFalse);
  });
}
