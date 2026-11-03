/// Só formata o que o backend mandou. Nenhuma conta de dinheiro acontece aqui.
///
/// Padrões do painel (RNF-08): português do Brasil, datas em DD/MM/AAAA HH:mm, valores como
/// R$ 1.234,56.
String formatarReais(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '${negativo ? '-' : ''}R\$ ${formatarMilhar(abs ~/ 100)},$cents';
}

/// 1234567 -> "1.234.567".
String formatarMilhar(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

String _dois(int n) => n.toString().padLeft(2, '0');

/// "02/11/2026 14:32".
String formatarData(DateTime d) => '${formatarDia(d)} ${_dois(d.hour)}:${_dois(d.minute)}';

/// "02/11/2026".
String formatarDia(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

/// "02/11" (eixo de gráfico).
String formatarDiaMes(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}';

/// "há 3 dias", "há 5 h", "agora".
String formatarHa(DateTime d, {DateTime? agora}) {
  final dif = (agora ?? DateTime.now()).difference(d);
  if (dif.inMinutes < 1) return 'agora';
  if (dif.inHours < 1) return 'há ${dif.inMinutes} min';
  if (dif.inHours < 24) return 'há ${dif.inHours} h';
  final dias = dif.inDays;
  return dias == 1 ? 'há 1 dia' : 'há $dias dias';
}

/// Tempo que falta até [limite]: "6 h", "3 dias", ou "vencido".
String formatarRestante(DateTime limite, {DateTime? agora}) {
  final dif = limite.difference(agora ?? DateTime.now());
  if (dif.isNegative) return 'vencido';
  if (dif.inHours < 1) return '${dif.inMinutes} min';
  if (dif.inHours < 48) return '${dif.inHours} h';
  return '${dif.inDays} dias';
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

/// Mostra o valor de uma configuração na unidade certa (bps vira %, centavos vira R$).
String formatarConfig(int valor, String unidade) => switch (unidade) {
      'bps' => '${(valor / 100).toStringAsFixed(2).replaceAll('.', ',')}%',
      'centavos' => formatarReais(valor),
      'horas' => valor == 1 ? '1 hora' : '$valor horas',
      'dias' => valor == 1 ? '1 dia' : '$valor dias',
      'dias_uteis' => valor == 1 ? '1 dia útil' : '$valor dias úteis',
      _ => '$valor',
    };

/// Mascara o telefone: "(31) •••••-4821".
String mascararTelefone(String telefone) {
  final d = telefone.replaceAll(RegExp(r'\D'), '');
  if (d.length < 10) return telefone;
  final ddd = d.substring(0, 2);
  final fim = d.substring(d.length - 4);
  return '($ddd) •••••-$fim';
}

/// Mascara o e-mail: "m•••••@gmail.com".
String mascararEmailPessoa(String email) {
  final i = email.indexOf('@');
  if (i <= 1) return email;
  return '${email[0]}•••••${email.substring(i)}';
}
