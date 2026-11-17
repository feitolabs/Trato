import 'cliente_api.dart';

class EnderecoPorCep {
  const EnderecoPorCep({
    required this.cep,
    required this.logradouro,
    required this.complemento,
    required this.bairro,
    required this.cidade,
    required this.uf,
  });

  factory EnderecoPorCep.deJson(Map<String, dynamic> j) => EnderecoPorCep(
        cep: (j['cep'] as String?) ?? '',
        logradouro: (j['logradouro'] as String?) ?? '',
        complemento: (j['complemento'] as String?) ?? '',
        bairro: (j['bairro'] as String?) ?? '',
        cidade: (j['cidade'] as String?) ?? '',
        uf: (j['uf'] as String?) ?? '',
      );

  final String cep;
  final String logradouro;
  final String complemento;
  final String bairro;
  final String cidade;
  final String uf;
}

abstract interface class ServicoCep {
  Future<EnderecoPorCep> consultar(String cep);
}

class ServicoCepApi implements ServicoCep {
  ServicoCepApi(this._api);

  final ClienteApi _api;

  @override
  Future<EnderecoPorCep> consultar(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'\D'), '');
    final resposta = await _api.get('/v1/cep/$digitos');
    return EnderecoPorCep.deJson(resposta! as Map<String, dynamic>);
  }
}

/// Usado na demonstração local ou em testes quando nenhuma implementação customizada é passada.
class ServicoCepFake implements ServicoCep {
  const ServicoCepFake();

  @override
  Future<EnderecoPorCep> consultar(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'\D'), '');
    return EnderecoPorCep(
      cep: digitos,
      logradouro: 'Av. Primeiro de Junho',
      complemento: '',
      bairro: 'Centro',
      cidade: 'Divinópolis',
      uf: 'MG',
    );
  }
}

