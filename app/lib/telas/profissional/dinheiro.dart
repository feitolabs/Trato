/// Dinheiro só para EXIBIR e LER campos. Valores em centavos inteiros (`int`), nunca `double`.
/// Nenhuma regra de dinheiro mora no app: taxa e líquido vêm do backend (ver `ServicoOrcamento`).
abstract final class Dinheiro {
  /// 4650 -> "R$ 46,50". Milhar com ponto: 123456 -> "R$ 1.234,56".
  static String formatar(int centavos) {
    final negativo = centavos < 0;
    final absoluto = centavos.abs();
    final reais = (absoluto ~/ 100).toString();
    final cents = (absoluto % 100).toString().padLeft(2, '0');
    final agrupado =
        reais.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return '${negativo ? '-' : ''}R\$ $agrupado,$cents';
  }

  /// "46", "46,5" ou "46,50" (ponto também vale) -> centavos. Vazio ou inválido -> null.
  static int? lerCentavos(String texto) {
    final m = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(texto.trim());
    if (m == null) return null;
    final reais = int.tryParse(m.group(1)!);
    if (reais == null) return null;
    final cents = int.parse((m.group(2) ?? '').padRight(2, '0'));
    return reais * 100 + cents;
  }

  /// Horas com até uma casa decimal ("3", "2,5") -> décimos de hora (30, 25). Inválido -> null.
  static int? lerDecimosDeHora(String texto) {
    final m = RegExp(r'^(\d+)(?:[.,](\d))?$').firstMatch(texto.trim());
    if (m == null) return null;
    final inteiras = int.tryParse(m.group(1)!);
    if (inteiras == null) return null;
    return inteiras * 10 + int.parse(m.group(2) ?? '0');
  }

  /// Valor da hora x horas, em centavos, arredondando meio centavo para cima. Só para exibir.
  static int valorDasHoras(int valorHoraCentavos, int decimosDeHora) =>
      (valorHoraCentavos * decimosDeHora + 5) ~/ 10;

  /// 500 -> "5%", 750 -> "7,5%", 725 -> "7,25%". Vem de pontos-base (bps) devolvidos pelo backend.
  static String formatarBps(int bps) {
    final inteiro = bps ~/ 100;
    final resto = bps % 100;
    if (resto == 0) return '$inteiro%';
    final casas =
        resto.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '');
    return '$inteiro,$casas%';
  }
}
