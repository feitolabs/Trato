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
}
