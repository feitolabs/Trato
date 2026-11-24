import '../comuns/formato_aparelho.dart';

/// Indique e ganhe Tratinhos. O app só pede e mostra: quem indica, quem ganha e quanto é do
/// backend (`/v1/indicacoes/...`).

class ResumoIndicacoes {
  const ResumoIndicacoes({
    this.cadastradas = 0,
    this.aguardandoLiberacao = 0,
    this.liberadas = 0,
    this.limiteMensal = 0,
    this.limiteMensalRestante = 0,
  });

  final int cadastradas;
  final int aguardandoLiberacao;
  final int liberadas;
  final int limiteMensal;
  final int limiteMensalRestante;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  /// Campo ausente (backend antigo) vira 0.
  factory ResumoIndicacoes.deJson(Object? j) {
    if (j is! Map) return const ResumoIndicacoes();
    return ResumoIndicacoes(
      cadastradas: _int(j['cadastradas']),
      aguardandoLiberacao: _int(j['aguardando_liberacao']),
      liberadas: _int(j['liberadas']),
      limiteMensal: _int(j['limite_mensal']),
      limiteMensalRestante: _int(j['limite_mensal_restante']),
    );
  }
}

class Indicacao {
  const Indicacao({
    required this.id,
    required this.status,
    this.nomeIndicado,
    this.tipo = '',
    this.bonusTratinhos = 0,
    this.liberacaoPrevista,
    this.liberadoEm,
  });

  final String id;

  /// `cadastrado`, `aguardando_liberacao`, `liberado` ou `cancelado` (o backend decide).
  final String status;

  /// Primeiro nome e inicial do sobrenome (o backend já abrevia).
  final String? nomeIndicado;
  final String tipo;
  final int bonusTratinhos;
  final DateTime? liberacaoPrevista;
  final DateTime? liberadoEm;

  /// Status em português simples para a lista.
  String get textoStatus {
    switch (status) {
      case 'cadastrado':
        return 'Aguardando 1º serviço';
      case 'aguardando_liberacao':
        final d = liberacaoPrevista;
        return d == null ? 'Aguardando liberação' : 'Liberação em ${diaMesDoAparelho(d)}';
      case 'liberado':
        return 'Liberado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Em análise';
    }
  }

  static Indicacao? deJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return Indicacao(
      id: j['id'] as String,
      status: (j['status'] as String?) ?? '',
      nomeIndicado: j['indicado_nome'] as String?,
      tipo: (j['tipo'] as String?) ?? '',
      bonusTratinhos: j['bonus_indicador_tratinhos'] is num
          ? (j['bonus_indicador_tratinhos'] as num).toInt()
          : 0,
      liberacaoPrevista: DateTime.tryParse('${j['liberacao_prevista_em'] ?? ''}')?.toLocal(),
      liberadoEm: DateTime.tryParse('${j['liberado_em'] ?? ''}')?.toLocal(),
    );
  }
}

class MeuCodigoIndicacao {
  const MeuCodigoIndicacao({
    required this.codigo,
    this.resumo = const ResumoIndicacoes(),
    this.indicacoes = const [],
  });

  final String codigo;
  final ResumoIndicacoes resumo;
  final List<Indicacao> indicacoes;

  factory MeuCodigoIndicacao.deJson(Object? j) {
    final mapa = j is Map ? j : const {};
    return MeuCodigoIndicacao(
      codigo: (mapa['codigo'] as String?) ?? '',
      resumo: ResumoIndicacoes.deJson(mapa['resumo']),
      indicacoes: [
        for (final i in (mapa['indicacoes'] as List? ?? const []))
          if (Indicacao.deJson(i) case final ind?) ind,
      ],
    );
  }
}

/// Resposta pública de `GET /v1/indicacoes/codigo/{codigo}` (sem login).
class ConviteIndicacao {
  const ConviteIndicacao({required this.valido, this.indicadorNomeCurto, this.indicadorPapel = ''});

  final bool valido;
  final String? indicadorNomeCurto;

  /// `cliente` ou `profissional`.
  final String indicadorPapel;

  factory ConviteIndicacao.deJson(Object? j) {
    final m = j is Map ? j : const {};
    return ConviteIndicacao(
      valido: m['valido'] != false,
      indicadorNomeCurto: m['indicador_nome_curto'] as String?,
      indicadorPapel: (m['indicador_papel'] as String?) ?? '',
    );
  }
}

/// Resposta de `POST /v1/indicacoes/aplicar`. [mensagem] já vem em português do backend.
class ResultadoAplicacao {
  const ResultadoAplicacao({
    required this.mensagem,
    this.bonusIndicadoTratinhos = 0,
    this.status = '',
  });

  final String mensagem;
  final int bonusIndicadoTratinhos;
  final String status;

  factory ResultadoAplicacao.deJson(Object? j) {
    final m = j is Map ? j : const {};
    return ResultadoAplicacao(
      mensagem: (m['mensagem'] as String?) ?? 'Código aplicado.',
      bonusIndicadoTratinhos:
          m['bonus_indicado_tratinhos'] is num ? (m['bonus_indicado_tratinhos'] as num).toInt() : 0,
      status: (m['status'] as String?) ?? '',
    );
  }
}

abstract interface class ServicoIndicacoes {
  /// `GET /v1/indicacoes/meu-codigo`.
  Future<MeuCodigoIndicacao> meuCodigo();

  /// `GET /v1/indicacoes/codigo/{codigo}` (público). Código inexistente: o backend responde com
  /// erro e o texto dele é mostrado como veio.
  Future<ConviteIndicacao> validar(String codigo);

  /// `POST /v1/indicacoes/aplicar`. Erros 404, 409 e 422 vêm com texto em português.
  Future<ResultadoAplicacao> aplicar(String codigo);
}
