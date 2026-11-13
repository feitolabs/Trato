import '../telas/conta/modelos.dart';
import 'servico_conta_api.dart';
import '../dispositivo/captura_check_in_dispositivo.dart';
import '../dispositivo/servico_camera.dart';
import '../dispositivo/servico_localizacao.dart';
import '../telas/aditivo/aditivo.dart';
import '../telas/disputa_profissional/disputa.dart';
import '../telas/lgpd/modelos.dart';
import '../telas/mensagens/modelos.dart';
import '../telas/nota_material/nota_material.dart';
import '../telas/perfil_publico/perfil_publico.dart';
import '../telas/profissional_cadastro/cadastro.dart';
import '../telas/verificacao/verificacao.dart';
import 'cliente_api.dart';
import 'config.dart';
import 'repositorios.dart';
import 'repositorios_catalogo.dart';
import 'repositorios_catalogo_api.dart';
import 'repositorios_api.dart';
import '../telas/mensagens/servico_conversas.dart';
import 'servico_upload.dart';
import 'servicos_api.dart';
import 'sessao.dart';

/// Todos os repositórios do app num lugar só. O `rotas.dart` entrega o que precisa a cada
/// tela; as telas não sabem se estão falando com a API ou com dados de exemplo.
class RepositoriosTrato {
  RepositoriosTrato({
    required this.pedidos,
    required this.orcamentos,
    required this.pagamento,
    required this.chat,
    required this.notificacoes,
    required this.perfil,
    required this.profissional,
    this.aditivo,
    this.notaMaterial,
    this.verificacao,
    this.capturaVerificacao,
    this.disputaProfissional,
    this.cadastroProfissional,
    this.perfilPublico,
    this.privacidade,
    this.conta,
    this.mensagens,
    this.mensagensProfissional,
    required this.catalogo,
    required this.servicos,
    required this.agenda,
    this.modoApi = false,
  });

  final ServicoDisputaProfissional? disputaProfissional;
  final ServicoCadastroProfissional? cadastroProfissional;
  final ServicoPerfilPublico? perfilPublico;
  final ServicoPrivacidade? privacidade;

  /// Dados pessoais, endereços, favoritos e contatos de confiança (`/v1/me/...`).
  final ServicoConta? conta;


  /// Listas de conversas. Nulo = montadas a partir dos pedidos (o normal); testes injetam as suas.
  final ServicoMensagens? mensagens;
  final ServicoMensagens? mensagensProfissional;

  /// Modo API. Cada área usa a API quando o backend já tem a rota; o que não tem rota segue em
  /// demonstração (lista em `docs/app-ligacao.md` e `docs/app-divergencias.md`).
  /// [captura] e [upload] (câmera e envio por URL assinada) são usados no check-in e na
  /// verificação; sem eles o app não captura nada.
  factory RepositoriosTrato.api(
    ClienteApi api, {
    CapturaCheckIn captura = const CapturaIndisponivel(),
    CapturaCheckIn Function(String pedidoId)? capturaDoPedido,
    CapturaCheckIn Function(String pedidoId)? capturaFinalDoPedido,
    ServicoUpload? upload,
    ServicoCamera? camera,
    Future<PosicaoAtual?> Function()? posicao,
  }) {
    final pedidos = RepositorioPedidosApi(api, upload: upload, posicao: posicao);
    final profissional = RepositorioProfissionalApi(
      api,
      captura: captura,
      capturaDoPedido: capturaDoPedido,
      capturaFinalDoPedido: capturaFinalDoPedido,
      upload: upload,
      posicao: posicao,
    );
    return RepositoriosTrato(
        modoApi: true,
        catalogo: RepositorioCatalogoApi(api),
        servicos: RepositorioServicosClienteApi(api, pedidos),
        agenda: RepositorioAgendaApi(profissional),
        pedidos: pedidos,
        orcamentos: RepositorioOrcamentosApi(api),
        pagamento: RepositorioPagamentoApi(api),
        chat: RepositorioChatApi(api, upload: upload),
        mensagens: ServicoConversasApi(api, comoProfissional: false),
        mensagensProfissional: ServicoConversasApi(api, comoProfissional: true),
        notificacoes: RepositorioNotificacoesApi(api),
        perfil: RepositorioPerfilApi(api, upload: upload),
        profissional: profissional,
        aditivo: ServicoAditivoApi(api),
        notaMaterial: ServicoNotaMaterialApi(api, upload: upload),
        verificacao: ServicoVerificacaoApi(api),
        disputaProfissional: ServicoDisputaProfissionalApi(api),
        cadastroProfissional: ServicoCadastroProfissionalApi(api),
        perfilPublico: ServicoPerfilPublicoApi(api),
        privacidade: ServicoPrivacidadeApi(api),
        conta: ServicoContaApi(api),
        capturaVerificacao:
            camera != null && upload != null ? CapturaVerificacao(camera, upload) : null,
    );
  }

  factory RepositoriosTrato.deConfig(
    ConfigTrato config,
    SessaoTrato sessao, {
    CapturaCheckIn captura = const CapturaIndisponivel(),
    ServicoUpload Function(ClienteApi api)? criarUpload,
    ServicoCamera? camera,
    ServicoLocalizacao? localizacao,
  }) {
    if (!config.usaApi) {
      throw StateError('App sem API configurada: passe TRATO_MODO=api e TRATO_API_URL.');
    }
    final api = ClienteApi(urlBase: config.apiUrl, sessao: sessao);
    final upload = criarUpload?.call(api);
    return RepositoriosTrato.api(
      api,
      captura: captura,
      capturaDoPedido: camera != null && localizacao != null && upload != null
          ? (pedidoId) => CapturaCheckInDispositivo(
                camera: camera,
                localizacao: localizacao,
                upload: upload,
                pedidoId: pedidoId,
              )
          : null,
      capturaFinalDoPedido: camera != null && localizacao != null && upload != null
          ? (pedidoId) => CapturaCheckInDispositivo(
                camera: camera,
                localizacao: localizacao,
                upload: upload,
                pedidoId: pedidoId,
                finalidadeFoto: FinalidadeArquivo.checkOut,
              )
          : null,
      upload: upload,
      camera: camera,
      posicao: localizacao == null
          ? null
          : () async {
              try {
                return await localizacao.posicaoAtual();
              } on ErroLocalizacao {
                return null;
              }
            },
    );
  }

  /// Verdadeiro no modo `api`. Algumas telas só aparecem onde há dados de verdade por trás
  /// (ex.: conversa antes de contratar, que o backend ainda não tem).
  final bool modoApi;

  /// Só no modo API; `null` = a rota segue com o serviço de demonstração.
  final ServicoAditivo? aditivo;
  final ServicoNotaMaterial? notaMaterial;
  final ServicoVerificacao? verificacao;
  final CapturaVerificacao? capturaVerificacao;

  final RepositorioPedidos pedidos;
  final RepositorioOrcamentos orcamentos;
  final RepositorioPagamento pagamento;
  final RepositorioChat chat;
  final RepositorioNotificacoes notificacoes;
  final RepositorioPerfil perfil;
  final RepositorioProfissional profissional;

  final RepositorioCatalogo catalogo;
  final RepositorioServicosCliente servicos;
  final RepositorioAgenda agenda;
}
