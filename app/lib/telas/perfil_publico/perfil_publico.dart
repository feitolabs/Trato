/// Modelos e serviço do perfil público do profissional e das avaliações recebidas (F6.7).
/// PROVISÓRIO: formato real vem do backend.
library;

import '../cliente/modelos.dart' show Avaliacao, EtiquetaTop;

export '../cliente/modelos.dart' show Avaliacao, DetalhePerfil, EtiquetaTop;

class PerfilPublico {
  const PerfilPublico({
    required this.nome,
    required this.iniciais,
    required this.categoria,
    required this.verificacao,
    required this.noTratoDesde,
    required this.nota,
    required this.totalAvaliacoes,
    required this.servicosConcluidos,
    required this.sobre,
    required this.cidade,
    required this.fotosPortfolio,
    required this.ultimasAvaliacoes,
    this.fotoReferencia,
    this.listaFotosPortfolio = const [],
    this.etiquetasTop = const [],
    this.respondeEmFaixa,
  });

  /// `responde_em_faixa` da API; nulo/vazio = não mostra o selo de resposta.
  final String? respondeEmFaixa;

  /// Elogios mais recebidos (`etiquetas_top`); vazio = não mostra.
  final List<EtiquetaTop> etiquetasTop;

  final String nome;
  final String iniciais;
  final String categoria;

  /// Texto neutro vindo do backend, ex.: "Identidade conferida". Nunca "profissional seguro".
  final String? verificacao;
  final int noTratoDesde;
  final double nota;
  final int totalAvaliacoes;
  final int servicosConcluidos;
  final String sobre;
  final String cidade;
  final int fotosPortfolio;
  final List<Avaliacao> ultimasAvaliacoes;
  final String? fotoReferencia;
  final List<String> listaFotosPortfolio;
}

abstract interface class RespostaAvaliacao {
  Future<String?> responderAvaliacao(String avaliacaoId, String resposta);
}

abstract interface class ServicoPerfilPublico {
  Future<PerfilPublico> carregarPerfil();
  Future<List<Avaliacao>> carregarAvaliacoes();
  Future<bool> temPerfilProfissional();
}
