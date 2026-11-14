// Dados da conta do cliente: dados pessoais, endereços, favoritos e contatos de confiança.
// O app só pede e mostra; validação e limites são do backend (`/v1/me/...`).

class DadosPessoaisConta {
  const DadosPessoaisConta({
    this.nome,
    this.email,
    this.cpfFinal,
    this.telefone,
    this.dataNascimento,
  });

  final String? nome;
  final String? email;

  /// Só os 2 últimos dígitos: o CPF inteiro nunca chega ao app.
  final String? cpfFinal;

  /// Só dígitos (DDD + número).
  final String? telefone;
  final DateTime? dataNascimento;
}

class EnderecoSalvo {
  const EnderecoSalvo({
    required this.id,
    required this.apelido,
    required this.cep,
    required this.logradouro,
    required this.numero,
    this.complemento,
    required this.bairro,
    required this.cidade,
    required this.uf,
    this.principal = false,
  });

  final String id;
  final String apelido;
  final String cep;
  final String logradouro;
  final String numero;
  final String? complemento;
  final String bairro;
  final String cidade;
  final String uf;
  final bool principal;

  String get linha1 => '$logradouro, $numero${(complemento ?? '').isEmpty ? '' : ' — $complemento'}';
  String get linha2 => '$bairro · $cidade/$uf';
}

class FavoritoConta {
  const FavoritoConta({required this.profissionalId, this.nome, this.nota, this.servicos});

  final String profissionalId;
  final String? nome;
  final double? nota;
  final int? servicos;
}

class ContatoDeConfianca {
  const ContatoDeConfianca({
    required this.id,
    required this.nome,
    required this.telefone,
    this.parentesco,
  });

  final String id;
  final String nome;
  final String telefone;
  final String? parentesco;
}

abstract interface class ServicoConta {
  Future<DadosPessoaisConta> dados();

  /// Telefone só com dígitos; [nascimento] nulo mantém. Use [removerTelefone] / [removerNascimento]
  /// para apagar.
  Future<DadosPessoaisConta> salvarDados({
    String? telefone,
    DateTime? nascimento,
    bool removerTelefone = false,
    bool removerNascimento = false,
  });

  /// Conta criada sem CPF: grava o CPF uma única vez (só dígitos). CPF de outra conta é recusado.
  Future<DadosPessoaisConta> registrarCpf(String cpf);

  Future<List<EnderecoSalvo>> enderecos();

  /// Sem [id], cria; com [id], edita.
  Future<EnderecoSalvo> salvarEndereco(EnderecoSalvo endereco);
  Future<void> removerEndereco(String id);

  Future<List<FavoritoConta>> favoritos();
  Future<void> favoritar(String profissionalId);
  Future<void> desfavoritar(String profissionalId);

  Future<List<ContatoDeConfianca>> contatos();
  Future<ContatoDeConfianca> adicionarContato({
    required String nome,
    required String telefone,
    String? parentesco,
  });
  Future<void> removerContato(String id);
}

/// "(11) 98888-7777" a partir dos dígitos.
String formatarTelefone(String? digitos) {
  final d = (digitos ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 11) return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  if (d.length == 10) return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  return digitos ?? '';
}

String formatarCep(String cep) =>
    cep.length == 8 ? '${cep.substring(0, 5)}-${cep.substring(5)}' : cep;
