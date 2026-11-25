import '../telas/carteira/modelos.dart';
import '../telas/conclusao/modelos.dart';
import '../telas/orcamentos/modelos.dart';
import '../telas/pagamento/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/modelos.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_check_out.dart';
import '../telas/profissional/servico_orcamento.dart';
import '../telas/profissional_inicio/modelos.dart';

/// Portas de dados do app. As telas não conhecem a rede: quem liga (rotas.dart) entrega a
/// implementação certa (API ou demonstração). Dinheiro em centavos; nenhuma regra aqui.

class PedidosDoCliente {
  const PedidosDoCliente({this.emAndamento = const [], this.finalizados = const []});

  final List<PedidoResumo> emAndamento;
  final List<PedidoResumo> finalizados;

  bool get vazio => emAndamento.isEmpty && finalizados.isEmpty;
}

/// O que o cliente descreveu no pedido e ainda pode mudar antes de aceitar um orçamento.
class DadosDoPedido {
  const DadosDoPedido({
    required this.titulo,
    required this.descricao,
    this.faixaMinCentavos,
    this.faixaMaxCentavos,
    this.logradouro,
    this.numero,
    this.bairro,
    this.complemento,
    this.cep,
    this.referencia,
    this.modalidade = 'presencial',
    this.fotos = const [],
    this.profissionalConvidadoId,
    this.estado = 'aberto',
    this.ofertaExclusividade,
    this.orcamentosRecebidos = 0,
    this.categoriaNome,
    this.urgente = false,
  });

  /// Nome da categoria (`categoria_nome`, opcional): vira o título do pedido.
  final String? categoriaNome;

  /// Pedido urgente (para hoje).
  final bool urgente;

  final List<String> fotos;
  final String? profissionalConvidadoId;
  final String estado;
  final OfertaExclusividadeCliente? ofertaExclusividade;
  final int orcamentosRecebidos;

  final String titulo;
  final String descricao;
  final int? faixaMinCentavos;
  final int? faixaMaxCentavos;
  final String? logradouro;
  final String? numero;
  final String? bairro;
  final String? complemento;
  final String? cep;
  final String? referencia;

  /// `presencial` ou `remoto`.
  final String modalidade;
  bool get remoto => modalidade == 'remoto';

  /// Endereço por extenso para o profissional contratado e para o mapa: "Rua das Flores, 10 ·
  /// apto 2 · Centro · CEP 35500-000 (perto da praça)". Nulo se não há endereço.
  String? get enderecoCompleto {
    final rua = logradouro;
    if (rua == null || rua.isEmpty) return null;
    String? parte(String? v, [String Function(String)? formato]) =>
        (v == null || v.trim().isEmpty) ? null : (formato?.call(v.trim()) ?? v.trim());
    final numeroTxt = parte(numero);
    return [
      numeroTxt == null ? rua : '$rua, $numeroTxt',
      parte(complemento),
      parte(bairro),
      parte(cep, (c) => 'CEP $c'),
      parte(referencia, (r) => '($r)'),
    ].whereType<String>().join(' · ');
  }

  /// Texto para pesquisar no mapa (sem referência nem complemento).
  String? get consultaDoMapa {
    final rua = logradouro;
    if (rua == null || rua.isEmpty) return null;
    return [
      if ((numero ?? '').trim().isNotEmpty) '$rua, ${numero!.trim()}' else rua,
      if ((bairro ?? '').trim().isNotEmpty) bairro!.trim(),
      if ((cep ?? '').trim().isNotEmpty) cep!.trim(),
    ].join(', ');
  }

  /// "Rua das Flores, 10 · Centro", ou nulo se não há endereço.
  String? get enderecoResumo {
    final rua = logradouro;
    if (rua == null || rua.isEmpty) return null;
    final n = (numero == null || numero!.isEmpty) ? '' : ', $numero';
    final b = (bairro == null || bairro!.isEmpty) ? '' : ' · $bairro';
    return '$rua$n$b';
  }
}

abstract interface class RepositorioPedidos {
  Future<PedidosDoCliente> listar();

  /// Descrição, valor pretendido e endereço do pedido.
  Future<DadosDoPedido> dados(String pedidoId);

  /// Troca esses dados. Só o cliente e só enquanto o pedido aguarda orçamentos (o backend decide).
  /// [faixaMaxCentavos] 0 = sem limite. Campos nulos ficam como estão.
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
  });

  /// Abre o pedido e devolve o id.
  Future<String> criar(RascunhoPedido rascunho);

  /// Linha do tempo e código de início do pedido.
  Future<PedidoEmExecucao> acompanhar(String pedidoId);

  Future<ResumoConclusao> conclusao(String pedidoId);

  /// Cliente confirma o serviço. O backend decide a liberação.
  Future<void> confirmarConclusao(String pedidoId);

  Future<DadosRelatoProblema> dadosRelato(String pedidoId);

  /// "Relatar problema": abre a disputa; o valor congelado é do backend.
  Future<void> relatarProblema(String pedidoId, EnvioRelato relato);

  /// Devolve as moedas de bônus ganhas pela avaliação (0 se nenhuma). O backend decide.
  Future<int> avaliar(String pedidoId, EnvioAvaliacao avaliacao);

  Future<DadosAvaliacao> dadosAvaliacao(String pedidoId);

  Future<DadosGarantia> garantia(String pedidoId);

  /// O contrato do serviço (o pedido, as partes, datas, local, pagamento e aditivos).
  Future<DadosContrato> contrato(String pedidoId);

  Future<void> pedirRetrabalho(String pedidoId, String descricao, {List<String> fotos});

  /// Cancela o pedido (cliente ou profissional contratado). O servidor diz se o estado permite e
  /// devolve o dinheiro quando já houve pagamento.
  Future<void> cancelar(String pedidoId, String motivo);

  /// Propostas de nova data do pedido, da mais recente para a mais antiga
  /// (`GET /v1/pedidos/{id}/reagendamentos`).
  Future<List<Reagendamento>> reagendamentos(String pedidoId);

  /// Propõe nova data (`POST /v1/pedidos/{id}/reagendamentos`). O backend diz se o estado permite.
  Future<void> proporReagendamento(
    String pedidoId, {
    required DateTime inicio,
    required DateTime fim,
    String? motivo,
  });

  /// A outra parte aceita (`POST .../reagendamentos/{rid}/aceitar`).
  Future<void> aceitarReagendamento(String pedidoId, String reagendamentoId);

  /// A outra parte recusa ou quem propôs cancela (`POST .../reagendamentos/{rid}/recusar`).
  Future<void> recusarReagendamento(String pedidoId, String reagendamentoId);

  /// Comprovante do pedido em PDF (`GET /v1/pedidos/{id}/recibo.pdf`), com o token do usuário.
  Future<List<int>> baixarReciboPdf(String pedidoId);

  /// Oferta de exclusividade em andamento para o pedido (`GET /v1/pedidos/{id}/exclusividade`).
  Future<OfertaExclusividadeCliente?> ofertaExclusividade(String pedidoId) async => null;

  /// Aceita ou recusa uma oferta de exclusividade (`POST /v1/pedidos/{id}/exclusividade/{eid}/responder`).
  Future<OfertaExclusividadeCliente> responderExclusividade(
    String pedidoId,
    String exclusividadeId,
    String decisao,
  ) =>
      throw UnimplementedError();
}

class OrcamentosDoPedido {
  const OrcamentosDoPedido({required this.pedido, required this.orcamentos});

  final ResumoPedido pedido;
  final List<Orcamento> orcamentos;
}

abstract interface class RepositorioOrcamentos {
  Future<OrcamentosDoPedido> listar(String pedidoId);

  /// Só pede ao backend. Taxa e líquido nunca são calculados no app.
  Future<void> aceitar(String pedidoId, String orcamentoId);

  /// Cliente recusa o orçamento (`POST /v1/pedidos/{id}/orcamentos/{orc}/recusar`).
  Future<void> recusar(String pedidoId, String orcamentoId);

  /// Cliente propõe um valor e/ou prazo em dias (vai para a conversa do profissional). O backend valida.
  Future<void> contraproporValor(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
    String? mensagem,
  });

  /// Profissional aceita a contraproposta: o orçamento ganha uma nova versão no valor e prazo combinados.
  Future<void> aceitarContraproposta(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
  });

  /// Profissional envia uma nova proposta (valor e/ou prazo em dias) diretamente pelo chat.
  Future<void> proporNovaCondicao(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
    String? mensagem,
  }) =>
      throw UnimplementedError();
}

enum StatusPagamento { aguardando, pago, falhou }

class Cobranca {
  const Cobranca({
    required this.id,
    this.pixCopiaECola,
    this.urlCheckout,
    this.segredoCartao,
    this.clienteCartaoId,
    this.chaveEfemera,
  });

  /// Cartão: o que a folha do provedor precisa (nunca aparece na tela).
  final String? segredoCartao;
  final String? clienteCartaoId;
  final String? chaveEfemera;

  bool get precisaDaFolhaDeCartao =>
      segredoCartao != null && clienteCartaoId != null && chaveEfemera != null;

  final String id;

  /// Código Pix "copia e cola" (modo teste do provedor).
  final String? pixCopiaECola;
  final String? urlCheckout;
}

abstract interface class RepositorioPagamento {
  Future<DadosPagamento> dados(String pedidoId);

  /// Valida e aplica um cupom no resumo de pagamento (`POST /v1/contratos/{id}/cupom`).
  Future<DadosPagamento> aplicarCupom(String pedidoId, String codigo) async =>
      throw UnimplementedError();

  /// Recalcula o resumo com cupom e/ou moedas (`GET /v1/pedidos/{id}/pagamento`). Quem decide
  /// quantas moedas entram é o backend.
  Future<DadosPagamento> recalcular(
    String pedidoId, {
    String? cupom,
    bool usarMoedas = false,
  }) async =>
      throw UnimplementedError();

  /// Cria a cobrança (modo teste). O app NUNCA marca como pago: só o backend, depois do
  /// webhook assinado do provedor (D14/D15).
  Future<Cobranca> criarCobranca(
    String pedidoId,
    MetodoPagamento metodo, {
    int parcelas = 1,
    String? cupom,
    bool usarMoedas = false,
  });

  Future<StatusPagamento> status(String pedidoId);

  /// Grava CPF e data de nascimento no perfil do cliente (`POST /v1/me/cpf`).
  Future<void> cadastrarCpf(String cpf, String nascimentoIso) async {}
}

/// Resumo seguro (LGPD) do cliente do pedido exibido ao profissional no topo do chat.
class ResumoPerfilCliente {
  const ResumoPerfilCliente({
    required this.nome,
    this.notaMedia,
    this.totalAvaliacoes = 0,
    this.servicosConcluidos = 0,
    this.membroDesde,
  });

  final String nome;
  final double? notaMedia;
  final int totalAvaliacoes;
  final int servicosConcluidos;
  final String? membroDesde;
}

abstract interface class RepositorioChat {
  Future<ConversaPedido> conversa(String pedidoId, {String? profissionalId});

  /// `GET /v1/pedidos/{pedido_id}/perfil-cliente`. Nulo em modo demo ou backend antigo.
  Future<ResumoPerfilCliente?> perfilClienteDoPedido(String pedidoId) async => null;
  /// [chaveIdempotencia]: mesma chave em cada tentativa da mesma mensagem, para o backend não
  /// duplicar quando o reenvio acontece depois de a internet voltar.
  Future<void> enviar(
    String pedidoId,
    String texto, {
    String? profissionalId,
    String? chaveIdempotencia,
  });
  Future<void> enviarFoto(String pedidoId, String referencia, {String? profissionalId});
  Future<void> proporAgenda(
    String pedidoId,
    DateTime inicio,
    DateTime fim, {
    String justificativa = '',
  }) async {}
  Future<void> aceitarAgenda(
    String pedidoId, {
    int? mensagemId,
    DateTime? inicio,
    DateTime? fim,
  }) async {}
}

class Notificacao {
  const Notificacao({
    required this.id,
    required this.titulo,
    required this.texto,
    required this.quando,
    this.lida = false,
    this.tipo,
    this.destinoId,
    this.tela,
    this.papel,
    this.recorrenciaId,
  });

  final String id;
  final String titulo;
  final String texto;

  /// `data.tela` do backend (`pedido`, `pedido_aberto`, `disputa`...), quando vem.
  final String? tela;

  /// `profissional` ou `cliente`: em que modo a tela abre. Ausente = o modo atual.
  final String? papel;
  final String? recorrenciaId;

  /// Quando o backend informa: `disputa` ou `retrabalho` (abrem a tela do profissional).
  final String? tipo;

  /// Id da disputa (ou do pedido) que o toque abre.
  final String? destinoId;

  /// Já formatado ("há 2 h").
  final String quando;
  final bool lida;
}

class PreferenciaNotificacao {
  const PreferenciaNotificacao({
    required this.categoria,
    this.app = true,
    this.push = true,
    this.email = true,
  });

  final String categoria;
  final bool app;
  final bool push;
  final bool email;

  PreferenciaNotificacao copiarCom({bool? app, bool? push, bool? email}) => PreferenciaNotificacao(
        categoria: categoria,
        app: app ?? this.app,
        push: push ?? this.push,
        email: email ?? this.email,
      );
}

abstract interface class RepositorioNotificacoes {
  Future<List<Notificacao>> listar();

  /// Grava no servidor que a notificação foi lida (o contador não volta depois).
  Future<void> marcarLida(String id);

  Future<List<PreferenciaNotificacao>> carregarPreferencias() async => const [];

  Future<List<PreferenciaNotificacao>> salvarPreferencias(
    List<PreferenciaNotificacao> itens,
  ) async =>
      itens;

  Future<void> registrarDispositivo(String token, String plataforma) async {}

  Future<void> removerDispositivo(String token) async {}
}

abstract interface class RepositorioPerfil {
  Future<PerfilCliente> carregar();
  String? get nomeSalvo;

  /// Foto de perfil de qualquer usuário (URL curta do backend) ou `null` se não tiver.
  Future<String?> fotoDe(String usuarioId);

  /// Envia a foto de perfil de quem está logado (a que o cliente e o profissional veem).
  Future<void> enviarFoto(String caminhoLocal);
}

/// Filtros de `GET /v1/profissional/pedidos-abertos`. O backend aplica; o app só pede.
class FiltroPedidosAbertos {
  const FiltroPedidosAbertos({
    this.categoriaId,
    this.bairro,
    this.precoMinCentavos,
    this.precoMaxCentavos,
    this.ordenar = 'recentes',
    this.limite = 50,
  });

  final String? categoriaId;
  final String? bairro;
  final int? precoMinCentavos;
  final int? precoMaxCentavos;

  /// `recentes`, `antigos`, `urgentes`, `maior_valor` ou `menor_valor`.
  final String ordenar;
  final int limite;

  Map<String, String> get consulta => {
        if (categoriaId != null) 'categoria_id': categoriaId!,
        if (bairro != null && bairro!.isNotEmpty) 'bairro': bairro!,
        if (precoMinCentavos != null) 'preco_min_centavos': '$precoMinCentavos',
        if (precoMaxCentavos != null) 'preco_max_centavos': '$precoMaxCentavos',
        'ordenar': ordenar,
        'limite': '$limite',
      };
}

abstract interface class RepositorioProfissional {
  /// Pedidos abertos com filtros (a tela de filtros ainda não existe).
  Future<List<PedidoAberto>> pedidosAbertos(FiltroPedidosAbertos filtro);

  Future<InicioProfissional> inicio();
  Future<DetalhePedido> detalhe(String pedidoId);
  Future<void> recusar(String pedidoId, MotivoRecusa motivo);

  /// Avisa o cliente que o profissional está a caminho (serviço agendado). [etaMinutos] opcional (5 a 180).
  Future<AvisoACaminho> avisarACaminho(String pedidoId, {int? etaMinutos});

  /// Marca a visita de um pedido já pago. Sem isso o check-in não é liberado.
  Future<void> confirmarAgenda(String pedidoId, DateTime inicio, DateTime fim);

  /// Carteira como EXTRATO (D15): sem saldo próprio, sem saque.
  Future<List<ItemExtrato>> extrato({int limite = 50, int deslocamento = 0});

  /// Valor inteiro, taxa, líquido, aditivos e notas de um pedido (detalhe de uma linha do extrato).
  Future<DetalheValoresPedido> valoresDoPedido(String pedidoId);

  /// O profissional avalia o cliente de um pedido concluído (uma vez). Devolve Tratinhos ganhos (0 se nenhum).
  Future<int> avaliarCliente(String pedidoId, int nota, String comentario);

  /// Calculadora: taxa e líquido vêm do backend.
  ServicoOrcamento servicoOrcamento(String pedidoId);

  /// Check-in do pedido. Remoto: só o código do cliente (sem foto nem localização).
  ServicoCheckIn servicoCheckIn(String pedidoId, {bool remoto = false});

  /// Check-out do pedido: foto final e código de conclusão que o cliente informa. Remoto: só o
  /// código.
  ServicoCheckOut servicoCheckOut(String pedidoId, {bool remoto = false});

  /// Conta bancária / chave Pix cadastrada para recebimento dos repasses (D15).
  Future<ContaRecebimento> obterContaRecebimento();

  /// Cadastra ou atualiza a chave Pix / conta de recebimento.
  Future<ContaRecebimento> salvarContaRecebimento({
    required String tipoPix,
    required String chavePix,
    String? bancoCodigo,
    String? bancoNome,
    String? agencia,
    String? conta,
    String? tipoConta,
  });

  /// Baixa os bytes do extrato mensal em PDF (`AAAA-MM`; padrão = mês atual).
  Future<List<int>> baixarExtratoPdf({String? mes});

  /// Atualiza o switch "Disponível agora" no backend para priorizar/notificar pedidos urgentes.
  Future<bool> alterarDisponivelAgora(bool disponivel);

  /// Detalhe completo de um orçamento enviado pelo profissional (antes ou após aceite).
  Future<DetalheOrcamentoEnviado> meuOrcamento(
    String orcamentoId, {
    String? tituloPedido,
    String? situacao,
  });

  /// Exclusividades de 48h e saldo de Tratinhos do profissional (`GET /v1/profissional/exclusividades`).
  Future<ResumoExclusividades> minhasExclusividades() async => const ResumoExclusividades();

  /// Pede exclusividade de 48h num pedido aberto (`POST /v1/profissional/exclusividades`).
  Future<ExclusividadeProfissional> solicitarExclusividade(
    String pedidoId,
    String chaveIdempotencia,
  ) =>
      throw UnimplementedError();
}
