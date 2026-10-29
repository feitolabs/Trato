/// Modelos e serviço da verificação do profissional (F6.1, V2).
/// Verificação proporcional ao risco: o texto não promete "profissional seguro".
/// PROVISÓRIO: status, motivo e textos de LGPD vêm do backend / jurídico.
library;

enum StatusVerificacao { naoEnviada, emAnalise, aprovada, pendente }

class SituacaoVerificacao {
  const SituacaoVerificacao({required this.status, this.motivo, this.atualizadaEm});

  final StatusVerificacao status;

  /// Só quando [status] é pendente: o que precisa ser refeito, em linguagem simples.
  final String? motivo;
  final DateTime? atualizadaEm;
}

/// Finalidade e retenção dos dados, em linguagem simples (LGPD). Quem decide o texto
/// final é o jurídico (ver docs/advogado-e-contador.md); a tela só mostra.
class TextoLgpd {
  const TextoLgpd({required this.finalidade, required this.retencao, required this.quemVe});

  final String finalidade;
  final String retencao;
  final String quemVe;
}

class EnvioVerificacao {
  const EnvioVerificacao({required this.documento, required this.selfie});

  /// Referências das fotos devolvidas por quem captura (a tela não guarda imagem).
  final String documento;
  final String selfie;
}

abstract interface class ServicoVerificacao {
  Future<SituacaoVerificacao> carregarSituacao();
  Future<TextoLgpd> carregarTextoLgpd();
  Future<void> enviar(EnvioVerificacao envio);
}

/// PROVISÓRIO — só para teste e demonstração.
class ServicoVerificacaoFake implements ServicoVerificacao {
  ServicoVerificacaoFake({
    this.situacao = const SituacaoVerificacao(status: StatusVerificacao.naoEnviada),
    this.falharAoCarregar = false,
    this.falharAoEnviar = false,
  });

  final SituacaoVerificacao situacao;
  final bool falharAoCarregar;
  final bool falharAoEnviar;
  final List<EnvioVerificacao> enviados = [];

  @override
  Future<SituacaoVerificacao> carregarSituacao() async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return situacao;
  }

  @override
  Future<TextoLgpd> carregarTextoLgpd() async => textoLgpdExemplo;

  @override
  Future<void> enviar(EnvioVerificacao envio) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    enviados.add(envio);
  }
}

const textoLgpdExemplo = TextoLgpd(
  finalidade: 'Conferir se o documento e o rosto são da mesma pessoa que fez o cadastro.',
  retencao: 'Guardamos pelo tempo que a lei pede. Depois disso, apagamos. '
      '(Prazo exato: a definir com o jurídico.)',
  quemVe: 'Só a equipe de análise do Trato. Os clientes não veem seu documento.',
);
