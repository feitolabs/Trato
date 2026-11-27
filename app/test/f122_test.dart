// APP-NOTA: a foto da nota de material vai sempre pelo envio conferido (Termos 6.9).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/imagem_trato.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/nota_material/enviar_nota_tela.dart';
import 'package:trato/telas/nota_material/nota_material.dart';

import 'apoio/fontes.dart';

const _foto = 'local/nota-f122.jpg';
const _envio = EnvioNota(
    pedidoId: 'p1', fotoNota: _foto, itens: [ItemNota(descricao: 'Tomada', centavos: 2300)]);

class _Upload implements ServicoUpload {
  ErroTrato? erro;
  var chamadas = 0;

  @override
  Future<ArquivoEnviado> enviar(ArquivoCapturado arquivo, FinalidadeArquivo finalidade,
      {String? pedidoId}) async {
    chamadas++;
    expect((finalidade, pedidoId), (FinalidadeArquivo.notaMaterial, 'p1'));
    if (erro case final e?) throw e;
    return ArquivoEnviado(arquivoId: 'midia-$chamadas');
  }
}

class _Api {
  final corpos = <Map<String, dynamic>>[];
  var status = 201;

  late final cliente = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      corpos.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response.bytes(utf8.encode(jsonEncode({'detail': 'Recusado.'})), status,
          headers: const {'content-type': 'application/json'});
    }),
  );
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() => registrarImagemEmMemoria(_foto, bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1])));

  test('envia só midia_id, nunca foto_storage_path', () async {
    final api = _Api();
    await ServicoNotaMaterialApi(api.cliente, upload: _Upload()).enviar(_envio);
    expect(api.corpos.single['midia_id'], 'midia-1');
    expect(api.corpos.single.containsKey('foto_storage_path'), isFalse);
  });

  test('sem serviço de envio, foto vazia ou ilegível: erro claro e nada vai à API', () async {
    final api = _Api();
    await expectLater(
        ServicoNotaMaterialApi(api.cliente).enviar(_envio), throwsA(isA<ErroTrato>()));
    for (final foto in ['', 'fake://nada', 'caminho/que/nao/existe.jpg']) {
      await expectLater(
        ServicoNotaMaterialApi(api.cliente, upload: _Upload())
            .enviar(EnvioNota(pedidoId: 'p1', fotoNota: foto, itens: _envio.itens)),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', contains('Tire outra'))),
      );
    }
    expect(api.corpos, isEmpty);
  });

  test('falha da nota reaproveita a foto; 422 envia a foto de novo', () async {
    final api = _Api()..status = 500;
    final upload = _Upload();
    final servico = ServicoNotaMaterialApi(api.cliente, upload: upload);
    await expectLater(servico.enviar(_envio), throwsA(isA<ErroTrato>()));
    api.status = 422;
    await expectLater(servico.enviar(_envio), throwsA(isA<ErroTrato>()));
    expect(upload.chamadas, 1);
    api.status = 201;
    await servico.enviar(_envio);
    expect(upload.chamadas, 2);
    expect(api.corpos.map((c) => c['midia_id']), ['midia-1', 'midia-1', 'midia-2']);
    // Nota registrada: um envio seguinte é outra nota, com foto enviada de novo.
    await servico.enviar(_envio);
    expect(upload.chamadas, 3);
  });

  for (final (nome, erro, aviso) in [
    (
      'servidor',
      ErroTrato.servidor,
      'A foto da nota não foi enviada, então a nota não foi registrada. '
          '${ErroTrato.servidor.mensagem} Tente de novo.'
    ),
    (
      'sem internet',
      ErroTrato.semInternet,
      'Não foi possível enviar a nota. Confira sua conexão e tente de novo.'
    ),
  ]) {
    testWidgets('na tela, falha da foto ($nome) mantém tudo e permite tentar de novo', (t) async {
      t.view.physicalSize = const Size(390, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      final upload = _Upload()..erro = erro;
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: EnviarNotaTela(
          servico: ServicoNotaMaterialApi(api.cliente, upload: upload),
          pedidoId: 'p1',
          tituloPedido: 'Troca de tomadas',
          aoCapturarFoto: () async => _foto,
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('Foto da nota').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(0), 'Tomada');
      await t.enterText(find.byType(TextField).at(2), '23');
      await t.tap(find.text('Adicionar item'));
      await t.pumpAndSettle();
      final enviar = find.text('Enviar nota ao cliente');
      await t.tap(enviar);
      await t.pumpAndSettle();
      expect(find.text(aviso), findsOneWidget);
      expect(api.corpos, isEmpty);
      expect(find.text('Tomada'), findsOneWidget);

      upload.erro = null;
      await t.tap(enviar);
      await t.pumpAndSettle();
      expect(api.corpos.single['midia_id'], 'midia-2');
      expect(find.text('Nota enviada ao cliente.'), findsOneWidget);
    });
  }
}
