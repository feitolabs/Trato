import 'package:flutter/services.dart';

/// Validação de formulário só no app (o backend decide de verdade).
/// Cada função devolve a mensagem de erro, ou null se o valor está certo.
abstract final class ValidacaoAuth {
  static String somenteDigitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  static String? obrigatorio(String valor, String mensagem) =>
      valor.trim().isEmpty ? mensagem : null;

  static String? nome(String valor) =>
      valor.trim().length < 3 ? 'Nome muito curto. Digite seu nome completo (mínimo de 3 letras).' : null;

  static String? cpf(String valor) {
    final d = somenteDigitos(valor);
    if (d.length != 11) return 'CPF incompleto. Digite os 11 números do seu documento.';
    if (d.split('').every((c) => c == d[0])) {
      return 'O CPF não pode ter todos os dígitos iguais. Digite um CPF válido.';
    }
    for (var posicao = 9; posicao < 11; posicao++) {
      var soma = 0;
      for (var i = 0; i < posicao; i++) {
        soma += int.parse(d[i]) * (posicao + 1 - i);
      }
      final resto = soma % 11;
      final digito = resto < 2 ? 0 : 11 - resto;
      if (d[posicao] != '$digito') {
        return 'Dígitos verificadores incorretos. Confira os 11 números do seu CPF.';
      }
    }
    return null;
  }

  /// Data no formato dd/mm/aaaa, de quem tem 18 anos ou mais ("O Trato é para maiores de 18 anos").
  static String? nascimento(String valor, {DateTime? hoje}) {
    final partes = valor.split('/');
    if (partes.length != 3 || partes[2].length != 4) {
      return 'Data incompleta. Digite dia, mês e ano com 4 dígitos (dd/mm/aaaa).';
    }
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) {
      return 'Formato de data inválido. Digite apenas números no formato dd/mm/aaaa.';
    }
    final data = DateTime(ano, mes, dia);
    if (data.day != dia || data.month != mes || data.year != ano) {
      return 'Data inexistente no calendário. Confira o dia e o mês digitados.';
    }
    final agora = hoje ?? DateTime.now();
    var idade = agora.year - ano;
    if (agora.month < mes || (agora.month == mes && agora.day < dia)) idade--;
    if (idade < 0) return 'Data no futuro. Digite sua data de nascimento real.';
    return idade < 18
        ? 'Idade inferior a 18 anos. O cadastro no Trato é exclusivo para maiores de 18 anos.'
        : null;
  }

  static String? celular(String valor) =>
      somenteDigitos(valor).length == 11
          ? null
          : 'Celular incompleto. Digite o DDD e o número com 11 dígitos.';

  static String? email(String valor) {
    final v = valor.trim();
    if (v.isEmpty) return 'E-mail não preenchido. Digite seu endereço de e-mail.';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
        ? null
        : 'E-mail incompleto ou sem arroba. Digite no formato nome@exemplo.com.';
  }

  /// Valida o identificador de login: e-mail, CPF (11 dígitos) ou telefone com DDD (10 a 13 dígitos).
  static String? identificadorLogin(String valor) {
    final v = valor.trim();
    if (v.isEmpty) return 'Campo não preenchido. Digite seu e-mail, CPF ou celular para continuar.';
    if (v.contains('@') || RegExp(r'[A-Za-z]').hasMatch(v)) {
      return email(v);
    }
    final d = somenteDigitos(v);
    if (d.length >= 10 && d.length <= 13) return null;
    return 'Identificador incompleto. Digite um e-mail válido, CPF (11 números) ou telefone com DDD.';
  }

  /// 8 ou mais caracteres, com pelo menos uma letra e um número.
  static String? senhaNova(String valor) {
    final forte = valor.length >= 8 &&
        RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(valor) &&
        RegExp(r'\d').hasMatch(valor);
    return forte
        ? null
        : 'Senha fraca. Use pelo menos 8 caracteres combinando letras e números.';
  }

  static String? codigoSms(String valor) =>
      somenteDigitos(valor).length == 6
          ? null
          : 'Código incompleto. Digite os 6 números recebidos por SMS.';

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
