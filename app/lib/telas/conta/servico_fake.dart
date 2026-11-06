import 'modelos.dart';

/// Demonstração e testes: guarda na memória, sem rede.
class ServicoContaFake implements ServicoConta {
  ServicoContaFake({
    DadosPessoaisConta? dados,
    List<EnderecoSalvo>? enderecos,
    List<FavoritoConta>? favoritos,
    List<ContatoDeConfianca>? contatos,
    this.falhar = false,
  })  : _dados = dados ??
            const DadosPessoaisConta(
              nome: 'Mariana Alves',
              email: 'mariana@exemplo.com',
              cpfFinal: '09',
            ),
        _enderecos = [...?enderecos],
        _favoritos = [...?favoritos],
        _contatos = [...?contatos];

  DadosPessoaisConta _dados;
  final List<EnderecoSalvo> _enderecos;
  final List<FavoritoConta> _favoritos;
  final List<ContatoDeConfianca> _contatos;
  final bool falhar;
  var _proximo = 1;

  void _checar() {
    if (falhar) throw Exception('falha de teste');
  }

  @override
  Future<DadosPessoaisConta> dados() async {
    _checar();
    return _dados;
  }

  @override
  Future<DadosPessoaisConta> salvarDados({
    String? telefone,
    DateTime? nascimento,
    bool removerTelefone = false,
    bool removerNascimento = false,
  }) async {
    _checar();
    _dados = DadosPessoaisConta(
      nome: _dados.nome,
      email: _dados.email,
      cpfFinal: _dados.cpfFinal,
      telefone: removerTelefone ? null : (telefone ?? _dados.telefone),
      dataNascimento: removerNascimento ? null : (nascimento ?? _dados.dataNascimento),
    );
    return _dados;
  }

  @override
  Future<List<EnderecoSalvo>> enderecos() async {
    _checar();
    return [..._enderecos];
  }

  @override
  Future<EnderecoSalvo> salvarEndereco(EnderecoSalvo e) async {
    _checar();
    final principal = e.principal || _enderecos.isEmpty;
    final salvo = EnderecoSalvo(
      id: e.id.isEmpty ? 'end-${_proximo++}' : e.id,
      apelido: e.apelido,
      cep: e.cep,
      logradouro: e.logradouro,
      numero: e.numero,
      complemento: e.complemento,
      bairro: e.bairro,
      cidade: e.cidade,
      uf: e.uf,
      principal: principal,
    );
    final i = _enderecos.indexWhere((x) => x.id == salvo.id);
    if (i >= 0) {
      _enderecos[i] = salvo;
    } else {
      _enderecos.add(salvo);
    }
    if (principal) {
      for (var k = 0; k < _enderecos.length; k++) {
        final x = _enderecos[k];
        if (x.id != salvo.id && x.principal) {
          _enderecos[k] = EnderecoSalvo(
            id: x.id, apelido: x.apelido, cep: x.cep, logradouro: x.logradouro,
            numero: x.numero, complemento: x.complemento, bairro: x.bairro,
            cidade: x.cidade, uf: x.uf,
          );
        }
      }
    }
    return salvo;
  }

  @override
  Future<void> removerEndereco(String id) async {
    _checar();
    _enderecos.removeWhere((e) => e.id == id);
  }

  @override
  Future<List<FavoritoConta>> favoritos() async {
    _checar();
    return [..._favoritos];
  }

  @override
  Future<void> favoritar(String profissionalId) async {
    _checar();
    if (_favoritos.every((f) => f.profissionalId != profissionalId)) {
      _favoritos.insert(0, FavoritoConta(profissionalId: profissionalId));
    }
  }

  @override
  Future<void> desfavoritar(String profissionalId) async {
    _checar();
    _favoritos.removeWhere((f) => f.profissionalId == profissionalId);
  }

  @override
  Future<List<ContatoDeConfianca>> contatos() async {
    _checar();
    return [..._contatos];
  }

  @override
  Future<ContatoDeConfianca> adicionarContato({
    required String nome,
    required String telefone,
    String? parentesco,
  }) async {
    _checar();
    final c = ContatoDeConfianca(
      id: 'cnt-${_proximo++}',
      nome: nome,
      telefone: telefone,
      parentesco: parentesco,
    );
    _contatos.add(c);
    return c;
  }

  @override
  Future<void> removerContato(String id) async {
    _checar();
    _contatos.removeWhere((c) => c.id == id);
  }
}
