import 'modelos.dart';

/// Perguntas frequentes embutidas no app (conteúdo de ajuda, não dado de usuário).
class ServicoAjudaLocal implements ServicoAjuda {
  const ServicoAjudaLocal();

  static const perguntasFrequentes = [
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
  Future<List<PerguntaFrequente>> perguntas() async => perguntasFrequentes;
}
