/// Só formata o que o backend mandou. Nenhuma conta de dinheiro acontece aqui.
String formatarReais(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final inteiro = (abs ~/ 100).toString();
  final partes = <String>[];
  for (var i = inteiro.length; i > 0; i -= 3) {
    partes.insert(0, inteiro.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '${negativo ? '-' : ''}R\$ ${partes.join('.')},$cents';
}

String formatarData(DateTime d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
}

/// Valor digitado em reais ("12,50") para centavos inteiros. Devolve null se for inválido.
int? lerReaisEmCentavos(String texto) {
  final limpo = texto.trim().replaceAll('R\$', '').replaceAll('.', '').replaceAll(' ', '');
  if (limpo.isEmpty) return null;
  final partes = limpo.split(',');
  if (partes.length > 2 || partes.any((p) => p.isEmpty || int.tryParse(p) == null)) return null;
  final reais = int.parse(partes[0]);
  final cents = partes.length == 2 ? int.parse(partes[1].padRight(2, '0').substring(0, 2)) : 0;
  return reais * 100 + cents;
}

/// Mostra o valor de uma configuração na unidade certa (bps vira %).
String formatarConfig(int valor, String unidade) => switch (unidade) {
      'bps' => '${(valor / 100).toStringAsFixed(2).replaceAll('.', ',')}%',
      'centavos' => formatarReais(valor),
      _ => '$valor $unidade',
    };
