// Modelos da tela de pagamento. O app só exibe o que vier daqui:
// quanto pagar agora e em que condição são decididos pelo backend.

import '../comuns/desconto_moedas.dart';
import '../profissional/dinheiro.dart';

enum MetodoPagamento { pix, cartao }

/// Termos 6.4: quanto o parcelado custa a mais que o à vista. O valor vem do servidor.
String textoDiferencaDoAVista(int custoCentavos) => custoCentavos > 0
    ? '${Dinheiro.formatar(custoCentavos)} a mais que à vista (custo do parcelamento).'
    : 'Sem diferença em relação ao à vista.';

/// Termos 6.3: prazo de validade/expiração do Pix vindo do servidor. Nulo se ambos ausentes.
String? textoPrazoPix(DateTime? expiraEm, int? validadeMinutos) {
  final temMin = validadeMinutos != null && validadeMinutos > 0;
  String? ate;
  if (expiraEm != null) {
    final d = expiraEm.day.toString().padLeft(2, '0');
    final m = expiraEm.month.toString().padLeft(2, '0');
    final h = expiraEm.hour.toString().padLeft(2, '0');
    final min = expiraEm.minute.toString().padLeft(2, '0');
    ate = '$d/$m, $h:$min';
  }
  if (temMin && ate != null) {
    return 'Pix válido por $validadeMinutos '
        '${validadeMinutos == 1 ? 'minuto' : 'minutos'} (até $ate).';
  }
  if (ate != null) return 'Código Pix válido até $ate.';
  if (temMin) {
    return 'Pix válido por $validadeMinutos ${validadeMinutos == 1 ? 'minuto' : 'minutos'}.';
  }
  return null;
}

/// Termos 6.10: rótulo legível do status de estorno devolvido pelo servidor.
String? rotuloEstornoStatus(String? status) {
  final limpo = (status ?? '').trim().toLowerCase();
  if (limpo.isEmpty) return null;
  return switch (limpo) {
    'solicitado' => 'Estorno solicitado',
    'em_processamento' => 'Estorno em processamento',
    'concluido' => 'Estorno concluído',
    'falhou' => 'Falha no estorno',
    _ => 'Estorno: ${status!.trim()}',
  };
}

class OpcaoPagamento {
  const OpcaoPagamento({required this.metodo, required this.titulo, required this.descricao});

  final MetodoPagamento metodo;
  final String titulo;
  final String descricao;
}

/// Termos 6.4: título da opção de parcelamento ("2x de R$ 50,00 sem juros" ou "2x de R$ 51,50").
String textoTituloParcela(OpcaoParcelamento p) {
  final base = '${p.parcelas}x de ${Dinheiro.formatar(p.valorParcelaCentavos)}';
  return opcaoSemJuros(p) ? '$base sem juros' : base;
}

/// Termos 6.4: só é "sem juros" se o servidor disser e não mandar uma taxa que contradiga.
bool opcaoSemJuros(OpcaoParcelamento p) => p.semJuros == true && (p.jurosMensalBps ?? 0) <= 0;

/// Termos 6.4: taxa de juros aplicada, só formatada ("1,99% ao mês"). Nulo se o servidor não
/// mandar a taxa, ou se ela vier junto de `sem_juros` verdadeiro (dados contraditórios).
String? textoJurosMensal(OpcaoParcelamento p) {
  final bps = p.jurosMensalBps;
  if (p.semJuros == true || bps == null || bps <= 0) return null;
  return 'Juros de ${Dinheiro.formatarBps(bps)} ao mês.';
}

/// Termos 6.4: detalhe da opção de parcelamento com os valores prontos do servidor.
/// Nunca inventa taxa mensal: a taxa é só `jurosMensalBps`; `custoTotalBps` é custo único
/// sobre o valor à vista.
String textoDetalheParcela(OpcaoParcelamento p) {
  final juros = textoJurosMensal(p);
  final partes = <String>[
    if (juros != null) juros,
    'Total ${Dinheiro.formatar(p.totalCentavos)}.',
  ];
  final ultima = p.ultimaParcelaCentavos;
  if (p.parcelas > 1 && ultima != null && ultima != p.valorParcelaCentavos) {
    partes.add('Última parcela de ${Dinheiro.formatar(ultima)} (fecha o total exato).');
  }
  final diferenca = p.diferencaAVistaCentavos ?? p.custoCentavos;
  final bps = p.custoTotalBps;
  if (opcaoSemJuros(p)) {
    partes.add(textoDiferencaDoAVista(diferenca));
  } else if (bps != null && bps > 0) {
    if (diferenca > 0) {
      partes.add(
        '${Dinheiro.formatar(diferenca)} a mais que à vista '
        '(${Dinheiro.formatarBps(bps)} de custo total no parcelamento).',
      );
    } else {
      partes.add('Custo total de ${Dinheiro.formatarBps(bps)} no parcelamento.');
    }
  } else {
    partes.add(textoDiferencaDoAVista(diferenca));
  }
  return partes.join(' ');
}

/// Cartão parcelado: o total por número de parcelas (custo do provedor repassado ao cliente).
/// Vem pronto do backend; lista vazia = parcelado desligado.
class OpcaoParcelamento {
  const OpcaoParcelamento({
    required this.parcelas,
    required this.custoCentavos,
    required this.totalCentavos,
    required this.valorParcelaCentavos,
    this.valoresParcelasCentavos = const [],
    this.ultimaParcelaCentavos,
    this.custoTotalBps,
    this.diferencaAVistaCentavos,
    this.semJuros,
    this.jurosMensalBps,
  });

  final int parcelas;
  final int custoCentavos;
  final int totalCentavos;
  final int valorParcelaCentavos;

  /// Uma por parcela, na ordem; a soma é `total_centavos`. Vazia em resposta antiga.
  final List<int> valoresParcelasCentavos;

  /// Valor da última parcela (absorve o resto da divisão). Null em resposta antiga.
  final int? ultimaParcelaCentavos;

  /// Custo único em pontos-base (100 = 1%) sobre o à vista (não é taxa mensal). Null em resposta antiga.
  final int? custoTotalBps;

  /// Diferença em centavos em relação ao à vista (Termos 6.4). Null em resposta antiga.
  final int? diferencaAVistaCentavos;

  /// `true`: opção sem juros/custo; `false`: tem custo. Null em resposta antiga.
  final bool? semJuros;

  /// `juros_mensal_bps`: juros ao mês em pontos-base (199 = 1,99%). Null: o servidor não informou.
  final int? jurosMensalBps;
}

class DadosPagamento {
  const DadosPagamento({
    required this.subtitulo,
    required this.valorAgoraCentavos,
    required this.opcoes,
    this.rotuloValor,
    this.parcelamento = const [],
    this.descontoCentavos = 0,
    this.descontoCupomCentavos,
    this.cupomCodigo,
    this.moedasSaldo = 0,
    this.moedasUsadas = 0,
    this.moedasDescontoCentavos = 0,
    this.descontoDisponivel = true,
    this.descontoIndisponivelMotivo,
    this.moedaValorCentavos,
    this.descontoPossivelCentavos,
    this.descontoVoltaEm,
    this.tetoDescontoMesCentavos,
    this.descontoUsadoMesCentavos,
    this.cpfCadastrado = true,
    this.validadeAte,
    this.pagoOuEmConfirmacao = false,
    this.pixExpiraEm,
    this.pixValidadeMinutos,
    this.estornoStatus,
    this.estornoPrazoEstimado,
  });

  /// O servidor diz que o pagamento já foi feito ou está sendo confirmado.
  final bool pagoOuEmConfirmacao;

  /// Termos 6.3: expiração e validade em minutos do Pix (opcionais).
  final DateTime? pixExpiraEm;
  final int? pixValidadeMinutos;

  /// Termos 6.10: status e prazo estimado do estorno (opcionais).
  final String? estornoStatus;
  final String? estornoPrazoEstimado;

  /// `validade_ate`: validade do orçamento aceito. Nula: o servidor não informou.
  final DateTime? validadeAte;

  /// Teto mensal do desconto com Tratinhos e quanto já foi usado (`/v1/me/moedas`).
  /// Nulo: o servidor não informou.
  final int? tetoDescontoMesCentavos;
  final int? descontoUsadoMesCentavos;

  /// Quanto o cliente pode abater neste serviço, em centavos (decidido pelo backend). Null: sem linha.
  final int? descontoPossivelCentavos;

  /// Quando o desconto volta (`desconto_volta_em`). Null: texto sem data.
  final DateTime? descontoVoltaEm;

  /// Se o cliente já informou CPF no perfil. Ausente (backend antigo) = true.
  final bool cpfCadastrado;

  /// Valor de 1 Tratinho em centavos, só para exibir "N Tratinhos = R$ X". Null: mostra a quantidade.
  final int? moedaValorCentavos;

  /// Backend diz se o desconto das moedas pode ser usado agora. Campo ausente = true.
  final bool descontoDisponivel;
  final MotivoDescontoIndisponivel? descontoIndisponivelMotivo;

  /// Total por número de parcelas no cartão. Vazio enquanto o parcelado estiver desligado.
  final List<OpcaoParcelamento> parcelamento;

  /// "Carlos Mendes · Troca de tomadas e chuveiro".
  final String subtitulo;

  /// Valor a pagar agora, em centavos (int). Vem pronto do backend.
  final int valorAgoraCentavos;

  /// Desconto aplicado pelo cupom (em centavos). Zero quando não há cupom.
  final int descontoCentavos;

  /// Parte do desconto que é do cupom (`desconto_cupom_centavos`), pronta do backend. Ausente
  /// (backend antigo) = null: a linha do cupom não aparece (o app não calcula dinheiro).
  final int? descontoCupomCentavos;

  /// Código de cupom aceito e aplicado neste cálculo.
  final String? cupomCodigo;

  /// Moedas do Trato: saldo do cliente, quantas entram neste cálculo e o desconto delas. Tudo
  /// vem pronto do backend; o app só mostra.
  final int moedasSaldo;
  final int moedasUsadas;
  final int moedasDescontoCentavos;

  /// Texto opcional sob o valor, ex.: "Adiantamento de 30%". Null = não mostra.
  final String? rotuloValor;
  final List<OpcaoPagamento> opcoes;

  DadosPagamento copiarCom({
    String? subtitulo,
    int? valorAgoraCentavos,
    List<OpcaoParcelamento>? parcelamento,
    int? descontoCentavos,
    int? descontoCupomCentavos,
    String? cupomCodigo,
    int? moedasSaldo,
    int? moedasUsadas,
    int? moedasDescontoCentavos,
    bool? descontoDisponivel,
    MotivoDescontoIndisponivel? descontoIndisponivelMotivo,
    int? moedaValorCentavos,
    bool? cpfCadastrado,
    int? descontoPossivelCentavos,
    DateTime? descontoVoltaEm,
    int? tetoDescontoMesCentavos,
    int? descontoUsadoMesCentavos,
    String? rotuloValor,
    List<OpcaoPagamento>? opcoes,
    DateTime? validadeAte,
    bool? pagoOuEmConfirmacao,
    DateTime? pixExpiraEm,
    int? pixValidadeMinutos,
    String? estornoStatus,
    String? estornoPrazoEstimado,
  }) =>
      DadosPagamento(
        subtitulo: subtitulo ?? this.subtitulo,
        valorAgoraCentavos: valorAgoraCentavos ?? this.valorAgoraCentavos,
        parcelamento: parcelamento ?? this.parcelamento,
        descontoCentavos: descontoCentavos ?? this.descontoCentavos,
        descontoCupomCentavos: descontoCupomCentavos ?? this.descontoCupomCentavos,
        cupomCodigo: cupomCodigo ?? this.cupomCodigo,
        moedasSaldo: moedasSaldo ?? this.moedasSaldo,
        moedasUsadas: moedasUsadas ?? this.moedasUsadas,
        moedasDescontoCentavos: moedasDescontoCentavos ?? this.moedasDescontoCentavos,
        descontoDisponivel: descontoDisponivel ?? this.descontoDisponivel,
        descontoIndisponivelMotivo: descontoIndisponivelMotivo ?? this.descontoIndisponivelMotivo,
        moedaValorCentavos: moedaValorCentavos ?? this.moedaValorCentavos,
        descontoPossivelCentavos: descontoPossivelCentavos ?? this.descontoPossivelCentavos,
        descontoVoltaEm: descontoVoltaEm ?? this.descontoVoltaEm,
        tetoDescontoMesCentavos: tetoDescontoMesCentavos ?? this.tetoDescontoMesCentavos,
        descontoUsadoMesCentavos: descontoUsadoMesCentavos ?? this.descontoUsadoMesCentavos,
        cpfCadastrado: cpfCadastrado ?? this.cpfCadastrado,
        rotuloValor: rotuloValor ?? this.rotuloValor,
        opcoes: opcoes ?? this.opcoes,
        validadeAte: validadeAte ?? this.validadeAte,
        pagoOuEmConfirmacao: pagoOuEmConfirmacao ?? this.pagoOuEmConfirmacao,
        pixExpiraEm: pixExpiraEm ?? this.pixExpiraEm,
        pixValidadeMinutos: pixValidadeMinutos ?? this.pixValidadeMinutos,
        estornoStatus: estornoStatus ?? this.estornoStatus,
        estornoPrazoEstimado: estornoPrazoEstimado ?? this.estornoPrazoEstimado,
      );
}
