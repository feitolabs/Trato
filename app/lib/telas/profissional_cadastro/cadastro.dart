/// Modelos e serviço do cadastro do profissional (F6.1).
/// PROVISÓRIO: as opções (categorias, raios, dias) vêm do backend; os valores aqui são exemplos.
library;

/// Opções que o backend oferece para montar o formulário.
class OpcoesCadastro {
  const OpcoesCadastro({
    required this.categorias,
    required this.raiosKm,
    required this.dias,
    required this.periodos,
  });

  final List<String> categorias;
  final List<int> raiosKm;
  final List<String> dias;
  final List<String> periodos;

  bool get vazio => categorias.isEmpty;
}

/// O que o profissional preencheu. A tela só coleta; o backend valida e grava.
class DadosCadastroProfissional {
  const DadosCadastroProfissional({
    required this.nome,
    required this.sobre,
    required this.categorias,
    required this.cidade,
    required this.raioKm,
    required this.dias,
    required this.periodos,
    required this.portfolio,
  });

  final String nome;
  final String sobre;
  final Set<String> categorias;
  final String cidade;
  final int raioKm;
  final Set<String> dias;
  final Set<String> periodos;

  /// Referências das fotos de trabalhos anteriores (devolvidas por quem captura a foto).
  final List<String> portfolio;
}

abstract interface class ServicoCadastroProfissional {
  Future<OpcoesCadastro> carregarOpcoes();

  /// Lança exceção se não conseguir salvar; a tela mostra mensagem simples e deixa tentar de novo.
  Future<void> salvar(DadosCadastroProfissional dados);
}

/// PROVISÓRIO — só para teste e demonstração.
class ServicoCadastroProfissionalFake implements ServicoCadastroProfissional {
  ServicoCadastroProfissionalFake({
    this.opcoes = opcoesCadastroExemplo,
    this.falharAoCarregar = false,
    this.falharAoSalvar = false,
  });

  final OpcoesCadastro opcoes;
  final bool falharAoCarregar;
  final bool falharAoSalvar;
  final List<DadosCadastroProfissional> salvos = [];

  @override
  Future<OpcoesCadastro> carregarOpcoes() async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return opcoes;
  }

  @override
  Future<void> salvar(DadosCadastroProfissional dados) async {
    if (falharAoSalvar) throw Exception('falha de teste');
    salvos.add(dados);
  }
}

const opcoesCadastroExemplo = OpcoesCadastro(
  categorias: ['Eletricista', 'Encanador', 'Pintor', 'Diarista', 'Montador de móveis'],
  raiosKm: [5, 10, 20, 30],
  dias: ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'],
  periodos: ['Manhã', 'Tarde', 'Noite'],
);
