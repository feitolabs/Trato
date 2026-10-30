/// Dados da Carteira do profissional. TUDO vem pronto do backend: o app só exibe.
/// Valores em centavos inteiros; saldos, taxa e líquido nunca são calculados na tela.
class ResumoCarteira {
  const ResumoCarteira({
    required this.disponivelCentavos,
    required this.textoPix,
    required this.retidoCentavos,
    required this.textoRetido,
    required this.aLiberarCentavos,
    required this.textoALiberar,
  });

  final int disponivelCentavos;

  /// Ex.: "Pix na chave CPF ***.482.***-12 · cai em até 1 dia útil". A chave só pode ser
  /// do mesmo CPF/CNPJ do profissional (regra do backend).
  final String textoPix;

  final int retidoCentavos;

  /// Ex.: "Serviço em andamento".
  final String textoRetido;

  final int aLiberarCentavos;

  /// Ex.: "Automático em até 48 h". O prazo depende de P1 (48 h x 7 dias): vem do dado.
  final String textoALiberar;
}

enum StatusExtrato { liberado, aLiberar }

class ItemExtrato {
  const ItemExtrato({
    required this.titulo,
    required this.detalheData,
    required this.brutoCentavos,
    required this.textoTaxa,
    required this.liquidoCentavos,
    required this.status,
  });

  final String titulo;

  /// Ex.: "26/10/2026" ou "Ontem · aguardando confirmação".
  final String detalheData;
  final int brutoCentavos;

  /// Texto da taxa já pronto, ex.: "R$ 10,00 de taxa". O percentual real é progressivo
  /// (P2/P5), por isso a tela não escreve nem calcula "5%".
  final String textoTaxa;
  final int liquidoCentavos;
  final StatusExtrato status;
}

/// Tudo que a tela precisa. [erro] preenchido mostra a mensagem com "Tentar de novo".
class DadosCarteira {
  const DadosCarteira({this.resumo, this.extrato = const [], this.erro});

  final ResumoCarteira? resumo;
  final List<ItemExtrato> extrato;
  final String? erro;
}
