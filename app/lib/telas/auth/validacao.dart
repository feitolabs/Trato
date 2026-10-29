import 'package:flutter/services.dart';

/// Validação de formulário só no app (o backend decide de verdade).
/// Cada função devolve a mensagem de erro, ou null se o valor está certo.
abstract final class ValidacaoAuth {
  static String somenteDigitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  static String? obrigatorio(String valor, String mensagem) =>
      valor.trim().isEmpty ? mensagem : null;

  static String? nome(String valor) =>
      valor.trim().length < 3 ? 'Informe seu nome completo.' : null;

  static String? cpf(String valor) =>
      somenteDigitos(valor).length == 11 ? null : 'O CPF tem 11 números.';

  /// Data no formato dd/mm/aaaa, de quem tem 18 anos ou mais ("O Trato é para maiores de 18 anos").
  static String? nascimento(String valor, {DateTime? hoje}) {
    final partes = valor.split('/');
    if (partes.length != 3 || partes[2].length != 4) return 'Use o formato dd/mm/aaaa.';
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return 'Use o formato dd/mm/aaaa.';
    final data = DateTime(ano, mes, dia);
    if (data.day != dia || data.month != mes || data.year != ano) return 'Data inválida.';
    final agora = hoje ?? DateTime.now();
    var idade = agora.year - ano;
    if (agora.month < mes || (agora.month == mes && agora.day < dia)) idade--;
    if (idade < 0) return 'Data inválida.';
    return idade < 18 ? 'O Trato é para maiores de 18 anos.' : null;
  }

  static String? celular(String valor) =>
      somenteDigitos(valor).length == 11 ? null : 'Informe DDD e número, com 11 dígitos.';

  static String? email(String valor) {
    final v = valor.trim();
    if (v.isEmpty) return 'Informe seu e-mail.';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v) ? null : 'E-mail inválido.';
  }

  /// 8 ou mais caracteres, com pelo menos uma letra e um número.
  static String? senhaNova(String valor) {
    final forte = valor.length >= 8 &&
        RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(valor) &&
        RegExp(r'\d').hasMatch(valor);
    return forte ? null : 'Use 8 ou mais caracteres, com letra e número.';
  }

  static String? codigoSms(String valor) =>
      somenteDigitos(valor).length == 6 ? null : 'O código tem 6 números.';

  /// "(31) 9••••-4417" a partir dos números digitados.
  static String celularMascarado(String valor) {
    final d = somenteDigitos(valor);
    if (d.length < 11) return valor;
    return '(${d.substring(0, 2)}) ${d[2]}••••-${d.substring(7)}';
  }
}

/// Aplica uma máscara onde `0` é um número. Ex.: `000.000.000-00`.
class MascaraNumerica extends TextInputFormatter {
  const MascaraNumerica(this.mascara);

  static const cpf = MascaraNumerica('000.000.000-00');
  static const data = MascaraNumerica('00/00/0000');
  static const celular = MascaraNumerica('(00) 00000-0000');

  final String mascara;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    final digitos = ValidacaoAuth.somenteDigitos(novo.text);
    final saida = StringBuffer();
    var i = 0;
    for (final c in mascara.split('')) {
      if (i >= digitos.length) break;
      if (c == '0') {
        saida.write(digitos[i++]);
      } else {
        saida.write(c);
      }
    }
    final texto = saida.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
