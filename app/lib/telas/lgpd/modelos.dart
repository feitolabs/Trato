/// Um consentimento que a pessoa pode ver (e, se não for obrigatório, desligar).
class Consentimento {
  const Consentimento({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.ativo,
    this.obrigatorio = false,
  });

  final String id;
  final String titulo;
  final String descricao;
  final bool ativo;

  /// Necessário para o app funcionar (ex.: dados do pedido): aparece, mas não desliga.
  final bool obrigatorio;
}

/// Contrato com o backend. Exportar e excluir só pedem; quem executa, registra e decide
/// o que a lei manda reter é o backend.
abstract interface class ServicoPrivacidade {
  Future<List<Consentimento>> consentimentos();
  Future<void> alterarConsentimento(String id, {required bool ativo});

  /// Pede a cópia dos dados. O backend avisa quando estiver pronta.
  Future<void> solicitarExportacao();

  /// Pede a exclusão da conta (só depois da confirmação em 2 passos).
  Future<void> solicitarExclusao();
}
