import '../telas/carteira/modelos.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_orcamento.dart';
import '../telas/profissional_inicio/modelos.dart';
import 'cliente_api.dart';
import 'config.dart';
import 'repositorios.dart';
import 'repositorios_api.dart';
import 'repositorios_fake.dart';
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

  /// Modo API. Cada área usa a API quando o backend já tem a rota; as demais seguem em
  /// demonstração (lista em `docs/app-ligacao.md`). Quando a rota existir, troque o fake
  /// pelo `...Api` aqui.
  factory RepositoriosTrato.api(ClienteApi api) => RepositoriosTrato(
        pedidos: RepositorioPedidosApi(api),
        orcamentos: RepositorioOrcamentosFake(),
        pagamento: RepositorioPagamentoFake(),
        chat: RepositorioChatFake(),
        notificacoes: RepositorioNotificacoesFake(),
        perfil: RepositorioPerfilFake(),
        profissional: RepositorioProfissionalMisto(
          demonstracao: RepositorioProfissionalFake(),
          api: RepositorioProfissionalApi(api),
        ),
      );

  factory RepositoriosTrato.deConfig(ConfigTrato config, SessaoTrato sessao) => config.usaApi
      ? RepositoriosTrato.api(ClienteApi(urlBase: config.apiUrl, sessao: sessao))
      : RepositoriosTrato.demo();

  final RepositorioPedidos pedidos;
  final RepositorioOrcamentos orcamentos;
  final RepositorioPagamento pagamento;
  final RepositorioChat chat;
  final RepositorioNotificacoes notificacoes;
  final RepositorioPerfil perfil;
  final RepositorioProfissional profissional;
}

/// Profissional: o extrato vem da API (a rota existe); o resto segue em demonstração.
class RepositorioProfissionalMisto implements RepositorioProfissional {
  RepositorioProfissionalMisto({required this.demonstracao, required this.api});

  final RepositorioProfissional demonstracao;
  final RepositorioProfissional api;

  @override
  Future<InicioProfissional> inicio() => demonstracao.inicio();

  @override
  Future<DetalhePedido> detalhe(String pedidoId) => demonstracao.detalhe(pedidoId);

  @override
  Future<void> recusar(String pedidoId, MotivoRecusa motivo) =>
      demonstracao.recusar(pedidoId, motivo);

  @override
  Future<List<ItemExtrato>> extrato() => api.extrato();

  @override
  ServicoOrcamento servicoOrcamento(String pedidoId) => demonstracao.servicoOrcamento(pedidoId);

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId) => demonstracao.servicoCheckIn(pedidoId);
}
