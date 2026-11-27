import 'dart:async';

import '../telas/compensacoes/modelos.dart';
import '../telas/contestacao_decisao/modelos.dart';
import '../telas/medidas/modelos.dart';
import '../telas/atendimento/modelos.dart';
import '../telas/conta/modelos.dart';
import '../telas/profissional_mei/mei.dart';
import '../telas/indicacoes/modelos.dart';
import 'servico_cep.dart';
import '../telas/recorrencias/modelos.dart';
import 'servico_indicacoes_api.dart';
import 'servico_recorrencias_api.dart';
import 'servico_conta_api.dart';
import '../dispositivo/captura_check_in_dispositivo.dart';
import '../dispositivo/servico_camera.dart';
import '../dispositivo/servico_localizacao.dart';
import '../telas/aditivo/aditivo.dart';
import '../telas/disputa_acordo/acordo.dart';
import '../telas/disputa_profissional/disputa.dart';
import '../telas/lgpd/modelos.dart';
import '../telas/mensagens/modelos.dart';
import '../telas/nota_material/nota_material.dart';
import '../telas/perfil_publico/perfil_publico.dart';
import '../telas/profissional_cadastro/cadastro.dart';
import '../telas/verificacao/verificacao.dart';
import 'cache_leitura.dart';
import 'cliente_api.dart';
import 'config_publica.dart';
import 'fila_offline.dart';
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
    this.acordoDisputa,
    this.cadastroProfissional,
    this.perfilPublico,
    this.primeirosPassos,
    this.privacidade,
    this.conta,
    this.mei,
    this.indicacoes,
    this.recorrencias,
    this.cep,
    this.sac,
    this.medidas,
    this.compensacoes,
    this.contestacaoDecisao,
    this.mensagens,
    this.mensagensProfissional,
    required this.catalogo,
    required this.servicos,
    required this.agenda,
    this.modoApi = false,
  });

  final ServicoDisputaProfissional? disputaProfissional;

  /// Proposta de devolução e acordo da disputa (Termos 8.2).
  final ServicoAcordoDisputa? acordoDisputa;
  final ServicoCadastroProfissional? cadastroProfissional;
  final ServicoPerfilPublico? perfilPublico;

  /// Trilha dos primeiros passos do profissional (só na API real).
  final ServicoPrimeirosPassosApi? primeirosPassos;
  final ServicoPrivacidade? privacidade;

  /// Dados pessoais, endereços, favoritos e contatos de confiança (`/v1/me/...`).
  final ServicoConta? conta;

  /// CNPJ do profissional (`/v1/profissional/mei`). Nulo = demonstração: a tela não aparece.
  final ServicoMei? mei;

  /// Indique e ganhe (`/v1/indicacoes/...`). Nulo = demonstração.
  final ServicoIndicacoes? indicacoes;

  /// Serviço recorrente (`/v1/recorrencias`). Nulo = demonstração.
  final ServicoRecorrencias? recorrencias;

  /// Medidas da conta (`/v1/me/medidas`). Nulo = demonstração.
  final ServicoMedidas? medidas;

  /// Compensações do profissional (`/v1/me/compensacoes`). Nulo = demonstração.
  final ServicoCompensacoes? compensacoes;

  /// Contestação da decisão de disputa (Termos 8.7). Nulo = demonstração.
  final ServicoContestacaoDecisao? contestacaoDecisao;

  /// "Falar com o Trato" (`/v1/sac/chamados`). Nulo = demonstração.
  final ServicoSac? sac;

  /// Consulta de endereço por CEP (`GET /v1/cep/{cep}`).
  final ServicoCep? cep;

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
    FilaOffline? fila,
  }) {
    // Termos 14.12: a localização só é lida no check-in e no check-out (as capturas acima).
    // Pedido e lista do profissional vão sem posição; o endereço digitado vale sozinho.
    final pedidos = RepositorioPedidosApi(api, upload: upload);
    final profissional = RepositorioProfissionalApi(
      api,
      captura: captura,
      capturaDoPedido: capturaDoPedido,
      capturaFinalDoPedido: capturaFinalDoPedido,
      upload: upload,
      fila: fila,
    );
    // Prazos e limites para os textos das telas (sem esperar: até chegar, valem os padrões).
    unawaited(ConfigPublica.carregar(api));
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
      disputaProfissional: ServicoDisputaProfissionalApi(api, upload: upload),
      acordoDisputa: ServicoAcordoDisputaApi(api),
      cadastroProfissional: ServicoCadastroProfissionalApi(api, upload: upload),
      perfilPublico: ServicoPerfilPublicoApi(api),
      primeirosPassos: ServicoPrimeirosPassosApi(api),
      privacidade: ServicoPrivacidadeApi(api),
      conta: ServicoContaApi(api),
      mei: ServicoMeiApi(api),
      indicacoes: ServicoIndicacoesApi(api),
      recorrencias: ServicoRecorrenciasApi(api),
      cep: ServicoCepApi(api),
      sac: ServicoSacApi(api),
      medidas: ServicoMedidasApi(api),
      compensacoes: ServicoCompensacoesApi(api),
      contestacaoDecisao: ServicoContestacaoDecisaoApi(api, upload: upload),
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
    FilaOffline? fila,
    CacheLeitura? cache,
  }) {
    if (!config.usaApi) {
      throw StateError('App sem API configurada: passe TRATO_MODO=api e TRATO_API_URL.');
    }
    // Últimas leituras por usuário, para mostrar sem internet (limpas ao sair da conta).
    final api = ClienteApi(
      urlBase: config.apiUrl,
      sessao: sessao,
      cache: cache ?? CacheLeitura(CacheArquivo(), usuarioId: () => sessao.usuarioId),
    );
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
      fila: fila,
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
