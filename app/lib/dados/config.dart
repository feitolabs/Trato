/// Configuração de execução do app. Tudo vem de `--dart-define`; nada de chave no código.
///
/// - `TRATO_MODO=demo|api` (padrão `demo`): demo usa dados de exemplo e não toca na rede.
/// - `TRATO_API_URL=https://...`: endereço base da API (só vale no modo `api`).
enum ModoTrato { demo, api }

class ConfigTrato {
  const ConfigTrato({required this.modo, this.apiUrl = ''});

  /// Lê os `--dart-define` da compilação.
  factory ConfigTrato.doAmbiente() => ConfigTrato(
        modo: _modo(const String.fromEnvironment('TRATO_MODO', defaultValue: 'demo')),
        apiUrl: const String.fromEnvironment('TRATO_API_URL'),
      );

  const ConfigTrato.demo() : this(modo: ModoTrato.demo);

  final ModoTrato modo;
  final String apiUrl;

  /// Modo `api` sem URL cai em demo: melhor abrir o app do que quebrar.
  bool get usaApi => modo == ModoTrato.api && apiUrl.isNotEmpty;

  static ModoTrato _modo(String texto) =>
      texto.trim().toLowerCase() == 'api' ? ModoTrato.api : ModoTrato.demo;
}
