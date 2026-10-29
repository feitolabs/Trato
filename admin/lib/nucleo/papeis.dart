/// Papéis da equipe (tabela `equipe.papel`, docs/modelo-de-dados.md 3.3) e o que cada um pode fazer.
///
/// Esta matriz só decide o que o painel **mostra**. Quem barra de verdade é o backend (e a RLS):
/// toda chamada admin volta 403 se o papel não tiver a permissão.
enum Papel {
  atendenteN1('atendente_n1', 'Atendente N1'),
  atendenteN2('atendente_n2', 'Atendente N2'),
  liderSuporte('lider_suporte', 'Líder de suporte'),
  mediador('mediador', 'Mediador'),
  cadastro('cadastro', 'Cadastro'),
  moderador('moderador', 'Moderador'),
  financeiro('financeiro', 'Financeiro'),
  seguranca('seguranca', 'Segurança'),
  juridico('juridico', 'Jurídico'),
  dpo('dpo', 'DPO'),
  administrador('administrador', 'Administrador');

  const Papel(this.codigo, this.rotulo);

  final String codigo;
  final String rotulo;

  static Papel? doCodigo(String codigo) {
    for (final p in values) {
      if (p.codigo == codigo) return p;
    }
    return null;
  }

  bool pode(Permissao permissao) => _matriz[this]!.contains(permissao);
}

enum Permissao {
  verificacoesVer,
  verificacoesDecidir,
  documentosRevelar,
  disputasVer,
  disputasDecidir,
  disputasSegundaPessoa,
  pagamentosVer,
  usuariosBuscar,
  dadosPessoaisRevelar,
  pedidosBuscar,
  suporteVer,
  categoriasEditar,
  configVer,
  configPropor,
  configAprovar,
  auditoriaVer,
  auditoriaVerificarCadeia,
}

const _matriz = <Papel, Set<Permissao>>{
  Papel.atendenteN1: {Permissao.usuariosBuscar, Permissao.pedidosBuscar, Permissao.suporteVer},
  Papel.atendenteN2: {
    Permissao.usuariosBuscar,
    Permissao.pedidosBuscar,
    Permissao.suporteVer,
    Permissao.disputasVer,
  },
  Papel.liderSuporte: {
    Permissao.usuariosBuscar,
    Permissao.pedidosBuscar,
    Permissao.suporteVer,
    Permissao.disputasVer,
    Permissao.disputasDecidir,
    Permissao.disputasSegundaPessoa,
  },
  Papel.mediador: {
    Permissao.pedidosBuscar,
    Permissao.disputasVer,
    Permissao.disputasDecidir,
  },
  Papel.cadastro: {
    Permissao.verificacoesVer,
    Permissao.verificacoesDecidir,
    Permissao.documentosRevelar,
    Permissao.usuariosBuscar,
    Permissao.dadosPessoaisRevelar,
  },
  Papel.moderador: {Permissao.usuariosBuscar, Permissao.pedidosBuscar, Permissao.categoriasEditar},
  Papel.financeiro: {
    Permissao.pagamentosVer,
    Permissao.pedidosBuscar,
    Permissao.configVer,
    Permissao.configPropor,
  },
  Papel.seguranca: {
    Permissao.verificacoesVer,
    Permissao.usuariosBuscar,
    Permissao.dadosPessoaisRevelar,
    Permissao.auditoriaVer,
    Permissao.auditoriaVerificarCadeia,
  },
  Papel.juridico: {
    Permissao.configVer,
    Permissao.auditoriaVer,
    Permissao.auditoriaVerificarCadeia,
  },
  Papel.dpo: {
    Permissao.usuariosBuscar,
    Permissao.dadosPessoaisRevelar,
    Permissao.auditoriaVer,
    Permissao.auditoriaVerificarCadeia,
  },
  Papel.administrador: {
    Permissao.verificacoesVer,
    Permissao.disputasVer,
    Permissao.disputasDecidir,
    Permissao.disputasSegundaPessoa,
    Permissao.pagamentosVer,
    Permissao.usuariosBuscar,
    Permissao.pedidosBuscar,
    Permissao.suporteVer,
    Permissao.categoriasEditar,
    Permissao.configVer,
    Permissao.configPropor,
    Permissao.configAprovar,
    Permissao.auditoriaVer,
    Permissao.auditoriaVerificarCadeia,
  },
};
