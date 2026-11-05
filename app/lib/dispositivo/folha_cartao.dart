import 'package:flutter_stripe/flutter_stripe.dart';

/// Resultado da folha de cartão do provedor.
enum ResultadoCartao { concluido, cancelado }

/// Dados que o backend entrega para abrir a folha. Nenhum número de cartão passa pelo Trato:
/// a folha do provedor lista os cartões salvos, cadastra um novo e confirma o pagamento.
class PreparoFolhaCartao {
  const PreparoFolhaCartao({
    required this.segredoDoPagamento,
    required this.clienteId,
    required this.chaveEfemera,
  });

  final String segredoDoPagamento;
  final String clienteId;
  final String chaveEfemera;
}

/// Falha ao abrir ou concluir a folha (cartão recusado, sem chave pública, etc.).
class ErroFolhaCartao implements Exception {
  const ErroFolhaCartao(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

abstract interface class FolhaCartao {
  /// Abre a folha, deixa escolher um cartão salvo ou cadastrar outro e confirma o pagamento.
  /// "Pago" continua só vindo do backend (webhook assinado).
  Future<ResultadoCartao> pagar(PreparoFolhaCartao preparo);
}

/// Folha real (Stripe PaymentSheet). A chave pública vem de `--dart-define`.
class FolhaCartaoStripe implements FolhaCartao {
  FolhaCartaoStripe({String chavePublica = const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY')})
      : _chave = chavePublica;

  final String _chave;

  @override
  Future<ResultadoCartao> pagar(PreparoFolhaCartao preparo) async {
    if (_chave.isEmpty) {
      throw const ErroFolhaCartao('Pagamento com cartão indisponível no momento.');
    }
    Stripe.publishableKey = _chave;
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: preparo.segredoDoPagamento,
          customerId: preparo.clienteId,
          customerEphemeralKeySecret: preparo.chaveEfemera,
          merchantDisplayName: 'Trato',
          // Cartões salvos aparecem para escolher; "Adicionar" cadastra um novo.
          allowsDelayedPaymentMethods: false,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return ResultadoCartao.concluido;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return ResultadoCartao.cancelado;
      throw ErroFolhaCartao(e.error.localizedMessage ?? 'Não foi possível pagar com o cartão.');
    }
  }
}

/// Para testes e modo demonstração: não abre nada.
class FolhaCartaoFake implements FolhaCartao {
  FolhaCartaoFake([this.resultado = ResultadoCartao.concluido]);

  final ResultadoCartao resultado;
  final List<PreparoFolhaCartao> abertas = [];

  @override
  Future<ResultadoCartao> pagar(PreparoFolhaCartao preparo) async {
    abertas.add(preparo);
    return resultado;
  }
}
