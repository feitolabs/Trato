import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';

// Regressão (04/11/2026): a tela de check-in marcava foto e localização como "Feito", mas ao
// tocar em "Iniciar serviço" o app dizia "Tire a foto de chegada e permita a localização".
// Também mostrava "A 0 m do endereço" mesmo sem conhecer o endereço.

class _Captura implements CapturaCheckIn {
  @override
  Future<FotoCapturada?> foto() async =>
      FotoCapturada(arquivoId: 'arq-1', tiradaEm: DateTime.utc(2026, 11, 5, 9, 1));

  @override
  Future<PosicaoCapturada?> posicao() async => const PosicaoCapturada(-19.9167, -43.9386);
}

void main() {
  test('foto e posição capturadas vão na prova do check-in; sem endereço não inventa 0 m', () async {
    final corpos = <Object?>[];
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async {
        corpos.add(r.body.isEmpty ? null : jsonDecode(r.body));
        expect(r.url.path, '/v1/pedidos/p1/acoes/fazer_check_in');
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    final s = ServicoCheckInApi(api, pedidoId: 'p1', captura: _Captura());

    final foto = await s.tirarFoto();
    final distancia = await s.localizar();
    final resultado = await s.iniciarServico('4749');

    expect(foto, isNotNull);
    expect(distancia, distanciaDesconhecidaMetros, reason: 'posição registrada, endereço desconhecido');
    expect(resultado, ResultadoInicio.iniciado);
    final prova = (corpos.single! as Map)['prova'] as Map;
    expect((prova['foto'] as Map)['arquivo_id'], 'arq-1');
    expect(prova['localizacao'], {'latitude': -19.9167, 'longitude': -43.9386});
    expect(prova['codigo_inicio'], '4749');
  });

  test('check-out: o repositório do profissional entrega um serviço que envia foto final e código',
      () async {
    // Regressão: a CheckOutTela existia, mas nada a abria e o repositório nem tinha o serviço.
    final corpos = <Object?>[];
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async {
        corpos.add(r.body.isEmpty ? null : jsonDecode(r.body));
        expect(r.url.path, '/v1/pedidos/p1/acoes/fazer_check_out');
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    final servico =
        RepositorioProfissionalApi(api, capturaFinalDoPedido: (_) => _Captura()).servicoCheckOut('p1');

    expect(await servico.tirarFotoFinal(), isNotNull);
    expect(await servico.finalizar('7310'), ResultadoFim.concluido);

    final prova = (corpos.single! as Map)['prova'] as Map;
    expect((prova['foto_final'] as Map)['arquivo_id'], 'arq-1');
    expect(prova['codigo_conclusao'], '7310');
  });

  test('sem permissão de localização a distância continua nula (o passo não fica "Feito")', () async {
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async => http.Response('{}', 200)),
    );
    final s = ServicoCheckInApi(api, pedidoId: 'p1', captura: const CapturaIndisponivel());

    expect(await s.localizar(), isNull);
  });
}
