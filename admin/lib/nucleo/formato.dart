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

/// Mensagem para um campo em reais com texto que não vale.
const kErroReais = 'Valor inválido. Use vírgula nos centavos: 12,50 ou 1.234,56.';

/// Única leitura de dinheiro digitado no painel: reais no padrão brasileiro ("1.234,56", "1234,5"
/// ou "12") para centavos inteiros, sem passar por double. É estrita de propósito: ponto só separa
/// milhar em grupos de três, então "12.50" e três casas são recusados em vez de mudar de valor.
/// Devolve null se for inválido (inclusive vazio e negativo); quem chama nunca troca null por zero.
int? lerReaisEmCentavos(String texto) {
  final m = RegExp(r'^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$').firstMatch(texto.trim());
  if (m == null) return null;
  final inteiros = m.group(1)!.replaceAll('.', '');
  if (inteiros.length > 10) return null;
  return int.parse(inteiros) * 100 + int.parse((m.group(2) ?? '').padRight(2, '0'));
}

/// Mensagem para um campo de percentual com texto que não vale.
const kErroPercentual = 'Percentual inválido. Use só vírgula nos decimais, com até 2 casas: 7,50.';

/// Percentual digitado ("7,50", "7,5" ou "7") para pontos-base inteiros (750), sem passar por
/// double. Só a vírgula é decimal: ponto e três casas são recusados, para "7.50" não virar 750%.
/// Devolve null se for inválido (inclusive vazio e negativo). A faixa quem confere é o parâmetro.
int? lerPercentualEmBps(String texto) {
  final m = RegExp(r'^(\d{1,6})(?:,(\d{1,2}))?$').firstMatch(texto.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 100 + int.parse((m.group(2) ?? '').padRight(2, '0'));
}

/// 1050 -> "10,50" (para preencher um campo em reais ou em percentual). Só inteiros.
String centavosParaCampo(int centavos) => '${centavos ~/ 100},${(centavos % 100).toString().padLeft(2, '0')}';

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
