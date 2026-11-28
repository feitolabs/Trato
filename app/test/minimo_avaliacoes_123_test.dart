// Termos 12.3: abaixo do mínimo de avaliações, mostra "Novo no Trato", serviços concluídos
// e total de avaliações. Campos ausentes (backend antigo) mantêm o comportamento atual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/catalogo/pecas_catalogo.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/comuns/contagem_avaliacoes.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester t, Widget tela) async {
  t.view.physicalSize = const Size(420, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

Profissional _profissional({
  double nota = 0,
  int servicos = 4,
  int totalAv = 2,
  ContagemAvaliacoes? contagem,
  String verificacao = 'Identidade verificada',
}) =>
    Profissional(
      id: 'p1',
      nome: 'Carlos M.',
      iniciais: 'CM',
      especialidade: 'Eletricista',
      nota: nota,
      servicosConcluidos: servicos,
      distanciaKm: 2.5,
      verificacao: verificacao,
      contagem: contagem,
      detalhe: DetalhePerfil(
        noTratoDesde: 2026,
        totalAvaliacoes: totalAv,
        taxaConclusao: 100,
        verificacoes: const ['Identidade verificada'],
        servicos: const ['Troca de chuveiro'],
        avaliacoes: const [],
      ),
    );

Orcamento _orcamento({
  double nota = 0,
  String notaResumo = semAvaliacoes,
  int servicos = 3,
  ContagemAvaliacoes? contagem,
}) =>
    Orcamento(
      id: 'o1',
      profissional: 'Carlos M.',
      iniciais: 'CM',
      verificacao: 'Identidade verificada',
      totalCentavos: 25000,
      nota: nota,
      notaResumo: notaResumo,
      servicosResumo: '$servicos',
      servicosConcluidos: servicos,
      quando: 'agora',
      inicio: DateTime(2026, 11, 28, 10),
      garantia: '30 dias',
      observacao: 'Levo escada.',
      contagem: contagem,
      detalhe: const DetalheOrcamento(
        validoAte: '30/11',
        itens: [ItemOrcamento(descricao: 'Mão de obra', centavos: 25000)],
        notaMaterial: 'Sem material.',
        agendaTitulo: 'Amanhã, 10h',
        agendaDetalhe: 'Visita de 1h.',
        garantiaTitulo: '30 dias',
        garantiaDetalhe: 'Cobre a instalação.',
        foraDoEscopo: 'Peças extras.',
        cancelamento: 'Sem taxa até 24h antes.',
      ),
    );

const _resumoPedido = ResumoPedido(
  numero: 'AB12',
  titulo: 'Trocar chuveiro',
  recebidos: 1,
  limite: 5,
  tempoRestante: '2 dias',
);

class _ServicoPerfilFake implements ServicoPerfilPublico {
  _ServicoPerfilFake(this._perfil);

  final PerfilPublico _perfil;

  @override
  Future<PerfilPublico> carregarPerfil() async => _perfil;

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => const [];

  @override
  Future<bool> temPerfilProfissional() async => true;
}

void main() {
  test('ContagemAvaliacoes.deJson lê campos, respeita mínimo e não quebra sem eles', () {
    final abaixo = ContagemAvaliacoes.deJson({
      'avaliacoes_total': 2,
      'nota_minimo_avaliacoes': 5,
    });
    expect(abaixo, isNotNull);
    expect(abaixo!.novoNoTrato, isTrue);
    expect(abaixo.textoAvaliacoes, '2 avaliações');

    final um = ContagemAvaliacoes.deJson({
      'profissional_avaliacoes_total': 1,
      'nota_minimo_avaliacoes': 3,
    }, chaveTotal: 'profissional_avaliacoes_total');
    expect(um!.novoNoTrato, isTrue);
    expect(um.textoAvaliacoes, '1 avaliação');

    final atingiu = ContagemAvaliacoes.deJson({
      'avaliacoes_total': 5,
      'nota_minimo_avaliacoes': 5,
    });
    expect(atingiu!.novoNoTrato, isFalse);

    expect(ContagemAvaliacoes.deJson(<String, dynamic>{}), isNull);
    expect(ContagemAvaliacoes.deJson({'avaliacoes_total': 2}), isNull);
    expect(
      ContagemAvaliacoes.deJson({'avaliacoes_total': null, 'nota_minimo_avaliacoes': 5}),
      isNull,
    );
    expect(ContagemAvaliacoes.deJson({'avaliacoes_total': 0, 'nota_minimo_avaliacoes': 0}), isNull);
    expect(textoServicosConcluidos(1), '1 serviço concluído');
    expect(textoServicosConcluidos(4), '4 serviços concluídos');
  });

  test('OfertaExclusividadeApi.deJson lê contagem e aceita servidor antigo', () {
    final base = {
      'id': 'e1',
      'pedido_id': 'ped1',
      'profissional_id': 'p1',
      'status': 'aguardando_cliente',
      'criada_em': '2026-11-27T10:00:00Z',
    };
    final nova = OfertaExclusividadeApi.deJson({
      ...base,
      'nota_publica': null,
      'avaliacoes_total': 2,
      'nota_minimo_avaliacoes': 5,
    });
    expect(nova.notaPublica, isNull);
    expect(nova.contagem?.novoNoTrato, isTrue);
    expect(nova.contagem?.total, 2);

    final antiga = OfertaExclusividadeApi.deJson({...base, 'nota_publica': 4.8});
    expect(antiga.notaPublica, 4.8);
    expect(antiga.contagem, isNull);
  });

  testWidgets('PerfilProfissionalTela: abaixo do mínimo mostra Novo no Trato e contagens',
      (t) async {
    await _abrir(
      t,
      PerfilProfissionalTela(
        profissional: _profissional(
          nota: 0,
          servicos: 4,
          totalAv: 2,
          contagem: const ContagemAvaliacoes(2, 5),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('novo-no-trato')), findsOneWidget);
    expect(find.textContaining('Novo no Trato'), findsOneWidget);
    expect(find.byKey(const ValueKey('contagem-novo')), findsOneWidget);
    expect(find.text('4 serviços concluídos · 2 avaliações'), findsOneWidget);
    expect(find.text('0,0'), findsNothing);
  });

  testWidgets('PerfilProfissionalTela: atingiu mínimo mostra nota; legado mantém comportamento',
      (t) async {
    await _abrir(
      t,
      PerfilProfissionalTela(
        profissional: _profissional(
          nota: 4.9,
          servicos: 6,
          totalAv: 5,
          contagem: const ContagemAvaliacoes(5, 5),
        ),
      ),
    );
    expect(find.text('Novo no Trato'), findsNothing);
    expect(find.textContaining('4,9'), findsOneWidget);
    expect(find.textContaining('(5)'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);

    await _abrir(
      t,
      PerfilProfissionalTela(
        profissional: _profissional(nota: 4.8, servicos: 4, totalAv: 2, contagem: null),
      ),
    );
    expect(find.textContaining('4,8'), findsOneWidget);
    expect(find.byKey(const ValueKey('novo-no-trato')), findsNothing);
  });

  testWidgets('DetalheOrcamentoTela e OrcamentosRecebidosTela respeitam mínimo e legado',
      (t) async {
    final abaixo = _orcamento(
      nota: 0,
      notaResumo: semAvaliacoes,
      servicos: 3,
      contagem: const ContagemAvaliacoes(2, 5),
    );
    await _abrir(t, DetalheOrcamentoTela(orcamento: abaixo));
    expect(find.textContaining('Novo no Trato'), findsOneWidget);
    expect(find.textContaining('3 serviços concluídos'), findsOneWidget);
    expect(find.textContaining('2 avaliações'), findsOneWidget);

    await _abrir(
      t,
      OrcamentosRecebidosTela(pedido: _resumoPedido, orcamentos: [abaixo]),
    );
    expect(find.text('Novo no Trato'), findsOneWidget);
    expect(find.text('Avaliações'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    final atingiu = _orcamento(
      nota: 4.7,
      notaResumo: '4,7',
      servicos: 7,
      contagem: const ContagemAvaliacoes(5, 5),
    );
    await _abrir(t, DetalheOrcamentoTela(orcamento: atingiu));
    expect(find.textContaining('Nota 4,7'), findsOneWidget);
    expect(find.textContaining('7 serviços concluídos'), findsOneWidget);
    expect(find.textContaining('5 avaliações'), findsOneWidget);

    final legado = _orcamento(nota: 4.8, notaResumo: '4,8', servicos: 2, contagem: null);
    await _abrir(
      t,
      OrcamentosRecebidosTela(pedido: _resumoPedido, orcamentos: [legado]),
    );
    expect(find.text('4,8'), findsOneWidget);
    expect(find.text('Avaliações'), findsNothing);
  });

  testWidgets('CartaoProfissional mostra Novo no Trato abaixo do mínimo e nota acima', (t) async {
    await _abrir(
      t,
      Scaffold(
        body: CartaoProfissional(
          profissional: _profissional(
            nota: 0,
            servicos: 3,
            totalAv: 1,
            contagem: const ContagemAvaliacoes(1, 5),
          ),
          aoAbrir: () {},
        ),
      ),
    );
    expect(find.text('Novo no Trato'), findsOneWidget);
    expect(find.textContaining('3 serviços concluídos · 1 avaliação'), findsOneWidget);
    expect(find.text('0,0'), findsNothing);

    await _abrir(
      t,
      Scaffold(
        body: CartaoProfissional(
          profissional: _profissional(
            nota: 4.8,
            servicos: 3,
            totalAv: 5,
            contagem: const ContagemAvaliacoes(5, 5),
          ),
          aoAbrir: () {},
        ),
      ),
    );
    expect(find.text('Novo no Trato'), findsNothing);
    expect(find.text('4,8'), findsOneWidget);
    expect(find.textContaining('3 serviços concluídos · 5 avaliações'), findsOneWidget);
  });

  testWidgets('PedidoAbertoTela: oferta de exclusividade mostra Novo no Trato e avaliações',
      (t) async {
    Widget tela(OfertaExclusividadeCliente oferta) => PedidoAbertoTela(
          numero: 'AB12',
          dados: DadosDoPedido(
            titulo: 'Trocar chuveiro',
            descricao: 'Chuveiro queimado.',
            faixaMaxCentavos: 30000,
            ofertaExclusividade: oferta,
          ),
          aoSalvar: ({
            required String descricao,
            required int faixaMaxCentavos,
            required String logradouro,
            required String numero,
            required String bairro,
            String? cep,
          }) async =>
              null,
          aoVerOrcamentos: () {},
        );

    await _abrir(
      t,
      tela(const OfertaExclusividadeCliente(
        id: 'e1',
        pedidoId: 'ped1',
        status: 'aguardando_cliente',
        profissionalNome: 'Carlos M.',
        notaPublica: null,
        contagem: ContagemAvaliacoes(2, 5),
      )),
    );
    expect(find.textContaining('Carlos M. · Novo no Trato'), findsOneWidget);
    expect(find.text('2 avaliações'), findsOneWidget);

    await _abrir(
      t,
      tela(const OfertaExclusividadeCliente(
        id: 'e1',
        pedidoId: 'ped1',
        status: 'aguardando_cliente',
        profissionalNome: 'Carlos M.',
        notaPublica: 4.9,
        contagem: ContagemAvaliacoes(5, 5),
      )),
    );
    expect(find.textContaining('Carlos M. · nota 4,9'), findsOneWidget);
    expect(find.text('5 avaliações'), findsOneWidget);
  });

  testWidgets('PerfilPublicoTela: mostra Novo no Trato e traço abaixo do mínimo', (t) async {
    PerfilPublico perfil({required double nota, required int total, ContagemAvaliacoes? c}) =>
        PerfilPublico(
          nome: 'Carlos M.',
          iniciais: 'CM',
          categoria: 'Eletricista',
          verificacao: 'Identidade conferida',
          noTratoDesde: 2026,
          nota: nota,
          totalAvaliacoes: total,
          contagem: c,
          servicosConcluidos: 4,
          sobre: 'Atendo BH.',
          cidade: 'Belo Horizonte/MG',
          fotosPortfolio: 0,
          ultimasAvaliacoes: const [],
        );

    await _abrir(
      t,
      PerfilPublicoTela(
        servico: _ServicoPerfilFake(
          perfil(nota: 0, total: 2, c: const ContagemAvaliacoes(2, 5)),
        ),
      ),
    );
    expect(find.text('Novo no Trato'), findsOneWidget);
    expect(find.textContaining('—'), findsOneWidget);
    expect(find.textContaining('(2)'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await _abrir(
      t,
      PerfilPublicoTela(
        key: const ValueKey('acima'),
        servico: _ServicoPerfilFake(
          perfil(nota: 4.9, total: 5, c: const ContagemAvaliacoes(5, 5)),
        ),
      ),
    );
    expect(find.text('Novo no Trato'), findsNothing);
    expect(find.textContaining('4,9'), findsOneWidget);
    expect(find.textContaining('(5)'), findsOneWidget);
  });
}
