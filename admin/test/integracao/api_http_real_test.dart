@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';

/// Painel (`ApiAdminHttp`) contra o backend de TESTE em memória, com HTTP de verdade.
///
/// Só roda quando `TRATO_BACKEND_TESTE` aponta para o servidor (ver `docs/painel-integracao.md`):
///   python harness/subir-backend-teste.py --porta 8765
///   TRATO_BACKEND_TESTE=http://127.0.0.1:8765 flutter test test/integracao
/// Sem a variável, os testes são pulados (o `harness/verificar` não depende de servidor).
final _url = Platform.environment['TRATO_BACKEND_TESTE'];
const _senha = 'senha-de-teste-local';

ApiAdminHttp _cliente() =>
    ApiAdminHttp(urlApi: _url!, urlSupabase: _url!, chaveAnonSupabase: 'anon-de-teste');

Future<ApiAdminHttp> _entrar(String papel) async {
  final api = _cliente();
  final eu = await api.entrar('$papel@teste.trato.local', _senha);
  expect(eu.papel.codigo, papel);
  return api;
}

void main() {
  final pular = _url == null ? 'defina TRATO_BACKEND_TESTE' : null;

  test('login por papel devolve papel e alçada; senha errada recusa', () async {
    final api = _cliente();
    final eu = await api.entrar('mediador@teste.trato.local', _senha);
    expect(eu.papel, Papel.mediador);
    expect(eu.alcadaCentavos, 200000);
    await expectLater(_cliente().entrar('mediador@teste.trato.local', 'errada'), throwsA(isA<ErroApi>()));
    // sem login, qualquer chamada pede entrada
    await expectLater(_cliente().listarVerificacoes(), throwsA(isA<ErroApi>().having((e) => e.sessao, 'sessao', true)));
  }, skip: pular);

  test('cada papel entra e o painel recebe o papel certo', () async {
    for (final p in ['cadastro', 'seguranca', 'financeiro', 'administrador', 'lider_suporte', 'dpo', 'atendente_n1']) {
      await _entrar(p);
    }
  }, skip: pular);

  test('verificação: lista, documento por URL assinada curta, recusa e aprovação com motivo', () async {
    final api = await _entrar('cadastro');
    final lista = await api.listarVerificacoes();
    expect(lista.length, greaterThanOrEqualTo(2));
    final v = lista.first;
    expect(v.cpfMascarado, startsWith('***.'));
    final url = await api.revelarDocumento(v.id, v.documentos.first, 'Conferir o documento');
    expect(url, isNotNull);
    expect(url, startsWith('https://'));
    expect(url, isNot(contains('bucket')));
    // outro papel não decide (403) nem abre arquivo
    final seg = await _entrar('seguranca');
    await seg.listarVerificacoes(); // segurança pode VER a fila, mas não abrir arquivo
    await expectLater(seg.revelarDocumento(v.id, v.documentos.first, 'Xereta'),
        throwsA(isA<ErroApi>().having((e) => e.proibido, 'proibido', true)));
    await api.decidirVerificacao(v.id, aprovar: false, motivo: 'Documento ilegível');
    await api.decidirVerificacao(lista[1].id, aprovar: true, motivo: 'Tudo conferido');
    final depois = await api.listarVerificacoes();
    expect(depois.where((x) => x.id == v.id), isEmpty); // saiu da fila de pendentes
  }, skip: pular);

  test('disputa: dentro da alçada decide; acima pede segunda pessoa, que não é quem decidiu', () async {
    final med = await _entrar('mediador');
    final lista = await med.listarDisputas();
    final ped1 = lista.firstWhere((d) => d.id == 'ped-1');
    final ped2 = lista.firstWhere((d) => d.id == 'ped-2');
    expect(ped1.valorEmAnaliseCentavos, 100000);
    final r1 = await med.decidirDisputa(ped1.id,
        decisao: DecisaoDisputa.reembolsoParcial, valorReembolsoCentavos: 40000, justificativa: 'Foto mostra o defeito');
    expect(r1.status, StatusDisputa.decidida);
    final r2 = await med.decidirDisputa(ped2.id, decisao: DecisaoDisputa.reembolsoTotal, justificativa: 'Serviço não foi feito');
    expect(r2.status, StatusDisputa.aguardandoSegundaPessoa);
    await expectLater(med.aprovarDisputa(ped2.id, justificativa: 'Eu mesmo'),
        throwsA(isA<ErroApi>().having((e) => e.proibido, 'proibido', true)));
    final lider = await _entrar('lider_suporte');
    final r3 = await lider.aprovarDisputa(ped2.id, justificativa: 'Confere com as provas');
    expect(r3.status, StatusDisputa.decidida);
    // a fila do painel só traz o que está aberto: decidida sai da lista
    expect((await lider.listarDisputas()).where((d) => d.id == 'ped-2'), isEmpty);
  }, skip: pular);

  test('pagamentos em leitura: resumo e extrato com divergência', () async {
    final fin = await _entrar('financeiro');
    final resumo = await fin.resumoConciliacao();
    expect(resumo.divergencias, 1);
    final extrato = await fin.extrato();
    expect(extrato.any((l) => l.divergente), isTrue);
    expect(extrato.every((l) => l.valorCentavos > 0), isTrue);
  }, skip: pular);

  test('busca: dados pessoais só com motivo e o painel recebe o que o backend liberou', () async {
    final cad = await _entrar('cadastro');
    final us = await cad.buscarUsuarios('Maria');
    expect(us.single.id, 'cli-1');
    final d = await cad.revelarDadosPessoais('cli-1', 'Validar cadastro');
    expect(d.cpf, isNotEmpty);
    final n1 = await _entrar('atendente_n1');
    await expectLater(n1.revelarDadosPessoais('cli-1', 'Curiosidade'),
        throwsA(isA<ErroApi>().having((e) => e.proibido, 'proibido', true)));
    expect((await n1.buscarPedidos('ped')).isNotEmpty, isTrue);
  }, skip: pular);

  test('configuração: proposta pelo financeiro, aprovação dupla pelo administrador', () async {
    final fin = await _entrar('financeiro');
    final antes = await fin.carregarConfig();
    expect(antes.definicoes, isNotEmpty);
    await fin.proporConfig({'adiantamento_bps': 2500}, 'Reduzir adiantamento');
    final c = await fin.carregarConfig();
    final pendente = c.versoes.firstWhere((v) => v.status == StatusVersao.aguardandoAprovacao);
    await expectLater(fin.aprovarConfig(pendente.id, 'Eu mesmo'),
        throwsA(isA<ErroApi>().having((e) => e.proibido, 'proibido', true)));
    final adm = await _entrar('administrador');
    await adm.aprovarConfig(pendente.id, 'Conferi os números');
    final depois = await adm.carregarConfig();
    expect(depois.versoes.firstWhere((v) => v.id == pendente.id).status, StatusVersao.vigente);
  }, skip: pular);

  test('auditoria: lista e cadeia íntegra; papel sem acesso é barrado', () async {
    final seg = await _entrar('seguranca');
    final itens = await seg.listarAuditoria(acao: 'config.');
    expect(itens, isNotEmpty);
    expect(itens.every((e) => e.acao.startsWith('config.')), isTrue);
    final cadeia = await seg.verificarCadeia();
    expect(cadeia.ok, isTrue);
    final fin = await _entrar('financeiro');
    await expectLater(fin.listarAuditoria(), throwsA(isA<ErroApi>().having((e) => e.proibido, 'proibido', true)));
  }, skip: pular);
}
