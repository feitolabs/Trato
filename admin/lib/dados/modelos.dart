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

  Disputa comDecisao(StatusDisputa novo, DecisaoDisputa d, int? reembolso) => Disputa(
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
      );
}

/// Resposta de `decidirDisputa`: o backend diz se ficou decidida ou esperando a segunda pessoa.
class ResultadoDecisao {
  const ResultadoDecisao({required this.status, this.mensagem});
  final StatusDisputa status;
  final String? mensagem;
}

/// Estado do pagamento no provedor. O painel nunca mostra "pago" antes de `confirmado` (D13).
enum StatusProvedor { aguardandoConfirmacao, confirmado, falhou, reembolsado }

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
    required this.aguardandoCentavos,
    required this.divergencias,
    required this.atualizadoEm,
  });
  final int confirmadoCentavos;
  final int aguardandoCentavos;
  final int divergencias;
  final DateTime atualizadoEm;
}

class UsuarioBusca {
  const UsuarioBusca({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.status,
    required this.emailMascarado,
    required this.cpfMascarado,
  });
  final String id;
  final String nome;
  final String tipo;
  final String status;
  final String emailMascarado;
  final String cpfMascarado;
}

class DadosPessoais {
  const DadosPessoais({required this.email, required this.cpf, required this.telefone});
  final String email;
  final String cpf;
  final String telefone;
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
  const CategoriaAdmin({required this.id, required this.nome, required this.ativa, required this.profissionais});
  final String id;
  final String nome;
  final bool ativa;
  final int profissionais;

  CategoriaAdmin comAtiva(bool valor) =>
      CategoriaAdmin(id: id, nome: nome, ativa: valor, profissionais: profissionais);
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

enum StatusVersao { rascunho, aguardandoAprovacao, vigente, substituida, revertida }

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
    required this.hash,
  });
  final int id;
  final DateTime ocorridaEm;
  final String ator;
  final String acao;
  final String entidade;
  final String? motivo;

  /// Hash da linha (a cadeia é conferida pelo backend).
  final String hash;
}

class ResultadoCadeia {
  const ResultadoCadeia({required this.ok, required this.verificadas, this.primeiraQuebraId});
  final bool ok;
  final int verificadas;
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
