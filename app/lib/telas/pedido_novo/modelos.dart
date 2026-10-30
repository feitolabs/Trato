// Modelos do Novo pedido. Provisórios: as perguntas guiadas de cada categoria virão do backend.

/// Faixa de preço em centavos inteiros ("R$ 200 a R$ 500"). Só exibe: não há regra no app.
class FaixaPreco {
  const FaixaPreco({required this.minimoCentavos, required this.maximoCentavos});

  final int minimoCentavos;
  final int maximoCentavos;
}

/// Perguntas e opções do formulário da categoria escolhida.
class FormularioPedido {
  const FormularioPedido({
    required this.categoria,
    required this.servicos,
    required this.servicosIniciais,
    required this.perguntaQuantidade,
    required this.dicaQuantidade,
    required this.quantidadeInicial,
    required this.perguntaVoltagem,
    required this.voltagens,
    required this.voltagemInicial,
    required this.descricaoInicial,
    required this.fotos,
    required this.prazos,
    required this.faixas,
    required this.endereco,
    required this.avisoEndereco,
    required this.avisoPrazo,
  });

  /// Ex.: "Elétrica · Tomadas e chuveiro".
  final String categoria;
  final List<String> servicos;
  final Set<String> servicosIniciais;
  final String perguntaQuantidade;
  final String dicaQuantidade;
  final int quantidadeInicial;
  final String perguntaVoltagem;
  final List<String> voltagens;
  final String voltagemInicial;
  final String descricaoInicial;

  /// Rótulos das fotos já anexadas ("[Foto 1]").
  final List<String> fotos;
  final List<String> prazos;
  final List<FaixaPreco> faixas;
  final String endereco;
  final String avisoEndereco;
  final String avisoPrazo;
}

/// O que o cliente preencheu, devolvido em `aoEnviar`.
class RascunhoPedido {
  const RascunhoPedido({
    required this.servicos,
    required this.quantidade,
    required this.voltagem,
    required this.descricao,
    required this.prazo,
    required this.faixa,
    this.fotos = const [],
  });

  final List<String> servicos;
  final int quantidade;
  final String voltagem;
  final String descricao;
  final String prazo;
  final FaixaPreco faixa;

  /// Referências (`arquivoId`) das fotos já enviadas.
  final List<String> fotos;
}
