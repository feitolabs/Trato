import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

class _ServicoCadastroF57Fake implements ServicoCadastroProfissional {
  _ServicoCadastroF57Fake({
    this.atual,
    this.erroAoSalvar,
  });

  final DadosCadastroProfissional? atual;
  final Object? erroAoSalvar;
  final List<DadosCadastroProfissional> salvos = [];

  @override
  Future<OpcoesCadastro> carregarOpcoes() async => opcoesCadastroPadrao;

  @override
  Future<DadosCadastroProfissional?> carregarAtual() async => atual;

  @override
  Future<void> salvar(DadosCadastroProfissional dados) async {
    if (erroAoSalvar != null) throw erroAoSalvar!;
    salvos.add(dados);
  }
}

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  ThemeData? tema,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? TemaTrato.claro,
      home: tela,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  group('F57 — CadastroProfissionalTela (4 passos no cadastro inicial)', () {
    testWidgets('valida passo 1, percorre os 4 passos com Voltar e salva corretamente',
        (tester) async {
      final servico = _ServicoCadastroF57Fake();
      var concluiu = false;

      await _abrir(
        tester,
        CadastroProfissionalTela(
          servico: servico,
          aoAdicionarFoto: () async => 'foto-portfolio-1',
          aoConcluir: () => concluiu = true,
        ),
      );

      // Passo 1: barra 1 de 4 + validação inline antes de avançar.
      expect(find.text('1 de 4'), findsOneWidget);
      expect(find.text('Quem é você'), findsOneWidget);
      await _tocar(tester, find.text('Continuar'));
      expect(find.text('Informe seu nome completo (mínimo 3 letras).'), findsOneWidget);
      expect(find.text('1 de 4'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Carlos Almeida');
      await tester.enterText(find.byType(TextField).at(1), '10 anos em elétrica residencial.');
      await _tocar(tester, find.text('Continuar'));

      // Passo 2: categorias + validação antes de avançar + Voltar.
      expect(find.text('2 de 4'), findsOneWidget);
      expect(find.text('O que você faz'), findsOneWidget);
      await _tocar(tester, find.text('Continuar'));
      expect(find.text('Escolha pelo menos uma categoria.'), findsOneWidget);

      await _tocar(tester, find.text('Eletricista'));
      await _tocar(tester, find.text('Voltar'));
      expect(find.text('1 de 4'), findsOneWidget);
      await _tocar(tester, find.text('Continuar'));
      expect(find.text('2 de 4'), findsOneWidget);
      await _tocar(tester, find.text('Continuar'));

      // Passo 3: cidade, raio e disponibilidade.
      expect(find.text('3 de 4'), findsOneWidget);
      expect(find.text('Onde e quando atende'), findsOneWidget);
      await _tocar(tester, find.text('Continuar'));
      expect(find.text('Escolha a cidade onde você atende.'), findsOneWidget);
      expect(find.text('Escolha pelo menos um dia.'), findsOneWidget);
      expect(find.text('Escolha pelo menos um período.'), findsOneWidget);

      await _tocar(tester, find.text('Belo Horizonte'));
      await _tocar(tester, find.text('20 km'));
      await _tocar(tester, find.text('Seg'));
      await _tocar(tester, find.text('Manhã'));
      await _tocar(tester, find.text('Continuar'));

      // Passo 4: portfólio + adicionar foto + Salvar cadastro.
      expect(find.text('4 de 4'), findsOneWidget);
      expect(find.text('Portfólio (opcional)'), findsOneWidget);
      expect(find.text('Pular por enquanto'), findsOneWidget);

      await _tocar(tester, find.text('+ Adicionar foto'));
      expect(find.text('Foto 1'), findsOneWidget);
      expect(find.text('Pular por enquanto'), findsNothing);

      await _tocar(tester, find.text('Salvar cadastro'));

      expect(concluiu, isTrue);
      expect(servico.salvos, hasLength(1));
      final salvo = servico.salvos.single;
      expect(salvo.nome, 'Carlos Almeida');
      expect(salvo.sobre, '10 anos em elétrica residencial.');
      expect(salvo.categorias, {'Eletricista'});
      expect(salvo.cidade, 'Belo Horizonte');
      expect(salvo.raioKm, 20);
      expect(salvo.dias, {'Seg'});
      expect(salvo.periodos, {'Manhã'});
      expect(salvo.portfolio, ['foto-portfolio-1']);
      expect(salvo.atendePresencial, isTrue);
      expect(salvo.atendeRemoto, isFalse);
    });

    testWidgets('passo 4 permite Pular por enquanto e salva sem fotos', (tester) async {
      final servico = _ServicoCadastroF57Fake();
      var concluiu = false;

      await _abrir(
        tester,
        CadastroProfissionalTela(
          servico: servico,
          aoConcluir: () => concluiu = true,
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'Maria Silva');
      await _tocar(tester, find.text('Continuar'));
      await _tocar(tester, find.text('Pintor'));
      await _tocar(tester, find.text('Continuar'));
      await _tocar(tester, find.text('Divinopolis'));
      await _tocar(tester, find.text('Ter'));
      await _tocar(tester, find.text('Tarde'));
      await _tocar(tester, find.text('Continuar'));

      await _tocar(tester, find.text('Pular por enquanto'));

      expect(concluiu, isTrue);
      expect(servico.salvos, hasLength(1));
      expect(servico.salvos.single.portfolio, isEmpty);
    });

    testWidgets('erro do backend ao salvar exibe aviso sem perder os dados', (tester) async {
      final servico = _ServicoCadastroF57Fake(
        erroAoSalvar: const ErroTrato(
          TipoErro.recusado,
          'Ainda não atendemos essa cidade.',
        ),
      );

      await _abrir(tester, CadastroProfissionalTela(servico: servico));
      await tester.enterText(find.byType(TextField).first, 'Carlos Almeida');
      await _tocar(tester, find.text('Continuar'));
      await _tocar(tester, find.text('Eletricista'));
      await _tocar(tester, find.text('Continuar'));
      await _tocar(tester, find.text('Belo Horizonte'));
      await _tocar(tester, find.text('Seg'));
      await _tocar(tester, find.text('Manhã'));
      await _tocar(tester, find.text('Continuar'));
      await _tocar(tester, find.text('Salvar cadastro'));

      expect(find.text('Ainda não atendemos essa cidade.'), findsOneWidget);
    });
  });

  group('F57 — CadastroProfissionalTela (modo edição por seções)', () {
    const cadastroExistente = DadosCadastroProfissional(
      nome: 'Carlos Almeida',
      sobre: 'Instalações elétricas',
      categorias: {'Eletricista'},
      cidade: 'Belo Horizonte',
      raioKm: 10,
      dias: {'Seg', 'Qua'},
      periodos: {'Manhã'},
      portfolio: ['foto-1'],
    );

    testWidgets('abre em modo edição com 4 seções quando já há cadastro carregado',
        (tester) async {
      final servico = _ServicoCadastroF57Fake(atual: cadastroExistente);
      var concluiu = false;

      await _abrir(
        tester,
        CadastroProfissionalTela(
          servico: servico,
          aoConcluir: () => concluiu = true,
        ),
      );

      // Não mostra barra de passos; mostra as 4 seções tocáveis com resumos.
      expect(find.text('1 de 4'), findsNothing);
      expect(find.text('Dados básicos'), findsOneWidget);
      expect(find.text('Categorias'), findsOneWidget);
      expect(find.text('Área e horários'), findsOneWidget);
      expect(find.text('Portfólio'), findsOneWidget);
      expect(find.text('1 foto adicionada'), findsOneWidget);

      // Edita apenas a seção de Área e horários sem passar pelos outros passos.
      await _tocar(tester, find.text('Área e horários'));
      expect(find.text('Até onde você vai'), findsOneWidget);
      await _tocar(tester, find.text('30 km'));
      await _tocar(tester, find.text('Salvar alterações'));

      expect(concluiu, isTrue);
      expect(servico.salvos, hasLength(1));
      final salvo = servico.salvos.single;
      expect(salvo.nome, 'Carlos Almeida');
      expect(salvo.categorias, {'Eletricista'});
      expect(salvo.raioKm, 30);
      expect(salvo.portfolio, ['foto-1']);
    });

    testWidgets('respeita categorias travadas e renderiza sem erro no tema escuro',
        (tester) async {
      final servico = _ServicoCadastroF57Fake(
        atual: cadastroExistente.comCategoriasTravadas(true),
      );

      await _abrir(
        tester,
        CadastroProfissionalTela(servico: servico, edicao: true),
        tema: TemaTrato.escuro,
      );

      await _tocar(tester, find.text('Categorias'));
      expect(find.text('Eletricista'), findsOneWidget);
      expect(find.text('Encanador'), findsNothing);
      expect(
        find.textContaining('Categorias vinculadas à sua verificação'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
