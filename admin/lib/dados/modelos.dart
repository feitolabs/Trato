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
  });

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

enum StatusDisputa { aberta, aguardandoProfissional, emAnalise, aguardandoSegundaPessoa, decidida }

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

class Disputa {
  const Disputa({
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
    this.decididoPor,
    this.titulo = '',
    this.respostaAte,
    this.atrasada = false,
    this.semResposta = false,
  });

  final String id;

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

  /// Id de quem decidiu (a segunda pessoa precisa ser outra).
  final String? decididoPor;

  Disputa comDecisao(StatusDisputa novo, DecisaoDisputa d, int? reembolso, {String? por}) => Disputa(
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
        decididoPor: por ?? decididoPor,
        titulo: titulo,
        respostaAte: respostaAte,
        atrasada: atrasada,
        semResposta: semResposta,
      );
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
    this.taxaCentavos,
    this.liquidoCentavos,
    this.conciliado = false,
  });

  /// Cobrança, repasse, reembolso ou taxa (RF-PAG-03).
  final String tipo;

  /// Taxa retida pelo Trato e líquido do profissional neste pedido (RF-PAG-05). Nulo = sem dado.
  final int? taxaCentavos;
  final int? liquidoCentavos;
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

class Chamado {
  const Chamado({
    required this.id,
    required this.assunto,
    required this.solicitante,
    required this.status,
    required this.aberto,
    this.prioridade = 'normal',
    this.responsavel,
    this.prazo,
  });
  final String id;
  final String assunto;
  final String solicitante;
  final String status;
  final DateTime aberto;
  final String prioridade;
  final String? responsavel;
  final DateTime? prazo;
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
  });
  final String id;
  final String nome;
  final bool ativa;
  final int profissionais;
  final String slug;
  final String? icone;
  final int? garantiaDias;
  final int ordem;

  CategoriaAdmin comAtiva(bool valor) => CategoriaAdmin(
        id: id,
        nome: nome,
        ativa: valor,
        profissionais: profissionais,
        slug: slug,
        icone: icone,
        garantiaDias: garantiaDias,
        ordem: ordem,
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
class ErroApi implements Exception {
  const ErroApi(this.mensagem, {this.proibido = false, this.sessao = false});
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
    required this.receitaTaxaCentavos,
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
    this.receitaTaxaAnteriorCentavos = 0,
    this.pedidosAtivos = 0,
    this.pedidosAtivosAnterior = 0,
    this.baseUsuarios = 0,
    this.baseUsuariosAnterior = 0,
    this.disputasAbertas = 0,
    this.alertasRiscoAbertos = 0,
  });

  /// Valores do período anterior de mesma duração (comparação dos quatro cards).
  final int gmvAnteriorCentavos;
  final int receitaTaxaAnteriorCentavos;
  final int pedidosAtivos;
  final int pedidosAtivosAnterior;
  final int baseUsuarios;
  final int baseUsuariosAnterior;
  final int disputasAbertas;
  final int alertasRiscoAbertos;

  final int gmvCentavos;
  final int receitaTaxaCentavos;
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
    required this.id,
    this.usuarioId,
    this.usuarioNome,
    this.usuarioTipo,
    this.usuarioStatus,
    this.pedido,
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

  /// Status da conta do usuário: "restrito" = saques travados; "bloqueado" = bloqueio preventivo.
  final String? usuarioStatus;

  /// Código do pedido ("PED-10498"), quando o alerta nasce de um pedido.
  final String? pedido;
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

  bool get saquesTravados => usuarioStatus == 'restrito';
  bool get contaBloqueada => usuarioStatus == 'bloqueado';

  AlertaRisco comResolucao(String resultado) => AlertaRisco(
        id: id,
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

  /// "operacional" (andamento de serviço) ou "marketing" (respeita a preferência de cada pessoa).
  final String tipo;
  final String? autor;
  final int enviados;
  final int entregues;
  final int abertos;
}

/// Quantas pessoas receberiam a campanha e quantas ficaram de fora por terem desligado o marketing.
class EstimativaCampanha {
  const EstimativaCampanha({required this.destinatarios, this.desativaram = 0});
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
