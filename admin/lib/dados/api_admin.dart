import 'modelos.dart';

/// Tudo que o painel pede ao backend. A implementação real (HTTP) virá quando a API admin existir;
/// os endpoints esperados estão em docs/painel-admin.md. Nenhuma regra de dinheiro mora aqui:
/// o painel pede, o backend decide.
abstract interface class ApiAdmin {
  Future<UsuarioEquipe> entrar(String email, String senha);
  Future<void> sair();

  // F7.1 verificação
  Future<List<Verificacao>> listarVerificacoes();
  Future<void> revelarDocumento(String verificacaoId, String documento, String motivo);
  Future<void> decidirVerificacao(String id, {required bool aprovar, required String motivo});

  // F7.2 disputas
  Future<List<Disputa>> listarDisputas();
  Future<ResultadoDecisao> decidirDisputa(
    String id, {
    required DecisaoDisputa decisao,
    int? valorReembolsoCentavos,
    required String justificativa,
    String? segundaPessoaEmail,
  });

  // F7.3 pagamentos (somente leitura)
  Future<ResumoConciliacao> resumoConciliacao();
  Future<List<LancamentoEspelho>> extrato();

  // F7.4 busca, suporte, categorias
  Future<List<UsuarioBusca>> buscarUsuarios(String termo);
  Future<DadosPessoais> revelarDadosPessoais(String usuarioId, String motivo);
  Future<List<PedidoBusca>> buscarPedidos(String termo);
  Future<List<Chamado>> listarChamados();
  Future<List<CategoriaAdmin>> listarCategorias();
  Future<void> alterarCategoria(String id, {required bool ativa, required String motivo});

  // F7.5 configurações
  Future<ConfigAtual> carregarConfig();
  Future<void> proporConfig(Map<String, int> valores, String motivo);
  Future<void> aprovarConfig(String versaoId, String motivo);
  Future<void> reverterConfig(String versaoId, String motivo);

  // F7.6 auditoria
  Future<List<EntradaAuditoria>> listarAuditoria({String? acao, String? ator});
  Future<ResultadoCadeia> verificarCadeia();
}
