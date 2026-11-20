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
    PerguntaFrequente(
      pergunta: 'O que são Tratinhos?',
      resposta:
          'São a moeda de desconto do Trato: 50 Tratinhos = R\$ 0,50. Você ganha ao avaliar serviços e usa no próximo pedido.',
    ),
    PerguntaFrequente(
      pergunta: 'Como funciona a exclusividade de 48h?',
      resposta:
          'Quando um profissional pede exclusividade de 48h, você decide sem compromisso se quer reservar o horário dele.',
    ),
    PerguntaFrequente(
      pergunta: 'O Trato cobra alguma taxa?',
      resposta:
          'Não. Pedir orçamento é grátis e o app opera com 0% de taxa para clientes e profissionais.',
    ),
    PerguntaFrequente(
      pergunta: 'O que é uma disputa?',
      resposta:
          'Se algo der errado no serviço, você abre uma disputa para nossa equipe analisar o caso enquanto o pagamento fica protegido.',
    ),
  ];

  @override
  Future<List<PerguntaFrequente>> perguntas() async => perguntasFrequentes;
}
