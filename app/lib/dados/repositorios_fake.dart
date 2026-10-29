import '../telas/carteira/dados_exemplo.dart';
import '../telas/carteira/modelos.dart';
import '../telas/conclusao/dados_exemplo.dart';
import '../telas/orcamentos/dados_exemplo.dart';
import '../telas/pagamento/dados_exemplo.dart' as pag;
import '../telas/pagamento/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/pedidos/dados_exemplo.dart' as ped;
import '../telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/dados_exemplo.dart' as per;
import '../telas/perfil_cliente/modelos.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_check_in_fake.dart';
import '../telas/profissional/servico_orcamento.dart';
import '../telas/profissional/servico_orcamento_fake.dart';
import '../telas/profissional_inicio/dados_exemplo.dart';
import '../telas/profissional_inicio/modelos.dart';
import 'repositorios.dart';

// MODO DEMONSTRAÇÃO. Dados de exemplo das telas, sem rede. Nada aqui é regra de negócio:
// o "pago" da demonstração é simulado só para a tela poder ser mostrada.

const _idDemo = 'demo-4821';

class RepositorioPedidosFake implements RepositorioPedidos {
  final List<String> criados = [];
  final List<EnvioRelato> relatos = [];
  final List<String> retrabalhos = [];
  bool conclusaoConfirmada = false;

  @override
  Future<PedidosDoCliente> listar() async => const PedidosDoCliente(
        emAndamento: ped.DadosExemplo.pedidosEmAndamento,
        finalizados: ped.DadosExemplo.pedidosFinalizados,
      );

  @override
  Future<String> criar(RascunhoPedido rascunho) async {
    criados.add(rascunho.descricao);
    return _idDemo;
  }

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => ped.DadosExemplo.pedidoEmExecucao;

  @override
  Future<ResumoConclusao> conclusao(String pedidoId) async => resumoConclusaoExemplo;

  @override
  Future<void> confirmarConclusao(String pedidoId) async => conclusaoConfirmada = true;

  @override
  Future<DadosRelatoProblema> dadosRelato(String pedidoId) async => dadosRelatoExemplo;

  @override
  Future<void> relatarProblema(String pedidoId, EnvioRelato relato) async => relatos.add(relato);

  @override
  Future<void> avaliar(String pedidoId, EnvioAvaliacao avaliacao) async {}

  @override
  Future<DadosAvaliacao> dadosAvaliacao(String pedidoId) async => dadosAvaliacaoExemplo;

  @override
  Future<DadosGarantia> garantia(String pedidoId) async => dadosGarantiaExemplo;

  @override
  Future<void> pedirRetrabalho(String pedidoId, String descricao) async =>
      retrabalhos.add(descricao);
}

class RepositorioOrcamentosFake implements RepositorioOrcamentos {
  final List<String> aceitos = [];

  @override
  Future<OrcamentosDoPedido> listar(String pedidoId) async =>
      OrcamentosDoPedido(pedido: resumoPedidoExemplo, orcamentos: orcamentosExemplo);

  @override
  Future<void> aceitar(String pedidoId, String orcamentoId) async => aceitos.add(orcamentoId);
}

class RepositorioPagamentoFake implements RepositorioPagamento {
  RepositorioPagamentoFake({this.consultasAteConfirmar = 2});

  /// Quantas consultas respondem "aguardando" antes da simulação dizer "pago".
  final int consultasAteConfirmar;
  int _consultas = 0;
  final List<MetodoPagamento> cobrancas = [];

  @override
  Future<DadosPagamento> dados(String pedidoId) async => pag.DadosExemplo.pagamento;

  @override
  Future<Cobranca> criarCobranca(String pedidoId, MetodoPagamento metodo) async {
    cobrancas.add(metodo);
    _consultas = 0;
    return const Cobranca(id: 'cobranca-demo', pixCopiaECola: '00020126-DEMONSTRACAO');
  }

  @override
  Future<StatusPagamento> status(String pedidoId) async {
    _consultas++;
    return _consultas > consultasAteConfirmar ? StatusPagamento.pago : StatusPagamento.aguardando;
  }
}

class RepositorioChatFake implements RepositorioChat {
  final List<String> enviadas = [];

  @override
  Future<ConversaPedido> conversa(String pedidoId) async => ped.DadosExemplo.conversa;

  @override
  Future<void> enviar(String pedidoId, String texto) async => enviadas.add(texto);
}

class RepositorioNotificacoesFake implements RepositorioNotificacoes {
  @override
  Future<List<Notificacao>> listar() async => const [
        Notificacao(
          id: 'n1',
          titulo: 'Carlos Mendes chegou',
          texto: 'Check-in feito às 14h06. Passe o código de início para começar.',
          quando: 'há 2 h',
        ),
        Notificacao(
          id: 'n2',
          titulo: 'Novo orçamento',
          texto: 'Você recebeu 2 orçamentos para "Instalar ventilador de teto".',
          quando: 'ontem',
          lida: true,
        ),
        Notificacao(
          id: 'n3',
          titulo: 'Disputa aberta no seu serviço',
          texto: 'O cliente abriu uma disputa. Responda dentro do prazo.',
          quando: 'ontem',
          tipo: 'disputa',
          destinoId: 'disp-1',
        ),
        Notificacao(
          id: 'n4',
          titulo: 'Retrabalho pedido',
          texto: 'Escolha um horário para refazer o serviço.',
          quando: 'há 3 dias',
          tipo: 'retrabalho',
          destinoId: 'disp-1',
        ),
      ];
}

class RepositorioPerfilFake implements RepositorioPerfil {
  @override
  Future<PerfilCliente> carregar() async => per.DadosExemplo.perfil;
}

class RepositorioProfissionalFake implements RepositorioProfissional {
  /// Taxa só de demonstração; a real é decidida pelo backend (progressiva, base 7,5%).
  static const taxaDemonstracaoBps = 750;

  final List<MotivoRecusa> recusas = [];

  @override
  Future<InicioProfissional> inicio() async => inicioProfissionalExemplo;

  @override
  Future<DetalhePedido> detalhe(String pedidoId) async => detalhePedidoExemplo;

  @override
  Future<void> recusar(String pedidoId, MotivoRecusa motivo) async => recusas.add(motivo);

  @override
  Future<List<ItemExtrato>> extrato() async => DadosExemploCarteira.completo.extrato;

  @override
  ServicoOrcamento servicoOrcamento(String pedidoId) =>
      ServicoOrcamentoFake(taxaBps: taxaDemonstracaoBps);

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId) => ServicoCheckInFake();
}
