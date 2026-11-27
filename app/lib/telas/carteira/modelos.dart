import '../../dados/config_publica.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho;

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
    this.proximaLiberacao,
  });

  final int disponivelCentavos;

  /// Ex.: "Pix na chave CPF ***.482.***-12 · cai em até 1 dia útil". A chave só pode ser
  /// do mesmo CPF/CNPJ do profissional (regra do backend).
  final String textoPix;

  final int retidoCentavos;

  /// Ex.: "Serviço em andamento".
  final String textoRetido;

  final int aLiberarCentavos;

  /// Ex.: "Automático em até 48 h". O prazo vem do dado (configuração), nunca fixo na tela.
  final String textoALiberar;

  /// Data do próximo repasse (API). Com data, ela substitui o texto de prazo.
  final DateTime? proximaLiberacao;
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
    this.pedidoId,
    this.rodape,
  });

  /// Texto no pé da linha, no lugar de "Sem taxa"/"Estorno".
  final String? rodape;

  /// Para abrir o detalhe dos valores do pedido ao tocar na linha.
  final String? pedidoId;

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

/// Um valor com nome, na tela de detalhe do pedido.
class LinhaDeValor {
  const LinhaDeValor(this.rotulo, this.centavos, {this.nota});

  final String rotulo;
  final int centavos;

  /// Texto pequeno abaixo (ex.: "Aguardando o cliente pagar").
  final String? nota;
}

/// Valores de um pedido para o profissional. Tudo sai pronto do backend (saldo do ledger,
/// aditivos e notas); o app só mostra.
class DetalheValoresPedido {
  const DetalheValoresPedido({
    required this.pedidoNumero,
    required this.pagoPeloClienteCentavos,
    required this.voceRecebeCentavos,
    required this.situacao,
    this.liberaEm,
    this.aditivos = const [],
    this.notas = const [],
    this.podeAvaliarCliente = false,
    this.avaliarAte,
  });

  final String pedidoNumero;

  /// Pedido concluído que o profissional ainda não avaliou.
  final bool podeAvaliarCliente;

  /// Termos 12.1: até quando dá para avaliar o cliente (do servidor).
  final DateTime? avaliarAte;

  /// O valor inteiro que o cliente pagou.
  final int pagoPeloClienteCentavos;

  /// O que fica para o profissional (o Trato não cobra taxa).
  final int voceRecebeCentavos;

  /// Ex.: "Retido até o serviço ser confirmado".
  final String situacao;

  /// Data prevista da liberação (opcional: `liberacao_prevista_em` do saldo do pedido).
  final DateTime? liberaEm;
  final List<LinhaDeValor> aditivos;
  final List<LinhaDeValor> notas;
}

/// Conta de recebimento (Pix / conta bancária para repasse de valores liberados, D15).
class ContaRecebimento {
  const ContaRecebimento({
    required this.cadastrada,
    this.tipoPix,
    this.chavePix,
    this.chavePixMascarada,
    this.bancoCodigo,
    this.bancoNome,
    this.agencia,
    this.conta,
    this.tipoConta,
    this.resumoExibicao,
  });

  final bool cadastrada;
  final String? tipoPix;
  final String? chavePix;
  final String? chavePixMascarada;
  final String? bancoCodigo;
  final String? bancoNome;
  final String? agencia;
  final String? conta;
  final String? tipoConta;
  final String? resumoExibicao;
}

/// Tudo que a tela precisa. [erro] preenchido mostra a mensagem com "Tentar de novo".
/// Quando o repasse cai na conta. A data (`DD/MM`) vem do backend; sem ela, só a regra geral,
/// sem citar número de horas ou dias (o prazo é da configuração e pode mudar).
String textoRegraLiberacao(DateTime? libera) => libera == null
    ? 'Cai na sua conta depois que o cliente confirmar o serviço'
    : 'Cai na sua conta em ${diaMesDoAparelho(libera)}';

/// Resposta do toque em "Por quê?" na regra de liberação.
const textoPorQueLiberacao =
    'O valor fica guardado até o cliente confirmar o serviço e o prazo de reclamação terminar. '
    'Depois é repassado à sua conta cadastrada. Sem taxa.';

/// Monta o resumo da Carteira só com o que a API do saldo devolveu (`liberado_centavos`,
/// `retido_centavos`, `a_liberar_centavos`, `proxima_liberacao_em`). Nada é somado nem calculado.
/// O prazo de queda do Pix não vem da API: a linha mostra só a chave.
ResumoCarteira resumoCarteiraDoSaldo({
  required int liberadoCentavos,
  required int retidoCentavos,
  required int aLiberarCentavos,
  DateTime? proximaLiberacao,
  ContaRecebimento? conta,
}) {
  final chave = conta?.resumoExibicao ?? conta?.chavePixMascarada;
  final cadastrada = conta?.cadastrada == true && (chave ?? '').isNotEmpty;
  return ResumoCarteira(
    disponivelCentavos: liberadoCentavos,
    textoPix: cadastrada ? 'Pix na chave $chave' : 'Cadastre sua conta Pix para receber',
    retidoCentavos: retidoCentavos,
    textoRetido: 'Serviço em andamento',
    aLiberarCentavos: aLiberarCentavos,
    textoALiberar:
        'Automático em até ${ConfigPublica.horas(ConfigPublica.atual.prazoConfirmacaoHoras)}',
    proximaLiberacao: proximaLiberacao,
  );
}

class DadosCarteira {
  const DadosCarteira({
    this.proximaLiberacao,
    this.tratinhosPendentesTexto,
    this.resumo,
    this.extrato = const [],
    this.contaRecebimento,
    this.erro,
  });

  /// Data do próximo repasse (a que o app já recebe do saldo); nula = só a regra, sem data.
  final DateTime? proximaLiberacao;

  /// "Você tem 50 Tratinhos a liberar em 27/11"; nulo = sem pendentes.
  final String? tratinhosPendentesTexto;

  final ResumoCarteira? resumo;
  final List<ItemExtrato> extrato;
  final ContaRecebimento? contaRecebimento;
  final String? erro;
}
