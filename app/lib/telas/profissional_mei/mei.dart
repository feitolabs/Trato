import '../../dados/cliente_api.dart';

/// Situação do CNPJ do profissional (`mei_status` da API). Valor desconhecido = [naoInformado].
enum StatusMei {
  naoInformado,
  pendente,
  valido,
  invalido;

  static StatusMei deTexto(Object? v) => switch (v) {
        'pendente' => pendente,
        'valido' => valido,
        'invalido' => invalido,
        _ => naoInformado,
      };
}

/// Resposta de `GET` e `PUT /v1/profissional/mei`. Campo ausente (backend antigo) vira um valor
/// seguro: sem CNPJ, sem permissão para orçar.
class DadosMei {
  const DadosMei({
    this.cnpj,
    this.status = StatusMei.naoInformado,
    this.motivo,
    this.razaoSocial,
    this.validadoEm,
    this.podeOrcarEReceber = false,
    this.tipoCnpj,
  });

  factory DadosMei.deJson(Map<String, dynamic> j) {
    String? texto(Object? v) {
      final t = v is String ? v.trim() : '';
      return t.isEmpty ? null : t;
    }

    return DadosMei(
      cnpj: texto(j['cnpj']),
      status: StatusMei.deTexto(j['mei_status']),
      motivo: texto(j['motivo']),
      razaoSocial: texto(j['razao_social']),
      validadoEm: DateTime.tryParse('${j['validado_em']}'),
      podeOrcarEReceber: j['pode_orcar_e_receber'] == true,
      tipoCnpj: switch (j['tipo_cnpj']) {
        'mei' => 'mei',
        'outro' => 'outro',
        _ => null, // ausente ou desconhecido: ignora
      },
    );
  }

  final String? cnpj;
  final StatusMei status;
  final String? motivo;
  final String? razaoSocial;
  final DateTime? validadoEm;
  final bool podeOrcarEReceber;

  /// `mei` ou `outro`; nulo se o backend ainda não manda.
  final String? tipoCnpj;
}

/// O que a tela "Meu CNPJ" pede ao servidor. Os testes trocam por um fake.
abstract interface class ServicoMei {
  Future<DadosMei> carregar();

  /// Envia o CNPJ (só dígitos). Erro 422 volta como `ErroTrato` com o texto do servidor.
  Future<DadosMei> validar(String cnpjSoDigitos);
}

class ServicoMeiApi implements ServicoMei {
  ServicoMeiApi(this._api);

  final ClienteApi _api;

  @override
  Future<DadosMei> carregar() async =>
      DadosMei.deJson((await _api.get('/v1/profissional/mei'))! as Map<String, dynamic>);

  @override
  Future<DadosMei> validar(String cnpjSoDigitos) async => DadosMei.deJson(
      (await _api.put('/v1/profissional/mei', corpo: {'cnpj': cnpjSoDigitos}))!
          as Map<String, dynamic>);
}

/// Só dígitos, no máximo 14.
String soDigitosCnpj(String v) {
  final d = v.replaceAll(RegExp(r'\D'), '');
  return d.length > 14 ? d.substring(0, 14) : d;
}

/// "12345678000195" vira "12.345.678/0001-95" (parcial enquanto digita).
String formatarCnpj(String v) {
  final d = soDigitosCnpj(v);
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 2 || i == 5) b.write('.');
    if (i == 8) b.write('/');
    if (i == 12) b.write('-');
    b.write(d[i]);
  }
  return b.toString();
}

/// Confere os 14 dígitos e os dois dígitos verificadores. Só ajuda a pessoa a digitar: quem
/// decide se o CNPJ vale é o servidor.
bool cnpjParecidoValido(String v) {
  final d = soDigitosCnpj(v);
  if (d.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(d)) return false;
  int dv(int n) {
    const pesos = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var soma = 0;
    for (var i = 0; i < n; i++) {
      soma += int.parse(d[i]) * pesos[13 - n + i];
    }
    final r = soma % 11;
    return r < 2 ? 0 : 11 - r;
  }

  return dv(12) == int.parse(d[12]) && dv(13) == int.parse(d[13]);
}

/// A mensagem do servidor é sobre CNPJ ou MEI (orçamento barrado por falta dele).
bool mensagemDeCnpj(String texto) {
  final t = texto.toLowerCase();
  return t.contains('cnpj') || RegExp(r'\bmei\b').hasMatch(t);
}
