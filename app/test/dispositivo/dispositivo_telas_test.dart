import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dispositivo/captura_foto.dart';
import 'package:trato/dispositivo/explicacao_permissao.dart';
import 'package:trato/dispositivo/permissao.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

/// Serviço de check-in controlável: a distância, a falha e o resultado vêm do teste.
class _CheckInControlado implements ServicoCheckIn {
  _CheckInControlado({this.distancia = 20, this.erroLocalizar, this.resultado});

  final int? distancia;
  final ErroTrato? erroLocalizar;
  final ResultadoInicio? resultado;
  int fotos = 0;

  @override
  Future<FotoChegada?> tirarFoto() async {
    fotos++;
    return const FotoChegada(hora: '14h06');
  }

  @override
  Future<int?> localizar() async {
    if (erroLocalizar != null) throw erroLocalizar!;
    return distancia;
  }

  @override
  Future<void> enviarMensagemRapida(String mensagem) async {}

  @override
  Future<void> avisarClienteAusente() async {}

  @override
  Future<ResultadoInicio> iniciarServico(String codigo) async =>
      resultado ?? ResultadoInicio.iniciado;
}

/// Botão que dispara [acao] com o contexto da tela.
Widget _botao(Future<void> Function(BuildContext) acao) => Scaffold(
      body: Builder(
        builder: (context) => TextButton(onPressed: () => acao(context), child: const Text('usar')),
      ),
    );

void main() {
  group('garantirPermissao', () {
    Future<List<bool>> abrirBotao(WidgetTester tester, ServicoPermissaoFake fake) async {
      final resultados = <bool>[];
      await _abrir(
        tester,
        _botao(
          (context) async => resultados.add(
            await garantirPermissao(
              context,
              fake,
              TipoPermissao.camera,
              TextoPermissao.cameraCheckIn,
            ),
          ),
        ),
      );
      return resultados;
    }

    testWidgets('concedida: segue sem mostrar tela nenhuma', (tester) async {
      final fake = ServicoPermissaoFake();
      final r = await abrirBotao(tester, fake);

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();

      expect(r, [true]);
      expect(fake.pedidos, 0);
      expect(find.text('Para que serve'), findsNothing);
    });

    testWidgets('negada: explica finalidade e retenção antes de pedir ao sistema', (tester) async {
      final fake = ServicoPermissaoFake(
        atual: EstadoPermissao.negada,
        aposPedir: EstadoPermissao.concedida,
      );
      final r = await abrirBotao(tester, fake);

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();

      expect(find.text('Para que serve'), findsOneWidget);
      expect(find.text('Por quanto tempo guardamos'), findsOneWidget);
      expect(find.textContaining('chegou ao local'), findsOneWidget);
      expect(fake.pedidos, 0, reason: 'o sistema só pergunta depois da explicação');

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(fake.pedidos, 1);
      expect(r, [true]);
    });

    testWidgets('negada: "Agora não" nunca chega ao pedido do sistema', (tester) async {
      final fake = ServicoPermissaoFake(atual: EstadoPermissao.negada);
      final r = await abrirBotao(tester, fake);

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agora não'));
      await tester.pumpAndSettle();

      expect(fake.pedidos, 0);
      expect(r, [false]);
    });

    testWidgets('negada de novo no pedido do sistema: não segue', (tester) async {
      final fake = ServicoPermissaoFake(atual: EstadoPermissao.negada);
      final r = await abrirBotao(tester, fake);

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(fake.pedidos, 1);
      expect(r, [false]);
    });

    testWidgets('negada para sempre: leva às configurações, sem perguntar', (tester) async {
      final fake = ServicoPermissaoFake(atual: EstadoPermissao.negadaParaSempre);
      final r = await abrirBotao(tester, fake);

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();

      expect(find.text('Permissão desligada'), findsOneWidget);
      await tester.tap(find.text('Abrir configurações'));
      await tester.pumpAndSettle();

      expect(fake.pedidos, 0);
      expect(fake.aberturasDeConfiguracao, 1);
      expect(r, [false]);
    });
  });

  group('Check-in com permissões', () {
    testWidgets('câmera negada para sempre: não tira foto e mostra o caminho das configurações',
        (tester) async {
      final fake = ServicoPermissaoFake(atual: EstadoPermissao.negadaParaSempre);
      final servico = _CheckInControlado();
      await _abrir(
        tester,
        CheckInTela(servico: servico, tituloBarra: 'Mariana', permissao: fake),
      );

      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Permissão desligada'), findsOneWidget);
      expect(servico.fotos, 0);
    });

    testWidgets('localização concedida mostra a distância', (tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInControlado(distancia: 35),
          tituloBarra: 'Mariana',
          permissao: ServicoPermissaoFake(),
        ),
      );

      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();

      expect(find.text('A 35 m do endereço'), findsOneWidget);
      expect(find.textContaining('longe do endereço'), findsNothing);
    });

    testWidgets('sem GPS: mostra o motivo e não marca o passo como feito', (tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInControlado(
            erroLocalizar: const ErroTrato(
              TipoErro.recusado,
              'O GPS está desligado. Ligue a localização do aparelho.',
            ),
          ),
          tituloBarra: 'Mariana',
          permissao: ServicoPermissaoFake(),
        ),
      );

      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GPS está desligado'), findsOneWidget);
      expect(find.text('Feito'), findsNothing);
    });

    testWidgets('longe do endereço: avisa, mas não bloqueia (quem decide é o backend)',
        (tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInControlado(distancia: 5200),
          tituloBarra: 'Mariana',
          permissao: ServicoPermissaoFake(),
        ),
      );

      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();

      expect(find.text('A 5200 m do endereço'), findsOneWidget);
      expect(find.textContaining('longe do endereço'), findsOneWidget);
    });

    testWidgets('offline: avisa que ficou guardado e NÃO inicia o serviço', (tester) async {
      var iniciou = false;
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInControlado(resultado: ResultadoInicio.guardadoOffline),
          tituloBarra: 'Mariana',
          permissao: ServicoPermissaoFake(),
          aoIniciar: () => iniciou = true,
        ),
      );
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '4821');
      await tester.pump();

      await tester.tap(find.text('Iniciar serviço'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sem internet'), findsOneWidget);
      expect(iniciou, isFalse);
    });
  });

  group('Check-out', () {
    testWidgets('offline: guarda e avisa, sem concluir', (tester) async {
      var concluiu = false;
      await _abrir(
        tester,
        CheckOutTela(
          servico: ServicoCheckOutFake(offline: true),
          tituloBarra: 'Mariana',
          permissao: ServicoPermissaoFake(),
          aoConcluir: () => concluiu = true,
        ),
      );
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '7310');
      await tester.pump();

      await tester.tap(find.text('Concluir serviço'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sem internet'), findsOneWidget);
      expect(concluiu, isFalse);
    });

    testWidgets('código errado mostra erro; certo conclui', (tester) async {
      var concluiu = false;
      await _abrir(
        tester,
        CheckOutTela(
          servico: ServicoCheckOutFake(),
          tituloBarra: 'Mariana',
          aoConcluir: () => concluiu = true,
        ),
      );
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0000');
      await tester.pump();
      await tester.tap(find.text('Concluir serviço'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Código incorreto'), findsOneWidget);
      expect(concluiu, isFalse);

      await tester.enterText(find.byType(TextField), '7310');
      await tester.pump();
      await tester.tap(find.text('Concluir serviço'));
      await tester.pumpAndSettle();
      expect(concluiu, isTrue);
    });
  });

  group('CapturaFotoGuiada', () {
    testWidgets('permissão concedida: tira, envia e devolve a referência', (tester) async {
      final upload = ServicoUploadFake();
      final captura = CapturaFotoGuiada(
        camera: ServicoCameraFake(),
        permissao: ServicoPermissaoFake(),
        upload: upload,
      );
      String? ref;
      await _abrir(
        tester,
        _botao(
          (context) async =>
              ref = await captura.capturar(context, FinalidadeArquivo.selfie, frontal: true),
        ),
      );

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();

      expect(ref, 'arq-1');
      expect(upload.enviados.single.$2, FinalidadeArquivo.selfie);
    });

    testWidgets('permissão negada para sempre: não abre a câmera', (tester) async {
      final camera = ServicoCameraFake();
      final captura = CapturaFotoGuiada(
        camera: camera,
        permissao: ServicoPermissaoFake(atual: EstadoPermissao.negadaParaSempre),
        upload: ServicoUploadFake(),
      );
      String? ref = 'antes';
      await _abrir(
        tester,
        _botao(
          (context) async => ref = await captura.capturar(context, FinalidadeArquivo.documento),
        ),
      );

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();
      expect(find.text('Permissão desligada'), findsOneWidget);
      await tester.tap(find.text('Agora não'));
      await tester.pumpAndSettle();

      expect(ref, isNull);
      expect(camera.tiradas, 0);
    });

    testWidgets('falha no envio: avisa em português simples e devolve nulo', (tester) async {
      final captura = CapturaFotoGuiada(
        camera: ServicoCameraFake(),
        permissao: ServicoPermissaoFake(),
        upload: ServicoUploadFake(falha: ErroTrato.semInternet),
      );
      String? ref = 'antes';
      await _abrir(
        tester,
        _botao(
          (context) async => ref = await captura.capturar(context, FinalidadeArquivo.notaMaterial),
        ),
      );

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();

      expect(ref, isNull);
      expect(find.textContaining('Sem conexão'), findsOneWidget);
    });

    testWidgets('galeria: não pede a permissão da câmera', (tester) async {
      final camera = ServicoCameraFake();
      final captura = CapturaFotoGuiada(
        camera: camera,
        permissao: ServicoPermissaoFake(atual: EstadoPermissao.negadaParaSempre),
        upload: ServicoUploadFake(),
      );
      String? ref;
      await _abrir(
        tester,
        _botao(
          (context) async => ref = await captura.capturar(
            context,
            FinalidadeArquivo.fotoPedido,
            permitirGaleria: true,
          ),
        ),
      );

      await tester.tap(find.text('usar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher da galeria'));
      await tester.pumpAndSettle();

      expect(ref, 'arq-1');
      expect(camera.daGaleria, 1);
      expect(find.text('Permissão desligada'), findsNothing);
    });
  });

  group('Novo pedido', () {
    testWidgets('foto capturada aparece como anexo', (tester) async {
      var chamadas = 0;
      await _abrir(tester, NovoPedidoTela(aoCapturarFoto: () async => 'arq-${++chamadas}'));

      await tester.ensureVisible(find.text('Adicionar'));
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      expect(chamadas, 1);
      expect(find.text('[Foto 3]'), findsOneWidget);
    });
  });
}
