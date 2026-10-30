import 'servico_auth.dart';

/// Limites do código de confirmação do celular: tentativas, reenvios e espera de 60 s.
/// Usado pelo fake e pelo serviço do Supabase (o servidor também limita; isto evita
/// gastar SMS à toa).
class ControleCodigoCelular {
  ControleCodigoCelular({DateTime Function()? agora})
      : _agora = agora ?? DateTime.now,
        _ultimoEnvio = (agora ?? DateTime.now)();

  final DateTime Function() _agora;
  var _tentativas = 0;
  var _reenvios = 0;
  DateTime _ultimoEnvio;

  /// Quantas vezes o código foi enviado ou reenviado.
  int get envios => _reenvios + 1;

  /// Um código novo foi enviado no cadastro: zera tudo.
  void novoCadastro() {
    _tentativas = 0;
    _reenvios = 0;
    _ultimoEnvio = _agora();
  }

  /// Chame antes de reenviar; lança [ErroAuth] se for cedo demais ou se acabaram os reenvios.
  void registrarReenvio() {
    final passou = _agora().difference(_ultimoEnvio).inSeconds;
    if (passou < LimitesCodigoCelular.segundosParaReenviar) {
      throw const ErroAuth(TipoErroAuth.reenvioMuitoCedo);
    }
    if (_reenvios >= LimitesCodigoCelular.maxReenvios) {
      throw const ErroAuth(TipoErroAuth.reenviosEsgotados);
    }
    _reenvios++;
    _tentativas = 0;
    _ultimoEnvio = _agora();
  }

  /// Chame antes de conferir o código.
  void checarTentativa() {
    if (_tentativas >= LimitesCodigoCelular.maxTentativas) {
      throw const ErroAuth(TipoErroAuth.tentativasEsgotadas);
    }
  }

  /// Chame quando o código estiver errado; devolve o erro certo para lançar.
  ErroAuth registrarErro() {
    _tentativas++;
    return ErroAuth(_tentativas >= LimitesCodigoCelular.maxTentativas
        ? TipoErroAuth.tentativasEsgotadas
        : TipoErroAuth.codigoInvalido);
  }
}
