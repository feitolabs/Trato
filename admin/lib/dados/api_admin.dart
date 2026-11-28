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

  /// Pede o e-mail de redefinição de senha. Não diz se o e-mail existe (a tela mostra mensagem neutra).
  /// O link do e-mail volta para o próprio painel.
  Future<void> pedirRecuperacaoSenha(String email);

  /// Define a senha nova com o token do link de recuperação. O token só vive em memória.
  /// Link vencido ou senha recusada viram [ErroApi] com texto claro.
  Future<void> definirNovaSenha(String token, String novaSenha);

  // F7.1 verificação
  /// Uma página da fila, filtrada no servidor. [status] vazio = todos; [busca] casa o nome ou o
  /// id curto (PRO-XXXX). Ordem: envio mais antigo primeiro.
  Future<PaginaRemota<Verificacao>> listarVerificacoes({
    List<StatusVerificacao> status = const [],
    String busca = '',
    int deslocamento = 0,
    int limite = 50,
  });

  /// Quantas verificações há em cada status (para os contadores dos filtros).
  Future<Map<StatusVerificacao, int>> contarVerificacoes();

  /// Assume a análise. Se outra pessoa já assumiu, o backend recusa (409), a menos que
  /// [substituir] seja true.
  Future<void> assumirVerificacao(String id, {required String motivo, bool substituir = false});

  /// Devolve a URL assinada de curta duração (ou null, no exemplo).
  Future<String?> revelarDocumento(String verificacaoId, String documento, String motivo);
  Future<void> decidirVerificacao(String id, {required bool aprovar, required String motivo});

  // F7.2 disputas
  /// Uma página da fila, leve: sem evidências nem linha do tempo (vêm em [obterDisputa]).
  /// [situacao]: `abertas`, `decididas` ou `todas`. Ordem: prazo de decisão mais curto primeiro.
  Future<PaginaRemota<Disputa>> listarDisputas({
    String situacao = 'abertas',
    int deslocamento = 0,
    int limite = 50,
  });

  /// O caso completo, com evidências e linha do tempo.
  Future<Disputa> obterDisputa(String id);

  // Pedidos de informação adicional em disputas (Termos 8.4).
  Future<List<PedidoInfoDisputa>> listarPedidosInfoDisputa(String disputaId);
  Future<PedidoInfoDisputa> solicitarInfoDisputa(
    String disputaId, {
    required String destinatarioPapel,
    required String mensagem,
  });
  Future<PedidoInfoDisputa> encerrarPedidoInfoSemResposta(
    String disputaId,
    String pedidoInfoId, {
    required String motivo,
  });

  // Faltas e cancelamentos repetidos de profissionais (Termos 7.7). Pede `disputas_ver`.
  Future<List<FaltaRepetidaProfissional>> listarFaltasRepetidas({int dias = 90, int minimo = 2});

  // Eventos externos / força maior (Termos 7.8 e 22.6).
  Future<PaginaRemota<EventoForcaMaior>> listarForcaMaior({
    String? status = 'pendente',
    int deslocamento = 0,
    int limite = 20,
  });
  Future<EventoForcaMaior> decidirForcaMaior(
    String eventoId, {
    required String decisao,
    required String justificativa,
    required String chaveIdempotencia,
  });

  Future<({int abertas, int decididas})> contarDisputas();

  /// Assume a análise da disputa. Se outra pessoa já assumiu, o backend recusa (409), a menos que
  /// [substituir] seja true.
  Future<void> assumirDisputa(String id, {required String motivo, bool substituir = false});

  /// [estadoEsperado]: o estado que a pessoa viu. Se a disputa mudou desde então, o backend
  /// recusa (409) e nada se move.
  Future<ResultadoDecisao> decidirDisputa(
    String id, {
    required DecisaoDisputa decisao,
    int? valorReembolsoCentavos,
    required String justificativa,
    StatusDisputa? estadoEsperado,
  });

  /// Segunda pessoa (outra, não quem decidiu) aprova uma decisão acima da alçada.
  Future<ResultadoDecisao> aprovarDisputa(String id, {required String justificativa});

  /// Falha do Trato numa exclusividade paga pelo cliente (Termos 13.6): o backend devolve os
  /// Tratinhos. `resultado` é `ok` ou `ja_devolvida`. Pede `disputas_decidir`.
  Future<({String resultado, int moedasDevolvidas})> registrarFalhaTrato(String exclusividadeId,
      {required String motivo});

  /// Contestação da decisão de disputa (Termos 8.7). Ver: `disputas_ver`; registrar:
  /// `sac_responder`; decidir: `disputas_decidir`; aprovar: `disputas_segunda_pessoa`.
  Future<PaginaRemota<ContestacaoDisputa>> listarContestacoesDisputa(FiltroContestacoes filtro,
      {int deslocamento = 0, int limite = 50});
  Future<ContestacaoDisputa> obterContestacaoDisputa(String id);

  /// `repetida` = o servidor devolveu a mesma contestação já registrada.
  Future<({ContestacaoDisputa contestacao, bool repetida})> registrarContestacaoDisputa(
      {required String pedidoId,
      required String contestanteId,
      required String chamadoId,
      required String oQueFaltou,
      List<String> anexos = const []});
  Future<ContestacaoDisputa> decidirContestacaoDisputa(String id,
      {required String resultado, required String resposta, String? novaDecisao, int? novoValorReembolsoCentavos});
  Future<ContestacaoDisputa> aprovarContestacaoDisputa(String id, {required bool aprovar, required String motivo});

  /// Pedidos de volta ao profissional (17.4). Ver e propor: `regresso_propor`; aprovar e
  /// recusar: `regresso_aprovar`. `resultado`: `ok` ou `ja_proposta`/`ja_aprovada`/`ja_recusada`.
  Future<PaginaRemota<Regresso>> listarRegressos({String? status, int deslocamento = 0, int limite = 50});
  Future<({String resultado, Regresso proposta})> proporRegresso(
      {required String pedidoId, required String referencia, required int valorCentavos, required String motivo});
  Future<({String resultado, Regresso proposta, bool avisado})> aprovarRegresso(String id);
  Future<({String resultado, Regresso proposta})> recusarRegresso(String id, {required String motivo});

  /// Incidentes de segurança (Termos 9.3 a 9.6). Ver: `incidentes_ver`; registrar, medida e
  /// situação: `incidentes_tratar`; encerrar: `incidentes_encerrar`.
  Future<PaginaRemota<Incidente>> listarIncidentes(
      {String? status, String? pedidoId, int deslocamento = 0, int limite = 50});
  Future<Incidente> obterIncidente(String id);
  /// `repetido` = o servidor devolveu o incidente de um toque repetido (5 minutos).
  Future<({Incidente incidente, bool repetido})> registrarIncidente(
      {required String tipo, required String descricao, required String contato, required String canal, String? pedidoId});
  Future<Incidente> adicionarMedidaIncidente(String id, {required String tipo, required String descricao});

  /// [status]: `cautela_adotada` ou `em_apuracao`.
  Future<Incidente> mudarStatusIncidente(String id, String status);
  Future<Incidente> encerrarIncidente(String id, {required String desfecho});

  /// Moderação e revisão de avaliações (Termos 12.6, 12.7 e 20.5). Tudo pede `avaliacoes_moderar`.
  Future<PaginaRemota<RevisaoAvaliacao>> listarRevisoesAvaliacao(
      {String? status, String? avaliacaoId, int deslocamento = 0, int limite = 50});
  Future<RevisaoAvaliacao> analisarRevisaoAvaliacao(String revisaoId);
  Future<RevisaoAvaliacao> decidirRevisaoAvaliacao(
    String revisaoId, {
    required String status,
    required String resposta,
    String? ocultarMotivo,
    String? mesmoAnalistaJustificativa,
    String? justificativaAdiamento,
  });
  Future<OcultacaoAvaliacao> ocultarAvaliacao(
    String avaliacaoId, {
    required String motivo,
    required String explicacao,
    String? justificativaAdiamento,
  });

  /// Envia o aviso adiado (ou que falhou) ao autor da avaliação oculta (Termos 11.8).
  Future<OcultacaoAvaliacao> avisarAutorAvaliacao(String avaliacaoId);
  Future<OcultacaoAvaliacao> reverterOcultacaoAvaliacao(String avaliacaoId, {required String motivo});

  /// Pedidos de titular LGPD e revisão automatizada (Termos 14.9 e 14.10).
  Future<PaginaRemota<PedidoTitularLgpd>> listarPedidosLgpd(
      {String? status, String? tipo, String? usuarioId, int deslocamento = 0, int limite = 50});
  Future<PedidoTitularLgpd> analisarPedidoLgpd(String pedidoId);
  Future<PedidoTitularLgpd> responderPedidoLgpd(
    String pedidoId, {
    required String status,
    required String resposta,
    String? motivoNaoAtendido,
    String? criteriosInformados,
  });

  /// Contestação de materiais (Termos 6.9). Permissão `materiais_contestacao_analisar`.
  /// A aprovação financeira não é chamada pelo painel.
  Future<PaginaRemota<ContestacaoMaterial>> listarContestacoesMaterial(
      {String? status, String? pedidoId, int deslocamento = 0, int limite = 50});
  Future<ContestacaoMaterial> analisarContestacaoMaterial(String contestacaoId);

  /// Links curtos da foto da nota e das provas. O acesso é auditado com o motivo (10 a 2000).
  Future<List<AnexoMaterial>> abrirAnexosContestacaoMaterial(String contestacaoId, {required String motivo});

  /// `valorReconhecidoCentavos` só vai na decisão `parcial`; nas outras o backend define.
  Future<ContestacaoMaterial> decidirContestacaoMaterial(String contestacaoId,
      {required String status, required String resposta, int? valorReconhecidoCentavos});

  /// Retorno de conta e impedimentos de cadastro (Termos 20.9).
  Future<PaginaRemota<PedidoRetornoConta>> listarRetornosConta(
      {String? status, String? usuarioId, int deslocamento = 0, int limite = 50});
  Future<PedidoRetornoConta> analisarRetornoConta(String retornoId);
  Future<PedidoRetornoConta> aprovarRetornoConta(String retornoId, {required String motivo});
  Future<PedidoRetornoConta> recusarRetornoConta(String retornoId,
      {required String motivo, required bool riscoIdentificado});
  Future<PaginaRemota<ImpedimentoCadastro>> listarImpedimentosConta(
      {String? medidaId, bool apenasAtivos = false, int deslocamento = 0, int limite = 50});
  Future<ImpedimentoCadastro> revogarImpedimentoConta(String impedimentoId, {required String motivo});

  /// Compensações (Termos 8.6). Ver, registrar e avisar: `disputas_decidir`; cancelar:
  /// `compensacoes_cancelar`.
  Future<PaginaRemota<Compensacao>> listarCompensacoes(
      {String? profissionalId,
      String? pedidoId,
      String? status,
      bool revisaoPendente = false,
      int deslocamento = 0,
      int limite = 50});

  /// `resultado`: `ok` ou `ja_registrada`.
  Future<({String resultado, Compensacao compensacao, bool avisado})> registrarCompensacao(
      {required String pedidoId, String? contestacaoId, required int valorCentavos, required String motivo});
  Future<({Compensacao compensacao, bool avisado})> avisarCompensacao(String id);

  /// `resultado`: `ok` ou `ja_cancelada`.
  /// Contestação reduziu a decisão: baixa a dívida sem novo estorno. Mesma permissão do cancelar.
  Future<({String resultado, int devolvidoCentavos, Compensacao compensacao})> reduzirCompensacao(String id,
      {required String contestacaoId, required int novoValorCentavos, required String motivo});

  Future<({String resultado, int devolvidoCentavos, Compensacao compensacao})> cancelarCompensacao(String id,
      {required String motivo});

  Future<PaginaRemota<ExclusividadeCliente>> listarExclusividades(
      {String? pedidoId, String? clienteId, String? status, int deslocamento = 0, int limite = 20});

  /// Medidas de conta (Termos 20). Tudo pede `medidas_aplicar`.
  Future<PaginaRemota<Medida>> listarMedidas(FiltroMedidas filtro, {int deslocamento = 0, int limite = 50});
  Future<Medida> obterMedida(String id);

  /// Prazo máximo (dias) configurado para a trava de saque por fraude. Pede `medidas_aplicar`.
  Future<int> prazoMaximoTravaFraude();

  /// `repetida` = o servidor devolveu a medida igual criada há menos de 5 minutos.
  Future<({Medida medida, bool repetida})> aplicarMedida(NovaMedida nova);
  Future<Medida> reverterMedida(String id, {required String motivo});

  /// Contestação recebida pelo atendimento. [anexos]: ids já enviados por [pedirAnexoContestacao].
  Future<Medida> registrarContestacaoMedida(String id, {required String versao, List<String> anexos = const []});
  Future<EnvioAssinado> pedirAnexoContestacao(String medidaId,
      {required String nomeArquivo, required String tipoConteudo, required int tamanhoBytes});

  /// Links curtos das provas. O backend grava o acesso na auditoria com o [motivo].
  Future<List<AnexoContestacao>> abrirAnexosContestacao(String medidaId, {required String motivo});

  /// Envia os bytes para o link assinado (PUT), sem o token de login. Só aceita https.
  Future<void> enviarArquivo(String url, {required String tipoConteudo, required List<int> bytes});

  /// Comprovantes da retenção por ausência. Pede `disputas_decidir`; o [motivo] vai no corpo.
  Future<List<ArquivoComprovante>> listarComprovantes(String pedidoId, {required String motivo});
  Future<EnvioAssinado> pedirEnvioComprovante(String pedidoId,
      {required String motivo, required String nomeArquivo, required String tipoConteudo, required int tamanhoBytes});
  Future<ArquivoComprovante> concluirComprovante(String pedidoId, String envioId, {required String motivo});
  Future<Medida> decidirContestacaoMedida(String id,
      {required String resultado, required String resposta, int? diasAPartirDeHoje, String? mesmoAnalistaJustificativa});

  /// Fila de "Cliente ausente" (Termos 7.6). Ver pede `disputas_ver`; decidir, `disputas_decidir`.
  Future<List<CasoAusencia>> listarAusencias();
  Future<CasoAusencia> obterAusencia(String pedidoId);
  Future<CasoAusencia> decidirAusencia(
    String pedidoId, {
    required bool aceitarJustificativa,
    required String justificativa,
    int retencaoCentavos = 0,
    String? retencaoJustificativa,
    List<String> retencaoComprovantes = const [],
  });

  /// Cancela com a retenção já mostrada ao cliente, ou sem ela ([retirarRetencao]).
  Future<CasoAusencia> confirmarAusencia(String pedidoId,
      {required bool retirarRetencao, required String motivo});

  /// Provas do caso com links de 300 s. O backend grava o acesso na auditoria com o [motivo].
  Future<List<AnexoCaso>> anexosAusencia(String pedidoId, {required String motivo});

  /// Responde a contestação da retenção. [resultado]: `mantida`, `alterada` ou `revertida`.
  Future<CasoAusencia> decidirContestacaoAusencia(String pedidoId,
      {required String resultado, required String resposta, int? retencaoCentavos});

  /// Mensagens de um pedido (Termos 11.3). Pede `conversas_ler`; o acesso fica na auditoria.
  Future<List<ConversaLida>> lerConversas(String pedidoId,
      {required String motivo, required String base, String? referencia});

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
  /// [motivoUsuario] e [clausulas] vão para a medida criada: é o que o usuário lê (20.4).
  /// Selo do profissional (Termos 10.3). [operacao]: `retirar`, `reconferencia` (pedem
  /// `selo_retirar`) ou `regularizar` (pede `selo_regularizar`).
  Future<ResultadoSeloAdmin> mudarSelo(String usuarioId, String operacao,
      {required String motivo, required String chaveIdempotencia});

  /// Devolve o resumo dos pedidos (vale quando a conta passa a bloqueada); null se não vier.
  Future<ResumoPedidos?> alterarStatusUsuario(String usuarioId,
      {required String status, required String motivo, String? motivoUsuario, List<String> clausulas = const []});

  /// Inativa conta por falta de uso após aviso prévio de 30 dias (Termos 4.9). Pede `usuarios_status`.
  Future<UsuarioBusca> inativarUsuario(String usuarioId, {required String motivo});

  /// Reativa conta inativa gratuitamente, sem medida punitiva (Termos 4.9). Pede `usuarios_status`.
  Future<UsuarioBusca> reativarUsuario(String usuarioId, {required String motivo});
  Future<List<PedidoBusca>> buscarPedidos(String termo);
  /// Fila do atendimento, na ordem do servidor (prazo mais próximo; encerrados no fim).
  /// Ver pede `suporte_ver`; as demais ações, `sac_responder`.
  Future<PaginaRemota<Chamado>> listarChamados(FiltroChamados filtro, {int deslocamento = 0, int limite = 50});
  Future<Chamado> obterChamado(String id);
  Future<Chamado> registrarContato(NovoContato contato);
  Future<Chamado> assumirChamado(String id, {bool substituir = false});
  Future<Chamado> responderChamado(String id, {required String texto, bool interna = false, bool aguardarUsuario = false});
  Future<Chamado> estenderPrazoChamado(String id, {required DateTime ate, required String motivo});
  Future<Chamado> encerrarChamado(String id, {required String mensagem});
  Future<List<CategoriaAdmin>> listarCategorias();
  Future<CategoriaAdmin> criarCategoria({
    required String nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int ordem = 0,
    bool ativa = true,
    bool aceitaRemoto = false,
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
    bool? aceitaRemoto,
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
  Future<void> aplicarBloqueioPreventivo(String usuarioId,
      {required String motivo, String? motivoUsuario, List<String> clausulas = const []});
  Future<void> desbloquearConta(String usuarioId, {required String motivo});
  /// A trava registra a medida e restringe a conta. Só a trava por fraude (com limite) adia a
  /// liberação no livro; pagamento manual ou no Stripe não é bloqueado.
  /// As duas ações devolvem a `mensagem` do backend (null se não vier), para mostrar na tela.
  Future<String?> travarSaque(String usuarioId,
      {required String motivo,
      String? motivoUsuario,
      List<String> clausulas = const [],
      bool motivoFraude = false,
      int? limiteRetencaoCentavos,
      int? dias});
  Future<String?> destravarSaque(String usuarioId, {required String motivo});

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

  // Falhas da plataforma (Termos 22.3). Pede `indisponibilidades_gerenciar`. Datas vão em ISO com fuso.
  Future<PaginaRemota<JanelaIndisponibilidade>> listarIndisponibilidades(
      {String? origem, bool abertas = false, int deslocamento = 0, int limite = 20});

  /// [repetida]: o servidor respondeu 200 (registro idêntico já existia).
  Future<({JanelaIndisponibilidade janela, bool repetida})> registrarIndisponibilidade(
      {required String origem, required String inicioEm, String? fimEm, required String motivo});

  /// [fimEm] nulo = agora.
  Future<JanelaIndisponibilidade> encerrarIndisponibilidade(String id, {String? fimEm, required String motivo});

  // Fila de check-out sem o Código Final (Termos 5.7, fase 1). Pede `checkout_sem_codigo_tratar`.
  Future<PaginaRemota<CasoCheckoutSemCodigo>> listarCheckoutSemCodigo({int deslocamento = 0, int limite = 20});
  Future<CasoCheckoutSemCodigo> registrarContatoCheckoutSemCodigo(
    String casoId, {
    required String canal,
    required String motivo,
  });
  Future<ResultadoDecisaoCheckoutSemCodigo> decidirCheckoutSemCodigo(
    String casoId, {
    required String decisao,
    required String motivo,
    required String chaveIdempotencia,
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

  // Moedas: orçamento do mês e configuração do programa.
  Future<MoedasOrcamento> orcamentoMoedas();
  Future<MoedasConfig> carregarMoedasConfig();

  /// Grava a configuração. O backend valida, decide e audita; [motivo] é obrigatório.
  Future<MoedasConfig> salvarMoedasConfig(MoedasConfig config, {required String motivo, String? avisoReferencia});

  /// Saldo, pendentes e extrato de Tratinhos de um usuário (Termos I.3, 12.10, 13.9 e I.10).
  /// Pede `moedas_configurar`.
  Future<MoedasUsuario> consultarMoedasUsuario(String usuarioId, {int limite = 30});

  /// Concede Tratinhos como compensação (Termos I.3). Pede `moedas_configurar`.
  Future<ResultadoConcederMoedas> concederMoedasUsuario(
    String usuarioId, {
    required String carteira,
    required int quantidade,
    int? validadeDias,
    required String motivo,
    String? chaveIdempotencia,
    String? referenciaId,
  });

  /// Cancela Tratinhos por fraude (Termos 12.10, 13.9 e I.10). Pede `moedas_configurar`.
  Future<ResultadoCancelarFraudeMoedas> cancelarFraudeMoedasUsuario(
    String usuarioId, {
    required String carteira,
    required int quantidade,
    required bool cancelarPendentes,
    required String motivo,
    String? chaveIdempotencia,
    String? referenciaId,
  });

  /// Aviso prévio dos Tratinhos aos usuários (Termos 13.11). Pede `notificacoes_enviar`.
  Future<ResultadoAvisoPrevio> enviarAvisoTratinhos(
      {required String referencia,
      required DateTime vigencia,
      required String resumo,
      required String motivo,
      Map<String, Object> mudancas = const {}});

  /// Aviso de mudança dos Termos (23.2). Pede `notificacoes_enviar`.
  Future<ResultadoAvisoPrevio> enviarAvisoTermos(
      {required String referencia,
      required DateTime vigencia,
      required String resumo,
      required String motivo,
      required String link});

  /// Aviso manual de conta sem uso (4.9): só avisa, não inativa. Pede `notificacoes_enviar`.
  Future<ResultadoAvisoPrevio> enviarAvisoInatividade(
      {required String usuarioId, required String referencia, required DateTime vigencia});

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

  /// Baixa o arquivo do link de uso único mandando o login no cabeçalho (o token nunca vai na URL)
  /// e entrega ao navegador. Falha (link usado/vencido, sem permissão) vira erro, não aviso de sucesso.
  Future<void> baixarArquivo(String url, String nomeArquivo);

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
