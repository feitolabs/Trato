import 'modelos.dart';

/// DADOS PROVISÓRIOS: textos da tela 14 do protótipo (valor cheio, como no PDF).
/// Serão trocados pelos dados reais da API.
abstract final class DadosExemplo {
  static const pagamento = DadosPagamento(
    subtitulo: 'Carlos Mendes · Troca de tomadas e chuveiro',
    valorAgoraCentavos: 38000,
    opcoes: [
      OpcaoPagamento(
        metodo: MetodoPagamento.pix,
        titulo: 'Pix',
        descricao: 'Sem custo extra. Confirmação na hora.',
      ),
      OpcaoPagamento(
        metodo: MetodoPagamento.cartao,
        titulo: 'Cartão de crédito à vista',
        descricao: 'Visa final 4417',
      ),
    ],
  );
}
