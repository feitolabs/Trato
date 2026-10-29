import 'modelos.dart';

class ServicoAjudaFake implements ServicoAjuda {
  const ServicoAjudaFake({this.itens = exemplo, this.falhar = false, this.travar = false});

  final List<PerguntaFrequente> itens;
  final bool falhar;
  final bool travar;

  static const exemplo = [
    PerguntaFrequente(
      pergunta: 'Como peço um serviço?',
      resposta: 'Descreva o problema, receba orçamentos e escolha o profissional que preferir.',
    ),
    PerguntaFrequente(
      pergunta: 'Quando o pagamento é liberado ao profissional?',
      resposta:
          'Depois que você confirma que o serviço foi feito, ou quando o prazo de confirmação '
          'termina sem contestação. Se houver disputa, o valor fica congelado até a decisão.',
    ),
    PerguntaFrequente(
      pergunta: 'O que fazer se algo deu errado no serviço?',
      resposta:
          'Use "Relatar um problema" nesta tela ou na tela do pedido. Nossa equipe analisa o caso.',
    ),
    PerguntaFrequente(
      pergunta: 'Como altero ou cancelo um pedido?',
      resposta: 'Abra o pedido em "Seus pedidos" e veja as opções disponíveis para o momento dele.',
    ),
  ];

  @override
  Future<List<PerguntaFrequente>> perguntas() {
    if (travar) return Future<List<PerguntaFrequente>>.delayed(const Duration(days: 1));
    if (falhar) return Future.error(StateError('falha simulada'));
    return Future.value(itens);
  }
}
