import '../comuns/textos_dos_termos.dart';
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
      pergunta: 'Posso falar com uma pessoa?',
      resposta:
          'Sim. $textoAtendimentoHumano Use "Falar com o suporte" ou escreva para suporte@tratofeitolabs.com.br.',
    ),
    PerguntaFrequente(
      pergunta: 'O que são Tratinhos?',
      resposta:
          'São pontos promocionais do Trato, não são dinheiro. Exemplo de conversão: 50 Tratinhos = R\$ 0,50. Campanhas informadas no app podem dar Tratinhos, e o app mostra quando dá para usá-los.',
    ),
    PerguntaFrequente(
      pergunta: 'Como funciona a exclusividade de 48h?',
      resposta:
          'Num pedido aberto, você pode usar Tratinhos para reservar o pedido a um profissional. O custo, o prazo e quando os Tratinhos voltam aparecem antes de confirmar.',
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
