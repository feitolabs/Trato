import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/fila_offline.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/captura_check_in_dispositivo.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/dispositivo/servico_localizacao.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';

class _Req {
  _Req(this.metodo, this.url, this.corpo, this.cabecalhos);

  final String metodo;
  final Uri url;
  final Object? corpo;
  final Map<String, String> cabecalhos;
}

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// API simulada. [online] liga/desliga a internet; guarda o que o app mandou.
class _Rede {
  bool online = true;
  final reqs = <_Req>[];

  ClienteApi get api {
    final sessao = SessaoTrato()..entrar('valor-de-teste');
    return ClienteApi(
      urlBase: 'https://api.teste',
      sessao: sessao,
      cliente: MockClient((r) async {
        if (!online) throw http.ClientException('sem rede');
        reqs.add(_Req(r.method, r.url, r.body.isEmpty ? null : jsonDecode(r.body), r.headers));
        return _json({'ok': true});
      }),
    );
  }
}

void main() {
  // JPEG de verdade e sem metadado: o envio recusa o que não é imagem (M8).
  final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4)));
  final foto = ArquivoCapturado(
    bytes: jpeg,
    sha256: 'abc',
    capturadaEm: DateTime.utc(2026, 10, 29, 17, 6),
  );

  group('ServicoUploadApi', () {
    test('pede a URL assinada e envia os bytes nela (sem chave no app)', () async {
      final puts = <_Req>[];
      final cliente = MockClient((r) async {
        if (r.method == 'PUT') {
          puts.add(_Req('PUT', r.url, r.bodyBytes, r.headers));
          return http.Response('', 200);
        }
        return _json({'arquivo_id': 'arq-9', 'url': 'https://storage.teste/x?assinatura=1'});
      });
      final sessao = SessaoTrato()..entrar('valor-de-teste');
      final posts = <_Req>[];
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((r) async {
          posts.add(_Req(r.method, r.url, jsonDecode(r.body), r.headers));
          return _json({'arquivo_id': 'arq-9', 'url': 'https://storage.teste/x?assinatura=1'});
        }),
      );

      final r = await ServicoUploadApi(api, cliente: cliente)
          .enviar(foto, FinalidadeArquivo.documento, pedidoId: 'p1');

      expect(r.arquivoId, 'arq-9');
      expect(posts.single.url.path, '/v1/arquivos/url-envio');
      final corpo = posts.single.corpo! as Map<String, dynamic>;
      expect(corpo['finalidade'], 'documento');
      expect(corpo['sha256'], 'abc');
      expect(corpo['tamanho_bytes'], jpeg.length);
      expect(corpo['pedido_id'], 'p1');
      expect(puts.single.url.host, 'storage.teste');
      expect(puts.single.corpo, jpeg);
      expect(puts.single.cabecalhos['content-type'], 'image/jpeg');
      expect(puts.single.cabecalhos.containsKey('authorization'), isFalse,
          reason: 'o token do app não vai para o armazenamento');
    });

    test('rota ainda inexistente no backend vira "indisponível"', () async {
      final sessao = SessaoTrato()..entrar('valor-de-teste');
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((_) async => _json({'detail': 'Not Found'}, 404)),
      );

      await expectLater(
        ServicoUploadApi(api).enviar(foto, FinalidadeArquivo.checkIn),
        throwsA(isA<ErroTrato>()),
      );
    });
  });

  group('CapturaCheckInDispositivo', () {
    test('sem internet a foto fica pendente, com o arquivo local', () async {
      final captura = CapturaCheckInDispositivo(
        camera: ServicoCameraFake(),
        localizacao: ServicoLocalizacaoFake(),
        upload: ServicoUploadFake(falha: ErroTrato.semInternet),
        pedidoId: 'p1',
      );

      final f = (await captura.foto())!;

      expect(f.pendente, isTrue);
      expect(f.local, isNotNull);
    });

    test('mede a distância até o endereço liberado', () async {
      final captura = CapturaCheckInDispositivo(
        camera: ServicoCameraFake(),
        localizacao: ServicoLocalizacaoFake(),
        upload: ServicoUploadFake(),
        pedidoId: 'p1',
        destinoLatitude: -23.499,
        destinoLongitude: -46.6,
      );

      final p = (await captura.posicao())!;

      expect(p.distanciaMetros, closeTo(111, 1));
    });

    test('GPS desligado vira erro em português simples', () async {
      final captura = CapturaCheckInDispositivo(
        camera: ServicoCameraFake(),
        localizacao: ServicoLocalizacaoFake(falha: FalhaLocalizacao.gpsDesligado),
        upload: ServicoUploadFake(),
        pedidoId: 'p1',
      );

      await expectLater(
        captura.posicao(),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', contains('GPS'))),
      );
    });
  });

  group('Check-in/out offline', () {
    ServicoCheckInApi servico(
      _Rede rede,
      ServicoUploadFake upload,
      FilaOffline fila, {
      ServicoCamera? camera,
    }) =>
        ServicoCheckInApi(
          rede.api,
          pedidoId: 'p1',
          captura: CapturaCheckInDispositivo(
            camera: camera ?? ServicoCameraFake(),
            localizacao: ServicoLocalizacaoFake(),
            upload: upload,
            pedidoId: 'p1',
          ),
          upload: upload,
          fila: fila,
        );

    test('online: envia direto, sem offline_capturada_em', () async {
      final rede = _Rede();
      final s = servico(rede, ServicoUploadFake(), FilaOfflineMemoria());
      await s.tirarFoto();
      await s.localizar();

      expect(await s.iniciarServico('4821'), ResultadoInicio.iniciado);

      final prova = (rede.reqs.single.corpo! as Map)['prova'] as Map;
      expect(prova.containsKey('offline_capturada_em'), isFalse);
      expect((prova['foto'] as Map)['arquivo_id'], 'arq-1');
    });

    test('sem internet: guarda, e reenvia depois com offline_capturada_em', () async {
      final rede = _Rede()..online = false;
      final upload = ServicoUploadFake(falha: ErroTrato.semInternet);
      final fila = FilaOfflineMemoria();
      final s = servico(rede, upload, fila);
      await s.tirarFoto();
      await s.localizar();

      expect(await s.iniciarServico('4821'), ResultadoInicio.guardadoOffline);
      expect(fila.pendentes, hasLength(1));
      expect(rede.reqs, isEmpty);

      // Ainda sem internet: continua na fila.
      expect(await s.reenviarPendentes(), 0);
      expect(fila.pendentes, hasLength(1));

      // A conexão volta: sobe a foto e depois o check-in.
      rede.online = true;
      upload.falha = null;
      expect(await s.reenviarPendentes(), 1);

      expect(fila.pendentes, isEmpty);
      expect(upload.enviados, hasLength(1));
      final prova = (rede.reqs.single.corpo! as Map)['prova'] as Map;
      expect(prova['offline_capturada_em'], '2026-10-29T17:06:00.000Z');
      expect(prova['codigo_inicio'], '4821');
      expect((prova['foto'] as Map)['arquivo_id'], 'arq-1');
    });

    test('check-out sem internet também fica guardado', () async {
      final rede = _Rede()..online = false;
      final fila = FilaOfflineMemoria();
      final s = servico(rede, ServicoUploadFake(), fila);

      final enviado = await s.fazerCheckOut(
        fotoFinal: FotoCapturada(tiradaEm: foto.capturadaEm, local: foto),
        codigo: '7310',
      );

      expect(enviado, isFalse);
      expect(fila.pendentes.single.tipo, TipoAcaoOffline.checkOut);
    });

    test('sem fila configurada, a falta de internet continua sendo um erro', () async {
      final rede = _Rede()..online = false;
      final s = ServicoCheckInApi(
        rede.api,
        pedidoId: 'p1',
        captura: CapturaCheckInDispositivo(
          camera: ServicoCameraFake(),
          localizacao: ServicoLocalizacaoFake(),
          upload: ServicoUploadFake(),
          pedidoId: 'p1',
        ),
      );
      await s.tirarFoto();
      await s.localizar();

      await expectLater(s.iniciarServico('4821'), throwsA(isA<ErroTrato>()));
    });
  });
}
