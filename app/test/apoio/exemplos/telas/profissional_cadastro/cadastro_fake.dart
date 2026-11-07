import 'package:trato/telas/profissional_cadastro/cadastro.dart';

/// PROVISÓRIO — só para teste e demonstração.
class ServicoCadastroProfissionalFake implements ServicoCadastroProfissional {
  ServicoCadastroProfissionalFake({
    this.opcoes = opcoesCadastroPadrao,
    this.falharAoCarregar = false,
    this.falharAoSalvar = false,
    this.atual,
  });

  final OpcoesCadastro opcoes;
  final bool falharAoCarregar;
  final bool falharAoSalvar;
  final List<DadosCadastroProfissional> salvos = [];

  /// O cadastro já salvo (edição). `null` = primeiro cadastro.
  DadosCadastroProfissional? atual;

  @override
  Future<OpcoesCadastro> carregarOpcoes() async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return opcoes;
  }

  @override
  Future<DadosCadastroProfissional?> carregarAtual() async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return atual;
  }

  @override
  Future<void> salvar(DadosCadastroProfissional dados) async {
    if (falharAoSalvar) throw Exception('falha de teste');
    salvos.add(dados);
    atual = dados;
  }
}
