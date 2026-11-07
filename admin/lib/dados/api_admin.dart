import 'modelos.dart';

/// Tudo que o painel pede ao backend. A implementação real (HTTP) virá quando a API admin existir;
/// os endpoints esperados estão em docs/painel-admin.md. Nenhuma regra de dinheiro mora aqui:
/// o painel pede, o backend decide.
abstract interface class ApiAdmin {
  /// Número do registro de auditoria gerado pela última ação (o backend manda em `X-Auditoria-Id`).
  /// O aviso de sucesso mostra esse número.
  int? get ultimoRegistroAuditoria;

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
  /// [dias] limita ao período (7, 30, 90…); nulo = tudo.
  Future<ResumoConciliacao> resumoConciliacao({int? dias});
  Future<List<LancamentoEspelho>> extrato({int? dias});

  /// Marca uma divergência como conciliada. Só anota: não mexe em dinheiro (RF-PAG-04).
  Future<void> conciliarDivergencia(String lancamentoId, {required String motivo});

  // F7.4 busca, suporte, categorias, cidades e usuários
  Future<List<UsuarioBusca>> buscarUsuarios(String termo);

  /// Detalhe com categorias cadastradas e histórico (contato continua mascarado).
  Future<UsuarioBusca> detalheUsuario(String usuarioId);

  /// RN-01: por que este pedido aparece (ou não) para este profissional.
  Future<DiagnosticoPedido> diagnosticarPedido(String usuarioId, String pedido);
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

  /// Recusa uma proposta que ainda espera aprovação (ela é descartada; o histórico fica na auditoria).
  Future<void> recusarConfig(String versaoId, String motivo);

  // F7.6 auditoria
  Future<PaginaAuditoria> listarAuditoria({
    String? acao,
    String? ator,
    String? entidade,
    DateTime? desde,
    DateTime? ate,
    int limite = 25,
    int deslocamento = 0,
  });
  Future<ResultadoCadeia> verificarCadeia();

  // Módulo 1: Dashboard
  /// Período: os últimos [dias] ou o intervalo [inicio]–[fim] (personalizado).
  Future<MetricasDashboard> metricasDashboard({int dias = 30, DateTime? inicio, DateTime? fim});
  Future<SeriesDashboard> seriesDashboard({int dias = 30, DateTime? inicio, DateTime? fim});

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
  Future<void> desbloquearConta(String usuarioId, {required String motivo});
  Future<void> travarSaque(String usuarioId, {required String motivo});
  Future<void> destravarSaque(String usuarioId, {required String motivo});

  /// Assume o alerta: ele vai para "Em análise" com a pessoa como responsável.
  Future<void> assumirAlertaRisco(String alertaId, {required String motivo});

  /// [resultado]: "procedente" ou "improcedente".
  Future<void> resolverAlertaRisco(String alertaId, {required String resultado, required String motivo});

  // Módulo 4: Notificações em Massa & Campanhas
  Future<List<CampanhaNotificacao>> listarCampanhasNotificacao();
  Future<EstimativaCampanha> estimarCampanhaNotificacao({
    required String segmento,
    required String tipo,
    String? categoriaId,
    String? cidadeId,
  });
  Future<CampanhaNotificacao> dispararCampanhaNotificacao({
    required String titulo,
    required String mensagem,
    required String segmento,
    String tipo = 'marketing',
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
    int? limitePorUsuario,
    String? validoDesde,
    String? validoAte,
    String? campanha,
    required String motivo,
  });
  Future<CupomAdmin> alterarStatusCupom(String cupomId, {required bool ativo, required String motivo});
  Future<void> excluirCupom(String cupomId, {required String motivo});

  // Módulo 6: Equipe Interna
  Future<List<MembroEquipeAdmin>> listarEquipe();

  /// Teto de alçada de cada papel, em centavos (RP-02).
  Future<Map<String, int>> tetosDosPapeis();
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

  // Financeiro: contestações, alertas, conciliação com o provedor e fechamento do mês.
  // Tudo leitura ou registro: nada aqui move dinheiro nem marca "pago" (D13).

  /// [status]: `em_aberto`, `aberta`, `em_analise`, `ganha`, `perdida` ou `encerrada`; nulo = todas.
  Future<List<ContestacaoCartao>> listarContestacoes({String? status});
  Future<AlertasFinanceiros> alertasFinanceiros();

  /// Pergunta ao provedor como está a cobrança. Não muda nada no Trato.
  Future<ConsultaCobranca> consultarCobranca(String cobrancaId);
  Future<ConciliacaoDia> conciliacaoDoDia(DateTime dia);
  Future<List<EventoProvedor>> listarEventosProvedor({int limite = 50});
  Future<List<MesFinanceiro>> listarMeses({int ultimos = 12});
  Future<FechamentoMes> verFechamento(String mes);
  Future<FechamentoMes> fecharMes(String mes, {required String motivo});
  Future<ArquivoPronto> exportarFechamento(String mes);

  /// Extrato de recebimentos do profissional em PDF (comprovante de renda).
  Future<ArquivoPronto> extratoProfissional(
    String usuarioId, {
    required DateTime inicio,
    required DateTime fim,
    required String motivo,
  });

  // Módulo 7: Exportação de Relatórios CSV

  /// Gera o relatório ([tipo]: `financeiro`, `pedidos` ou `repasses`) e devolve o link de uso único.
  /// Toda exportação grava na auditoria quem exportou, os filtros e a data (RF-REL-03).
  Future<RelatorioPronto> solicitarRelatorio(
    String tipo, {
    DateTime? inicio,
    DateTime? fim,
    String? cidadeId,
    String formato = 'excel_br',
    required String motivo,
  });
}
