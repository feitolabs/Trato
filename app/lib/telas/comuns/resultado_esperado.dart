// Termos 8.4: o que o cliente espera ao relatar um problema. É um pedido, não o resultado.

/// Códigos de `resultado_esperado`, na mesma ordem das opções da tela.
const codigosResultadoEsperado = ['retrabalho', 'reembolso_parcial', 'reembolso_total'];

/// Linha que vai no fim do relato (disputas antigas só têm ela).
const marcaSolucaoPreferida = 'Solução que o cliente prefere:';

const avisoEscolhaDoCliente =
    'É o que você está pedindo. Não é promessa de resultado: o caso ainda será tratado.';
const avisoPedidoDoCliente = 'É o que o cliente está pedindo. Não é o resultado do caso.';

/// Texto do código do servidor. Nulo: ausente ou desconhecido.
String? textoResultadoEsperado(Object? codigo) => switch (codigo) {
      'retrabalho' => 'Retrabalho sem custo',
      'reembolso_parcial' => 'Reembolso parcial',
      'reembolso_total' => 'Reembolso total',
      _ => null,
    };

/// Separa o relato da escolha. O campo do servidor vale mais que a linha escrita no relato.
({String descricao, String? pedido}) separarRelato(Object? descricao, Object? codigo) {
  final relato = descricao is String ? descricao.trim() : '';
  final corte = relato.lastIndexOf(marcaSolucaoPreferida);
  final escrito = corte < 0 ? '' : relato.substring(corte + marcaSolucaoPreferida.length).trim();
  return (
    descricao: corte < 0 ? relato : relato.substring(0, corte).trim(),
    pedido: textoResultadoEsperado(codigo) ?? (escrito.isEmpty ? null : escrito),
  );
}
