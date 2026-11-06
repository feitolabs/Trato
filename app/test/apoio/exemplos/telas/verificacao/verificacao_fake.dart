import 'package:trato/telas/verificacao/verificacao.dart';

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
  Future<TextoLgpd> carregarTextoLgpd() async => textoLgpdPadrao;

  @override
  Future<void> enviar(EnvioVerificacao envio) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    enviados.add(envio);
  }
}
