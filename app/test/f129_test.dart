// APP-VENCIDO: orçamento vencido não é oferecido nem cobrado; avaliação sem prazo fixo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/comuns/orcamento_vencido.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';

import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as pag;
import 'apoio/fontes.dart';

const _mensagem = 'Este orçamento venceu e perdeu o efeito (Termos 5.2). Peça um novo.';
const _vencido = ErroTrato(
  TipoErro.recusado,
  _mensagem,
  codigoHttp: 409,
  codigo: 'orcamento_vencido',
);

Orcamento _orcamento({DateTime? venceEm}) => Orcamento(
      id: 'o1',
      profissional: 'Carlos M.',
      iniciais: 'CM',
      verificacao: '',
      totalCentavos: 20000,
      nota: 0,
      notaResumo: semAvaliacoes,
      servicosResumo: '0',
      servicosConcluidos: 0,
      quando: 'hoje',
      inicio: DateTime(2026, 11, 20),
      garantia: '90 dias',
      observacao: '',
      detalhe: DetalheOrcamento(
        validoAte: '30/11',
        venceEm: venceEm,
        itens: const [],
        notaMaterial: '',
        agendaTitulo: '',
        agendaDetalhe: '',
        garantiaTitulo: 'Garantia',
        garantiaDetalhe: '90 dias',
        foraDoEscopo: '',
        cancelamento: '',
      ),
    );

Future<void> _abrir(WidgetTester t, Widget tela, {Size tamanho = const Size(390, 1600)}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

Future<void> _marcarLi(WidgetTester t) async {
  await t.ensureVisible(find.byType(Checkbox));
  await t.pumpAndSettle();
  await t.tap(find.byType(Checkbox));
  await t.pumpAndSettle();
}

const _aceitar = 'Aceitar e ir para o pagamento';

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('já vencido: sem aceitar nem contrapropor; dá para recusar', (t) async {
    await _abrir(
      t,
      DetalheOrcamentoTela(
        orcamento: _orcamento(venceEm: DateTime.now().subtract(const Duration(minutes: 1))),
        aoAceitar: (_) {},
        aoFazerContraproposta: (_) {},
        aoRecusar: (_) {},
      ),
    );
    expect(find.text(textoOrcamentoVencido), findsOneWidget);
    expect(find.text(_aceitar), findsNothing);
    expect(find.text('Fazer contraproposta'), findsNothing);
    expect(find.byKey(const ValueKey('botao-recusar-orcamento')), findsOneWidget);
  });

  for (final contraproposta in [false, true]) {
    testWidgets('409 ${contraproposta ? 'na contraproposta' : 'no aceite'}: aviso, uma vez só',
        (t) async {
      var chamadas = 0;
      Future<void> recusa(Orcamento _) async {
        chamadas++;
        throw _vencido;
      }

      await _abrir(
        t,
        DetalheOrcamentoTela(
          orcamento: _orcamento(venceEm: DateTime.now().add(const Duration(days: 1))),
          aoAceitar: recusa,
          aoFazerContraproposta: recusa,
        ),
      );
      if (contraproposta) {
        await t.tap(find.text('Fazer contraproposta'));
      } else {
        await _marcarLi(t);
        await t.tap(find.text(_aceitar));
      }
      await t.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text(_mensagem), findsOneWidget);
      expect(find.text(_aceitar), findsNothing);
      expect(chamadas, 1);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('cobrança recusada: aviso no lugar do botão de pagar', (t) async {
    var chamadas = 0;
    await _abrir(
      t,
      PagamentoTela(
        dados: pag.DadosExemplo.pagamento,
        aoPagarDetalhado: (_, __, ___) async {
          chamadas++;
          throw _vencido;
        },
      ),
      tamanho: const Size(390, 844),
    );
    await t.tap(find.textContaining('Pagar R\$'));
    await t.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text(_mensagem), findsOneWidget);
    expect(find.textContaining('Pagar R\$'), findsNothing);
    expect(chamadas, 1);
  });

  testWidgets('cobrança devolvida: diz só isso e para de consultar', (t) async {
    var consultas = 0;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: AguardandoPagamentoTela(
        consultar: () async {
          consultas++;
          return StatusPagamento.devolvido;
        },
        aoConfirmar: () => fail('não confirma'),
      ),
    ));
    await t.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text('Pagamento devolvido'), findsOneWidget);
    expect(find.text('A cobrança consta como devolvida.'), findsOneWidget);
    expect(find.textContaining('Nada foi cobrado'), findsNothing);
    expect(consultas, 1);
  });

  for (final profissional in [false, true]) {
    testWidgets('conversa, ${profissional ? 'aceitar contraproposta' : 'aceitar proposta'} vencida',
        (t) async {
      var chamadas = 0;
      Future<void> recusa(ContrapropostaChat _) async {
        chamadas++;
        throw _vencido;
      }

      await _abrir(
        t,
        ChatPedidoTela(
          conversa: ConversaPedido(
            nome: 'Carlos M.',
            iniciais: 'CM',
            numeroPedido: '#1234',
            situacao: 'Aguardando',
            souCliente: !profissional,
            orcamentosAtivos: const {'o1'},
            respostasRapidas: const [],
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.texto,
                hora: '10:00',
                texto: 'Nova condição',
                contraproposta: ContrapropostaChat(
                  orcamentoId: 'o1',
                  valorCentavos: 20000,
                  ehPropostaDoProfissional: !profissional,
                ),
              ),
            ],
          ),
          aoAceitarProposta: recusa,
          aoAceitarContraproposta: recusa,
          intervaloAtualizacao: const Duration(hours: 1),
        ),
      );
      await t.tap(find.text(profissional ? 'Aceitar e atualizar orçamento' : 'Aceitar e pagar'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('proposta-vencida')), findsOneWidget);
      expect(find.textContaining('Aceitar e'), findsNothing);
      expect(chamadas, 1);
      await t.pumpWidget(const SizedBox());
    });
  }

  test('o servidor: código do 409, validade do orçamento e cobrança devolvida', () async {
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        final (status, Object corpo) = r.method == 'POST'
            ? (409, {'detail': _mensagem, 'codigo': 'orcamento_vencido'})
            : (200, {'pago': false, 'estado_pagamento': 'devolvida'});
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    );
    expect(await RepositorioPagamentoApi(api).status('p1'), StatusPagamento.devolvido);
    await expectLater(
      RepositorioOrcamentosApi(api).aceitar('p1', 'o1'),
      throwsA(predicate<Object>(ehOrcamentoVencido)),
    );
  });

  for (final (bonus, valor) in [(0, null), (30, null), (30, 1)]) {
    testWidgets('avaliação do cliente sem prazo fixo ($bonus, $valor)', (t) async {
      await _abrir(
        t,
        AvaliacaoTela(
          dados: DadosAvaliacao(
            nomeProfissional: 'Carlos',
            valorLiberadoCentavos: 10000,
            criterios: const ['Qualidade'],
            gorjetasCentavos: const [],
            bonusDisponivel: true,
            bonusMoedas: bonus,
            valorMoedaCentavos: valor,
          ),
        ),
      );
      final legenda = find.byKey(const ValueKey('legenda-bonus-tratinhos'), skipOffstage: false);
      expect(legenda, findsOneWidget);
      expect(find.textContaining('7 dias', skipOffstage: false), findsNothing);
      expect(find.textContaining('qualquer nota', skipOffstage: false), findsOneWidget);
    });
  }
}
