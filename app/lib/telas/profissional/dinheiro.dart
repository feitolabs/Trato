/// Dinheiro só para EXIBIR e LER campos. Valores em centavos inteiros (`int`), nunca `double`.
/// Nenhuma regra de dinheiro mora no app: taxa e líquido vêm do backend (ver `ServicoOrcamento`).
abstract final class Dinheiro {
  /// Limite máximo aceito para o valor total de um orçamento (R$ 500.000,00).
  static const int limiteOrcamentoMaximoCentavos = 50000000;

  /// Limite máximo para o valor de um aditivo (R$ 100.000,00).
  static const int limiteAditivoMaximoCentavos = 10000000;

  /// Limite máximo do valor da hora (R$ 5.000,00 / hora).
  static const int limiteValorHoraMaximoCentavos = 500000;

  /// Limite máximo para valor de deslocamento (R$ 5.000,00).
  static const int limiteDeslocamentoMaximoCentavos = 500000;

  /// Limite máximo para horas (500 horas = 5000 décimos de hora).
  static const int limiteDecimosHorasMaximo = 5000;

  /// 4650 -> "R$ 46,50". Milhar com ponto: 123456 -> "R$ 1.234,56".
  static String formatar(int centavos) {
    final negativo = centavos < 0;
    final absoluto = centavos.abs();
    final reais = (absoluto ~/ 100).toString();
    final cents = (absoluto % 100).toString().padLeft(2, '0');
    final agrupado = reais.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return '${negativo ? '-' : ''}R\$ $agrupado,$cents';
  }

  /// "46", "46,5" ou "46,50" (ponto também vale) -> centavos. Vazio ou inválido -> null.
  /// Limita o comprimento para evitar overflow de inteiros de 64 bits.
  static int? lerCentavos(String texto) {
    final m = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(texto.trim());
    if (m == null) return null;
    final parteInteira = m.group(1)!;
    // Mais de 10 dígitos na parte inteira já ultrapassa qualquer valor razoável e arrisca overflow
    if (parteInteira.length > 10) return null;
    final reais = int.tryParse(parteInteira);
    if (reais == null || reais > 100000000) return null;
    final cents = int.parse((m.group(2) ?? '').padRight(2, '0'));
    return reais * 100 + cents;
  }

  /// Horas com até uma casa decimal ("3", "2,5") -> décimos de hora (30, 25). Inválido -> null.
  static int? lerDecimosDeHora(String texto) {
    final m = RegExp(r'^(\d+)(?:[.,](\d))?$').firstMatch(texto.trim());
    if (m == null) return null;
    final parteInteira = m.group(1)!;
    if (parteInteira.length > 5) return null;
    final inteiras = int.tryParse(parteInteira);
    if (inteiras == null || inteiras > 10000) return null;
    return inteiras * 10 + int.parse(m.group(2) ?? '0');
  }

  /// Valor da hora x horas, em centavos, arredondando meio centavo para cima. Só para exibir.
  /// Protegido contra overflow de multiplicação de inteiros grandes.
  static int valorDasHoras(int valorHoraCentavos, int decimosDeHora) {
    if (valorHoraCentavos <= 0 || decimosDeHora <= 0) return 0;
    // Se passar de valores gigantescos, limita para evitar overflow aritmético
    if (valorHoraCentavos > 1000000000 || decimosDeHora > 100000) return 0;
    return (valorHoraCentavos * decimosDeHora + 5) ~/ 10;
  }

  /// 500 -> "5%", 750 -> "7,5%", 725 -> "7,25%". Vem de pontos-base (bps) devolvidos pelo backend.
  static String formatarBps(int bps) {
    final inteiro = bps ~/ 100;
    final resto = bps % 100;
    if (resto == 0) return '$inteiro%';
    final casas = resto.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '');
    return '$inteiro,$casas%';
  }
}
