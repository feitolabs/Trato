import '../dispositivo/captura_check_in_dispositivo.dart';
import '../dispositivo/servico_camera.dart';
import '../dispositivo/servico_localizacao.dart';
import '../telas/aditivo/aditivo.dart';
import '../telas/nota_material/nota_material.dart';
import '../telas/verificacao/verificacao.dart';
import 'cliente_api.dart';
import 'config.dart';
import 'repositorios.dart';
import 'repositorios_api.dart';
import 'repositorios_fake.dart';
import 'servico_upload.dart';
import 'servicos_api.dart';
import 'sessao.dart';

/// Todos os repositórios do app num lugar só. O `rotas.dart` entrega o que precisa a cada
/// tela; as telas não sabem se estão falando com a API ou com dados de exemplo.
class RepositoriosTrato {
  const RepositoriosTrato({
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
  });

  /// Modo demonstração: só dados de exemplo, sem rede.
  factory RepositoriosTrato.demo() => RepositoriosTrato(
        pedidos: RepositorioPedidosFake(),
        orcamentos: RepositorioOrcamentosFake(),
        pagamento: RepositorioPagamentoFake(),
        chat: RepositorioChatFake(),
        notificacoes: RepositorioNotificacoesFake(),
        perfil: RepositorioPerfilFake(),
        profissional: RepositorioProfissionalFake(),
      );

  /// Modo API. Cada área usa a API quando o backend já tem a rota; o que não tem rota segue em
  /// demonstração (lista em `docs/app-ligacao.md` e `docs/app-divergencias.md`).
  /// [captura] e [upload] (câmera e envio por URL assinada) são usados no check-in e na
  /// verificação; sem eles o app não captura nada.
  factory RepositoriosTrato.api(
    ClienteApi api, {
    CapturaCheckIn captura = const CapturaIndisponivel(),
    CapturaCheckIn Function(String pedidoId)? capturaDoPedido,
    ServicoUpload? upload,
    ServicoCamera? camera,
  }) =>
      RepositoriosTrato(
        pedidos: RepositorioPedidosApi(api),
        orcamentos: RepositorioOrcamentosApi(api),
        pagamento: RepositorioPagamentoApi(api),
        chat: RepositorioChatApi(api),
        notificacoes: RepositorioNotificacoesApi(api),
        perfil: RepositorioPerfilApi(api),
        profissional: RepositorioProfissionalApi(
          api,
          captura: captura,
          capturaDoPedido: capturaDoPedido,
          upload: upload,
        ),
        aditivo: ServicoAditivoApi(api),
        notaMaterial: ServicoNotaMaterialApi(api),
        verificacao: ServicoVerificacaoApi(api),
        capturaVerificacao:
            camera != null && upload != null ? CapturaVerificacao(camera, upload) : null,
      );

  factory RepositoriosTrato.deConfig(
    ConfigTrato config,
    SessaoTrato sessao, {
    CapturaCheckIn captura = const CapturaIndisponivel(),
    ServicoUpload Function(ClienteApi api)? criarUpload,
    ServicoCamera? camera,
    ServicoLocalizacao? localizacao,
  }) {
    if (!config.usaApi) return RepositoriosTrato.demo();
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
      upload: upload,
      camera: camera,
    );
  }

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
}
