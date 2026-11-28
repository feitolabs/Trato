// Termos 8.4: o que o cliente espera no Relato de Problema.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/comuns/resultado_esperado.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/disputa_acordo/acordo.dart';
import 'package:trato/telas/disputa_acordo/secao_acordo.dart';

ClienteApi _api((int, Object) Function(http.Request r) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        final (status, corpo) = responder(r);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    );

Map<String, Object?> _disputa(Map<String, Object?> extra) => {
      'pedido_id': 'p1',
      'estado': 'aberta',
      'motivo': 'mal_feito',
      'valor_congelado_centavos': 100,
      ...extra,
    };

const _antiga = 'Vazou.\n\nSolução que o cliente prefere: Reembolso total';

void main() {
  test('o campo vale mais que o texto; ausente ou desconhecido não quebra', () {
    expect(separarRelato(_antiga, 'retrabalho'),
        (descricao: 'Vazou.', pedido: 'Retrabalho sem custo'));
    expect(separarRelato(_antiga, null), (descricao: 'Vazou.', pedido: 'Reembolso total'));
    expect(separarRelato('Vazou.', 'outro_valor'), (descricao: 'Vazou.', pedido: null));
    expect(separarRelato(null, 7), (descricao: '', pedido: null));
  });

  for (var i = 0; i < codigosResultadoEsperado.length; i++) {
    final codigo = codigosResultadoEsperado[i];
    test('abertura envia resultado_esperado=$codigo, nas duas telas', () async {
      final corpos = <Map<String, dynamic>>[];
      final repo = RepositorioPedidosApi(_api((r) {
        corpos.add(jsonDecode(r.body) as Map<String, dynamic>);
        return (201, <String, Object>{});
      }));
      final texto = repo.textos.solucoes[i];
      expect(texto, textoResultadoEsperado(codigo));
      await repo.relatarProblema(
          'p1', EnvioRelato(motivo: repo.textos.motivos.first, descricao: 'x', solucao: texto));
      await repo.relatarPedidoContratado('p1',
          motivo: 'mal_feito', descricao: 'x', resultadoEsperado: codigo);
      expect(corpos.map((c) => c['resultado_esperado']), [codigo, codigo]);
      expect(corpos.every((c) => !c.keys.any((k) => k.contains('centavos'))), isTrue);
    });
  }

  test('servidor antigo (422): reenvia uma vez sem o campo', () async {
    final corpos = <Map<String, dynamic>>[];
    final repo = RepositorioPedidosApi(_api((r) {
      final c = jsonDecode(r.body) as Map<String, dynamic>;
      corpos.add(c);
      return c.containsKey('resultado_esperado')
          ? (422, {'detail': 'Extra inputs are not permitted'})
          : (201, <String, Object>{});
    }));
    await repo.relatarPedidoContratado('p1',
        motivo: 'mal_feito', descricao: 'x', resultadoEsperado: 'retrabalho');
    expect(corpos.map((c) => c.containsKey('resultado_esperado')), [true, false]);
  });

  test('outras recusas não são reenviadas e a mensagem chega', () async {
    for (final (status, corpo, vezes) in [
      (409, {'detail': 'Já existe disputa.'}, 1),
      (422, {'detail': 'Informe o CPF.', 'codigo': 'cpf_obrigatorio'}, 1),
      (422, {'detail': 'Descreva melhor.'}, 2),
    ]) {
      var chamadas = 0;
      final repo = RepositorioPedidosApi(_api((r) {
        chamadas++;
        return (status, corpo);
      }));
      await expectLater(
        repo.relatarPedidoContratado('p1',
            motivo: 'mal_feito', descricao: 'x', resultadoEsperado: 'retrabalho'),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', corpo['detail'])),
      );
      expect(chamadas, vezes);
    }
  });

  test('detalhe: bloqueado e profissional leem o campo, com e sem ele', () async {
    for (final (extra, pedido) in <(Map<String, Object?>, String?)>[
      ({'descricao': 'Vazou.', 'resultado_esperado': 'reembolso_parcial'}, 'Reembolso parcial'),
      ({'descricao': _antiga, 'resultado_esperado': null}, 'Reembolso total'),
      ({'descricao': 'Vazou.'}, null),
    ]) {
      final api = _api((r) =>
          r.url.path.endsWith('/disputa') ? (200, _disputa(extra)) : (404, {'detail': 'Nada.'}));
      final relato = (await RepositorioPedidosApi(api).relatoDoPedidoContratado('p1'))!;
      expect((relato.resultadoEsperado, relato.descricao), (pedido, 'Vazou.'));
      final prof = (await ServicoDisputaProfissionalApi(api).carregarDisputa('p1'))!;
      expect(prof.solucaoPedida, pedido ?? 'Não informada');
      expect((await ServicoAcordoDisputaApi(api).ver('p1'))!.pedidoDoCliente, pedido);
    }
  });

  for (final profissional in [false, true]) {
    testWidgets('detalhe na tela do pedido (profissional: $profissional)', (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Scaffold(
          body: SecaoAcordoDisputa(
            servico: ServicoAcordoDisputaApi(
                _api((r) => (200, _disputa({'resultado_esperado': 'reembolso_total'})))),
            pedidoId: 'p1',
            profissional: profissional,
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(
        find.text(
            profissional ? 'O cliente pediu: Reembolso total' : 'Você pediu: Reembolso total'),
        findsOneWidget,
      );
      expect(
          find.text(profissional ? avisoPedidoDoCliente : avisoEscolhaDoCliente), findsOneWidget);
      expect(find.textContaining('R\$'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
