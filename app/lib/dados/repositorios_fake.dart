import '../auth/servico_auth.dart';
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
  final Map<String, ConversaPedido> _conversas = {};

  static String _horaAtual() {
    final agora = DateTime.now();
    return '${agora.hour}h${agora.minute.toString().padLeft(2, '0')}';
  }

  static String _normalizarId(String pedidoId) => switch (pedidoId) {
        'pedido-1' ||
        'srv-tomadas' ||
        'srv-orcamentos' ||
        'ped-tomadas' ||
        'demo' ||
        'demo-4821' =>
          'pedido-1',
        'pedido-2' || 'srv-pintura' => 'pedido-2',
        'srv-vazamento' => 'srv-vazamento',
        'srv-limpeza' => 'srv-limpeza',
        'srv-pagamento' || 'ped-luminarias' => 'srv-pagamento',
        'ped-disjuntor' => 'ped-disjuntor',
        _ => pedidoId,
      };

  static ConversaPedido _conversaInicial(String chave) => switch (chave) {
        'pedido-2' => const ConversaPedido(
            nome: 'Rafael Souza',
            iniciais: 'RS',
            numeroPedido: '#5E10',
            situacao: 'finalizado',
            respostasRapidas: ['Ficou ótimo!', 'Obrigado pelo atendimento', 'Vou avaliar agora'],
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.sistema,
                texto: 'Serviço concluído e confirmado em 02/10.',
                hora: '16h30',
              ),
              MensagemChat(
                tipo: TipoMensagem.texto,
                texto: 'Finalizei a pintura das duas demãos na sala.',
                hora: '16h20',
              ),
              MensagemChat(tipo: TipoMensagem.foto, texto: '[Depois]', hora: '16h21'),
              MensagemChat(
                tipo: TipoMensagem.texto,
                texto: 'Obrigado! Qualquer coisa me chame.',
                hora: '16h35',
              ),
            ],
          ),
        'srv-vazamento' => const ConversaPedido(
            nome: 'Joana Ribeiro',
            iniciais: 'JR',
            numeroPedido: '#B2F7',
            situacao: 'em análise',
            respostasRapidas: [
              'Podemos agendar retorno?',
              'Vou enviar foto do sifão',
              'Qual horário você pode?',
            ],
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.sistema,
                texto: 'Relato aberto · valor retido até a solução.',
                hora: '11h00',
              ),
              MensagemChat(
                tipo: TipoMensagem.texto,
                texto: 'Olá! Vi seu relato sobre o pingamento no sifão. Posso passar amanhã às 10h para revisar a vedação.',
                hora: '11h15',
              ),
              MensagemChat(tipo: TipoMensagem.foto, texto: '[Foto]', hora: '11h16'),
            ],
          ),
        'srv-limpeza' => const ConversaPedido(
            nome: 'Lia Carvalho',
            iniciais: 'LC',
            numeroPedido: '#3C19',
            situacao: 'finalizado',
            respostasRapidas: ['Tudo certo!', 'Obrigada'],
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.sistema,
                texto: 'Serviço concluído em 18/09.',
                hora: '17h00',
              ),
              MensagemChat(
                tipo: TipoMensagem.texto,
                texto: 'Limpeza pós-obra concluída em todos os cômodos.',
                hora: '16h50',
              ),
            ],
          ),
        'srv-pagamento' => const ConversaPedido(
            nome: 'André Lopes',
            iniciais: 'AL',
            numeroPedido: '#C90D',
            situacao: 'aguardando pagamento',
            respostasRapidas: [
              'Já vou confirmar o pagamento',
              'Você traz a escada?',
              'Pode ser na quinta às 9h?',
            ],
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.sistema,
                texto: 'Orçamento aceito. Confirme o pagamento para agendar.',
                hora: '09h40',
              ),
              MensagemChat(
                tipo: TipoMensagem.texto,
                texto: 'Bom dia! Assim que confirmar o pagamento já reservo sua manhã.',
                hora: '09h45',
              ),
            ],
          ),
        'ped-disjuntor' => const ConversaPedido(
            nome: 'Cliente Renata',
            iniciais: 'CR',
            numeroPedido: '#8D14',
            situacao: 'recebendo orçamentos',
            respostasRapidas: [
              'Qual a amperagem do disjuntor?',
              'Consigo atender hoje à tarde',
              'Pode enviar foto do quadro?',
            ],
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.sistema,
                texto: 'Tire dúvidas com o cliente antes de enviar seu orçamento.',
                hora: '13h00',
              ),
              MensagemChat(
                tipo: TipoMensagem.texto,
                texto: 'Olá! O disjuntor geral desarma sempre que ligo o chuveiro e o forno juntos.',
                hora: '13h05',
              ),
            ],
          ),
        _ => ped.DadosExemplo.conversa,
      };

  ConversaPedido _obter(String pedidoId) {
    final chave = _normalizarId(pedidoId);
    return _conversas.putIfAbsent(chave, () => _conversaInicial(chave));
  }

  @override
  Future<ConversaPedido> conversa(String pedidoId, {String? profissionalId}) async =>
      _obter(pedidoId);

  @override
  Future<void> enviar(String pedidoId, String texto, {String? profissionalId}) async {
    enviadas.add(texto);
    final chave = _normalizarId(pedidoId);
    final atual = _obter(chave);
    _conversas[chave] = ConversaPedido(
      nome: atual.nome,
      iniciais: atual.iniciais,
      numeroPedido: atual.numeroPedido,
      situacao: atual.situacao,
      respostasRapidas: atual.respostasRapidas,
      mensagens: [
        ...atual.mensagens,
        MensagemChat(
          tipo: TipoMensagem.texto,
          texto: texto,
          hora: _horaAtual(),
          minha: true,
        ),
      ],
    );
  }

  @override
  Future<void> enviarFoto(String pedidoId, String referencia, {String? profissionalId}) async {
    enviadas.add(referencia);
    final chave = _normalizarId(pedidoId);
    final atual = _obter(chave);
    _conversas[chave] = ConversaPedido(
      nome: atual.nome,
      iniciais: atual.iniciais,
      numeroPedido: atual.numeroPedido,
      situacao: atual.situacao,
      respostasRapidas: atual.respostasRapidas,
      mensagens: [
        ...atual.mensagens,
        MensagemChat(
          tipo: TipoMensagem.foto,
          texto: referencia,
          hora: _horaAtual(),
          minha: true,
        ),
      ],
    );
  }
}

class RepositorioNotificacoesFake implements RepositorioNotificacoes {
  @override
  Future<List<Notificacao>> listar() async => const [
        Notificacao(
          id: 'n1',
          titulo: 'Carlos Mendes chegou',
          texto: 'Check-in feito às 14h06. Passe o código de início para começar.',
          quando: 'há 2 h',
          tipo: 'pedido',
          destinoId: 'srv-tomadas',
        ),
        Notificacao(
          id: 'n2',
          titulo: 'Novo orçamento',
          texto: 'Você recebeu 2 orçamentos para "Instalar ventilador de teto".',
          quando: 'ontem',
          lida: true,
          tipo: 'orcamento',
          destinoId: 'srv-orcamentos',
        ),
        Notificacao(
          id: 'n3',
          titulo: 'Disputa aberta no seu serviço',
          texto: 'O cliente abriu uma disputa. Responda dentro do prazo.',
          quando: 'ontem',
          tipo: 'disputa',
          destinoId: 'srv-vazamento',
        ),
        Notificacao(
          id: 'n4',
          titulo: 'Retrabalho pedido',
          texto: 'Escolha um horário para refazer o serviço.',
          quando: 'há 3 dias',
          tipo: 'retrabalho',
          destinoId: 'srv-vazamento',
        ),
        Notificacao(
          id: 'n5',
          titulo: 'Nova mensagem de Carlos Mendes',
          texto: 'Posso passar amanhã às 9h?',
          quando: 'há 3 dias',
          lida: true,
          tipo: 'mensagem',
          destinoId: 'pedido-1',
        ),
        Notificacao(
          id: 'n6',
          titulo: 'Pagamento pendente',
          texto: 'O orçamento de "Instalar 4 luminárias" aguarda o seu pagamento.',
          quando: 'há 4 dias',
          lida: true,
          tipo: 'pagamento',
          destinoId: 'srv-pagamento',
        ),
      ];
}

class RepositorioPerfilFake implements RepositorioPerfil {
  @override
  Future<PerfilCliente> carregar() async {
    final sessao = ServicoAuthPadrao.atual.sessaoAtual;
    final base = per.DadosExemplo.perfil;
    final nomeUsuario = (sessao?.nome?.trim().isNotEmpty == true)
        ? sessao!.nome!.trim()
        : (sessao?.email.isNotEmpty == true
            ? sessao!.email.split('@').first
            : base.nome);
    if (sessao == null) return base;
    return PerfilCliente(
      nome: nomeUsuario,
      iniciais: _iniciais(nomeUsuario),
      resumo: base.resumo,
      grupos: base.grupos,
      fotoReferencia: base.fotoReferencia,
    );
  }

  static String _iniciais(String nome) {
    final partes = nome.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return 'CL';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  @override
  String? get nomeSalvo => ServicoAuthPadrao.atual.sessaoAtual?.nome ?? per.DadosExemplo.perfil.nome;
}

class RepositorioProfissionalFake implements RepositorioProfissional {
  /// Taxa só de demonstração; a real é decidida pelo backend (progressiva, base 7,5%).
  static const taxaDemonstracaoBps = 750;

  final List<MotivoRecusa> recusas = [];

  @override
  Future<void> confirmarAgenda(String pedidoId, DateTime inicio, DateTime fim) async {}

  @override
  Future<List<PedidoAberto>> pedidosAbertos(FiltroPedidosAbertos filtro) async =>
      inicioProfissionalExemplo.pedidos;

  @override
  Future<InicioProfissional> inicio() async {
    final sessao = ServicoAuthPadrao.atual.sessaoAtual;
    if (sessao != null && sessao.nome != null && sessao.nome!.trim().isNotEmpty) {
      final primeiroNome = sessao.nome!.trim().split(' ').first;
      return InicioProfissional(
        nome: primeiroNome,
        pedidos: inicioProfissionalExemplo.pedidos,
        proximo: inicioProfissionalExemplo.proximo,
        carteira: inicioProfissionalExemplo.carteira,
        disponivelAgora: inicioProfissionalExemplo.disponivelAgora,
      );
    }
    return inicioProfissionalExemplo;
  }

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
