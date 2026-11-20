import 'package:trato/auth/servico_auth.dart';
import '../telas/carteira/dados_exemplo.dart';
import 'package:trato/telas/orcamentos/modelos.dart' show DadosContrato;
import 'package:trato/telas/carteira/modelos.dart';
import '../telas/conclusao/dados_exemplo.dart';
import '../telas/orcamentos/dados_exemplo.dart';
import '../telas/pagamento/dados_exemplo.dart' as pag;
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import '../telas/pedidos/dados_exemplo.dart' as ped;
import 'package:trato/telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/dados_exemplo.dart' as per;
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_check_in_fake.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';
import '../telas/profissional/servico_check_out_fake.dart';
import 'package:trato/telas/profissional/servico_orcamento.dart';
import '../telas/profissional/servico_orcamento_fake.dart';
import '../telas/profissional_inicio/dados_exemplo.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/conclusao/modelos.dart';

// MODO DEMONSTRAÇÃO. Dados de exemplo das telas, sem rede. Nada aqui é regra de negócio:
// o "pago" da demonstração é simulado só para a tela poder ser mostrada.

const _idDemo = 'demo-4821';

class RepositorioPedidosFake implements RepositorioPedidos {
  @override
  Future<DadosContrato> contrato(String pedidoId) async => const DadosContrato(
        numeroPedido: '#AAAA',
        titulo: 'Troca de tomadas e chuveiro',
        descricao: 'Trocar 4 tomadas e o chuveiro do banheiro.',
        local: 'Rua das Flores, 10 · Centro',
        cliente: 'Mariana A.',
        contratadoEm: '28/10/2026',
      );

  final List<String> criados = [];
  final List<EnvioRelato> relatos = [];
  final List<String> retrabalhos = [];
  bool conclusaoConfirmada = false;

  DadosDoPedido _dadosDemo = const DadosDoPedido(
    titulo: 'Pedido de exemplo',
    descricao: 'Descrição de exemplo',
    faixaMaxCentavos: 50000,
  );

  OfertaExclusividadeCliente? _ofertaExclusividade;

  @override
  Future<DadosDoPedido> dados(String pedidoId) async => _dadosDemo;

  @override
  Future<OfertaExclusividadeCliente?> ofertaExclusividade(String pedidoId) async =>
      _ofertaExclusividade;

  @override
  Future<OfertaExclusividadeCliente> responderExclusividade(
    String pedidoId,
    String exclusividadeId,
    String decisao,
  ) async {
    final atual = _ofertaExclusividade;
    final novoStatus = decisao == 'aceitar' ? 'ativa' : 'recusada';
    final resp = OfertaExclusividadeCliente(
      id: exclusividadeId,
      pedidoId: pedidoId,
      status: novoStatus,
      profissionalId: atual?.profissionalId ?? 'prof-1',
      profissionalNome: atual?.profissionalNome ?? 'Carlos M.',
      notaPublica: atual?.notaPublica ?? 4.9,
      expiraEm: decisao == 'aceitar' ? DateTime.now().add(const Duration(hours: 48)) : null,
      outrosOrcamentosContinuamVisiveis: true,
    );
    _ofertaExclusividade = resp;
    return resp;
  }

  @override
  Future<DadosDoPedido> editar(
    String pedidoId, {
    String? descricao,
    int? faixaMinCentavos,
    int? faixaMaxCentavos,
    String? cep,
    String? logradouro,
    String? numero,
    String? bairro,
    String? complemento,
  }) async {
    _dadosDemo = DadosDoPedido(
      titulo: _dadosDemo.titulo,
      descricao: descricao ?? _dadosDemo.descricao,
      faixaMinCentavos:
          faixaMinCentavos == 0 ? null : (faixaMinCentavos ?? _dadosDemo.faixaMinCentavos),
      faixaMaxCentavos:
          faixaMaxCentavos == 0 ? null : (faixaMaxCentavos ?? _dadosDemo.faixaMaxCentavos),
      cep: cep ?? _dadosDemo.cep,
      logradouro: logradouro ?? _dadosDemo.logradouro,
      numero: numero ?? _dadosDemo.numero,
      bairro: bairro ?? _dadosDemo.bairro,
      complemento: complemento ?? _dadosDemo.complemento,
    );
    return _dadosDemo;
  }

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
  Future<int> avaliar(String pedidoId, EnvioAvaliacao avaliacao) async => 0;

  @override
  Future<DadosAvaliacao> dadosAvaliacao(String pedidoId) async => dadosAvaliacaoExemplo;

  @override
  Future<DadosGarantia> garantia(String pedidoId) async => dadosGarantiaExemplo;

  final List<String> cancelados = [];
  final List<(String, DateTime, DateTime)> agendasRemarcadas = [];

  @override
  Future<void> cancelar(String pedidoId, String motivo) async => cancelados.add(pedidoId);

  @override
  Future<void> remarcarAgenda(String pedidoId, DateTime inicio, DateTime fim) async =>
      agendasRemarcadas.add((pedidoId, inicio, fim));

  @override
  Future<void> pedirRetrabalho(String pedidoId, String descricao,
          {List<String> fotos = const []}) async =>
      retrabalhos.add(descricao);
}

class RepositorioOrcamentosFake implements RepositorioOrcamentos {
  /// (pedido, orçamento, valor) de cada contraproposta feita — para os testes.
  final List<(String, String, int)> contrapropostas = [];
  final List<(String, String, int)> aceitesDeContraproposta = [];

  @override
  Future<void> contraproporValor(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
    String? mensagem,
  }) async {
    contrapropostas.add((pedidoId, orcamentoId, valorCentavos));
  }

  @override
  Future<void> aceitarContraproposta(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
  }) async {
    aceitesDeContraproposta.add((pedidoId, orcamentoId, valorCentavos));
  }

  @override
  Future<void> proporNovaCondicao(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
    String? mensagem,
  }) async {
    aceitesDeContraproposta.add((pedidoId, orcamentoId, valorCentavos));
  }

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
  final List<(MetodoPagamento, int, String?)> cobrancasDetalhadas = [];

  @override
  Future<DadosPagamento> dados(String pedidoId) async => pag.DadosExemplo.pagamento;

  /// Simula o backend: com moedas, 5.000 centavos de desconto (limite do exemplo).
  @override
  Future<DadosPagamento> recalcular(
    String pedidoId, {
    String? cupom,
    bool usarMoedas = false,
  }) async {
    final base =
        (cupom ?? '').isEmpty ? pag.DadosExemplo.pagamento : await aplicarCupom(pedidoId, cupom!);
    if (!usarMoedas) return base.copiarCom(moedasSaldo: 5000);
    return base.copiarCom(
      valorAgoraCentavos: base.valorAgoraCentavos - 5000,
      descontoCentavos: base.descontoCentavos + 5000,
      moedasSaldo: 5000,
      moedasUsadas: 5000,
      moedasDescontoCentavos: 5000,
    );
  }

  @override
  Future<DadosPagamento> aplicarCupom(String pedidoId, String codigo) async {
    final limpo = codigo.trim().toUpperCase();
    final base = pag.DadosExemplo.pagamento;
    if (limpo.isEmpty) return base;
    if (limpo == 'TRATO10') {
      final desconto = (base.valorAgoraCentavos * 0.1).round();
      final finalValor = base.valorAgoraCentavos - desconto;
      return base.copiarCom(
        valorAgoraCentavos: finalValor,
        descontoCentavos: desconto,
        cupomCodigo: 'TRATO10',
        parcelamento: [
          for (final p in base.parcelamento)
            OpcaoParcelamento(
              parcelas: p.parcelas,
              custoCentavos: p.custoCentavos,
              totalCentavos: finalValor + p.custoCentavos,
              valorParcelaCentavos: ((finalValor + p.custoCentavos) / p.parcelas).round(),
            ),
        ],
      );
    }
    throw Exception('Cupom inválido ou expirado.');
  }

  @override
  Future<Cobranca> criarCobranca(
    String pedidoId,
    MetodoPagamento metodo, {
    int parcelas = 1,
    String? cupom,
    bool usarMoedas = false,
  }) async {
    cobrancas.add(metodo);
    cobrancasDetalhadas.add((metodo, parcelas, cupom));
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
                texto:
                    'Olá! Vi seu relato sobre o pingamento no sifão. Posso passar amanhã às 10h para revisar a vedação.',
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
                texto:
                    'Olá! O disjuntor geral desarma sempre que ligo o chuveiro e o forno juntos.',
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

  final List<(String, DateTime, DateTime)> agendasPropostas = [];
  final List<String> agendasAceitas = [];

  @override
  Future<void> proporAgenda(
    String pedidoId,
    DateTime inicio,
    DateTime fim, {
    String justificativa = '',
  }) async {
    agendasPropostas.add((pedidoId, inicio, fim));
    final chave = _normalizarId(pedidoId);
    final atual = _obter(chave);
    _conversas[chave] = ConversaPedido(
      nome: atual.nome,
      iniciais: atual.iniciais,
      numeroPedido: atual.numeroPedido,
      situacao: atual.situacao,
      respostasRapidas: atual.respostasRapidas,
      orcamentosAtivos: atual.orcamentosAtivos,
      pedidoAberto: atual.pedidoAberto,
      souCliente: atual.souCliente,
      usuarioId: atual.usuarioId,
      mensagens: [
        ...atual.mensagens,
        MensagemChat(
          id: atual.mensagens.length + 1,
          tipo: TipoMensagem.texto,
          texto: 'Sugestão de visita enviada.${justificativa.isEmpty ? '' : ' $justificativa'}',
          hora: _horaAtual(),
          minha: true,
          propostaAgenda: PropostaAgendaChat(inicio: inicio, fim: fim),
        ),
      ],
    );
  }

  @override
  Future<void> aceitarAgenda(
    String pedidoId, {
    int? mensagemId,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    agendasAceitas.add(pedidoId);
  }
}

class RepositorioNotificacoesFake implements RepositorioNotificacoes {
  final List<String> lidas = [];
  final List<String> dispositivosRegistrados = [];
  List<PreferenciaNotificacao> preferenciasSalvas = const [
    PreferenciaNotificacao(categoria: 'orcamentos'),
    PreferenciaNotificacao(categoria: 'pagamentos'),
    PreferenciaNotificacao(categoria: 'agenda'),
    PreferenciaNotificacao(categoria: 'execucao'),
    PreferenciaNotificacao(categoria: 'disputas'),
    PreferenciaNotificacao(categoria: 'avaliacoes'),
    PreferenciaNotificacao(categoria: 'mensagens'),
  ];

  @override
  Future<void> marcarLida(String id) async => lidas.add(id);

  @override
  Future<List<PreferenciaNotificacao>> carregarPreferencias() async => preferenciasSalvas;

  @override
  Future<List<PreferenciaNotificacao>> salvarPreferencias(
    List<PreferenciaNotificacao> itens,
  ) async {
    preferenciasSalvas = List.of(itens);
    return preferenciasSalvas;
  }

  @override
  Future<void> registrarDispositivo(String token, String plataforma) async =>
      dispositivosRegistrados.add('$plataforma:$token');

  @override
  Future<void> removerDispositivo(String token) async =>
      dispositivosRegistrados.removeWhere((item) => item.endsWith(':$token'));

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
  Future<String?> fotoDe(String usuarioId) async => null;

  @override
  Future<void> enviarFoto(String caminhoLocal) async {}

  @override
  Future<PerfilCliente> carregar() async {
    final sessao = ServicoAuthPadrao.atual.sessaoAtual;
    final base = per.DadosExemplo.perfil;
    final nomeUsuario = (sessao?.nome?.trim().isNotEmpty == true)
        ? sessao!.nome!.trim()
        : (sessao?.email.isNotEmpty == true ? sessao!.email.split('@').first : base.nome);
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
  String? get nomeSalvo =>
      ServicoAuthPadrao.atual.sessaoAtual?.nome ?? per.DadosExemplo.perfil.nome;
}

class RepositorioProfissionalFake implements RepositorioProfissional {
  /// Taxa só de demonstração; a real é decidida pelo backend (progressiva, base 7,5%).

  final List<MotivoRecusa> recusas = [];
  final List<(String, DateTime, DateTime)> agendasRemarcadas = [];

  @override
  Future<void> confirmarAgenda(String pedidoId, DateTime inicio, DateTime fim) async {}

  @override
  Future<void> remarcarAgenda(String pedidoId, DateTime inicio, DateTime fim) async =>
      agendasRemarcadas.add((pedidoId, inicio, fim));

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
  Future<List<ItemExtrato>> extrato({int limite = 50, int deslocamento = 0}) async {
    final todos = DadosExemploCarteira.completo.extrato;
    if (deslocamento >= todos.length) return const [];
    return todos.skip(deslocamento).take(limite).toList();
  }

  final List<int> notasDoCliente = [];
  int moedasAoAvaliarCliente = 50;

  @override
  Future<int> avaliarCliente(String pedidoId, int nota, String comentario) async {
    notasDoCliente.add(nota);
    return moedasAoAvaliarCliente;
  }

  @override
  Future<DetalheValoresPedido> valoresDoPedido(String pedidoId) async => const DetalheValoresPedido(
        pedidoNumero: '#AAAA',
        pagoPeloClienteCentavos: 70500,
        voceRecebeCentavos: 70500,
        situacao: 'Retido até o cliente confirmar o serviço.',
      );

  @override
  ServicoOrcamento servicoOrcamento(String pedidoId) => ServicoOrcamentoFake();

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId, {bool remoto = false}) => ServicoCheckInFake();

  @override
  ServicoCheckOut servicoCheckOut(String pedidoId, {bool remoto = false}) => ServicoCheckOutFake();

  ContaRecebimento _contaRecebimento = const ContaRecebimento(cadastrada: false);
  bool _disponivelAgora = inicioProfissionalExemplo.disponivelAgora;

  @override
  Future<ContaRecebimento> obterContaRecebimento() async => _contaRecebimento;

  @override
  Future<ContaRecebimento> salvarContaRecebimento({
    required String tipoPix,
    required String chavePix,
    String? bancoCodigo,
    String? bancoNome,
    String? agencia,
    String? conta,
    String? tipoConta,
  }) async {
    final limpa = chavePix.trim();
    _contaRecebimento = ContaRecebimento(
      cadastrada: true,
      tipoPix: tipoPix,
      chavePix: limpa,
      chavePixMascarada: limpa,
      bancoCodigo: bancoCodigo,
      bancoNome: bancoNome,
      agencia: agencia,
      conta: conta,
      tipoConta: tipoConta,
      resumoExibicao: 'Pix (${tipoPix.toUpperCase()}): $limpa'
          '${bancoNome != null && bancoNome.isNotEmpty ? ' · $bancoNome' : ''}',
    );
    return _contaRecebimento;
  }

  @override
  Future<List<int>> baixarExtratoPdf({String? mes}) async =>
      '%PDF-1.4\n%Trato extrato fake\n%%EOF'.codeUnits;

  ResumoExclusividades _exclusividades = const ResumoExclusividades(
    saldoProfissional: 150,
    limiteMaximo: 3,
  );

  @override
  Future<ResumoExclusividades> minhasExclusividades() async => _exclusividades;

  @override
  Future<ExclusividadeProfissional> solicitarExclusividade(
    String pedidoId,
    String chaveIdempotencia,
  ) async {
    final existente = _exclusividades.itens.where((i) => i.pedidoId == pedidoId && i.emAndamento);
    if (existente.isNotEmpty) return existente.first;
    final saldoDepois = _exclusividades.saldoProfissional - 100;
    final nova = ExclusividadeProfissional(
      id: 'exc-$pedidoId',
      pedidoId: pedidoId,
      status: 'aguardando_cliente',
      moedasCobradas: 100,
      responderAte: DateTime.now().add(const Duration(hours: 6)),
      saldoRestante: saldoDepois,
    );
    _exclusividades = _exclusividades.comNovaOferta(nova);
    return nova;
  }

  @override
  Future<bool> alterarDisponivelAgora(bool disponivel) async {
    _disponivelAgora = disponivel;
    return _disponivelAgora;
  }

  @override
  Future<DetalheOrcamentoEnviado> meuOrcamento(
    String orcamentoId, {
    String? tituloPedido,
    String? situacao,
  }) async =>
      DetalheOrcamentoEnviado(
        orcamentoId: orcamentoId.isEmpty ? 'orc-exemplo' : orcamentoId,
        pedidoId: 'ped-tomadas',
        tituloPedido: tituloPedido ?? 'Troca de tomadas e chuveiro',
        versao: 1,
        situacao: situacao ?? 'aguardando',
        valorCentavos: 35000,
        prazoExecucaoDias: 2,
        garantiaDias: 90,
        foraDoEscopo: 'Fornecimento de disjuntor geral',
        observacoes: 'Atendimento em horário comercial.',
        horasDeslocamento: '1.0',
        horasTrabalhadas: '2.5',
        itens: const [
          ItemOrcamentoEnviado(
            tipo: 'deslocamento',
            descricao: 'Horas de deslocamento',
            quantidade: '1.0',
            valorUnitarioCentavos: 10000,
            totalCentavos: 10000,
          ),
          ItemOrcamentoEnviado(
            tipo: 'horas',
            descricao: 'Horas trabalhadas',
            quantidade: '2.5',
            valorUnitarioCentavos: 10000,
            totalCentavos: 25000,
          ),
        ],
      );
}
