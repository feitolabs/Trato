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

class Verificacao {
  const Verificacao({
    required this.id,
    required this.profissional,
    required this.categoria,
    required this.cidade,
    required this.enviadaEm,
    required this.cpfMascarado,
    required this.documentos,
    this.status = StatusVerificacao.enviada,
    this.motivoDecisao,
  });

  final String id;
  final String profissional;
  final String categoria;
  final String cidade;
  final DateTime enviadaEm;
  final String cpfMascarado;

  /// Rótulos dos arquivos (ex.: "Documento (frente)", "Selfie"). O conteúdo só vem ao revelar.
  final List<String> documentos;
  final StatusVerificacao status;
  final String? motivoDecisao;

  Verificacao comStatus(StatusVerificacao novo, String motivo) => Verificacao(
        id: id,
        profissional: profissional,
        categoria: categoria,
        cidade: cidade,
        enviadaEm: enviadaEm,
        cpfMascarado: cpfMascarado,
        documentos: documentos,
        status: novo,
        motivoDecisao: motivo,
      );
}

enum DecisaoDisputa {
  liberarTudo('liberar_tudo', 'Liberar tudo ao profissional'),
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
  });

  final String id;
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
  });

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
  });
  final int confirmadoCentavos;
  final int estornadoCentavos;
  final int emAndamentoCentavos;
  final int divergencias;
  final DateTime atualizadoEm;
}

class UsuarioBusca {
  const UsuarioBusca({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.status,
    this.emailMascarado,
    this.cpfMascarado,
  });
  final String id;
  final String nome;
  final String tipo;
  final String status;
  final String? emailMascarado;
  final String? cpfMascarado;
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
  });
  final String id;
  final String titulo;
  final String cliente;
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
  });
  final String id;
  final String assunto;
  final String solicitante;
  final String status;
  final DateTime aberto;
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
  });
  final String id;
  final int numero;
  final StatusVersao status;
  final String motivo;
  final String criadaPor;
  final DateTime criadaEm;
  final String? aprovadaPor;

  /// chave -> valor inteiro na unidade da definição.
  final Map<String, int> valores;

  ConfigVersao comStatus(StatusVersao novo, {String? aprovadaPor}) => ConfigVersao(
        id: id,
        numero: numero,
        status: novo,
        motivo: motivo,
        criadaPor: criadaPor,
        criadaEm: criadaEm,
        valores: valores,
        aprovadaPor: aprovadaPor ?? this.aprovadaPor,
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
  });
  final int id;
  final DateTime ocorridaEm;
  final String ator;
  final String acao;
  final String entidade;
  final String? motivo;

  /// Hash da linha (a cadeia é conferida pelo backend).
  final String? hash;
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
  });

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
    required this.tipo,
    required this.severidade,
    required this.detalhes,
    this.resolvido = false,
    required this.criadoEm,
  });

  final String id;
  final String? usuarioId;
  final String? usuarioNome;
  final String tipo;
  final String severidade;
  final String detalhes;
  final bool resolvido;
  final String criadoEm;
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
  });

  final String id;
  final String titulo;
  final String mensagem;
  final String segmento;
  final String? categoriaId;
  final String? cidadeId;
  final int totalDestinatarios;
  final String criadoEm;
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
    required this.ativo,
    required this.criadoEm,
  });

  final String id;
  final String codigo;
  final String tipo;
  final int valor;
  final int valorMinimoCentavos;
  final int? limiteUsos;
  final int usosAtuais;
  final String? validoAte;
  final bool ativo;
  final String criadoEm;
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
  });

  final String usuarioId;
  final String nome;
  final String email;
  final String papel;
  final bool ativo;
  final int alcadaCentavos;
  final String criadoEm;
}
