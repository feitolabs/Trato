/// Um consentimento que a pessoa pode ver (e, se não for obrigatório, desligar).
class Consentimento {
  const Consentimento({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.ativo,
    this.obrigatorio = false,
  });

  final String id;
  final String titulo;
  final String descricao;
  final bool ativo;

  /// Necessário para o app funcionar (ex.: dados do pedido): aparece, mas não desliga.
  final bool obrigatorio;
}

/// Contrato com o backend. Exportar e excluir só pedem; quem executa, registra e decide
/// o que a lei manda reter é o backend.
abstract interface class CancelamentoExclusao {
  Future<void> cancelarExclusao();
}

/// Tratinhos que a pessoa perderá ao encerrar a conta (`/v1/me/exclusao` e `/v1/me/moedas`).
class SaldoTratinhos {
  const SaldoTratinhos({
    this.tratinhosAPerder,
    this.cliente,
    this.profissional,
    this.valorMoedaCentavos,
    this.pendencias = const [],
    this.guardadosAte,
  });

  /// `pendencias` de `/v1/me/exclusao`, no texto do servidor.
  final List<String> pendencias;

  /// `tratinhos_guardados_ate`: até quando os Tratinhos ficam guardados. Nulo: sem guarda.
  final DateTime? guardadosAte;

  /// Soma dos Tratinhos válidos disponíveis que serão perdidos (`tratinhos_a_perder`
  /// de `GET /v1/me/exclusao` ou `POST /v1/me/exclusao` passo 1). Nulo: backend antigo.
  final int? tratinhosAPerder;

  /// Nulo: o servidor não informou.
  final int? cliente;
  final int? profissional;
  final int? valorMoedaCentavos;
}

/// Resposta de consulta (`GET /v1/me/exclusao`) ou passo 1 (`POST /v1/me/exclusao`).
class PreviaExclusao {
  const PreviaExclusao({
    this.tokenConfirmacao,
    this.tratinhosAPerder,
    this.pendencias = const [],
    this.guardadosAte,
  });

  final List<String> pendencias;
  final DateTime? guardadosAte;

  final String? tokenConfirmacao;
  final int? tratinhosAPerder;
}

/// Quem sabe o saldo, para o aviso antes de encerrar a conta (Termos 13.10).
abstract interface class ConsultaDeTratinhos {
  /// Nulo: o servidor não tem a função (404/503).
  Future<SaldoTratinhos?> saldoDeTratinhos();
}

/// Pedido do titular sobre os próprios dados (Termos 14.9 e 14.10). Campo ausente vira vazio.
class PedidoLgpd {
  const PedidoLgpd({
    this.id = '',
    this.protocolo = '',
    this.tipo = '',
    this.decisaoAutomatizada,
    this.descricao = '',
    this.status = '',
    this.abertoEm,
    this.responderAte,
    this.resposta,
    this.motivoNaoAtendido,
    this.criteriosInformados,
    this.respondidoEm,
  });

  factory PedidoLgpd.deJson(Map<Object?, Object?> json) {
    String? texto(String chave) {
      final v = json[chave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    DateTime? data(String chave) => DateTime.tryParse(texto(chave) ?? '');

    return PedidoLgpd(
      id: texto('id') ?? '',
      protocolo: texto('protocolo') ?? '',
      tipo: texto('tipo') ?? '',
      decisaoAutomatizada: texto('decisao_automatizada'),
      descricao: texto('descricao') ?? '',
      status: texto('status') ?? '',
      abertoEm: data('aberto_em'),
      responderAte: data('responder_ate'),
      resposta: texto('resposta'),
      motivoNaoAtendido: texto('motivo_nao_atendido'),
      criteriosInformados: texto('criterios_informados'),
      respondidoEm: data('respondido_em'),
    );
  }

  final String id;
  final String protocolo;
  final String tipo;
  final String? decisaoAutomatizada;
  final String descricao;
  final String status;
  final DateTime? abertoEm;
  final DateTime? responderAte;
  final String? resposta;
  final String? motivoNaoAtendido;
  final String? criteriosInformados;
  final DateTime? respondidoEm;
}

class PaginaPedidosLgpd {
  const PaginaPedidosLgpd({required this.itens, required this.total});

  final List<PedidoLgpd> itens;
  final int total;
}

const tipoRevisaoAutomatizada = 'revisao_decisao_automatizada';

/// Códigos de `tipo` aceitos pelo backend, com o nome que a pessoa lê.
const tiposPedidoLgpd = <String, String>{
  'confirmacao': 'Confirmar se vocês usam meus dados',
  'acesso': 'Ver os meus dados',
  'correcao': 'Corrigir meus dados',
  'anonimizacao_bloqueio_eliminacao': 'Tornar anônimos, bloquear ou apagar dados',
  'portabilidade': 'Levar meus dados para outro serviço',
  'eliminacao_consentimento': 'Apagar dados que usam meu consentimento',
  'compartilhamento': 'Saber com quem meus dados são compartilhados',
  'nao_consentir': 'Saber o que acontece se eu não consentir',
  'revogacao_consentimento': 'Retirar meu consentimento',
  tipoRevisaoAutomatizada: 'Revisão por uma pessoa de decisão automática',
};

const decisoesAutomatizadas = <String, String>{
  'ocultacao_contato': 'Contato escondido no chat',
  'documentos_rosto': 'Conferência de documentos e do rosto',
  'alerta_fraude': 'Alerta de fraude',
  'ordem_resultados': 'Ordem dos resultados',
  'outra': 'Outra decisão automática',
};

/// Pedidos do titular (`/v1/me/lgpd/pedidos`).
abstract interface class PedidosDoTitular {
  /// Nulo: o servidor não tem a função (404/503).
  Future<PaginaPedidosLgpd?> listarPedidosLgpd({int deslocamento = 0});

  /// Abre o pedido. Pedido igual ainda aberto: o servidor devolve o que já existe.
  Future<PedidoLgpd> abrirPedidoLgpd({
    required String tipo,
    String descricao = '',
    String? decisaoAutomatizada,
  });
}

abstract interface class ServicoPrivacidade {
  Future<List<Consentimento>> consentimentos();
  Future<void> alterarConsentimento(String id, {required bool ativo});

  /// Baixa a cópia dos dados pessoais do usuário (JSON formatado quando disponível).
  Future<String?> solicitarExportacao();

  /// Pede a exclusão da conta (só depois da confirmação em 2 passos).
  Future<void> solicitarExclusao();
}

/// Finalidades de consentimento que o app apresenta (textos da tela de privacidade). O estado
/// de cada uma vem da API; estes são só os rótulos.
const consentimentosPadrao = [
  Consentimento(
    id: 'dados_pedido',
    titulo: 'Dados para executar pedidos',
    descricao: 'Nome, endereço do serviço e conversa do pedido. Necessário para usar o app.',
    ativo: true,
    obrigatorio: true,
  ),
  Consentimento(
    id: 'localizacao',
    titulo: 'Localização',
    descricao: 'Confirmar a chegada e a saída no local do serviço (check-in e check-out).',
    ativo: true,
  ),
  Consentimento(
    id: 'avisos',
    titulo: 'Avisos e novidades',
    descricao: 'Mensagens sobre novidades do Trato, por push ou WhatsApp.',
    ativo: false,
  ),
];
