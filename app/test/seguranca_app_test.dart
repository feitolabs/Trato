import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:trato/auth/armazenamento_sessao.dart';
import 'package:trato/auth/servico_auth_fake.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/defines_publicos.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/preparador_imagem.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/tema/tema.dart';

class _Antiga implements SessaoAntiga {
  _Antiga(this.valor);
  String? valor;
  @override
  Future<String?> ler(String chave) async => valor;
  @override
  Future<void> apagar(String chave) async => valor = null;
}

Uint8List _jpegComGps() {
  final imagem = img.Image(width: 40, height: 30);
  img.fill(imagem, color: img.ColorRgb8(10, 90, 200));
  imagem.exif.gpsIfd.data[0x0001] = img.IfdValueAscii('S');
  imagem.exif.gpsIfd.data[0x0002] = img.IfdValueRational(23, 1);
  return Uint8List.fromList(img.encodeJpg(imagem));
}

void main() {
  group('M13 sessão em armazenamento seguro', () {
    test('migra a sessão antiga para o cofre e apaga o texto puro', () async {
      final cofre = ArmazenamentoSessaoMemoria();
      final antiga = _Antiga('sessao-antiga');
      final s = LocalStorageSeguro(chave: 'sb-x-auth-token', armazenamento: cofre, antiga: antiga);
      await s.initialize();
      expect(antiga.valor, isNull);
      expect(await s.accessToken(), 'sessao-antiga');
      expect(await s.hasAccessToken(), isTrue);
    });

    test('grava e remove só no cofre', () async {
      final cofre = ArmazenamentoSessaoMemoria();
      final s = LocalStorageSeguro(chave: 'k', armazenamento: cofre, antiga: _Antiga(null));
      await s.initialize();
      await s.persistSession('abc');
      expect(cofre.dados['k'], 'abc');
      await s.removePersistedSession();
      expect(await s.hasAccessToken(), isFalse);
    });

    test('a chave segue o nome que o Supabase usava', () {
      expect(LocalStorageSeguro.chaveDaUrl('https://abcd.supabase.co'), 'sb-abcd-auth-token');
    });
  });

  group('M14 lista permitida de dart-define', () {
    test('nomes e valores com cara de segredo são barrados', () {
      expect(nomeComCaraDeSegredo('SUPABASE_SERVICE_ROLE_KEY'), isTrue);
      expect(nomeComCaraDeSegredo('JWT_SECRET'), isTrue);
      expect(nomeComCaraDeSegredo('DATABASE_URL'), isTrue);
      expect(nomeComCaraDeSegredo('SUPABASE_ANON_KEY'), isFalse);
      expect(valorComCaraDeSegredo('sk_test_abcdefghij'), isTrue);
      final carga = base64Url.encode(utf8.encode('{"role":"service_role"}')).replaceAll('=', '');
      expect(valorComCaraDeSegredo('eyJhbGciOiJIUzI1NiJ9.$carga.assinatura'), isTrue);
      final anon = base64Url.encode(utf8.encode('{"role":"anon"}')).replaceAll('=', '');
      expect(valorComCaraDeSegredo('eyJhbGciOiJIUzI1NiJ9.$anon.assinatura'), isFalse);
    });

    test('em debug, segredo para com erro sem mostrar o valor', () {
      expect(
        () => filtrarDefines({'TRATO_MODO': 'api', 'DATABASE_URL': 'postgres://x'}),
        throwsA(isA<StateError>().having((e) => e.message, 'mensagem', isNot(contains('postgres')))),
      );
      expect(filtrarDefines({'TRATO_MODO': 'api', 'SUPABASE_URL': 'https://a.b'}).length, 2);
    });
  });

  group('M8 EXIF removido antes do envio', () {
    test('temMetadados enxerga o GPS e não acusa a imagem limpa', () {
      final suja = _jpegComGps();
      expect(temMetadados(suja), isTrue);
      final limpa = const PreparadorImagem().preparar(suja, capturadaEm: DateTime.utc(2026)).bytes;
      expect(temMetadados(limpa), isFalse);
    });

    test('ServicoUploadApi limpa a foto mesmo que ela chegue com GPS', () async {
      Uint8List? enviado;
      final cliente = MockClient((req) async {
        if (req.method == 'PUT') {
          enviado = req.bodyBytes;
          return http.Response('', 200);
        }
        return http.Response(
          jsonEncode({'arquivo_id': 'a1', 'url': 'https://armazem.teste/x'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final sessao = SessaoTrato()..entrar('t');
      final api = ClienteApi(urlBase: 'https://api.teste', sessao: sessao, cliente: cliente);
      final bytes = _jpegComGps();
      final suja = ArquivoCapturado(bytes: bytes, sha256: sha256Hex(bytes), capturadaEm: DateTime.utc(2026));
      await ServicoUploadApi(api, cliente: cliente).enviar(suja, FinalidadeArquivo.fotoPedido);
      expect(enviado, isNotNull);
      expect(img.decodeJpg(enviado!)!.exif.gpsIfd.isEmpty, isTrue);
      expect(temMetadados(enviado!), isFalse);
    });
  });

  group('401 da API', () {
    test('limpa a sessão e avisa uma vez', () async {
      final sessao = SessaoTrato()..entrar('t');
      var avisos = 0;
      sessao.aoExpirar = () => avisos++;
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((_) async => http.Response('{}', 401)),
      );
      await expectLater(api.get('/v1/x'), throwsA(isA<ErroTrato>()));
      await expectLater(api.get('/v1/x'), throwsA(isA<ErroTrato>()));
      expect(sessao.logada, isFalse);
      expect(avisos, 1);
    });

    testWidgets('login por sessão expirada avisa, e ao entrar volta à tela de baixo', (tester) async {
      final chave = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: chave,
        theme: TemaTrato.claro,
        home: const Scaffold(body: TextField(key: Key('rascunho'))),
      ));
      await tester.enterText(find.byKey(const Key('rascunho')), 'texto digitado');
      chave.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => LoginTela(servico: ServicoAuthFake(), sessaoExpirada: true),
      ));
      await tester.pumpAndSettle();
      expect(find.text(ErroTrato.sessaoExpirada.mensagem), findsOneWidget);
      chave.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('texto digitado'), findsOneWidget);
    });
  });
}
