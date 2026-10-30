import 'servico_orcamento.dart';

/// PROVISÓRIO — SÓ PARA TESTE E DEMONSTRAÇÃO. NÃO É REGRA DE NEGÓCIO.
/// Aplica um percentual qualquer recebido por parâmetro. A taxa real (progressiva, base 7,5%,
/// mínima configurável) é decidida pelo backend (P2/P5). Trocar por uma implementação que
/// chame a API antes de qualquer uso fora de teste.
class ServicoOrcamentoFake implements ServicoOrcamento {
  ServicoOrcamentoFake({required this.taxaBps});

  final int taxaBps;

  /// Totais pedidos, na ordem. Usado nos testes para conferir o que a tela mandou.
  final List<int> pedidos = [];

  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async {
    pedidos.add(totalCentavos);
    final taxa = totalCentavos * taxaBps ~/ 10000;
    return ResumoOrcamento(
      totalCentavos: totalCentavos,
      taxaCentavos: taxa,
      taxaBps: taxaBps,
      liquidoCentavos: totalCentavos - taxa,
    );
  }
}
