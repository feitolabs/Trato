import 'modelos.dart';

/// PROVISÓRIO — dados do protótipo (tela 27) só para demonstração e testes.
/// Os textos de taxa e prazo aparecem aqui porque vêm do dado, não da tela.
abstract final class DadosExemploCarteira {
  static const completo = DadosCarteira(
    resumo: ResumoCarteira(
      disponivelCentavos: 71250,
      textoPix: 'Pix na chave CPF ***.482.***-12 · cai em até 1 dia útil',
      retidoCentavos: 42500,
      textoRetido: 'Serviço em andamento',
      aLiberarCentavos: 19000,
      textoALiberar: 'Automático em até 48 h',
    ),
    extrato: [
      ItemExtrato(
        titulo: 'Instalar 4 luminárias',
        detalheData: 'Ontem · aguardando confirmação',
        brutoCentavos: 20000,
        textoTaxa: 'R\$ 10,00 de taxa',
        liquidoCentavos: 19000,
        status: StatusExtrato.aLiberar,
      ),
      ItemExtrato(
        titulo: 'Pintura de portão',
        detalheData: '26/10/2026',
        brutoCentavos: 40000,
        textoTaxa: 'R\$ 20,00 de taxa',
        liquidoCentavos: 38000,
        status: StatusExtrato.liberado,
      ),
      ItemExtrato(
        titulo: 'Troca de resistência',
        detalheData: '24/10/2026',
        brutoCentavos: 15000,
        textoTaxa: 'R\$ 7,50 de taxa',
        liquidoCentavos: 14250,
        status: StatusExtrato.liberado,
      ),
      ItemExtrato(
        titulo: 'Ventilador de teto',
        detalheData: '22/10/2026',
        brutoCentavos: 20000,
        textoTaxa: 'R\$ 10,00 de taxa',
        liquidoCentavos: 19000,
        status: StatusExtrato.liberado,
      ),
    ],
  );

  static const vazio = DadosCarteira(
    resumo: ResumoCarteira(
      disponivelCentavos: 0,
      textoPix: 'Cadastre uma chave Pix no seu CPF ou CNPJ para sacar',
      retidoCentavos: 0,
      textoRetido: 'Nenhum serviço em andamento',
      aLiberarCentavos: 0,
      textoALiberar: 'Nada a liberar',
    ),
  );

  static const comErro =
      DadosCarteira(erro: 'Não foi possível carregar a carteira.');
}
