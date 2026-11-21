import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/disputa_profissional/atender_retrabalho_tela.dart';
import 'package:trato/telas/disputa_profissional/disputa.dart';
import 'package:trato/telas/nota_material/enviar_nota_tela.dart';
import 'package:trato/telas/nota_material/nota_material.dart';
import 'package:trato/telas/nota_material/ver_nota_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';
import 'package:trato/telas/profissional_inicio/filtros_pedidos_tela.dart';

Widget _envolver(
  Widget child, {
  Size tamanho = const Size(390, 844),
  double escalaFonte = 1.0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: tamanho,
        textScaler: TextScaler.linear(escalaFonte),
      ),
      child: child,
    ),
  );
}

Future<void> _configurarTela(
  WidgetTester tester, {
  required Size tamanho,
  double escalaFonte = 1.0,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = escalaFonte;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

class _ServicoNotaVazio implements ServicoNotaMaterial {
  @override
  Future<NotaMaterial> carregar(String pedidoId) => throw UnimplementedError();

  @override
  Future<List<NotaMaterial>> carregarTodas(String pedidoId) async => [];

  @override
  Future<void> enviar(EnvioNota envio) async {}
}

class _ServicoCheckOutEspiao implements ServicoCheckOut {
  _ServicoCheckOutEspiao({
    this.aoTirarFoto,
    this.aoLocalizar,
    this.aoFinalizar,
  });

  Future<FotoChegada?> Function()? aoTirarFoto;
  Future<int?> Function()? aoLocalizar;
  Future<ResultadoFim> Function(String codigo, bool semCodigo, String? justificativa)? aoFinalizar;

  int chamadasFoto = 0;
  int chamadasLocalizar = 0;
  int chamadasFinalizar = 0;

  @override
  Future<FotoChegada?> tirarFotoFinal() async {
    chamadasFoto++;
    if (aoTirarFoto != null) return aoTirarFoto!();
    return const FotoChegada(hora: '16h40');
  }

  @override
  Future<int?> localizar() async {
    chamadasLocalizar++;
    if (aoLocalizar != null) return aoLocalizar!();
    return 15;
  }

  @override
  Future<ResultadoFim> finalizar(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) async {
    chamadasFinalizar++;
    if (aoFinalizar != null) return aoFinalizar!(codigo, semCodigo, justificativa);
    return ResultadoFim.concluido;
  }
}

class _ServicoNotaEspiao implements ServicoNotaMaterial {
  _ServicoNotaEspiao({this.aoEnviar});

  Future<void> Function(EnvioNota envio)? aoEnviar;
  int chamadasEnviar = 0;
  final List<EnvioNota> enviados = [];

  @override
  Future<NotaMaterial?> carregar(String pedidoId) async => null;

  @override
  Future<List<NotaMaterial>> carregarTodas(String pedidoId) async => const [];

  @override
  Future<void> enviar(EnvioNota envio) async {
    chamadasEnviar++;
    if (aoEnviar != null) {
      await aoEnviar!(envio);
    }
    enviados.add(envio);
  }
}

class _ServicoDisputaEspiao implements ServicoDisputaProfissional {
  _ServicoDisputaEspiao({
    this.aoCarregarRetrabalho,
    this.aoAgendar,
    this.aoAvancar,
  });

  Future<DadosRetrabalho?> Function(String disputaId)? aoCarregarRetrabalho;
  Future<void> Function(AgendamentoRetrabalho agendamento)? aoAgendar;
  Future<void> Function(String disputaId, String etapa)? aoAvancar;

  int chamadasCarregar = 0;
  int chamadasAgendar = 0;
  int chamadasAvancar = 0;

  @override
  Future<DetalheDisputa?> carregarDisputa(String disputaId) async => null;

  @override
  Future<void> responder(RespostaDisputa resposta) async {}

  @override
  Future<DadosRetrabalho?> carregarRetrabalho(String disputaId) async {
    chamadasCarregar++;
    if (aoCarregarRetrabalho != null) return aoCarregarRetrabalho!(disputaId);
    return null;
  }

  @override
  Future<void> agendarRetrabalho(AgendamentoRetrabalho agendamento) async {
    chamadasAgendar++;
    if (aoAgendar != null) await aoAgendar!(agendamento);
  }

  @override
  Future<void> avancarRetrabalho(String disputaId, String etapa) async {
    chamadasAvancar++;
    if (aoAvancar != null) await aoAvancar!(disputaId, etapa);
  }
}

class _ServicoPerfilEspiao implements ServicoPerfilPublico {
  _ServicoPerfilEspiao({required this.aoCarregar});

  Future<PerfilPublico> Function() aoCarregar;
  int chamadasCarregar = 0;

  @override
  Future<PerfilPublico> carregarPerfil() {
    chamadasCarregar++;
    return aoCarregar();
  }

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => const [];

  @override
  Future<bool> temPerfilProfissional() async => true;
}

const _retrabalhoPadrao = DadosRetrabalho(
  disputaId: 'disp-qa5',
  titulo: 'Vazamento na pia da cozinha',
  descricaoProblema: 'Voltou a pingar embaixo do sifão dois dias depois.',
  prazoAtendimentoDias: 7,
  opcoesHorario: ['Qui, 05/11 · manhã', 'Sex, 06/11 · tarde'],
);

const _perfilVazio = PerfilPublico(
  nome: 'Joao Silva',
  iniciais: 'JS',
  categoria: '',
  verificacao: null,
  noTratoDesde: 2026,
  nota: 0,
  totalAvaliacoes: 0,
  servicosConcluidos: 0,
  sobre: '',
  cidade: '',
  fotosPortfolio: 0,
  ultimasAvaliacoes: [],
);

void main() {
  // ---- Testes pré-existentes preservados ----
  group('QA5 Profissional — FiltrosPedidosAbertosTela', () {
    testWidgets('renderiza em 320x568 e tablet 1.3x sem overflow', (tester) async {
      const cats = [
        CategoriaServico('Elétrica', Icons.bolt, id: 'eletrica'),
        CategoriaServico('Hidráulica', Icons.water_drop, id: 'hidraulica'),
      ];
      await tester.pumpWidget(_envolver(
        const FiltrosPedidosAbertosTela(categorias: cats),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_envolver(
        const FiltrosPedidosAbertosTela(categorias: cats),
        tamanho: const Size(800, 1280),
        escalaFonte: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('QA5 Profissional — VerNotaTela', () {
    testWidgets('lista vazia exibe estado vazio sem quebrar', (tester) async {
      await tester.pumpWidget(_envolver(
        VerNotaTela(servico: _ServicoNotaVazio(), pedidoId: 'ped-1'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma nota enviada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---- QA5-P: CheckOutTela ----
  group('QA5 Profissional — CheckOutTela', () {
    testWidgets('foto vazia, codigo incompleto ou justificativa em branco mantem concluir desabilitado',
        (tester) async {
      final servico = _ServicoCheckOutEspiao(
        aoTirarFoto: () async => null, // profissional cancelou foto
      );
      await tester.pumpWidget(_envolver(
        CheckOutTela(servico: servico, tituloBarra: 'Troca de chuveiro'),
      ));
      await tester.pumpAndSettle();

      BotaoPrimario botao() => tester.widget<BotaoPrimario>(find.byType(BotaoPrimario));
      expect(botao().aoTocar, isNull);

      // Digita 4 digitos sem foto: ainda desabilitado.
      await tester.enterText(find.byType(TextField), '7310');
      await tester.pump();
      expect(botao().aoTocar, isNull);

      // Tenta tirar foto e cancela (retorna null): continua desabilitado.
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      expect(botao().aoTocar, isNull);

      // Agora retorna foto valida, mas codigo tem letras/3 digitos -> desabilitado.
      servico.aoTirarFoto = () async => const FotoChegada(hora: '17h00');
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12a');
      await tester.pump();
      expect(botao().aoTocar, isNull);

      // Alterna para sem codigo: falta localizacao e justificativa.
      await tester.tap(find.text('Cliente sem bateria ou sinal?'));
      await tester.pumpAndSettle();
      expect(botao().aoTocar, isNull);

      await tester.enterText(find.byType(TextField), '     ');
      await tester.pump();
      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();
      // Localizacao ok + foto ok, mas justificativa so espacos -> desabilitado.
      expect(botao().aoTocar, isNull);

      await tester.enterText(find.byType(TextField), 'Cliente ficou sem bateria no fim');
      await tester.pump();
      expect(botao().aoTocar, isNotNull);
    });

    testWidgets('duplo toque rapido em Concluir servico dispara apenas uma chamada', (tester) async {
      final completer = Completer<ResultadoFim>();
      final servico = _ServicoCheckOutEspiao(
        aoFinalizar: (c, s, j) => completer.future,
      );
      await tester.pumpWidget(_envolver(
        CheckOutTela(servico: servico, tituloBarra: 'Troca de chuveiro', remoto: true),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '7310');
      await tester.pump();

      // Dois toques rapidos no mesmo frame antes do rebuild + um toque enquanto carregando.
      final btn = find.byType(BotaoPrimario);
      await tester.tap(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.tap(btn, warnIfMissed: false);
      await tester.pump();

      expect(servico.chamadasFinalizar, 1);

      completer.complete(ResultadoFim.concluido);
      await tester.pumpAndSettle();
    });

    testWidgets('timeout ou erro nao-ErroTrato ao concluir nao vaza excecao nem trava botao',
        (tester) async {
      final servico = _ServicoCheckOutEspiao(
        aoFinalizar: (c, s, j) async => throw TimeoutException('tempo esgotado'),
      );
      await tester.pumpWidget(_envolver(
        CheckOutTela(servico: servico, tituloBarra: 'Troca de chuveiro', remoto: true),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '7310');
      await tester.pump();

      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final btn = tester.widget<BotaoPrimario>(find.byType(BotaoPrimario));
      expect(btn.carregando, isFalse);
      expect(btn.aoTocar, isNotNull);
    });

    testWidgets('erro nao-ErroTrato ao tirar foto ou localizar nao vaza excecao', (tester) async {
      final servico = _ServicoCheckOutEspiao(
        aoTirarFoto: () async => throw Exception('camera indisponivel'),
        aoLocalizar: () async => throw TimeoutException('gps travou'),
      );
      await tester.pumpWidget(_envolver(
        CheckOutTela(servico: servico, tituloBarra: 'Troca de chuveiro'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cliente sem bateria ou sinal?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErroTrato, codigo incorreto e modo offline sao exibidos e permitem nova tentativa',
        (tester) async {
      var tentativa = 0;
      var concluiu = false;
      final servico = _ServicoCheckOutEspiao(
        aoFinalizar: (c, s, j) async {
          tentativa++;
          if (tentativa == 1) {
            throw const ErroTrato(TipoErro.semInternet, 'Sem conexão com o servidor.');
          }
          if (tentativa == 2) return ResultadoFim.codigoIncorreto;
          if (tentativa == 3) return ResultadoFim.guardadoOffline;
          return ResultadoFim.concluido;
        },
      );
      await tester.pumpWidget(_envolver(
        CheckOutTela(
          servico: servico,
          tituloBarra: 'Instalação de ventilador',
          remoto: true,
          aoConcluir: () => concluiu = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '7310');
      await tester.pump();

      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);

      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.textContaining('Código incorreto'), findsOneWidget);

      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.textContaining('Guardamos a conclusão'), findsOneWidget);
      expect(concluiu, isFalse);

      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(concluiu, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza em 320x568 e tablet 800x1280 com fonte 1.3x sem overflow', (tester) async {
      for (final cfg in [
        (const Size(320, 568), 1.0),
        (const Size(800, 1280), 1.3),
      ]) {
        await _configurarTela(tester, tamanho: cfg.$1, escalaFonte: cfg.$2);
        final servico = _ServicoCheckOutEspiao();
        await tester.pumpWidget(MaterialApp(
          home: CheckOutTela(
            key: ValueKey(cfg),
            servico: servico,
            tituloBarra: 'Serviço muito longo com descrição extensa no topo',
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tirar foto'));
        await tester.pumpAndSettle();
        final linkSemCodigo = find.text('Cliente sem bateria ou sinal?');
        await tester.ensureVisible(linkSemCodigo);
        await tester.tap(linkSemCodigo);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ---- QA5-P: EnviarNotaTela ----
  group('QA5 Profissional — EnviarNotaTela', () {
    testWidgets('rejeita descricao vazia, quantidade <= 0, valor 0, negativo, texto e 11 digitos',
        (tester) async {
      final servico = _ServicoNotaEspiao();
      await tester.pumpWidget(_envolver(
        EnviarNotaTela(
          servico: servico,
          pedidoId: 'ped-nota',
          tituloPedido: 'Troca de registro',
          aoCapturarFoto: () async => 'foto-nota-1',
        ),
      ));
      await tester.pumpAndSettle();

      final campos = find.byType(TextField);
      expect(campos, findsNWidgets(3));
      final btnAdd = find.text('Adicionar item');

      // 1) Descricao vazia
      await tester.ensureVisible(btnAdd);
      await tester.tap(btnAdd);
      await tester.pump();
      expect(find.textContaining('Descrição vazia'), findsOneWidget);

      // 2) Quantidade 0, negativa e texto
      await tester.enterText(campos.at(0), 'Registro 3/4');
      for (final qtdInvalida in ['0', '-2', 'abc']) {
        await tester.enterText(campos.at(1), qtdInvalida);
        await tester.enterText(campos.at(2), '25,00');
        await tester.ensureVisible(btnAdd);
        await tester.tap(btnAdd);
        await tester.pump();
        expect(find.textContaining('Quantidade inválida'), findsOneWidget);
      }

      // 3) Valor 0, negativo, texto e valor com 11 digitos
      await tester.enterText(campos.at(1), '1');
      for (final valorInvalido in ['0', '0,00', '-15,50', 'abc', '99999999999']) {
        await tester.enterText(campos.at(2), valorInvalido);
        await tester.ensureVisible(btnAdd);
        await tester.tap(btnAdd);
        await tester.pump();
        expect(find.textContaining('Valor não informado'), findsOneWidget);
      }

      // Nenhum item foi adicionado e envio segue bloqueado
      expect(find.textContaining('Nenhum item ainda'), findsOneWidget);
      final btnEnviar = tester.widget<BotaoPrimario>(find.byType(BotaoPrimario));
      expect(btnEnviar.aoTocar, isNull);
    });

    testWidgets('quantidade e valor gigantes nao causam overflow de inteiro nem soma negativa',
        (tester) async {
      final servico = _ServicoNotaEspiao();
      await tester.pumpWidget(_envolver(
        EnviarNotaTela(
          servico: servico,
          pedidoId: 'ped-nota-gigante',
          tituloPedido: 'Obra elétrica',
          aoCapturarFoto: () async => 'foto-nota-1',
        ),
      ));
      await tester.pumpAndSettle();

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Cabo industrial');
      await tester.enterText(campos.at(1), '999999999');
      await tester.enterText(campos.at(2), '100000000');
      await tester.ensureVisible(find.text('Adicionar item'));
      await tester.tap(find.text('Adicionar item'));
      await tester.pump();

      // Nao pode aceitar multiplicacao que estoura int64 e exibe valor negativo (-R$).
      expect(find.textContaining('-R\$'), findsNothing);
      expect(find.textContaining('Nenhum item ainda'), findsOneWidget);
    });

    testWidgets('duplo toque rapido em Enviar nota ao cliente dispara apenas uma chamada',
        (tester) async {
      final completer = Completer<void>();
      final servico = _ServicoNotaEspiao(aoEnviar: (_) => completer.future);

      await tester.pumpWidget(_envolver(
        EnviarNotaTela(
          servico: servico,
          pedidoId: 'ped-nota-dup',
          tituloPedido: 'Troca de tomadas',
          aoCapturarFoto: () async => 'foto-1',
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foto da nota'));
      await tester.pumpAndSettle();

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Tomada 20A');
      await tester.enterText(campos.at(1), '2');
      await tester.enterText(campos.at(2), '18,50');
      await tester.ensureVisible(find.text('Adicionar item'));
      await tester.tap(find.text('Adicionar item'));
      await tester.pumpAndSettle();

      final btn = find.byType(BotaoPrimario);
      await tester.tap(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.tap(btn, warnIfMissed: false);
      await tester.pump();

      expect(servico.chamadasEnviar, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Nota enviada ao cliente.'), findsOneWidget);
    });

    testWidgets('timeout ou ErroTrato ao enviar mostra erro e destrava botao para nova tentativa',
        (tester) async {
      var tentativa = 0;
      final servico = _ServicoNotaEspiao(
        aoEnviar: (_) async {
          tentativa++;
          if (tentativa == 1) throw TimeoutException('rede lenta');
          if (tentativa == 2) {
            throw const ErroTrato(TipoErro.recusado, 'Serviço ainda não iniciado.');
          }
        },
      );

      await tester.pumpWidget(_envolver(
        EnviarNotaTela(
          servico: servico,
          pedidoId: 'ped-nota-err',
          tituloPedido: 'Troca de tomadas',
          aoCapturarFoto: () async => 'foto-1',
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foto da nota'));
      await tester.pumpAndSettle();
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Fita isolante');
      await tester.enterText(campos.at(2), '9,90');
      await tester.ensureVisible(find.text('Adicionar item'));
      await tester.tap(find.text('Adicionar item'));
      await tester.pumpAndSettle();

      // 1) TimeoutException -> erro de conexao e botao destravado
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Confira sua conexão'), findsOneWidget);
      expect(tester.widget<BotaoPrimario>(find.byType(BotaoPrimario)).carregando, isFalse);

      // 2) ErroTrato -> mensagem do servidor
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.text('Serviço ainda não iniciado.'), findsOneWidget);

      // 3) Sucesso no retry
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.text('Nota enviada ao cliente.'), findsOneWidget);
    });

    testWidgets('erro ao capturar foto da nota nao vaza excecao nao tratada', (tester) async {
      final servico = _ServicoNotaEspiao();
      await tester.pumpWidget(_envolver(
        EnviarNotaTela(
          servico: servico,
          pedidoId: 'ped-nota-foto-err',
          tituloPedido: 'Troca de tomadas',
          aoCapturarFoto: () async => throw TimeoutException('falha ao subir foto'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foto da nota'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza em 320x568 e tablet 1.3x sem overflow com item normal', (tester) async {
      for (final cfg in [
        (const Size(320, 568), 1.0),
        (const Size(800, 1280), 1.3),
      ]) {
        await _configurarTela(tester, tamanho: cfg.$1, escalaFonte: cfg.$2);
        final servico = _ServicoNotaEspiao();
        await tester.pumpWidget(MaterialApp(
          home: EnviarNotaTela(
            key: ValueKey(cfg),
            servico: servico,
            pedidoId: 'ped-resp',
            tituloPedido: 'Troca de tomadas',
            aoCapturarFoto: () async => 'foto-1',
          ),
        ));
        await tester.pumpAndSettle();
        final campos = find.byType(TextField);
        await tester.enterText(campos.at(0), 'Tomada 20A');
        await tester.enterText(campos.at(1), '2');
        await tester.enterText(campos.at(2), '24,50');
        await tester.ensureVisible(find.text('Adicionar item'));
        await tester.tap(find.text('Adicionar item'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('texto hostil longo em 320x568 e tablet 1.3x sem overflow', (tester) async {
      for (final cfg in [
        (const Size(320, 568), 1.0),
        (const Size(800, 1280), 1.3),
      ]) {
        await _configurarTela(tester, tamanho: cfg.$1, escalaFonte: cfg.$2);
        final servico = _ServicoNotaEspiao();
        await tester.pumpWidget(MaterialApp(
          home: EnviarNotaTela(
            key: ValueKey(cfg),
            servico: servico,
            pedidoId: 'ped-hostil',
            tituloPedido: 'PedidoComTituloExtremamenteLongoSemEspacosParaTestarQuebraDeLinha1234567890',
            aoCapturarFoto: () async => 'foto-1',
          ),
        ));
        await tester.pumpAndSettle();

        final campos = find.byType(TextField);
        await tester.enterText(
          campos.at(0),
          'MaterialSuperExtensoSemQuebraDePalavraComCaracteresEspeciais<script>alert(1)</script>999999',
        );
        await tester.enterText(campos.at(1), '10');
        await tester.enterText(campos.at(2), '1234,56');
        await tester.ensureVisible(find.text('Adicionar item'));
        await tester.tap(find.text('Adicionar item'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ---- QA5-P: AtenderRetrabalhoTela ----
  group('QA5 Profissional — AtenderRetrabalhoTela', () {
    testWidgets('duplo toque rapido em Confirmar horario dispara apenas uma chamada', (tester) async {
      final completer = Completer<void>();
      final servico = _ServicoDisputaEspiao(
        aoCarregarRetrabalho: (_) async => _retrabalhoPadrao,
        aoAgendar: (_) => completer.future,
      );
      await tester.pumpWidget(_envolver(
        AtenderRetrabalhoTela(servico: servico, disputaId: 'disp-qa5'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Qui, 05/11 · manhã'));
      await tester.pump();

      final btn = find.byType(BotaoPrimario);
      await tester.tap(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.tap(btn, warnIfMissed: false);
      await tester.pump();

      expect(servico.chamadasAgendar, 1);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('erro de rede e timeout ao carregar e ao agendar permite tentar de novo',
        (tester) async {
      var carga = 0;
      var envio = 0;
      final servico = _ServicoDisputaEspiao(
        aoCarregarRetrabalho: (_) async {
          carga++;
          if (carga == 1) throw TimeoutException('timeout ao carregar');
          return _retrabalhoPadrao;
        },
        aoAgendar: (_) async {
          envio++;
          if (envio == 1) throw TimeoutException('timeout ao salvar');
        },
      );

      await tester.pumpWidget(_envolver(
        AtenderRetrabalhoTela(servico: servico, disputaId: 'disp-qa5'),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Não foi possível carregar'), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Quando você volta?'), findsOneWidget);

      await tester.tap(find.text('Qui, 05/11 · manhã'));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Não foi possível salvar. Tente de novo.'), findsOneWidget);
      expect(tester.widget<BotaoPrimario>(find.byType(BotaoPrimario)).carregando, isFalse);

      // Nova tentativa funciona e avanca estado para aceito
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.text('Começar o retrabalho'), findsOneWidget);
    });

    testWidgets('payload nulo ou aberto sem opcoesHorario exibe estado vazio', (tester) async {
      await tester.pumpWidget(_envolver(
        AtenderRetrabalhoTela(
          servico: _ServicoDisputaEspiao(aoCarregarRetrabalho: (_) async => null),
          disputaId: 'disp-null',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sem retrabalho para agendar'), findsOneWidget);

      await tester.pumpWidget(_envolver(
        AtenderRetrabalhoTela(
          servico: _ServicoDisputaEspiao(
            aoCarregarRetrabalho: (_) async => const DadosRetrabalho(
              disputaId: 'disp-sem-hora',
              titulo: 'Vazamento',
              descricaoProblema: 'Pingando',
              prazoAtendimentoDias: 3,
              opcoesHorario: [],
            ),
          ),
          disputaId: 'disp-sem-hora',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sem retrabalho para agendar'), findsOneWidget);
    });

    testWidgets('retrabalho ja aceito sem opcoesHorario ainda mostra botao Comecar o retrabalho',
        (tester) async {
      final servico = _ServicoDisputaEspiao(
        aoCarregarRetrabalho: (_) async => const DadosRetrabalho(
          disputaId: 'disp-aceito',
          estado: 'aceito',
          titulo: 'Vazamento na pia',
          descricaoProblema: 'Refazer vedação do sifão.',
          prazoAtendimentoDias: 5,
          opcoesHorario: [],
        ),
      );
      await tester.pumpWidget(_envolver(
        AtenderRetrabalhoTela(servico: servico, disputaId: 'disp-aceito'),
      ));
      await tester.pumpAndSettle();

      // Ja foi agendado (estado == aceito): nao depende de opcoesHorario para iniciar o retrabalho.
      expect(find.text('Começar o retrabalho'), findsOneWidget);
      expect(find.text('Sem retrabalho para agendar'), findsNothing);
    });

    testWidgets('payload hostil longo em 320x568 e tablet 1.3x sem overflow', (tester) async {
      const hostil = DadosRetrabalho(
        disputaId: 'disp-hostil',
        titulo: 'TituloExtremamenteLongoSemEspacosParaForcarQuebraDeLinhaEmTelasPequenas1234567890',
        descricaoProblema:
            'Descrição muito longa com texto repetido e payload hostil <img src=x onerror=1> '
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        prazoAtendimentoDias: 0,
        opcoesHorario: [
          'Quinta-feira 05/11 · período da manhã com observação bem longa para testar pilula',
          'Sexta-feira 06/11 · tarde',
        ],
      );
      for (final cfg in [
        (const Size(320, 568), 1.0),
        (const Size(800, 1280), 1.3),
      ]) {
        await _configurarTela(tester, tamanho: cfg.$1, escalaFonte: cfg.$2);
        await tester.pumpWidget(MaterialApp(
          home: AtenderRetrabalhoTela(
            servico: _ServicoDisputaEspiao(aoCarregarRetrabalho: (_) async => hostil),
            disputaId: 'disp-hostil',
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ---- QA5-P: PerfilPublicoTela ----
  group('QA5 Profissional — PerfilPublicoTela', () {
    setUp(PerfilPublicoTela.limparFotoSessao);

    testWidgets('perfil vazio exibe placeholders sem quebrar', (tester) async {
      await tester.pumpWidget(_envolver(
        PerfilPublicoTela(
          servico: _ServicoPerfilEspiao(aoCarregar: () async => _perfilVazio),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('— (0)'), findsOneWidget);
      expect(find.text('Você ainda não escreveu sobre você.'), findsOneWidget);
      expect(find.text('Sem fotos de trabalhos ainda.'), findsOneWidget);
      expect(find.text('Você ainda não recebeu avaliações.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erro de rede ou timeout ao carregar perfil exibe erro e permite tentar de novo',
        (tester) async {
      var tentativa = 0;
      final servico = _ServicoPerfilEspiao(
        aoCarregar: () async {
          tentativa++;
          if (tentativa == 1) throw TimeoutException('rede indisponivel');
          return _perfilVazio;
        },
      );
      await tester.pumpWidget(_envolver(PerfilPublicoTela(servico: servico)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Não foi possível carregar'), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Joao Silva'), findsOneWidget);
    });

    testWidgets('erro de rede ao atualizar foto de perfil nao vaza excecao nao tratada',
        (tester) async {
      await tester.pumpWidget(_envolver(
        PerfilPublicoTela(
          servico: _ServicoPerfilEspiao(aoCarregar: () async => _perfilVazio),
          aoCapturarFotoPerfil: () async => throw TimeoutException('falha upload avatar'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('JS'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('texto hostil longo em 320x568 e tablet 800x1280 com fonte 1.3x sem overflow',
        (tester) async {
      const perfilHostil = PerfilPublico(
        nome: 'Carlos Alberto da Silva Pereira Fernandes de Souza Junior Muito Longo',
        iniciais: 'CA',
        categoria: 'Eletricista Residencial Industrial Predial e Automação',
        verificacao: 'Identidade conferida e documentos verificados pela equipe completa do Trato',
        noTratoDesde: 2026,
        nota: 4.95,
        totalAvaliacoes: 9999,
        servicosConcluidos: 12345,
        sobre:
            'Sobre muito longo sem pausas aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa '
            '<script>alert(1)</script> com vários detalhes técnicos.',
        cidade: 'São José dos Campos dos Goytacazes',
        fotosPortfolio: 3,
        ultimasAvaliacoes: [
          Avaliacao(
            cliente: 'Mariana Souza Oliveira Pereira da Silva',
            servico: 'Instalação elétrica completa do quadro trifásico residencial',
            nota: 5,
            comentario: 'Excelente trabalho, muito detalhista e organizado em cada etapa.',
            detalhes: 'Pontualidade 5 · Qualidade 5 · Limpeza 5',
          ),
        ],
      );

      for (final cfg in [
        (const Size(320, 568), 1.0),
        (const Size(800, 1280), 1.3),
      ]) {
        await _configurarTela(tester, tamanho: cfg.$1, escalaFonte: cfg.$2);
        await tester.pumpWidget(MaterialApp(
          home: PerfilPublicoTela(
            servico: _ServicoPerfilEspiao(aoCarregar: () async => perfilHostil),
            aoVerAvaliacoes: () {},
            aoEditarCadastro: () {},
            aoUsarComoCliente: () {},
            aoAbrirConfiguracoes: () {},
            aoAbrirVerificacao: () {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('portfolio com muitas fotos em 320x568 nao causa RenderFlex overflow',
        (tester) async {
      await _configurarTela(tester, tamanho: const Size(320, 568), escalaFonte: 1.0);
      const perfilMuitasFotos = PerfilPublico(
        nome: 'Carlos',
        iniciais: 'CA',
        categoria: 'Eletricista',
        verificacao: 'Identidade conferida',
        noTratoDesde: 2026,
        nota: 4.8,
        totalAvaliacoes: 10,
        servicosConcluidos: 12,
        sobre: 'Experiência.',
        cidade: 'Belo Horizonte',
        fotosPortfolio: 12,
        ultimasAvaliacoes: [],
      );
      await tester.pumpWidget(MaterialApp(
        home: PerfilPublicoTela(
          servico: _ServicoPerfilEspiao(aoCarregar: () async => perfilMuitasFotos),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
