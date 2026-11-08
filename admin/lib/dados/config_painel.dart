import 'defines_publicos.dart';
import 'package:http/http.dart' as http;

import 'api_admin.dart';
import 'api_http.dart';

/// Como o painel escolhe a API. Tudo vem de `--dart-define` na hora de rodar ou compilar:
///
/// ```
/// flutter run -d chrome \
///   --dart-define=ADMIN_MODO=api \
///   --dart-define=ADMIN_API_URL=https://api.exemplo.com.br \
///   --dart-define=ADMIN_SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=ADMIN_SUPABASE_ANON_KEY=<chave pública (anon)>
/// ```
///
/// `ADMIN_AMBIENTE=producao` só no ambiente real; sem isso o painel mostra a faixa de teste.
///
/// O painel só fala com a API real: sem `ADMIN_MODO=api` e os três valores, ele não abre.
/// Nunca ponha a chave de serviço (service role) aqui: o painel só usa a chave pública.
class ConfigPainel {
  const ConfigPainel({
    this.modo = '',
    this.urlApi = '',
    this.urlSupabase = '',
    this.chaveAnon = '',
    this.ambiente = '',
    this.atualizarSegundos = '',
  });

  /// Lê os `--dart-define` pela lista permitida (M14): em debug, segredo para o painel; em release é ignorado.
  factory ConfigPainel.doAmbiente() => ConfigPainel.deValores(filtrarDefines(lerDefinesDoAmbiente()));

  factory ConfigPainel.deValores(Map<String, String> v) => ConfigPainel(
        modo: v['ADMIN_MODO'] ?? '',
        urlApi: v['ADMIN_API_URL'] ?? '',
        urlSupabase: v['ADMIN_SUPABASE_URL'] ?? '',
        chaveAnon: v['ADMIN_SUPABASE_ANON_KEY'] ?? '',
        ambiente: v['ADMIN_AMBIENTE'] ?? '',
        atualizarSegundos: v['ADMIN_ATUALIZAR_SEGUNDOS'] ?? '',
      );

  final String modo;
  final String urlApi;
  final String urlSupabase;
  final String chaveAnon;

  /// `producao` esconde a faixa de ambiente. Qualquer outro valor (ou vazio) mostra a faixa fixa
  /// "Ambiente de teste" (RNF-07): na dúvida, a pessoa vê que não é produção.
  final String ambiente;

  /// `ADMIN_ATUALIZAR_SEGUNDOS`: de quanto em quanto tempo as filas da Operação se atualizam
  /// sozinhas. Vazio ou inválido = 60 s; `0` desliga (continua atualizando ao voltar para a aba).
  final String atualizarSegundos;

  Duration get intervaloAtualizacao {
    final n = int.tryParse(atualizarSegundos.trim());
    if (n == null || n < 0) return const Duration(seconds: 60);
    // Abaixo de 15 s a fila martela o backend sem ganho para quem analisa.
    return n == 0 ? Duration.zero : Duration(seconds: n < 15 ? 15 : n);
  }

  bool get ehProducao => ambiente.trim().toLowerCase() == 'producao';

  bool get usaApi =>
      modo.trim().toLowerCase() == 'api' && urlApi.isNotEmpty && urlSupabase.isNotEmpty && chaveAnon.isNotEmpty;
}

/// Cria o cliente da API real. Configuração incompleta é erro: não existe dado de exemplo.
ApiAdmin criarApi(ConfigPainel config, {http.Client? cliente}) {
  if (!config.usaApi) {
    throw StateError('Painel sem API configurada: passe ADMIN_MODO=api, ADMIN_API_URL, ADMIN_SUPABASE_URL e ADMIN_SUPABASE_ANON_KEY.');
  }
  return ApiAdminHttp(
    urlApi: config.urlApi,
    urlSupabase: config.urlSupabase,
    chaveAnonSupabase: config.chaveAnon,
    cliente: cliente,
  );
}
