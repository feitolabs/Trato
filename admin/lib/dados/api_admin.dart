import 'modelos.dart';

/// Tudo que o painel pede ao backend. A implementação real (HTTP) virá quando a API admin existir;
/// os endpoints esperados estão em docs/painel-admin.md. Nenhuma regra de dinheiro mora aqui:
/// o painel pede, o backend decide.
abstract interface class ApiAdmin {
  Future<UsuarioEquipe> entrar(String email, String senha);
  Future<void> sair();

  // F7.1 verificação
  Future<List<Verificacao>> listarVerificacoes();
  /// Devolve a URL assinada de curta duração (ou null, no exemplo).
  Future<String?> revelarDocumento(String verificacaoId, String documento, String motivo);
  Future<void> decidirVerificacao(String id, {required bool aprovar, required String motivo});

  // F7.2 disputas
  Future<List<Disputa>> listarDisputas();
  Future<ResultadoDecisao> decidirDisputa(
    String id, {
    required DecisaoDisputa decisao,
    int? valorReembolsoCentavos,
    required String justificativa,
  });

  /// Segunda pessoa (outra, não quem decidiu) aprova uma decisão acima da alçada.
  Future<ResultadoDecisao> aprovarDisputa(String id, {required String justificativa});

  // F7.3 pagamentos (somente leitura)
  Future<ResumoConciliacao> resumoConciliacao();
  Future<List<LancamentoEspelho>> extrato();

  // F7.4 busca, suporte, categorias, cidades e usuários
  Future<List<UsuarioBusca>> buscarUsuarios(String termo);
  Future<DadosPessoais> revelarDadosPessoais(String usuarioId, String motivo);
  Future<void> alterarStatusUsuario(String usuarioId, {required String status, required String motivo});
  Future<List<PedidoBusca>> buscarPedidos(String termo);
  Future<List<Chamado>> listarChamados();
  Future<List<CategoriaAdmin>> listarCategorias();
  Future<CategoriaAdmin> criarCategoria({
    required String nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int ordem = 0,
    bool ativa = true,
    required String motivo,
  });
  Future<CategoriaAdmin> editarCategoria(
    String id, {
    String? nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int? ordem,
    bool? ativa,
    required String motivo,
  });
  Future<void> alterarCategoria(String id, {required bool ativa, required String motivo});
  Future<void> excluirCategoria(String id, {required String motivo});

  // Gestão de cidades (expansão regional)
  Future<List<CidadeAdmin>> listarCidades();
  Future<CidadeAdmin> criarCidade({
    required String nome,
    required String uf,
    bool ativa = true,
    double? centroLat,
    double? centroLng,
    required String motivo,
  });
  Future<void> alterarCidade(String id, {required bool ativa, required String motivo});

  // F7.5 configurações
  Future<ConfigAtual> carregarConfig();
  Future<void> proporConfig(Map<String, int> valores, String motivo);
  Future<void> aprovarConfig(String versaoId, String motivo);
  Future<void> publicarConfig(String versaoId, String motivo);
  Future<void> reverterConfig(String versaoId, String motivo);

  // F7.6 auditoria
  Future<List<EntradaAuditoria>> listarAuditoria({String? acao, String? ator});
  Future<ResultadoCadeia> verificarCadeia();

  // Módulo 1: Dashboard
  Future<MetricasDashboard> metricasDashboard();
  Future<SeriesDashboard> seriesDashboard({int dias = 7});

  // Módulo 2: Perguntas Dinâmicas da Categoria
  Future<List<PerguntaCategoriaAdmin>> listarPerguntasCategoria(String categoriaId);
  Future<PerguntaCategoriaAdmin> criarPerguntaCategoria(
    String categoriaId, {
    required String texto,
    required String tipo,
    List<String>? opcoes,
    bool obrigatoria = false,
    int ordem = 0,
    required String motivo,
  });
  Future<PerguntaCategoriaAdmin> editarPerguntaCategoria(
    String categoriaId,
    String perguntaId, {
    String? texto,
    String? tipo,
    List<String>? opcoes,
    bool? obrigatoria,
    int? ordem,
    bool? ativa,
    required String motivo,
  });
  Future<void> desativarPerguntaCategoria(String categoriaId, String perguntaId, {required String motivo});

  // Módulo 3: Central Antifraude e Risco
  Future<List<AlertaRisco>> listarAlertasRisco();
  Future<void> aplicarBloqueioPreventivo(String usuarioId, {required String motivo});
  Future<void> travarSaque(String usuarioId, {required String motivo});
  Future<void> resolverAlertaRisco(String alertaId, {required String motivo});

  // Módulo 4: Notificações em Massa & Campanhas
  Future<List<CampanhaNotificacao>> listarCampanhasNotificacao();
  Future<CampanhaNotificacao> dispararCampanhaNotificacao({
    required String titulo,
    required String mensagem,
    required String segmento,
    String? categoriaId,
    String? cidadeId,
    required String motivo,
  });

  // Módulo 5: Gestão de Cupons
  Future<List<CupomAdmin>> listarCupons();
  Future<CupomAdmin> criarCupom({
    required String codigo,
    required String tipo,
    required int valor,
    int valorMinimoCentavos = 0,
    int? limiteUsos,
    String? validoAte,
    required String motivo,
  });
  Future<CupomAdmin> alterarStatusCupom(String cupomId, {required bool ativo, required String motivo});
  Future<void> excluirCupom(String cupomId, {required String motivo});

  // Módulo 6: Equipe Interna
  Future<List<MembroEquipeAdmin>> listarEquipe();
  Future<MembroEquipeAdmin> adicionarMembroEquipe({
    required String nome,
    required String email,
    required String papel,
    int alcadaCentavos = 0,
    required String motivo,
  });
  Future<MembroEquipeAdmin> editarMembroEquipe(
    String usuarioId, {
    String? papel,
    int? alcadaCentavos,
    bool? ativo,
    required String motivo,
  });
  Future<void> revogarMembroEquipe(String usuarioId, {required String motivo});

  // Módulo 7: Exportação de Relatórios CSV
  String urlRelatorioFinanceiroCsv();
  String urlRelatorioPedidosCsv();
  String urlRelatorioRepassesCsv();
}
