import '../telas/conta/modelos.dart';
import 'cliente_api.dart';

Map<String, dynamic> _mapa(Object? json) => json! as Map<String, dynamic>;
List<Map<String, dynamic>> _lista(Object? json) =>
    [for (final item in json! as List) item as Map<String, dynamic>];

String _dia(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `/v1/me/dados-pessoais`, `/enderecos`, `/favoritos` e `/contatos-confianca`.
class ServicoContaApi implements ServicoConta {
  ServicoContaApi(this._api);

  final ClienteApi _api;

  static DadosPessoaisConta _dadosDe(Map<String, dynamic> j) {
    final nasc = j['data_nascimento'] as String?;
    return DadosPessoaisConta(
      nome: j['nome'] as String?,
      email: j['email'] as String?,
      cpfFinal: j['cpf_final'] as String?,
      telefone: j['telefone'] as String?,
      dataNascimento: nasc == null ? null : DateTime.tryParse(nasc),
    );
  }

  static EnderecoSalvo _enderecoDe(Map<String, dynamic> j) => EnderecoSalvo(
        id: j['id'] as String,
        apelido: j['apelido'] as String,
        cep: j['cep'] as String,
        logradouro: j['logradouro'] as String,
        numero: j['numero'] as String,
        complemento: j['complemento'] as String?,
        bairro: j['bairro'] as String,
        cidade: j['cidade'] as String,
        uf: j['uf'] as String,
        principal: j['principal'] == true,
      );

  static ContatoDeConfianca _contatoDe(Map<String, dynamic> j) => ContatoDeConfianca(
        id: j['id'] as String,
        nome: j['nome'] as String,
        telefone: j['telefone'] as String,
        parentesco: j['parentesco'] as String?,
      );

  @override
  Future<DadosPessoaisConta> dados() async =>
      _dadosDe(_mapa(await _api.get('/v1/me/dados-pessoais')));

  @override
  Future<DadosPessoaisConta> salvarDados({
    String? telefone,
    DateTime? nascimento,
    bool removerTelefone = false,
    bool removerNascimento = false,
  }) async =>
      _dadosDe(_mapa(await _api.patch('/v1/me/dados-pessoais', corpo: {
        if (telefone != null) 'telefone': telefone,
        if (nascimento != null) 'data_nascimento': _dia(nascimento),
        'remover_telefone': removerTelefone,
        'remover_data_nascimento': removerNascimento,
      })));

  @override
  Future<List<EnderecoSalvo>> enderecos() async =>
      [for (final j in _lista(await _api.get('/v1/me/enderecos'))) _enderecoDe(j)];

  @override
  Future<EnderecoSalvo> salvarEndereco(EnderecoSalvo e) async {
    final corpo = {
      'apelido': e.apelido,
      'cep': e.cep,
      'logradouro': e.logradouro,
      'numero': e.numero,
      'complemento': (e.complemento ?? '').isEmpty ? null : e.complemento,
      'bairro': e.bairro,
      'cidade': e.cidade,
      'uf': e.uf,
      'principal': e.principal,
    };
    final resposta = e.id.isEmpty
        ? await _api.post('/v1/me/enderecos', corpo: corpo)
        : await _api.put('/v1/me/enderecos/${e.id}', corpo: corpo);
    return _enderecoDe(_mapa(resposta));
  }

  @override
  Future<void> removerEndereco(String id) async {
    await _api.delete('/v1/me/enderecos/$id');
  }

  @override
  Future<List<FavoritoConta>> favoritos() async => [
        for (final j in _lista(await _api.get('/v1/me/favoritos')))
          FavoritoConta(
            profissionalId: j['profissional_id'] as String,
            nome: j['nome'] as String?,
            nota: (j['nota_publica'] as num?)?.toDouble(),
            servicos: j['servicos_concluidos'] as int?,
          ),
      ];

  @override
  Future<void> favoritar(String profissionalId) async {
    await _api.put('/v1/me/favoritos/$profissionalId');
  }

  @override
  Future<void> desfavoritar(String profissionalId) async {
    await _api.delete('/v1/me/favoritos/$profissionalId');
  }

  @override
  Future<List<ContatoDeConfianca>> contatos() async =>
      [for (final j in _lista(await _api.get('/v1/me/contatos-confianca'))) _contatoDe(j)];

  @override
  Future<ContatoDeConfianca> adicionarContato({
    required String nome,
    required String telefone,
    String? parentesco,
  }) async =>
      _contatoDe(_mapa(await _api.post('/v1/me/contatos-confianca', corpo: {
        'nome': nome,
        'telefone': telefone,
        if ((parentesco ?? '').isNotEmpty) 'parentesco': parentesco,
      })));

  @override
  Future<void> removerContato(String id) async {
    await _api.delete('/v1/me/contatos-confianca/$id');
  }
}
