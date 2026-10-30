class PerguntaFrequente {
  const PerguntaFrequente({required this.pergunta, required this.resposta});

  final String pergunta;
  final String resposta;
}

/// Contrato com o backend (textos de ajuda podem mudar sem nova versão do app).
abstract interface class ServicoAjuda {
  Future<List<PerguntaFrequente>> perguntas();
}
