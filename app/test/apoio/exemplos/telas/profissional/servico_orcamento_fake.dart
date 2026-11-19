import 'package:trato/telas/profissional/servico_orcamento.dart';

/// PROVISÓRIO — SÓ PARA TESTE E DEMONSTRAÇÃO. NÃO É REGRA DE NEGÓCIO.
/// O Trato é gratuito (sem taxa): devolve o mesmo valor que recebeu. Trocar por uma implementação
/// que chame a API antes de qualquer uso fora de teste.
class ServicoOrcamentoFake implements ServicoOrcamento {
  ServicoOrcamentoFake();

  /// Totais pedidos, na ordem. Usado nos testes para conferir o que a tela mandou.
  final List<int> pedidos = [];

  /// Orçamentos enviados, na ordem.
  final List<OrcamentoPronto> enviados = [];

  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async {
    pedidos.add(totalCentavos);
    return ResumoOrcamento(totalCentavos: totalCentavos);
  }

  @override
  Future<void> enviar(OrcamentoPronto pronto) async {
    enviados.add(pronto);
  }
}
