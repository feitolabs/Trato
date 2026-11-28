import '../nucleo/papeis.dart';

/// Quem está logado no painel. `alcadaCentavos` vem do backend (tabela `equipe`).
class UsuarioEquipe {
  const UsuarioEquipe({
    required this.id,
    required this.nome,
    required this.email,
    required this.papel,
    this.alcadaCentavos = 0,
  });

  final String id;
  final String nome;
  final String email;
  final Papel papel;
  final int alcadaCentavos;
}

enum StatusVerificacao { enviada, emAnalise, aprovada, recusada }

/// Uma página de uma lista do servidor: os itens e quantos existem ao todo com o mesmo filtro.
class PaginaRemota<T> {
  const PaginaRemota(this.itens, this.total);
  final List<T> itens;
  final int total;
}

/// Um envio anterior do mesmo profissional (RF-VER-02).
class EnvioVerificacao {
  const EnvioVerificacao({required this.enviadoEm, required this.aprovado, this.motivo});
  final DateTime enviadoEm;
  final bool aprovado;
  final String? motivo;
}

class Verificacao {
  const Verificacao({
    required this.id,
    required this.profissional,
    required this.cidade,
    required this.enviadaEm,
    required this.documentos,
    this.profissionalId = '',
    this.idPublico = '',
    this.nivel = '',
    this.categorias = const [],
    this.cpfMascarado,
    this.enviosAnteriores = const [],
    this.status = StatusVerificacao.enviada,
    this.motivoDecisao,
    this.analistaId,
    this.analistaNome,
  });

  /// Quem assumiu a análise. Outra pessoa só decide depois de assumir no lugar dela.
  final String? analistaId;
  final String? analistaNome;

  final String id;

  /// Id da conta do profissional (para revelar o CPF com motivo).
  final String profissionalId;
  final String profissional;

  /// "PRO-2281": o identificador curto que a equipe fala em voz alta.
  final String idPublico;

  /// Nível de verificação pedido (ex.: "Verificado"). Não é a categoria de serviço.
  final String nivel;

  /// Categorias de serviço solicitadas (ex.: Pintor, Eletricista).
  final List<String> categorias;
  final String cidade;
  final DateTime enviadaEm;

  /// Nulo = o profissional não informou o CPF: a tela mostra "Não informado" com alerta.
  final String? cpfMascarado;

  /// Rótulos dos arquivos (ex.: "Frente do documento", "Selfie"). O conteúdo só vem ao revelar.
  final List<String> documentos;
  final List<EnvioVerificacao> enviosAnteriores;
  final StatusVerificacao status;
  final String? motivoDecisao;

  Verificacao comStatus(StatusVerificacao novo, String motivo) => Verificacao(
        id: id,
        profissionalId: profissionalId,
        profissional: profissional,
        idPublico: idPublico,
        nivel: nivel,
        categorias: categorias,
        cidade: cidade,
        enviadaEm: enviadaEm,
        cpfMascarado: cpfMascarado,
        documentos: documentos,
        enviosAnteriores: enviosAnteriores,
        status: novo,
        motivoDecisao: motivo,
        analistaId: analistaId,
        analistaNome: analistaNome,
      );

  Verificacao assumidaPor(String id, String nome) => Verificacao(
        id: this.id,
        profissionalId: profissionalId,
        profissional: profissional,
        idPublico: idPublico,
        nivel: nivel,
        categorias: categorias,
        cidade: cidade,
        enviadaEm: enviadaEm,
        cpfMascarado: cpfMascarado,
        documentos: documentos,
        enviosAnteriores: enviosAnteriores,
        status: StatusVerificacao.emAnalise,
        motivoDecisao: motivoDecisao,
        analistaId: id,
        analistaNome: nome,
      );
}

enum DecisaoDisputa {
  liberarTudo('liberar_tudo', 'Liberar ao profissional'),
  reembolsoTotal('reembolso_total', 'Reembolso total ao cliente'),
  reembolsoParcial('reembolso_parcial', 'Reembolso parcial'),
  novaVisita('nova_visita', 'Nova visita do profissional');

  const DecisaoDisputa(this.codigo, this.rotulo);
  final String codigo;
  final String rotulo;
}

enum StatusDisputa {
  aberta,
  aguardandoProfissional,
  emAnalise,
  aguardandoSegundaPessoa,
  decidida,

  /// Final: as partes se acertaram (Termos 8.2). Não há o que decidir.
  acordo,

  /// Estado que este painel ainda não conhece: só mostra, sem nenhuma ação.
  desconhecida;

  /// Nada mais a decidir.
  bool get encerrada => this == decidida || this == acordo;

  /// Só estes estados aceitam assumir e decidir (o backend confere de novo).
  bool get aceitaDecisao => this == aberta || this == aguardandoProfissional || this == emAnalise;
}

class EventoDisputa {
  const EventoDisputa(this.quando, this.autor, this.texto);
  final DateTime quando;
  final String autor;
  final String texto;
}

class EvidenciaDisputa {
  const EvidenciaDisputa({
    required this.autor,
    required this.tipo,
    required this.texto,
    this.nota = false,
  });
  final String autor;

  /// `relato`, `resposta`, `foto`, `documento` ou `nota_interna`.
  final String tipo;
  final String texto;

  /// Nota interna: só a equipe enxerga.
  final bool nota;
}

/// Divisão do dinheiro na disputa (decisão da equipe ou acordo entre as partes).
class DivisaoDisputa {
  const DivisaoDisputa({
    required this.paraClienteCentavos,
    required this.paraProfissionalCentavos,
    required this.retidoCentavos,
  });

  final int paraClienteCentavos;
  final int paraProfissionalCentavos;
  final int retidoCentavos;
}

/// Resposta de uma ação sobre o selo do profissional (Termos 10.3).
class ResultadoSeloAdmin {
  const ResultadoSeloAdmin({required this.jaExistia, required this.nivelVerificacao, required this.retiradaAberta});
  final bool jaExistia;
  final String nivelVerificacao;
  final bool retiradaAberta;
}

class Disputa {
  const Disputa({
    this.resultadoEsperado,
    required this.id,
    required this.pedido,
    required this.cliente,
    required this.profissional,
    required this.motivo,
    required this.descricao,
    required this.valorEmAnaliseCentavos,
    required this.decisaoAte,
    required this.evidencias,
    required this.linhaDoTempo,
    this.status = StatusDisputa.emAnalise,
    this.decisao,
    this.valorReembolsoCentavos,
    this.divisao,
    this.decididoPor,
    this.titulo = '',
    this.respostaAte,
    this.atrasada = false,
    this.semResposta = false,
    this.responsavelId,
    this.responsavelNome,
    this.desistencia = false,
  });

  /// O que o cliente pediu ao abrir (Termos 8.4): `retrabalho`, `reembolso_parcial` ou
  /// `reembolso_total`. Null = não informado.
  final String? resultadoEsperado;

  final String id;

  /// Caso aberto por desistência com o serviço iniciado (Termos 7.3). Só vem no detalhe.
  final bool desistencia;

  /// Quem assumiu a análise. Só essa pessoa decide (o backend confere).
  final String? responsavelId;
  final String? responsavelNome;

  /// Título legível do pedido (ex.: "Pintura de sala e cozinha"). Vazio = só o motivo.
  final String titulo;

  /// Prazo para o profissional responder; depois dele passa a valer o prazo de decisão.
  final DateTime? respostaAte;
  final bool atrasada;
  final bool semResposta;

  /// Código curto do pedido (ex.: "PED-10482").
  final String pedido;
  final String cliente;
  final String profissional;
  final String motivo;
  final String descricao;
  final int valorEmAnaliseCentavos;
  final DateTime decisaoAte;
  final List<EvidenciaDisputa> evidencias;
  final List<EventoDisputa> linhaDoTempo;
  final StatusDisputa status;
  final DecisaoDisputa? decisao;
  final int? valorReembolsoCentavos;
  final DivisaoDisputa? divisao;

  /// Id de quem decidiu (a segunda pessoa precisa ser outra).
  final String? decididoPor;

  Disputa comDecisao(
    StatusDisputa novo,
    DecisaoDisputa? d,
    int? reembolso, {
    String? por,
    DivisaoDisputa? divisao,
    bool manterDecididoPor = true,
  }) =>
      Disputa(
        id: id,
        pedido: pedido,
        cliente: cliente,
        profissional: profissional,
        motivo: motivo,
        descricao: descricao,
        valorEmAnaliseCentavos: valorEmAnaliseCentavos,
        decisaoAte: decisaoAte,
        evidencias: evidencias,
        linhaDoTempo: linhaDoTempo,
        status: novo,
        decisao: d,
        valorReembolsoCentavos: reembolso,
        divisao: divisao ?? this.divisao,
        decididoPor: manterDecididoPor ? (por ?? decididoPor) : por,
        titulo: titulo,
        respostaAte: respostaAte,
        atrasada: atrasada,
        semResposta: semResposta,
        responsavelId: novo.encerrada ? null : responsavelId,
        responsavelNome: novo.encerrada ? null : responsavelNome,
        desistencia: desistencia,
        resultadoEsperado: resultadoEsperado,
      );

  Disputa assumidaPor(String id, String nome) => Disputa(
        id: this.id,
        pedido: pedido,
        cliente: cliente,
        profissional: profissional,
        motivo: motivo,
        descricao: descricao,
        valorEmAnaliseCentavos: valorEmAnaliseCentavos,
        decisaoAte: decisaoAte,
        evidencias: evidencias,
        linhaDoTempo: linhaDoTempo,
        status: status,
        decisao: decisao,
        valorReembolsoCentavos: valorReembolsoCentavos,
        divisao: divisao,
        decididoPor: decididoPor,
        titulo: titulo,
        respostaAte: respostaAte,
        atrasada: atrasada,
        semResposta: semResposta,
        responsavelId: id,
        responsavelNome: nome,
        desistencia: desistencia,
        resultadoEsperado: resultadoEsperado,
      );
}

/// Caso de "Cliente ausente" (Termos 7.6), como o backend manda. Os valores já vêm calculados.
class CasoAusencia {
  const CasoAusencia({
    required this.pedidoId,
    required this.status,
    required this.chegadaEm,
    this.registradaEm,
    this.justificativaAte,
    this.justificativaTexto,
    this.anexos = const [],
    this.justificativaEnviadaEm,
    this.decisao,
    this.retencaoCentavos,
    this.retencaoJustificativa,
    this.retencaoComprovantes = const [],
    this.cancelamentoStatus,
    this.reembolsoCentavos,
    this.contestarAte,
    this.contestacao,
    this.valorServicoCentavos,
    this.pedidoNumero,
    this.clienteNome,
    this.profissionalNome,
  });

  /// Até quando o cliente contesta a retenção. Calculado pelo backend.
  final DateTime? contestarAte;
  final ContestacaoAusencia? contestacao;
  final int? valorServicoCentavos;
  final int? pedidoNumero;
  final String? clienteNome;
  final String? profissionalNome;

  bool get contestacaoAberta => contestacao?.status == ContestacaoAusencia.aberta;

  static const aguardandoEspera = 'aguardando_espera';
  static const aguardandoJustificativa = 'aguardando_justificativa';
  static const emAnalise = 'em_analise';
  static const aceita = 'justificativa_aceita';
  static const recusada = 'justificativa_recusada';
  static const expirada = 'expirada_sem_justificativa';
  static const propostaRetencao = 'proposta_retencao_enviada';

  final String pedidoId;
  final String status;
  final DateTime chegadaEm;
  final DateTime? registradaEm;
  final DateTime? justificativaAte;
  final String? justificativaTexto;
  final List<String> anexos;
  final DateTime? justificativaEnviadaEm;

  /// Motivo escrito pelo analista.
  final String? decisao;
  final int? retencaoCentavos;
  final String? retencaoJustificativa;
  final List<String> retencaoComprovantes;
  final String? cancelamentoStatus;
  final int? reembolsoCentavos;

  String get pedido {
    if (pedidoNumero != null) return 'PED-$pedidoNumero';
    final limpo = pedidoId.replaceAll('-', '').toUpperCase();
    return 'PED-${limpo.length > 8 ? limpo.substring(0, 8) : limpo}';
  }

  bool get esperaConfirmacao =>
      cancelamentoStatus == propostaRetencao && (status == recusada || status == expirada);

  /// O prazo do cliente passou sem justificativa. Só orienta a tela: o backend confere.
  bool semResposta(DateTime agora) =>
      status == aguardandoJustificativa && justificativaAte != null && agora.isAfter(justificativaAte!);
}

/// Contestação da retenção (Termos 8.7).
class ContestacaoAusencia {
  const ContestacaoAusencia({
    required this.status,
    required this.texto,
    required this.abertaEm,
    required this.responderAte,
    this.protocolo,
    this.resposta,
    this.decididaEm,
  });

  static const aberta = 'aberta';

  /// `aberta`, `mantida`, `alterada` ou `revertida`.
  final String status;
  final String texto;
  final DateTime abertaEm;
  final DateTime responderAte;
  final String? protocolo;
  final String? resposta;
  final DateTime? decididaEm;
}

/// Prova de um caso, com link assinado curto. `url` nula = arquivo que o servidor não liberou.
class AnexoCaso {
  const AnexoCaso(
      {required this.tipo, required this.arquivoId, this.enviadoPor, this.url, this.expiraEmSegundos, this.tipoConteudo});

  /// `content_type` do arquivo (ex.: image/jpeg), quando o servidor informa.
  final String? tipoConteudo;
  final String tipo;
  final String arquivoId;
  final String? enviadoPor;
  final String? url;
  final int? expiraEmSegundos;
}

class MensagemLida {
  const MensagemLida({
    required this.autorId,
    required this.texto,
    required this.textoExibido,
    required this.mascarada,
    required this.enviadaEm,
  });
  final String autorId;

  /// Original, como foi escrito.
  final String texto;

  /// O que a outra parte viu no app.
  final String textoExibido;
  final bool mascarada;
  final DateTime enviadaEm;
}

class ConversaLida {
  const ConversaLida({required this.id, required this.profissionalId, required this.mensagens});
  final String id;
  final String profissionalId;
  final List<MensagemLida> mensagens;
}

/// O que aconteceu com os pedidos da conta suspensa, encerrada ou bloqueada (Termos 20.6).
class ResumoPedidos {
  const ResumoPedidos({
    this.futurosCancelados = 0,
    this.emAndamento = 0,
    this.emAndamentoIds = const [],
    this.futurosPendentesIds = const [],
  });
  final int futurosCancelados;
  final int emAndamento;
  final List<String> emAndamentoIds;

  /// Futuros que o servidor não cancelou.
  final List<String> futurosPendentesIds;
}

/// Falha da plataforma que pode adiar prazos (Termos 22.3). [origem]: `app` ou `pagamento`.
class JanelaIndisponibilidade {
  const JanelaIndisponibilidade({
    required this.id,
    required this.origem,
    required this.inicioEm,
    required this.ativa,
    required this.motivo,
    required this.criadaPor,
    this.fimEm,
    this.encerradaPor,
  });
  final String id;
  final String origem;
  final DateTime inicioEm;
  final DateTime? fimEm;
  final bool ativa;
  final String motivo;
  final String criadaPor;
  final String? encerradaPor;
}

/// Caso aberto de check-out sem o Código Final (Termos 5.7, fase 1).
/// Nenhum campo daqui libera ou estorna dinheiro.
class CasoCheckoutSemCodigo {
  const CasoCheckoutSemCodigo({
    required this.id,
    required this.pedidoId,
    required this.clienteId,
    this.profissionalId,
    required this.checkOutEm,
    this.contatadoEm,
    this.canal,
    this.responderAte,
    this.vencido = false,
  });

  final String id;
  final String pedidoId;
  final String clienteId;
  final String? profissionalId;
  final DateTime checkOutEm;
  final DateTime? contatadoEm;
  final String? canal;
  final DateTime? responderAte;
  final bool vencido;

  bool get semContato => contatadoEm == null;
}

/// Retorno da decisão administrativa no check-out sem Código Final (Termos 5.7, fase 2).
class ResultadoDecisaoCheckoutSemCodigo {
  const ResultadoDecisaoCheckoutSemCodigo({
    required this.id,
    required this.pedidoId,
    required this.estadoPedido,
    required this.decisao,
    required this.analistaId,
    required this.justificativa,
    required this.decididoEm,
    required this.chaveIdempotencia,
    this.idempotente = false,
  });

  final String id;
  final String pedidoId;
  final String estadoPedido;
  final String decisao;
  final String analistaId;
  final String justificativa;
  final DateTime decididoEm;
  final String chaveIdempotencia;
  final bool idempotente;
}

/// Pedido de informação adicional em uma disputa (Termos 8.4).
class PedidoInfoDisputa {
  const PedidoInfoDisputa({
    required this.id,
    required this.disputaId,
    required this.pedidoId,
    required this.solicitanteId,
    required this.destinatarioPapel,
    required this.mensagem,
    required this.solicitadoEm,
    required this.responderAte,
    required this.status,
    this.respondidoEm,
    this.respostaTexto,
    this.encerradoSemRespostaEm,
  });

  final String id;
  final String disputaId;
  final String pedidoId;
  final String solicitanteId;

  /// `cliente` ou `profissional`.
  final String destinatarioPapel;
  final String mensagem;
  final DateTime solicitadoEm;
  final DateTime responderAte;
  final DateTime? respondidoEm;
  final String? respostaTexto;
  final DateTime? encerradoSemRespostaEm;

  /// `aguardando_resposta`, `vencido`, `respondido` ou `encerrado_sem_resposta`.
  final String status;
}

/// Profissional com faltas ou cancelamentos repetidos no período (Termos 7.7).
class FaltaRepetidaProfissional {
  const FaltaRepetidaProfissional({
    required this.profissionalId,
    required this.totalCancelamentos,
    required this.ultimoCancelamentoEm,
    required this.periodoDias,
  });

  final String profissionalId;
  final int totalCancelamentos;
  final DateTime ultimoCancelamentoEm;
  final int periodoDias;
}

/// Solicitação de isenção por evento externo / força maior (Termos 7.8 e 22.6).
class EventoForcaMaior {
  const EventoForcaMaior({
    required this.id,
    required this.pedidoId,
    required this.solicitanteId,
    required this.solicitantePapel,
    required this.acaoSolicitada,
    required this.descricao,
    this.comprovantes = const [],
    required this.status,
    this.criadoEm,
    this.analistaId,
    this.justificativaDecisao,
    this.decididoEm,
    this.chaveIdempotencia,
    this.idempotente = false,
  });

  final String id;
  final String pedidoId;
  final String solicitanteId;

  /// `cliente` ou `profissional`.
  final String solicitantePapel;

  /// `reagendar` ou `cancelar`.
  final String acaoSolicitada;
  final String descricao;
  final List<String> comprovantes;

  /// `pendente`, `aprovado` ou `recusado`.
  final String status;
  final DateTime? criadoEm;
  final String? analistaId;
  final String? justificativaDecisao;
  final DateTime? decididoEm;
  final String? chaveIdempotencia;
  final bool idempotente;
}

/// Medida de conta (Termos 20), como o backend manda.
class Medida {
  const Medida({
    this.avisadoEm,
    this.semFalta,
    this.motivoFraude = false,
    this.limiteRetencaoCentavos,
    required this.id,
    required this.usuarioId,
    required this.tipo,
    required this.motivoAoUsuario,
    required this.motivoCompleto,
    required this.clausulas,
    required this.inicioEm,
    required this.efeito,
    required this.comoContestar,
    required this.vigente,
    this.protocolo,
    this.usuarioNome,
    this.fimEm,
    this.detalheAdiado = false,
    this.revertidaEm,
    this.contestavelAte,
    this.contestacao,
    this.origem = 'analista',
    this.aplicadaPor,
    this.notaInterna,
    this.justificativaAdiamento,
    this.aplicadaPorNome,
    this.contestacaoAnalistaNome,
    this.infracaoGrave = false,
    this.impedirNovaConta = false,
    this.pedidos,
  });

  /// Null = o servidor não mandou os campos. Só vale em suspensão ou encerramento em vigor.
  final ResumoPedidos? pedidos;

  final String? aplicadaPorNome;
  final String? contestacaoAnalistaNome;

  /// Quando o usuário foi avisado.
  final DateTime? avisadoEm;

  /// Encerramento avisado que ainda não começou (Termos 20.8): a conta segue ativa.
  bool get agendada =>
      tipo == 'encerramento' &&
      revertidaEm == null &&
      !vigente &&
      fimEm == null &&
      avisadoEm != null &&
      inicioEm.isAfter(avisadoEm!);

  /// Encerramento sem falta do usuário (Termos 13.10). Null = não informado.
  final bool? semFalta;

  /// Trava de saques por fraude (Termos 20.6) e o limite que o backend registrou.
  final bool motivoFraude;
  final int? limiteRetencaoCentavos;
  final bool infracaoGrave;
  final bool impedirNovaConta;
  final String id;
  final String? protocolo;
  final String usuarioId;
  final String? usuarioNome;
  final String tipo;

  /// O texto que o usuário lê (genérico quando o detalhe foi adiado).
  final String motivoAoUsuario;

  /// O motivo escrito pelo analista.
  final String motivoCompleto;
  final List<String> clausulas;
  final DateTime inicioEm;
  final DateTime? fimEm;
  final String efeito;
  final String comoContestar;
  final bool detalheAdiado;
  final bool vigente;
  final DateTime? revertidaEm;
  final DateTime? contestavelAte;
  final ContestacaoMedida? contestacao;
  final String origem;
  final String? aplicadaPor;
  final String? notaInterna;
  final String? justificativaAdiamento;

  bool get contestacaoAberta => contestacao?.status == 'aberta' || contestacao?.status == 'em_analise';
}

class ContestacaoMedida {
  const ContestacaoMedida({
    required this.status,
    required this.versao,
    required this.canal,
    required this.abertaEm,
    required this.responderAte,
    this.protocolo,
    this.resposta,
    this.decididaEm,
    this.anexos = const [],
  });
  final List<AnexoContestacao> anexos;
  final String status;
  final String versao;
  final String canal;
  final DateTime abertaEm;
  final DateTime responderAte;
  final String? protocolo;
  final String? resposta;
  final DateTime? decididaEm;
}

class FiltroMedidas {
  const FiltroMedidas({this.usuarioId, this.tipo, this.vigentes = false, this.contestacaoAberta = false});
  final String? usuarioId;
  final String? tipo;
  final bool vigentes;
  final bool contestacaoAberta;

  @override
  bool operator ==(Object other) =>
      other is FiltroMedidas &&
      other.usuarioId == usuarioId &&
      other.tipo == tipo &&
      other.vigentes == vigentes &&
      other.contestacaoAberta == contestacaoAberta;

  @override
  int get hashCode => Object.hash(usuarioId, tipo, vigentes, contestacaoAberta);
}

/// Pedido de nova medida. Textos opcionais nulos usam o padrão do servidor.
class NovaMedida {
  const NovaMedida({
    this.semFalta,
    this.motivoFraude = false,
    this.limiteRetencaoCentavos,
    required this.usuarioId,
    required this.tipo,
    required this.motivo,
    required this.clausulas,
    this.dias,
    this.efeito,
    this.comoContestar,
    this.detalheAdiado = false,
    this.justificativaAdiamento,
    this.notaInterna,
    this.infracaoGrave = false,
    this.impedirNovaConta = false,
  });
  final String usuarioId;
  final String tipo;
  final String motivo;
  final List<String> clausulas;
  final int? dias;
  final String? efeito;
  final String? comoContestar;
  final bool detalheAdiado;
  final String? justificativaAdiamento;
  final String? notaInterna;
  final bool infracaoGrave;
  final bool impedirNovaConta;
  final bool motivoFraude;
  final int? limiteRetencaoCentavos;

  /// Só em encerramento; a tela obriga a escolher.
  final bool? semFalta;
}

/// Exclusividade paga pelo cliente (Termos 13.6).
class ExclusividadeCliente {
  const ExclusividadeCliente({
    required this.id,
    required this.pedidoId,
    required this.clienteId,
    required this.profissionalId,
    required this.status,
    required this.moedas,
    required this.estornada,
    required this.criadaEm,
    this.clienteNome,
    this.profissionalNome,
    this.encerradaEm,
    this.motivoEncerramento,
  });
  final String id;
  final String pedidoId;
  final String clienteId;
  final String profissionalId;
  final String? clienteNome;
  final String? profissionalNome;
  final String status;
  final int moedas;
  final bool estornada;
  final DateTime criadaEm;
  final DateTime? encerradaEm;
  final String? motivoEncerramento;
}

/// Arquivo do pedido que serve de comprovante da retenção. [url] vale pouco tempo.
class ArquivoComprovante {
  const ArquivoComprovante({
    required this.arquivoId,
    required this.finalidade,
    required this.enviadoPor,
    required this.tamanhoBytes,
    required this.enviadoEm,
    required this.url,
    required this.expiraEmSegundos,
    this.tipoConteudo,
  });
  final String arquivoId;
  final String finalidade;

  /// `profissional` ou `equipe`.
  final String enviadoPor;
  final String? tipoConteudo;
  final int tamanhoBytes;
  final DateTime enviadoEm;
  final String url;
  final int expiraEmSegundos;
}

/// Link curto para enviar um arquivo (PUT). [id] é o `envio_id` ou o `anexo_id`.
class EnvioAssinado {
  const EnvioAssinado({required this.id, required this.url, required this.expiraEmSegundos});
  final String id;
  final String url;
  final int expiraEmSegundos;
}

/// Prova de contestação de medida. [url] só vem quando a pessoa abre, com motivo.
class AnexoContestacao {
  const AnexoContestacao(
      {required this.anexoId, required this.tipoConteudo, required this.tamanhoBytes, this.url, this.expiraEmSegundos});
  final String anexoId;
  final String tipoConteudo;
  final int tamanhoBytes;
  final String? url;
  final int? expiraEmSegundos;
}

/// Compensação: reembolso descontado de repasses futuros (Termos 8.6). Todos os valores, em
/// centavos, vêm calculados do backend.
class Compensacao {
  /// Decisão posterior mais baixa sem tratamento: `reducao`, `reversao`, `analisar` ou null.
  final String? revisao;
  final String? revisaoContestacaoId;

  /// O servidor decide o que esta pessoa pode fazer; o painel não deduz.
  final bool podeReduzir;
  final int? reducaoMaximaCentavos;
  final bool podeCancelar;

  /// Valor registrado antes das reduções; null se o servidor não informa. [valorCentavos] é o que vale hoje.
  final int? valorOriginalCentavos;
  final int reduzidoCentavos;

  /// O que voltou ao profissional por causa de reduções.
  final int devolvidoReducaoCentavos;

  /// Informado pelo servidor: dívida aberta com a decisão revertida ou reduzida; nada é descontado.
  final bool suspensa;

  const Compensacao({
    this.suspensa = false,
    this.revisao,
    this.revisaoContestacaoId,
    this.podeReduzir = false,
    this.reducaoMaximaCentavos,
    this.podeCancelar = false,
    this.valorOriginalCentavos,
    this.reduzidoCentavos = 0,
    this.devolvidoReducaoCentavos = 0,
    required this.id,
    required this.pedidoId,
    required this.origem,
    required this.valorCentavos,
    required this.compensadoCentavos,
    required this.restanteCentavos,
    required this.motivo,
    required this.status,
    required this.criadaEm,
    this.avisadoEm,
    this.canceladaEm,
    this.motivoCancelamento,
  });
  final String id;
  final String pedidoId;

  /// `disputa`, `disputa_contestacao` ou `regresso`.
  final String origem;
  final int valorCentavos;
  final int compensadoCentavos;
  final int restanteCentavos;

  /// O profissional lê.
  final String motivo;

  /// `aberta`, `quitada` ou `cancelada`.
  final String status;
  final DateTime criadaEm;

  /// Sem aviso registrado, nada é descontado.
  final DateTime? avisadoEm;
  final DateTime? canceladaEm;
  final String? motivoCancelamento;
}

/// Decisão de disputa em um momento: resultado e quanto volta ao cliente, vindos do backend.
class DecisaoResumida {
  const DecisaoResumida(this.resultado, this.reembolsoCentavos);
  final String resultado;
  final int reembolsoCentavos;
}

/// Contestação da decisão de uma disputa (Termos 8.7).
class ContestacaoDisputa {
  const ContestacaoDisputa({
    required this.id,
    required this.protocolo,
    required this.pedidoId,
    required this.disputaId,
    required this.contestanteId,
    required this.oQueFaltou,
    required this.canal,
    required this.status,
    required this.abertaEm,
    required this.contestarAte,
    required this.responderAte,
    required this.efeitoFinanceiro,
    this.contestantePapel,
    this.anexos = const [],
    this.atrasada = false,
    this.analistaId,
    this.resposta,
    this.novaDecisao,
    this.novoValorReembolsoCentavos,
    this.aprovadaPor,
    this.decididaEm,
    this.valorCongeladoCentavos,
    this.decisaoOriginal,
    this.decisaoVigente,
    this.decididaPor,
    this.disputaAprovadaPor,
  });

  static const aguardandoAprovacao = 'aguardando_aprovacao';
  static const pendenteFinanceiro = 'pendente_financeiro';

  final String id;
  final String protocolo;
  final String pedidoId;
  final String disputaId;
  final String contestanteId;

  /// `cliente` ou `profissional`.
  final String? contestantePapel;
  final String oQueFaltou;
  final List<String> anexos;
  final String canal;

  /// `aberta`, `em_analise`, `aguardando_aprovacao`, `mantida`, `alterada` ou `revertida`.
  final String status;
  final DateTime abertaEm;
  final DateTime contestarAte;
  final DateTime responderAte;
  final bool atrasada;
  final String? analistaId;
  final String? resposta;
  final String? novaDecisao;
  final int? novoValorReembolsoCentavos;
  final String? aprovadaPor;
  final DateTime? decididaEm;

  /// `nenhum`, `pendente_financeiro` ou `executado`.
  final String efeitoFinanceiro;

  // Só no detalhe.
  final int? valorCongeladoCentavos;
  final DecisaoResumida? decisaoOriginal;
  final DecisaoResumida? decisaoVigente;
  final String? decididaPor;
  final String? disputaAprovadaPor;

  bool get paraDecidir => status == 'aberta' || status == 'em_analise';
}

class FiltroContestacoes {
  const FiltroContestacoes({this.status, this.efeito, this.pedidoId, this.atrasadas = false});
  final String? status;
  final String? efeito;
  final String? pedidoId;
  final bool atrasadas;

  @override
  bool operator ==(Object other) =>
      other is FiltroContestacoes &&
      other.status == status &&
      other.efeito == efeito &&
      other.pedidoId == pedidoId &&
      other.atrasadas == atrasadas;

  @override
  int get hashCode => Object.hash(status, efeito, pedidoId, atrasadas);
}

/// Pedido de volta ao profissional (regresso, Termos 17.4): um propõe, outra pessoa decide.
class Regresso {
  const Regresso({
    required this.id,
    required this.pedidoId,
    required this.profissionalId,
    required this.referencia,
    required this.valorCentavos,
    required this.motivo,
    required this.status,
    required this.propostaPor,
    required this.propostaEm,
    this.decididaEm,
    this.motivoDecisao,
    this.compensacaoId,
  });
  final String id;
  final String pedidoId;
  final String profissionalId;
  final String referencia;
  final int valorCentavos;

  /// O profissional lê.
  final String motivo;

  /// `proposta`, `aprovada` ou `recusada`.
  final String status;
  final String propostaPor;
  final DateTime propostaEm;
  final DateTime? decididaEm;
  final String? motivoDecisao;
  final String? compensacaoId;
}

/// Incidente de segurança (Termos 9.3 a 9.6), como o backend manda.
class Incidente {
  const Incidente({
    required this.id,
    required this.protocolo,
    required this.canal,
    required this.tipo,
    required this.descricao,
    required this.status,
    required this.abertoEm,
    required this.cautelaAte,
    this.contato,
    this.pedidoId,
    this.cautelaAdotadaEm,
    this.responsavelId,
    this.desfecho,
    this.encerradoEm,
    this.medidas = const [],
    this.cautelaAtrasada = false,
    this.sinaisAntifraude = const [],
  });

  /// Códigos de sinal para a equipe conferir (9.5). Não são prova de fraude.
  final List<String> sinaisAntifraude;

  /// O backend diz que passou o prazo sem cautela adotada. Ausente = falso: nada a mostrar.
  final bool cautelaAtrasada;
  final String id;
  final String protocolo;
  final String canal;
  final String tipo;
  final String descricao;
  final String? contato;
  final String? pedidoId;

  /// `aberto`, `cautela_adotada`, `em_apuracao` ou `encerrado`.
  final String status;
  final DateTime abertoEm;

  /// Prazo das 24 h para a cautela (calculado pelo backend).
  final DateTime cautelaAte;
  final DateTime? cautelaAdotadaEm;
  final String? responsavelId;
  final String? desfecho;
  final DateTime? encerradoEm;
  final List<MedidaIncidente> medidas;

  bool get encerrado => status == 'encerrado';
}

class MedidaIncidente {
  const MedidaIncidente(
      {required this.id, required this.tipo, required this.descricao, required this.origem, required this.aplicadaEm});
  final String id;
  final String tipo;
  final String descricao;

  /// `analista` ou `automatica`.
  final String origem;
  final DateTime aplicadaEm;
}

/// Ocultação de avaliação aplicada ou revertida (Termos 12.6).
class OcultacaoAvaliacao {
  const OcultacaoAvaliacao({
    required this.id,
    required this.avaliacaoId,
    required this.motivo,
    required this.explicacao,
    required this.analistaId,
    required this.ocultadaEm,
    required this.statusAnterior,
    this.autorAvisadoEm,
    this.revertidaEm,
    this.revertidaPor,
  });

  final String id;
  final String avaliacaoId;
  final String motivo;
  final String explicacao;
  final String analistaId;
  final DateTime ocultadaEm;
  final String statusAnterior;
  final DateTime? autorAvisadoEm;
  final DateTime? revertidaEm;
  final String? revertidaPor;
}

/// Pedido de revisão ou contestação de ocultação de avaliação (Termos 12.6, 12.7 e 20.5).
class RevisaoAvaliacao {
  const RevisaoAvaliacao({
    required this.id,
    required this.protocolo,
    required this.avaliacaoId,
    required this.tipo,
    required this.solicitanteId,
    required this.justificativa,
    required this.canal,
    required this.abertaEm,
    required this.responderAte,
    required this.status,
    this.ocultacaoId,
    this.anexos = const [],
    this.analistaId,
    this.resposta,
    this.mesmoAnalistaJustificativa,
    this.decididaEm,
    this.ocultacaoAplicadaId,
  });

  final String id;
  final String protocolo;
  final String avaliacaoId;

  /// `revisao` ou `contestacao_ocultacao`.
  final String tipo;
  final String? ocultacaoId;
  final String solicitanteId;
  final String justificativa;
  final List<String> anexos;
  final String canal;
  final DateTime abertaEm;
  final DateTime responderAte;

  /// `aberta`, `em_analise`, `aceita` ou `recusada`.
  final String status;
  final String? analistaId;
  final String? resposta;
  final String? mesmoAnalistaJustificativa;
  final DateTime? decididaEm;
  final String? ocultacaoAplicadaId;

  bool get decidida => status == 'aceita' || status == 'recusada';
  bool atrasada(DateTime agora) => !decidida && agora.isAfter(responderAte);
}

/// Pedido de titular LGPD ou revisão de decisão automatizada (Termos 14.9 e 14.10).
class PedidoTitularLgpd {
  const PedidoTitularLgpd({
    required this.id,
    required this.protocolo,
    required this.tipo,
    required this.descricao,
    required this.canal,
    required this.abertoEm,
    required this.responderAte,
    required this.status,
    this.usuarioId,
    this.contato,
    this.decisaoAutomatizada,
    this.referenciaTipo,
    this.referenciaId,
    this.exclusaoId,
    this.analistaId,
    this.resposta,
    this.motivoNaoAtendido,
    this.criteriosInformados,
    this.respondidoEm,
  });

  final String id;
  final String protocolo;
  final String? usuarioId;
  final String? contato;
  final String tipo;
  final String? decisaoAutomatizada;
  final String? referenciaTipo;
  final String? referenciaId;
  final String descricao;
  final String canal;
  final String? exclusaoId;
  final DateTime abertoEm;
  final DateTime responderAte;

  /// `aberto`, `em_analise`, `aguardando_titular`, `atendido`, `atendido_parcial` ou `negado`.
  final String status;
  final String? analistaId;
  final String? resposta;
  final String? motivoNaoAtendido;
  final String? criteriosInformados;
  final DateTime? respondidoEm;

  bool get respondido => status == 'atendido' || status == 'atendido_parcial' || status == 'negado';

  /// Prazo legal vencido. O relógio local serve apenas para destacar na tela.
  bool atrasado(DateTime agora) => !respondido && agora.isAfter(responderAte);
}

/// Impedimento de novo cadastro por infração grave (Termos 20.9).
class ImpedimentoCadastro {
  const ImpedimentoCadastro({
    required this.id,
    required this.medidaId,
    required this.tipoIdentificador,
    required this.criadoPor,
    required this.criadoEm,
    this.revogadoEm,
    this.revogadoPor,
    this.motivoRevogacao,
  });

  final String id;
  final String medidaId;
  final String tipoIdentificador;
  final String criadoPor;
  final DateTime criadoEm;
  final DateTime? revogadoEm;
  final String? revogadoPor;
  final String? motivoRevogacao;

  bool get ativo => revogadoEm == null;
}

/// Pedido de retorno de conta após encerramento (Termos 20.9).
class PedidoRetornoConta {
  const PedidoRetornoConta({
    required this.id,
    required this.protocolo,
    required this.usuarioId,
    required this.medidaId,
    required this.justificativaUsuario,
    required this.canal,
    required this.status,
    required this.solicitadoEm,
    required this.prazoDiasAplicado,
    required this.elegivelAPartirDe,
    this.analistaId,
    this.decisaoMotivo,
    this.riscoIdentificado = false,
    this.decididoEm,
  });

  final String id;
  final String protocolo;
  final String usuarioId;
  final String medidaId;
  final String justificativaUsuario;
  final String canal;

  /// `aberto`, `em_analise`, `aprovado` ou `recusado`.
  final String status;
  final DateTime solicitadoEm;
  final int prazoDiasAplicado;
  final DateTime elegivelAPartirDe;
  final String? analistaId;
  final String? decisaoMotivo;
  final bool riscoIdentificado;
  final DateTime? decididoEm;

  bool get decidido => status == 'aprovado' || status == 'recusado';
}

/// Resposta de `decidirDisputa`: o backend diz se ficou decidida ou esperando a segunda pessoa.
class ResultadoDecisao {
  const ResultadoDecisao({required this.status, this.mensagem});
  final StatusDisputa status;
  final String? mensagem;
}

/// Estado do pagamento no provedor. O painel nunca mostra "pago" antes de `confirmado` (D13).
enum StatusProvedor { aguardandoConfirmacao, confirmado, falhou, reembolsado, reembolsadoParcial }

class LancamentoEspelho {
  const LancamentoEspelho({
    required this.id,
    required this.data,
    required this.descricao,
    required this.valorCentavos,
    required this.status,
    required this.pedido,
    required this.refProvedor,
    this.divergente = false,
    this.tipo = 'Cobrança',
    this.conciliado = false,
  });

  /// Cobrança, repasse, reembolso ou taxa (RF-PAG-03).
  final String tipo;

  final bool conciliado;

  final String id;
  final DateTime data;
  final String descricao;

  /// Positivo entra, negativo sai. Sempre centavos inteiros.
  final int valorCentavos;
  final StatusProvedor status;
  final String pedido;
  final String refProvedor;
  final bool divergente;
}

class ResumoConciliacao {
  const ResumoConciliacao({
    required this.confirmadoCentavos,
    required this.estornadoCentavos,
    required this.emAndamentoCentavos,
    required this.divergencias,
    required this.atualizadoEm,
    this.cobrancas = 0,
    this.reembolsos = 0,
    this.valorDivergenteCentavos = 0,
  });
  final int cobrancas;
  final int reembolsos;
  final int valorDivergenteCentavos;
  final int confirmadoCentavos;
  final int estornadoCentavos;
  final int emAndamentoCentavos;
  final int divergencias;
  final DateTime atualizadoEm;
}

class CategoriaProfissional {
  const CategoriaProfissional({required this.nome, required this.ativaNoPerfil, required this.ativaNaPlataforma});
  final String nome;
  final bool ativaNoPerfil;
  final bool ativaNaPlataforma;
}

class EventoUsuario {
  const EventoUsuario(this.em, this.texto);
  final DateTime em;
  final String texto;
}

class UsuarioBusca {
  const UsuarioBusca({
    this.travaFraudeVigente,
    this.nivelVerificacao,
    required this.id,
    required this.nome,
    required this.tipo,
    required this.status,
    this.emailMascarado,
    this.cpfMascarado,
    this.telefoneMascarado,
    this.idPublico = '',
    this.cidade,
    this.categorias = const [],
    this.historico = const [],
  });
  final String id;
  final String nome;
  final String tipo;
  final String status;
  final String? emailMascarado;
  final String? cpfMascarado;
  final String? telefoneMascarado;

  /// "PRO-2281": o identificador curto que a equipe fala em voz alta.
  final String idPublico;
  final String? cidade;

  /// Trava de saques por fraude em vigor. Null = não informado (nunca "sem trava").
  final bool? travaFraudeVigente;

  /// `nivel_verificacao` como o servidor manda. Null = não informado.
  final String? nivelVerificacao;

  /// Só para profissional: as categorias cadastradas no perfil (RF-BUS-03).
  final List<CategoriaProfissional> categorias;
  final List<EventoUsuario> historico;
}

class ItemDiagnostico {
  const ItemDiagnostico({required this.ok, required this.titulo, required this.detalhe});
  final bool ok;
  final String titulo;
  final String detalhe;
}

/// Resposta de "por que este pedido não aparece para este profissional?" (RN-01).
class DiagnosticoPedido {
  const DiagnosticoPedido({
    required this.pedido,
    required this.titulo,
    required this.categoria,
    required this.aparece,
    required this.itens,
  });
  final String pedido;
  final String titulo;
  final String categoria;
  final bool aparece;
  final List<ItemDiagnostico> itens;
}

class DadosPessoais {
  const DadosPessoais({this.email, required this.cpf, required this.telefone, this.nascimento});
  final String? email;
  final String cpf;
  final String telefone;
  final String? nascimento;
}

class PedidoBusca {
  const PedidoBusca({
    required this.id,
    required this.titulo,
    required this.cliente,
    required this.status,
    required this.valorCentavos,
    this.codigo = '',
    this.categoria,
    this.cidade,
    this.profissional,
  });
  final String id;

  /// Código curto ("PED-10482"); a linha mostra isto e o título, nunca só o UUID.
  final String codigo;
  final String titulo;
  final String cliente;
  final String? profissional;
  final String? categoria;
  final String? cidade;
  final String status;
  final int valorCentavos;
}

/// Filtros da fila do atendimento (todos opcionais).
class FiltroChamados {
  const FiltroChamados({this.status, this.categoria, this.prioridade, this.responsavelId, this.protocolo, this.atrasados = false});
  final String? status;
  final String? categoria;
  final String? prioridade;
  final String? responsavelId;
  final String? protocolo;
  final bool atrasados;

  @override
  bool operator ==(Object other) =>
      other is FiltroChamados &&
      other.status == status &&
      other.categoria == categoria &&
      other.prioridade == prioridade &&
      other.responsavelId == responsavelId &&
      other.protocolo == protocolo &&
      other.atrasados == atrasados;

  @override
  int get hashCode => Object.hash(status, categoria, prioridade, responsavelId, protocolo, atrasados);
}

/// Contato recebido fora do app, registrado pela equipe.
class NovoContato {
  const NovoContato({
    required this.canal,
    required this.categoria,
    required this.assunto,
    required this.texto,
    this.nomeContato,
    this.contato,
    this.usuarioId,
    this.pedidoId,
    this.prioridade = 'normal',
  });
  final String canal;
  final String categoria;
  final String assunto;
  final String texto;
  final String? nomeContato;
  final String? contato;
  final String? usuarioId;
  final String? pedidoId;
  final String prioridade;
}

/// Chamado do atendimento (Termos 25), como o backend manda.
class Chamado {
  const Chamado({
    required this.id,
    required this.protocolo,
    required this.assunto,
    required this.solicitante,
    required this.status,
    required this.abertoEm,
    required this.categoria,
    required this.canal,
    required this.responderAte,
    this.prioridade = 'normal',
    this.usuarioId,
    this.nomeContato,
    this.contato,
    this.pedidoId,
    this.responsavelId,
    this.responsavelNome,
    this.contestacaoRetencao = false,
    this.novoPrazoAte,
    this.motivoExtensao,
    this.primeiraRespostaEm,
    this.encerradoEm,
    this.atrasado = false,
    this.mensagens = const [],
  });

  final String id;
  final String protocolo;
  final String assunto;
  final String solicitante;

  /// `aberto`, `em_atendimento`, `aguardando_usuario`, `respondido` ou `encerrado`.
  final String status;
  final DateTime abertoEm;
  final String categoria;
  final String canal;
  final DateTime responderAte;
  final String prioridade;
  final String? usuarioId;
  final String? nomeContato;
  final String? contato;
  final String? pedidoId;
  final String? responsavelId;
  final String? responsavelNome;

  /// Contestação de retenção: não se encerra pelo atendimento (quem marca é o backend).
  final bool contestacaoRetencao;
  final DateTime? novoPrazoAte;
  final String? motivoExtensao;
  final DateTime? primeiraRespostaEm;
  final DateTime? encerradoEm;

  /// Calculado pelo backend.
  final bool atrasado;

  /// Só vem no detalhe.
  final List<MensagemChamado> mensagens;

  DateTime get prazo => novoPrazoAte ?? responderAte;
  bool get encerrado => status == 'encerrado';
}

class MensagemChamado {
  const MensagemChamado({required this.autor, required this.texto, required this.criadaEm, this.interna = false});

  /// `usuario`, `equipe` ou `sistema`.
  final String autor;
  final String texto;
  final DateTime criadaEm;
  final bool interna;
}

class CategoriaAdmin {
  const CategoriaAdmin({
    required this.id,
    required this.nome,
    required this.ativa,
    required this.profissionais,
    this.slug = '',
    this.icone,
    this.garantiaDias,
    this.ordem = 0,
    this.aceitaRemoto = false,
  });
  final String id;
  final String nome;
  final bool ativa;
  final int profissionais;
  final String slug;
  final String? icone;
  final int? garantiaDias;
  final int ordem;

  /// O serviço desta categoria também pode ser feito de forma remota (o cliente escolhe entre
  /// presencial e remoto). Padrão: só presencial, com endereço obrigatório.
  final bool aceitaRemoto;

  CategoriaAdmin comAtiva(bool valor) => CategoriaAdmin(
        id: id,
        nome: nome,
        ativa: valor,
        profissionais: profissionais,
        slug: slug,
        icone: icone,
        garantiaDias: garantiaDias,
        ordem: ordem,
        aceitaRemoto: aceitaRemoto,
      );
}

class CidadeAdmin {
  const CidadeAdmin({
    required this.id,
    required this.nome,
    required this.uf,
    required this.ativa,
    this.centroLat,
    this.centroLng,
  });
  final String id;
  final String nome;
  final String uf;
  final bool ativa;
  final double? centroLat;
  final double? centroLng;
}

enum UnidadeConfig {
  centavos('centavos'),
  bps('bps'),
  horas('horas'),
  minutos('minutos'),
  dias('dias'),
  diasUteis('dias_uteis'),
  quantidade('quantidade');

  const UnidadeConfig(this.codigo);
  final String codigo;
}

/// Catálogo de um parâmetro (`config_definicoes`): o limite vem do banco, não do código.
class ConfigDefinicao {
  const ConfigDefinicao({
    required this.chave,
    required this.descricao,
    required this.unidade,
    required this.minimo,
    required this.maximo,
    required this.exigeDuplaAprovacao,
  });
  final String chave;
  final String descricao;
  final UnidadeConfig unidade;
  final int minimo;
  final int maximo;
  final bool exigeDuplaAprovacao;
}

enum StatusVersao { rascunho, aguardandoAprovacao, aprovada, vigente, substituida, revertida }

class ConfigVersao {
  const ConfigVersao({
    required this.id,
    required this.numero,
    required this.status,
    required this.motivo,
    required this.criadaPor,
    required this.criadaEm,
    required this.valores,
    this.aprovadaPor,
    this.criadaPorNome,
    this.aprovadaPorNome,
  });
  final String id;
  final int numero;
  final StatusVersao status;
  final String motivo;

  /// Id de quem propôs (a regra "quem propõe não aprova" compara ids).
  final String criadaPor;
  final DateTime criadaEm;
  final String? aprovadaPor;

  /// Nomes para mostrar na tela (nunca o id).
  final String? criadaPorNome;
  final String? aprovadaPorNome;

  /// chave -> valor inteiro na unidade da definição.
  final Map<String, int> valores;

  ConfigVersao comStatus(StatusVersao novo, {String? aprovadaPor, String? aprovadaPorNome}) => ConfigVersao(
        id: id,
        numero: numero,
        status: novo,
        motivo: motivo,
        criadaPor: criadaPor,
        criadaEm: criadaEm,
        valores: valores,
        aprovadaPor: aprovadaPor ?? this.aprovadaPor,
        criadaPorNome: criadaPorNome,
        aprovadaPorNome: aprovadaPorNome ?? this.aprovadaPorNome,
      );
}

class ConfigAtual {
  const ConfigAtual({required this.definicoes, required this.versoes});
  final List<ConfigDefinicao> definicoes;
  final List<ConfigVersao> versoes;
}

class EntradaAuditoria {
  const EntradaAuditoria({
    required this.id,
    required this.ocorridaEm,
    required this.ator,
    required this.acao,
    required this.entidade,
    required this.motivo,
    this.hash,
    this.atorNome,
    this.entidadeNome,
    this.detalhes = const {},
  });
  final int id;
  final DateTime ocorridaEm;

  /// Identificador técnico de quem agiu (id ou e-mail). A tela mostra [atorNome] quando existe.
  final String ator;
  final String? atorNome;

  /// Código técnico da ação (ex.: `categoria.desativada`). Fica no detalhe expansível.
  final String acao;

  /// Entidade técnica (ex.: `categorias:uuid`).
  final String entidade;
  final String? entidadeNome;
  final String? motivo;

  /// Campos do que ficou depois da ação (ex.: status novo, relatório exportado).
  final Map<String, dynamic> detalhes;

  /// Hash da linha (a cadeia é conferida pelo backend).
  final String? hash;
}

/// Uma página da trilha: o total ajuda a mostrar "Mostrando 1 a 25 de 4.813".
class PaginaAuditoria {
  const PaginaAuditoria({required this.itens, required this.total});
  final List<EntradaAuditoria> itens;
  final int total;
}

class ResultadoCadeia {
  const ResultadoCadeia({required this.ok, this.verificadas, this.primeiraQuebraId});
  final bool ok;
  final int? verificadas;
  final int? primeiraQuebraId;
}

/// Erro de chamada admin. `proibido` = 403 (papel sem permissão); `sessao` = 401.
/// Resposta do aviso prévio. Com [falhas] acima de zero o envio não libera mudança.
class ResultadoAvisoPrevio {
  const ResultadoAvisoPrevio(
      {required this.antecedenciaMinimaDias, required this.destinatarios, required this.avisosNovos, required this.falhas});
  final int antecedenciaMinimaDias;
  final int destinatarios;
  final int avisosNovos;
  final int falhas;
}

class ErroApi implements Exception {
  const ErroApi(this.mensagem,
      {this.proibido = false,
      this.sessao = false,
      this.status,
      this.codigo,
      this.maximoCentavos,
      this.campos = const [],
      this.podeValerEm});

  /// Recusa de mudança dos Tratinhos: campos afetados e, no prazo do aviso, quando pode valer.
  final List<String> campos;
  final String? podeValerEm;

  /// Só em `acima_do_devido`: o máximo que o servidor aceita compensar.
  final int? maximoCentavos;

  /// Código estável da recusa (`{detail, codigo}`), quando o servidor manda.
  final String? codigo;

  /// Código HTTP da recusa, quando veio do servidor.
  final int? status;
  final String mensagem;
  final bool proibido;
  final bool sessao;

  @override
  String toString() => mensagem;
}

// =============================================================================
// MÓDULO 1: DASHBOARD EXECUTIVO
// =============================================================================

class MetricasDashboard {
  const MetricasDashboard({
    required this.gmvCentavos,
    required this.pedidosTotal,
    required this.pedidosConcluidos,
    required this.pedidosEmAndamento,
    required this.pedidosAbertos,
    required this.pedidosDisputa,
    required this.clientesTotal,
    required this.profissionaisTotal,
    required this.profissionaisPendentes,
    required this.cidadesAtivas,
    required this.categoriasAtivas,
    this.gmvAnteriorCentavos = 0,
    this.pedidosAtivos = 0,
    this.pedidosAtivosAnterior = 0,
    this.baseUsuarios = 0,
    this.baseUsuariosAnterior = 0,
    this.disputasAbertas = 0,
    this.alertasRiscoAbertos = 0,
  });

  /// Valores do período anterior de mesma duração (comparação dos quatro cards).
  final int gmvAnteriorCentavos;
  final int pedidosAtivos;
  final int pedidosAtivosAnterior;
  final int baseUsuarios;
  final int baseUsuariosAnterior;
  final int disputasAbertas;
  final int alertasRiscoAbertos;

  final int gmvCentavos;
  final int pedidosTotal;
  final int pedidosConcluidos;
  final int pedidosEmAndamento;
  final int pedidosAbertos;
  final int pedidosDisputa;
  final int clientesTotal;
  final int profissionaisTotal;
  final int profissionaisPendentes;
  final int cidadesAtivas;
  final int categoriasAtivas;
}

class PontoSerieDashboard {
  const PontoSerieDashboard({required this.data, required this.pedidos, required this.gmvCentavos});
  final String data;
  final int pedidos;
  final int gmvCentavos;
}

class EtapaFunilDashboard {
  const EtapaFunilDashboard({required this.etapa, required this.quantidade, required this.taxaConversaoPct});
  final String etapa;
  final int quantidade;
  final double taxaConversaoPct;
}

class SeriesDashboard {
  const SeriesDashboard({required this.historicoDias, required this.funil});
  final List<PontoSerieDashboard> historicoDias;
  final List<EtapaFunilDashboard> funil;
}

// =============================================================================
// MÓDULO 2: QUESTIONÁRIOS DINÂMICOS DA CATEGORIA
// =============================================================================

class PerguntaCategoriaAdmin {
  const PerguntaCategoriaAdmin({
    required this.id,
    required this.categoriaId,
    required this.texto,
    required this.tipo,
    this.opcoes,
    this.obrigatoria = false,
    this.ordem = 0,
    this.ativa = true,
  });

  final String id;
  final String categoriaId;
  final String texto;
  final String tipo;
  final List<String>? opcoes;
  final bool obrigatoria;
  final int ordem;
  final bool ativa;
}

// =============================================================================
// MÓDULO 3: CENTRAL ANTIFRAUDE E GESTÃO DE RISCO
// =============================================================================

class AlertaRisco {
  const AlertaRisco({
    this.travaFraudeVigente,
    required this.id,
    this.usuarioId,
    this.usuarioNome,
    this.usuarioTipo,
    this.usuarioStatus,
    this.pedido,
    this.pedidoId,
    required this.tipo,
    required this.severidade,
    required this.detalhes,
    this.status = 'em_aberto',
    this.resultado,
    this.responsavel,
    this.resolvido = false,
    required this.criadoEm,
  });

  final String id;
  final String? usuarioId;
  final String? usuarioNome;

  /// "cliente", "profissional" ou "equipe".
  final String? usuarioTipo;

  /// Status da conta do usuário: "restrito" (trava de saques ou outra restrição; sozinho não retém dinheiro) ou
  /// "bloqueado".
  final String? usuarioStatus;

  /// Trava de saques por fraude em vigor. Null = não informado (nunca "sem trava").
  final bool? travaFraudeVigente;

  /// Código do pedido ("PED-10498"), quando o alerta nasce de um pedido.
  final String? pedido;

  /// Id completo do pedido (o [pedido] é só o código curto).
  final String? pedidoId;
  final String tipo;

  /// "baixa", "media", "alta" ou "critica".
  final String severidade;
  final String detalhes;

  /// "em_aberto", "em_analise" ou "resolvido".
  final String status;

  /// "procedente" ou "improcedente" (só depois de resolvido).
  final String? resultado;
  final String? responsavel;
  final bool resolvido;
  final String criadoEm;

  bool get contaRestrita => usuarioStatus == 'restrito';
  bool get contaBloqueada => usuarioStatus == 'bloqueado';

  AlertaRisco comResolucao(String resultado) => AlertaRisco(
        id: id,
        travaFraudeVigente: travaFraudeVigente,
        usuarioId: usuarioId,
        usuarioNome: usuarioNome,
        usuarioTipo: usuarioTipo,
        usuarioStatus: usuarioStatus,
        pedido: pedido,
        tipo: tipo,
        severidade: severidade,
        detalhes: detalhes,
        status: 'resolvido',
        resultado: resultado,
        responsavel: responsavel,
        resolvido: true,
        criadoEm: criadoEm,
      );

  AlertaRisco comUsuarioStatus(String? novo) => AlertaRisco(
        id: id,
        travaFraudeVigente: travaFraudeVigente,
        usuarioId: usuarioId,
        usuarioNome: usuarioNome,
        usuarioTipo: usuarioTipo,
        usuarioStatus: novo,
        pedido: pedido,
        tipo: tipo,
        severidade: severidade,
        detalhes: detalhes,
        status: status,
        resultado: resultado,
        responsavel: responsavel,
        resolvido: resolvido,
        criadoEm: criadoEm,
      );
}

// =============================================================================
// MÓDULO 4: NOTIFICAÇÕES EM MASSA & CAMPANHAS
// =============================================================================

class CampanhaNotificacao {
  const CampanhaNotificacao({
    required this.id,
    required this.titulo,
    required this.mensagem,
    required this.segmento,
    this.categoriaId,
    this.cidadeId,
    required this.totalDestinatarios,
    required this.criadoEm,
    this.tipo = 'marketing',
    this.autor,
    this.enviados = 0,
    this.entregues = 0,
    this.abertos = 0,
  });

  final String id;
  final String titulo;
  final String mensagem;
  final String segmento;
  final String? categoriaId;
  final String? cidadeId;
  final int totalDestinatarios;
  final String criadoEm;

  /// "operacional" (andamento de serviço e avisos de conta, sem oferta nem propaganda) ou
  /// "marketing" (só quem aceitou receber avisos e novidades e não desligou o push; Termos 15.4).
  final String tipo;
  final String? autor;
  final int enviados;
  final int entregues;
  final int abertos;
}

/// Quantas pessoas receberiam a campanha e quantas ficaram de fora por terem desligado o marketing.
class EstimativaCampanha {
  const EstimativaCampanha({required this.destinatarios, this.desativaram = 0});

  /// No marketing, quem fica de fora: sem consentimento, com ele revogado ou com o push
  /// desligado, sem contar a mesma pessoa duas vezes.
  final int destinatarios;
  final int desativaram;
}

// =============================================================================
// MÓDULO 5: GESTÃO DE CUPONS DE DESCONTO
// =============================================================================

class CupomAdmin {
  const CupomAdmin({
    required this.id,
    required this.codigo,
    required this.tipo,
    required this.valor,
    required this.valorMinimoCentavos,
    this.limiteUsos,
    required this.usosAtuais,
    this.validoAte,
    this.validoDesde,
    this.campanha,
    this.limitePorUsuario,
    required this.ativo,
    required this.criadoEm,
  });

  final String id;
  final String codigo;

  /// "percentual" ou "fixo". Em "percentual", [valor] é o % (1 a 100); em "fixo", é em centavos.
  final String tipo;
  final int valor;
  final int valorMinimoCentavos;
  final int? limiteUsos;
  final int usosAtuais;
  final String? validoAte;
  final String? validoDesde;
  final String? campanha;
  final int? limitePorUsuario;
  final bool ativo;
  final String criadoEm;

  CupomAdmin comAtivo(bool novo) => CupomAdmin(
        id: id,
        codigo: codigo,
        tipo: tipo,
        valor: valor,
        valorMinimoCentavos: valorMinimoCentavos,
        limiteUsos: limiteUsos,
        usosAtuais: usosAtuais,
        validoAte: validoAte,
        validoDesde: validoDesde,
        campanha: campanha,
        limitePorUsuario: limitePorUsuario,
        ativo: novo,
        criadoEm: criadoEm,
      );
}

// =============================================================================
// MOEDAS: orçamento mensal de desconto e configuração do programa
// =============================================================================

/// Quanto do orçamento de desconto em moedas já foi usado no mês. Tudo vem pronto do backend:
/// o painel só mostra (valores em centavos inteiros).
class MoedasOrcamento {
  const MoedasOrcamento({
    required this.mesRef,
    required this.orcamentoCentavos,
    required this.usadoCentavos,
    required this.percentualUsado,
    required this.aviso,
    this.diaRef = '',
    this.usadoDiaCentavos = 0,
    this.tetoDiaCentavos = 0,
  });

  /// Dia de referência do teto diário ("2026-11-20"), como o backend mandou.
  final String diaRef;
  final int usadoDiaCentavos;
  final int tetoDiaCentavos;

  /// Limite de hoje atingido (usado do dia >= teto do dia). Só exibição: o backend é quem barra.
  bool get limiteDiaAtingido => tetoDiaCentavos > 0 && usadoDiaCentavos >= tetoDiaCentavos;

  /// Mês de referência, como o backend mandou ("2026-11" ou "2026-11-01").
  final String mesRef;
  final int orcamentoCentavos;
  final int usadoCentavos;

  /// Percentual já calculado pelo backend (pode ter casas decimais).
  final double percentualUsado;

  /// O backend liga o aviso quando o uso chegou ao percentual de aviso da configuração.
  final bool aviso;

  /// Desconto fechado: o orçamento acabou (usado >= orçamento). Só exibição.
  bool get fechado => usadoCentavos >= orcamentoCentavos;
}

/// Configuração do programa de moedas. Valores em centavos ou unidades inteiras, como no backend.
class MoedasConfig {
  const MoedasConfig({
    required this.ativo,
    required this.bonusAvaliacaoMoedas,
    required this.valorMoedaCentavos,
    required this.tetoMensalMoedas,
    required this.minServicoCentavos,
    required this.maxBonusPorProfissionalMes,
    required this.maxDescontoPercentual,
    this.validadeDias,
    required this.orcamentoMensalDescontoCentavos,
    required this.avisoPercentual,
    required this.tetoDescontoClienteMesCentavos,
    required this.tetoDiarioDescontoCentavos,
    required this.diasLiberacaoBonus,
    this.extras = const {},
  });

  /// Campos de exclusividade e bônus do profissional (inteiros). Só entram as chaves que o backend
  /// mandou: backend antigo = mapa vazio e a tela esconde esses campos.
  final Map<String, int> extras;

  static const chavesExtras = [
    'bonus_avaliacao_profissional_moedas',
    'exclusividade_custo_moedas',
    'exclusividade_duracao_horas',
    'exclusividade_max_simultaneas',
    'exclusividade_prazo_resposta_horas',
    'exclusividade_bloqueio_recusa_dias',
  ];

  final bool ativo;
  final int bonusAvaliacaoMoedas;
  final int valorMoedaCentavos;
  final int tetoMensalMoedas;
  final int minServicoCentavos;
  final int maxBonusPorProfissionalMes;
  final int maxDescontoPercentual;
  /// Nulo = os Tratinhos não vencem. Nunca vira 0.
  final int? validadeDias;
  final int orcamentoMensalDescontoCentavos;
  final int avisoPercentual;
  final int tetoDescontoClienteMesCentavos;
  final int tetoDiarioDescontoCentavos;
  final int diasLiberacaoBonus;
}

/// Bônus de Tratinhos ainda aguardando liberação para um usuário.
class PendenteMoedaUsuario {
  const PendenteMoedaUsuario({
    required this.chaveIdempotencia,
    this.pedidoId,
    required this.quantidade,
    required this.liberarEm,
    required this.criadaEm,
    required this.tipoLancamento,
    required this.status,
  });

  final String chaveIdempotencia;
  final String? pedidoId;
  final int quantidade;
  final DateTime liberarEm;
  final DateTime criadaEm;
  final String tipoLancamento;
  final String status;
}

/// Um lançamento no extrato de Tratinhos de um usuário.
class LancamentoMoedaUsuario {
  const LancamentoMoedaUsuario({
    required this.tipo,
    required this.quantidade,
    required this.carteira,
    required this.chaveIdempotencia,
    required this.criadaEm,
    this.expiraEm,
    this.referenciaId,
  });

  final String tipo;
  final int quantidade;
  final String carteira;
  final String chaveIdempotencia;
  final DateTime criadaEm;
  final DateTime? expiraEm;
  final String? referenciaId;
}

/// Saldo, pendentes e extrato de Tratinhos de um usuário (carteiras cliente e profissional).
class MoedasUsuario {
  const MoedasUsuario({
    required this.usuarioId,
    required this.saldoCliente,
    required this.saldoProfissional,
    this.pendentesCliente = const [],
    this.pendentesProfissional = const [],
    this.extratoCliente = const [],
    this.extratoProfissional = const [],
  });

  final String usuarioId;
  final int saldoCliente;
  final int saldoProfissional;
  final List<PendenteMoedaUsuario> pendentesCliente;
  final List<PendenteMoedaUsuario> pendentesProfissional;
  final List<LancamentoMoedaUsuario> extratoCliente;
  final List<LancamentoMoedaUsuario> extratoProfissional;
}

/// Retorno da concessão de Tratinhos como compensação (Termos I.3).
class ResultadoConcederMoedas {
  const ResultadoConcederMoedas({
    required this.usuarioId,
    required this.carteira,
    required this.quantidade,
    required this.expiraEm,
    required this.chaveIdempotencia,
    required this.idempotente,
    required this.saldoAtual,
  });

  final String usuarioId;
  final String carteira;
  final int quantidade;
  final DateTime expiraEm;
  final String chaveIdempotencia;
  final bool idempotente;
  final int saldoAtual;
}

/// Retorno do cancelamento de Tratinhos por fraude (Termos 12.10, 13.9 e I.10).
class ResultadoCancelarFraudeMoedas {
  const ResultadoCancelarFraudeMoedas({
    required this.usuarioId,
    required this.carteira,
    required this.quantidadeDebitada,
    required this.pendentesCancelados,
    required this.chaveIdempotencia,
    required this.idempotente,
    required this.saldoAtual,
  });

  final String usuarioId;
  final String carteira;
  final int quantidadeDebitada;
  final int pendentesCancelados;
  final String chaveIdempotencia;
  final bool idempotente;
  final int saldoAtual;
}

// =============================================================================
// MÓDULO 6: GESTÃO DE EQUIPE INTERNA
// =============================================================================

class MembroEquipeAdmin {
  const MembroEquipeAdmin({
    required this.usuarioId,
    required this.nome,
    required this.email,
    required this.papel,
    required this.ativo,
    required this.alcadaCentavos,
    required this.criadoEm,
    this.status = 'ativo',
    this.ultimoAcesso,
    this.tetoPapelCentavos = 0,
  });

  final String usuarioId;
  final String nome;
  final String email;
  final String papel;
  final bool ativo;

  /// A alçada que vale de fato: nunca passa do teto do papel (RP-02).
  final int alcadaCentavos;
  final String criadoEm;

  /// "ativo", "convite_enviado" (nunca entrou) ou "revogado".
  final String status;
  final String? ultimoAcesso;
  final int tetoPapelCentavos;
}

/// Relatório CSV pronto para baixar. O link vale uma vez e por poucos minutos.
class RelatorioPronto {
  const RelatorioPronto({
    required this.url,
    required this.nomeArquivo,
    required this.linhas,
    required this.colunas,
    required this.comDadosPessoais,
  });
  final String url;
  final String nomeArquivo;
  final int linhas;
  final int colunas;
  final bool comDadosPessoais;
}

// ---------- Financeiro: contestações, alertas, conciliação, fechamento ----------

/// Contestação de cartão (chargeback) avisada pelo provedor.
class ContestacaoCartao {
  const ContestacaoCartao({
    required this.id,
    required this.pedido,
    required this.valorCentavos,
    required this.motivo,
    required this.status,
    required this.abertaEm,
    this.prazoProvas,
    this.horasParaPrazo,
    this.encerradaEm,
    this.repasseLiberado = false,
    this.cobrancaId,
  });
  final String id;
  final String pedido; // "PED-10482 · Pintura" ou o começo do id
  final int valorCentavos;
  final String motivo; // texto legível
  final String status; // aberta | em_analise | ganha | perdida | encerrada
  final DateTime abertaEm;
  final DateTime? prazoProvas;
  final int? horasParaPrazo;
  final DateTime? encerradaEm;
  final bool repasseLiberado;
  final String? cobrancaId;

  bool get emAberto => status == 'aberta' || status == 'em_analise';
}

class PagamentoParado {
  const PagamentoParado({
    required this.cobrancaId,
    required this.pedido,
    required this.valorCentavos,
    required this.meio,
    required this.criadaEm,
    required this.minutosParado,
    required this.clienteAvisou,
  });
  final String cobrancaId;
  final String pedido;
  final int valorCentavos;
  final String meio;
  final DateTime criadaEm;
  final int minutosParado;
  final bool clienteAvisou;
}

class EventoEmRevisao {
  const EventoEmRevisao({required this.eventoId, required this.tipo, required this.recebidoEm, required this.motivo});
  final String eventoId;
  final String tipo;
  final DateTime recebidoEm;
  final String motivo;
}

class EstornoPendente {
  const EstornoPendente({required this.pedido, required this.cobrancaId, required this.valorCentavos, required this.criadaEm});
  final String pedido;
  final String cobrancaId;
  final int valorCentavos;
  final DateTime criadaEm;
}

class AlertasFinanceiros {
  const AlertasFinanceiros({
    required this.minutosPagamentoParado,
    required this.provedorLigado,
    required this.pagamentosParados,
    required this.repassesComFalha,
    required this.estornosPendentes,
    required this.eventosEmRevisao,
    required this.contestacoesEmAberto,
  });
  final int minutosPagamentoParado;
  final bool provedorLigado;
  final List<PagamentoParado> pagamentosParados;
  final List<EventoEmRevisao> repassesComFalha;
  final List<EstornoPendente> estornosPendentes;
  final List<EventoEmRevisao> eventosEmRevisao;
  final int contestacoesEmAberto;

  int get total => pagamentosParados.length + repassesComFalha.length + estornosPendentes.length + eventosEmRevisao.length;
}

class ConsultaCobranca {
  const ConsultaCobranca({required this.statusNoProvedor, required this.statusNoTrato, required this.orientacao});
  final String statusNoProvedor;
  final String? statusNoTrato;
  final String orientacao;
}

/// Um evento recebido do provedor (webhook), sem o conteúdo bruto.
class EventoProvedor {
  const EventoProvedor({
    required this.eventoId,
    required this.tipo,
    required this.recebidoEm,
    this.pedidoId,
    this.referencia,
    this.valorCentavos,
    this.revisao,
  });
  final String eventoId;
  final String tipo;
  final DateTime recebidoEm;
  final String? pedidoId;
  final String? referencia;
  final int? valorCentavos;
  final String? revisao;
}

class LinhaConciliacao {
  const LinhaConciliacao({
    required this.tipo,
    required this.referencia,
    required this.pedido,
    required this.valorProvedorCentavos,
    required this.valorTratoCentavos,
    required this.situacao,
  });
  final String tipo; // cobranca | estorno | contestacao
  final String referencia;
  final String? pedido;
  final int valorProvedorCentavos;
  final int valorTratoCentavos;
  final String situacao; // confere | so_no_provedor | so_no_trato | valor_diferente

  int get diferencaCentavos => valorProvedorCentavos - valorTratoCentavos;
}

class ConciliacaoDia {
  const ConciliacaoDia({
    required this.dia,
    required this.confere,
    required this.cobradoProvedorCentavos,
    required this.cobradoTratoCentavos,
    required this.taxasProvedorCentavos,
    required this.divergencias,
    required this.linhas,
  });
  final DateTime dia;
  final bool confere;
  final int cobradoProvedorCentavos;
  final int cobradoTratoCentavos;
  final int taxasProvedorCentavos;
  final List<LinhaConciliacao> divergencias;
  final List<LinhaConciliacao> linhas;
}

class MesFinanceiro {
  const MesFinanceiro({required this.mes, required this.fechado, required this.podeFechar, this.fechadoEm});
  final String mes; // AAAA-MM
  final bool fechado;
  final bool podeFechar;
  final DateTime? fechadoEm;
}

class FechamentoMes {
  const FechamentoMes({
    required this.mes,
    required this.fechado,
    required this.podeFechar,
    required this.totais,
    this.gravado,
    this.confere,
    this.hash,
    this.fechadoPorNome,
    this.fechadoEm,
    this.motivo,
  });
  final String mes;
  final bool fechado;
  final bool podeFechar;
  final Map<String, int> totais;
  final Map<String, int>? gravado;
  final bool? confere;
  final String? hash;
  final String? fechadoPorNome;
  final DateTime? fechadoEm;
  final String? motivo;

  /// O que vale para mostrar: o retrato gravado (mês fechado) ou a prévia.
  Map<String, int> get valores => gravado ?? totais;
}

/// Arquivo pronto para baixar por link de uso único (o token nunca vai na URL).
class ArquivoPronto {
  const ArquivoPronto({required this.url, required this.nomeArquivo});
  final String url;
  final String nomeArquivo;
}

/// Arquivo de uma contestação de materiais. [url] é curta e só vive na tela; nula = indisponível.
class AnexoMaterial {
  const AnexoMaterial({required this.tipo, this.enviadoPor, this.url, this.tipoConteudo, this.expiraEmSegundos});

  /// `nota_material` ou `contestacao`.
  final String tipo;
  final String? enviadoPor;
  final String? url;
  final String? tipoConteudo;
  final int? expiraEmSegundos;
}

/// Contestação de nota de material (Termos 6.9). Nenhum campo daqui significa dinheiro movido.
class ContestacaoMaterial {
  const ContestacaoMaterial({
    required this.id,
    required this.protocolo,
    required this.pedidoId,
    required this.notaId,
    required this.clienteId,
    required this.motivo,
    required this.descricao,
    required this.valorContestadoCentavos,
    required this.abertaEm,
    required this.responderAte,
    required this.status,
    this.itemId,
    this.anexos = const [],
    this.analistaId,
    this.resposta,
    this.valorReconhecidoCentavos,
    this.decididaEm,
    this.efeitoFinanceiro = 'nenhum',
  });

  final String id;
  final String protocolo;
  final String pedidoId;
  final String notaId;
  final String? itemId;
  final String clienteId;

  /// `nao_comprovado` ou `diferente_do_combinado`.
  final String motivo;
  final String descricao;
  final List<String> anexos;
  final int valorContestadoCentavos;
  final DateTime abertaEm;
  final DateTime responderAte;

  /// `aberta`, `em_analise`, `procedente`, `parcial` ou `improcedente`.
  final String status;
  final String? analistaId;
  final String? resposta;
  final int? valorReconhecidoCentavos;
  final DateTime? decididaEm;
  final String efeitoFinanceiro;

  bool get pendenteDeDecisao => status == 'aberta' || status == 'em_analise';
  bool get decidida => status == 'procedente' || status == 'parcial' || status == 'improcedente';

  /// Prazo vencido sem decisão. O relógio local serve apenas para destacar na tela.
  bool atrasada(DateTime agora) => pendenteDeDecisao && agora.isAfter(responderAte);
}
