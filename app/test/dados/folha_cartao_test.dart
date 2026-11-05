import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/folha_cartao.dart';
import 'package:trato/telas/pagamento/modelos.dart';


void main() {
  Future<Cobranca> criar(Map<String, Object?> corpo, MetodoPagamento metodo) {
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((req) async => http.Response.bytes(
            utf8.encode(jsonEncode(corpo)),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    return RepositorioPagamentoApi(api).criarCobranca('ab12cd34', metodo);
  }

  test('cartão: o app guarda cliente, chave e segredo só para a folha', () async {
    final c = await criar({
      'cobranca_id': 'pi_1',
      'tipo_instrucao': 'cartao_segredo_do_cliente',
      'instrucao': 'pi_1_secret_x',
      'cliente_externo_id': 'cus_1',
      'chave_efemera': 'ek_test_1',
    }, MetodoPagamento.cartao);
    expect(c.precisaDaFolhaDeCartao, isTrue);
    expect(c.pixCopiaECola, isNull); // o segredo do cartão nunca vira texto de tela
    expect(c.clienteCartaoId, 'cus_1');
  });

  test('pix não abre a folha de cartão', () async {
    final c = await criar({
      'cobranca_id': 'pi_2',
      'tipo_instrucao': 'pix_copia_e_cola',
      'instrucao': '000201pix',
    }, MetodoPagamento.pix);
    expect(c.precisaDaFolhaDeCartao, isFalse);
    expect(c.pixCopiaECola, '000201pix');
  });

  test('folha fake registra o que o backend entregou', () async {
    final folha = FolhaCartaoFake(ResultadoCartao.cancelado);
    final r = await folha.pagar(const PreparoFolhaCartao(
        segredoDoPagamento: 's', clienteId: 'cus_1', chaveEfemera: 'ek'));
    expect(r, ResultadoCartao.cancelado);
    expect(folha.abertas.single.clienteId, 'cus_1');
  });

  test('sem chave pública a folha real avisa em vez de travar', () async {
    expect(
      () => FolhaCartaoStripe(chavePublica: '').pagar(const PreparoFolhaCartao(
          segredoDoPagamento: 's', clienteId: 'c', chaveEfemera: 'e')),
      throwsA(isA<ErroFolhaCartao>()),
    );
  });
}
