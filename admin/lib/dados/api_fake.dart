import '../nucleo/papeis.dart';
import 'api_admin.dart';
import 'modelos.dart';

/// API de exemplo em memória, só até o backend admin existir. Tudo aqui é dado de teste.
///
/// Login: o papel vem do começo do e-mail (`financeiro@teste.local` -> papel `financeiro`) e a senha
/// só precisa ter 8 caracteres ou mais. Não há senha real em lugar nenhum do painel.
class ApiFake implements ApiAdmin {
  ApiFake({this.atraso = Duration.zero, this.erro = false, this.vazio = false, this.cadeiaQuebradaEm});

  final Duration atraso;

  /// Faz as leituras falharem (para ver o estado de erro).
  final bool erro;

  /// Devolve listas vazias (para ver o estado vazio).
  final bool vazio;

  /// Id da primeira linha de auditoria adulterada (simula a cadeia quebrada).
  final int? cadeiaQuebradaEm;

  UsuarioEquipe? _eu;
  final _base = DateTime(2026, 10, 29, 9);
  late final List<EntradaAuditoria> _auditoria = _auditoriaInicial();
  late List<Verificacao> _verificacoes = _verificacoesIniciais();
  late List<Disputa> _disputas = _disputasIniciais();
  late List<CategoriaAdmin> _categorias = _categoriasIniciais();
  late List<ConfigVersao> _versoes = _versoesIniciais();

  Future<T> _ler<T>(T Function() dados, T vazioValor) async {
    await Future<void>.delayed(atraso);
    if (erro) throw const ErroApi('Não foi possível falar com o servidor.');
    return vazio ? vazioValor : dados();
  }

  int? _ultimoRegistro;

  @override
  int? get ultimoRegistroAuditoria => _ultimoRegistro;

  void _registrar(String acao, String entidade, String? motivo, {Map<String, dynamic> detalhes = const {}}) {
    final id = _auditoria.length + 1;
    _ultimoRegistro = id;
    _auditoria.add(EntradaAuditoria(
      id: id,
      ocorridaEm: _base.add(Duration(minutes: 30 + id)),
      ator: _eu?.email ?? 'sistema',
      atorNome: _eu?.nome,
      acao: acao,
      entidade: entidade,
      motivo: motivo,
      detalhes: detalhes,
      hash: 'a${(id * 7919).toRadixString(16).padLeft(7, '0')}',
    ));
  }

  @override
  Future<UsuarioEquipe> entrar(String email, String senha) async {
    await Future<void>.delayed(atraso);
    final nome = email.trim().toLowerCase();
    if (!nome.contains('@') || senha.length < 8) {
      throw const ErroApi('E-mail ou senha incorretos.');
    }
    final Papel? papel;
    final String rotuloUsuario;
    if (nome == 'cardosojoaovitor47@gmail.com' || nome == 'cardosojoavitor47@gmail.com') {
      papel = Papel.administrador;
      rotuloUsuario = 'João Vitor Cardoso';
    } else if (nome == 'emanoel.cabral@trato.feitolabs.com.br') {
      papel = Papel.administrador;
      rotuloUsuario = 'Emanoel Cabral';
    } else if (nome == 'gabriel.victor@trato.feitolabs.com.br') {
      papel = Papel.administrador;
      rotuloUsuario = 'Gabriel Victor';
    } else {
      papel = Papel.doCodigo(nome.split('@').first);
      rotuloUsuario = papel?.rotulo ?? '';
    }
    if (papel == null) {
      throw const ErroApi('Esta conta não tem papel na equipe.', proibido: true);
    }
    _eu = UsuarioEquipe(
      id: 'eq-${papel.codigo}',
      nome: rotuloUsuario,
      email: nome,
      papel: papel,
      alcadaCentavos: switch (papel) {
        Papel.administrador => 1000000,
        Papel.liderSuporte => 200000,
        Papel.mediador => 50000,
        _ => 0,
      },
    );
    _registrar('equipe.login', 'equipe', null);
    return _eu!;
  }

  @override
  Future<void> sair() async {
    _registrar('equipe.logout', 'equipe', null);
    _eu = null;
  }

  // ---------- F7.1 ----------
  @override
  Future<List<Verificacao>> listarVerificacoes() => _ler(() => _verificacoes, const []);

  @override
  Future<String?> revelarDocumento(String verificacaoId, String documento, String motivo) async {
    await Future<void>.delayed(atraso);
    _registrar('dado_pessoal.documento_revelado', 'verificacao:$verificacaoId', motivo);
    return null;
  }

  @override
  Future<void> decidirVerificacao(String id, {required bool aprovar, required String motivo}) async {
    await Future<void>.delayed(atraso);
    _verificacoes = [
      for (final v in _verificacoes)
        if (v.id == id)
          v.comStatus(aprovar ? StatusVerificacao.aprovada : StatusVerificacao.recusada, motivo)
        else
          v,
    ];
    _registrar(aprovar ? 'verificacao.aprovada' : 'verificacao.recusada', 'verificacao:$id', motivo);
  }

  // ---------- F7.2 ----------
  @override
  Future<List<Disputa>> listarDisputas() => _ler(() => _disputas, const []);

  @override
  Future<ResultadoDecisao> decidirDisputa(
    String id, {
    required DecisaoDisputa decisao,
    int? valorReembolsoCentavos,
    required String justificativa,
  }) async {
    await Future<void>.delayed(atraso);
    final d = _disputas.firstWhere((x) => x.id == id);
    final valor = switch (decisao) {
      DecisaoDisputa.reembolsoTotal => d.valorEmAnaliseCentavos,
      DecisaoDisputa.reembolsoParcial => valorReembolsoCentavos,
      _ => null,
    };
    final acima = (valor ?? 0) > (_eu?.alcadaCentavos ?? 0);
    final novo = acima ? StatusDisputa.aguardandoSegundaPessoa : StatusDisputa.decidida;
    _disputas = [for (final x in _disputas) x.id == id ? x.comDecisao(novo, decisao, valor, por: _eu?.id) : x];
    _registrar('disputa.decidida', 'disputa:$id', justificativa);
    return ResultadoDecisao(
      status: novo,
      mensagem: acima ? 'Acima da alçada: aguarda a aprovação de outra pessoa.' : 'Decisão registrada.',
    );
  }

  @override
  Future<ResultadoDecisao> aprovarDisputa(String id, {required String justificativa}) async {
    await Future<void>.delayed(atraso);
    final d = _disputas.firstWhere((x) => x.id == id);
    if (d.decididoPor == _eu?.id) {
      throw const ErroApi('Quem decidiu não aprova a própria decisão.', proibido: true);
    }
    _disputas = [
      for (final x in _disputas) x.id == id ? x.comDecisao(StatusDisputa.decidida, x.decisao!, x.valorReembolsoCentavos) : x,
    ];
    _registrar('financeiro.disputa_decidida', 'disputa:$id', justificativa);
    return const ResultadoDecisao(status: StatusDisputa.decidida, mensagem: 'Decisão aprovada.');
  }

  // ---------- F7.3 ----------
  final _conciliados = <String>{};

  @override
  Future<ResumoConciliacao> resumoConciliacao({int? dias}) => _ler(
        () => ResumoConciliacao(
          confirmadoCentavos: 1284500,
          estornadoCentavos: 12000,
          emAndamentoCentavos: 96000,
          divergencias: _conciliados.contains('l-4') ? 0 : 1,
          atualizadoEm: _base,
          cobrancas: 412,
          reembolsos: 9,
          valorDivergenteCentavos: _conciliados.contains('l-4') ? 0 : 15000,
        ),
        ResumoConciliacao(
          confirmadoCentavos: 0,
          estornadoCentavos: 0,
          emAndamentoCentavos: 0,
          divergencias: 0,
          atualizadoEm: _base,
        ),
      );

  @override
  Future<void> conciliarDivergencia(String lancamentoId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _conciliados.add(lancamentoId);
    _registrar('pagamento.divergencia_conciliada', 'lancamento:$lancamentoId', motivo);
  }

  @override
  Future<List<LancamentoEspelho>> extrato({int? dias}) => _ler(
        () => [
          LancamentoEspelho(
            id: 'l-1',
            data: _base,
            descricao: 'Sinal do orçamento',
            valorCentavos: 36000,
            status: StatusProvedor.confirmado,
            pedido: 'PED-10490',
            refProvedor: 'pay_8f21...c3a',
            taxaCentavos: 2700,
            liquidoCentavos: 33300,
          ),
          LancamentoEspelho(
            id: 'l-2',
            data: _base.subtract(const Duration(hours: 5)),
            descricao: 'Pagamento final',
            valorCentavos: 84000,
            status: StatusProvedor.aguardandoConfirmacao,
            pedido: 'PED-10482',
            refProvedor: 'pay_3e9f...b77',
          ),
          LancamentoEspelho(
            id: 'l-3',
            data: _base.subtract(const Duration(days: 1)),
            descricao: 'Reembolso decidido em disputa',
            valorCentavos: -12000,
            status: StatusProvedor.reembolsado,
            pedido: 'PED-10455',
            refProvedor: 'rf_19bd...a40',
            tipo: 'Reembolso',
          ),
          LancamentoEspelho(
            id: 'l-4',
            data: _base.subtract(const Duration(days: 2)),
            descricao: 'Pagamento recusado pelo cartão',
            valorCentavos: 15000,
            status: StatusProvedor.falhou,
            pedido: 'PED-10471',
            refProvedor: 'pay_77c0...d12',
            divergente: !_conciliados.contains('l-4'),
            conciliado: _conciliados.contains('l-4'),
          ),
        ],
        const [],
      );

  // ---------- F7.4 ----------
  List<UsuarioBusca> get _usuarios => [
        const UsuarioBusca(
          id: 'u-1',
          nome: 'Marina Souza',
          tipo: 'Cliente',
          status: 'ativo',
          idPublico: 'CLI-1042',
          cidade: 'Belo Horizonte',
          emailMascarado: 'm•••••@exemplo.com',
          telefoneMascarado: '(31) •••••-1190',
        ),
        UsuarioBusca(
          id: 'u-2',
          nome: 'Carlos Pereira',
          tipo: 'Profissional',
          status: 'ativo',
          idPublico: 'PRO-2281',
          cidade: 'Belo Horizonte',
          emailMascarado: 'c•••••@exemplo.com',
          telefoneMascarado: '(31) •••••-4821',
          categorias: const [
            CategoriaProfissional(nome: 'Pintor', ativaNoPerfil: true, ativaNaPlataforma: true),
            CategoriaProfissional(nome: 'Eletricista', ativaNoPerfil: false, ativaNaPlataforma: true),
          ],
          historico: [
            EventoUsuario(_base.subtract(const Duration(days: 4)), 'Categoria Eletricista desativada pelo profissional'),
            EventoUsuario(_base.subtract(const Duration(days: 5)), 'Pedido PED-10482 concluído'),
            EventoUsuario(_base.subtract(const Duration(days: 14)), 'Verificação aprovada por Emanuel Cabral'),
          ],
        ),
        const UsuarioBusca(
          id: 'u-3',
          nome: 'Paulo Lima',
          tipo: 'Profissional',
          status: 'restrito',
          idPublico: 'PRO-3307',
          cidade: 'Contagem',
          emailMascarado: 'p•••••@exemplo.com',
          telefoneMascarado: '(31) •••••-7734',
        ),
      ];

  @override
  Future<List<UsuarioBusca>> buscarUsuarios(String termo) => _ler(() {
        final t = termo.trim().toLowerCase();
        return [
          for (final u in _usuarios)
            if (t.isEmpty ||
                u.nome.toLowerCase().contains(t) ||
                u.idPublico.toLowerCase().contains(t) ||
                (u.emailMascarado ?? '').toLowerCase().contains(t))
              u,
        ];
      }, const []);

  @override
  Future<UsuarioBusca> detalheUsuario(String usuarioId) async {
    await Future<void>.delayed(atraso);
    return _usuarios.firstWhere((u) => u.id == usuarioId);
  }

  @override
  Future<DiagnosticoPedido> diagnosticarPedido(String usuarioId, String pedido) async {
    await Future<void>.delayed(atraso);
    if (pedido.trim().isEmpty) throw const ErroApi('Pedido não encontrado.');
    return const DiagnosticoPedido(
      pedido: 'PED-10482',
      titulo: 'Troca de fiação do quarto',
      categoria: 'Eletricista',
      aparece: false,
      itens: [
        ItemDiagnostico(
          ok: false,
          titulo: 'Não tem a categoria ativa.',
          detalhe: 'O pedido é de Eletricista, e essa categoria está inativa no perfil dele.',
        ),
        ItemDiagnostico(
          ok: true,
          titulo: 'Categoria ativa na plataforma.',
          detalhe: 'Eletricista não foi desativada em Categorias.',
        ),
        ItemDiagnostico(ok: true, titulo: 'Profissional verificado.', detalhe: 'Aprovado em 20/10/2026.'),
        ItemDiagnostico(ok: true, titulo: 'Sem bloqueio na conta.', detalhe: 'Nenhum bloqueio preventivo ativo.'),
      ],
    );
  }

  @override
  Future<DadosPessoais> revelarDadosPessoais(String usuarioId, String motivo) async {
    await Future<void>.delayed(atraso);
    _registrar('dado_pessoal.revelado', 'usuario:$usuarioId', motivo);
    return const DadosPessoais(email: 'pessoa@exemplo.com', cpf: '000.000.000-00', telefone: '(31) 90000-0000');
  }

  @override
  Future<List<PedidoBusca>> buscarPedidos(String termo) => _ler(() {
        const todos = [
          PedidoBusca(
            id: 'p-1',
            codigo: 'PED-10482',
            titulo: 'Troca de chuveiro',
            cliente: 'Marina Souza',
            profissional: 'Carlos Pereira',
            categoria: 'Eletricista',
            cidade: 'Belo Horizonte',
            status: 'Em andamento',
            valorCentavos: 120000,
          ),
          PedidoBusca(
            id: 'p-2',
            codigo: 'PED-10455',
            titulo: 'Pintura de sala',
            cliente: 'Marina Souza',
            profissional: 'Paulo Lima',
            categoria: 'Pintor',
            cidade: 'Belo Horizonte',
            status: 'Em disputa',
            valorCentavos: 240000,
          ),
        ];
        final t = termo.trim().toLowerCase();
        return [
          for (final p in todos)
            if (t.isEmpty || p.codigo.toLowerCase().contains(t) || p.titulo.toLowerCase().contains(t)) p,
        ];
      }, const []);

  @override
  Future<List<Chamado>> listarChamados() => _ler(
        () => [
          Chamado(
            id: 'CH-31',
            assunto: 'Não recebi o código de confirmação',
            solicitante: 'Paulo Lima',
            status: 'aberto',
            aberto: _base.subtract(const Duration(hours: 3)),
            prioridade: 'alta',
            prazo: _base.add(const Duration(hours: 5)),
          ),
          Chamado(
            id: 'CH-30',
            assunto: 'Dúvida sobre o orçamento',
            solicitante: 'Marina Souza',
            status: 'em atendimento',
            aberto: _base.subtract(const Duration(days: 1)),
            responsavel: 'Bruna Teixeira',
            prazo: _base.add(const Duration(hours: 20)),
          ),
        ],
        const [],
      );

  @override
  Future<List<CategoriaAdmin>> listarCategorias() => _ler(() => _categorias, const []);

  @override
  Future<void> alterarStatusUsuario(String usuarioId, {required String status, required String motivo}) async {
    await Future<void>.delayed(atraso);
    _registrar('usuario.status_alterado', 'usuario:$usuarioId', motivo);
  }

  @override
  Future<void> alterarCategoria(String id, {required bool ativa, required String motivo}) async {
    await Future<void>.delayed(atraso);
    _categorias = [for (final c in _categorias) c.id == id ? c.comAtiva(ativa) : c];
    _registrar(ativa ? 'categoria.ativada' : 'categoria.desativada', 'categoria:$id', motivo);
  }

  @override
  Future<CategoriaAdmin> criarCategoria({
    required String nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int ordem = 0,
    bool ativa = true,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    final cat = CategoriaAdmin(
      id: 'c-${_categorias.length + 1}',
      nome: nome,
      slug: slug ?? nome.toLowerCase(),
      icone: icone,
      garantiaDias: garantiaDias,
      ordem: ordem,
      ativa: ativa,
      profissionais: 0,
    );
    _categorias = [..._categorias, cat];
    _registrar('categoria.criada', 'categoria:${cat.id}', motivo);
    return cat;
  }

  @override
  Future<CategoriaAdmin> editarCategoria(
    String id, {
    String? nome,
    String? slug,
    String? icone,
    int? garantiaDias,
    int? ordem,
    bool? ativa,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    CategoriaAdmin? atualizada;
    _categorias = [
      for (final c in _categorias)
        if (c.id == id)
          atualizada = CategoriaAdmin(
            id: c.id,
            nome: nome ?? c.nome,
            slug: slug ?? c.slug,
            icone: icone ?? c.icone,
            garantiaDias: garantiaDias ?? c.garantiaDias,
            ordem: ordem ?? c.ordem,
            ativa: ativa ?? c.ativa,
            profissionais: c.profissionais,
          )
        else
          c,
    ];
    _registrar('categoria.editada', 'categoria:$id', motivo);
    return atualizada ?? _categorias.first;
  }

  @override
  Future<void> excluirCategoria(String id, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _categorias = [for (final c in _categorias) if (c.id != id) c];
    _registrar('categoria.excluida', 'categoria:$id', motivo);
  }

  late List<CidadeAdmin> _cidades = [
    const CidadeAdmin(id: 'cid-1', nome: 'Belo Horizonte', uf: 'MG', ativa: true),
    const CidadeAdmin(id: 'cid-2', nome: 'Divinópolis', uf: 'MG', ativa: true),
  ];

  @override
  Future<List<CidadeAdmin>> listarCidades() => _ler(() => _cidades, const []);

  @override
  Future<CidadeAdmin> criarCidade({
    required String nome,
    required String uf,
    bool ativa = true,
    double? centroLat,
    double? centroLng,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    final cid = CidadeAdmin(
      id: 'cid-${_cidades.length + 1}',
      nome: nome,
      uf: uf,
      ativa: ativa,
      centroLat: centroLat,
      centroLng: centroLng,
    );
    _cidades = [..._cidades, cid];
    _registrar('cidade.criada', 'cidade:${cid.id}', motivo);
    return cid;
  }

  @override
  Future<void> alterarCidade(String id, {required bool ativa, required String motivo}) async {
    await Future<void>.delayed(atraso);
    _cidades = [
      for (final c in _cidades)
        if (c.id == id)
          CidadeAdmin(
            id: c.id,
            nome: c.nome,
            uf: c.uf,
            ativa: ativa,
            centroLat: c.centroLat,
            centroLng: c.centroLng,
          )
        else
          c,
    ];
    _registrar(ativa ? 'cidade.ativada' : 'cidade.desativada', 'cidade:$id', motivo);
  }

  // ---------- F7.5 ----------
  static ConfigDefinicao _def(
    String chave,
    String descricao,
    UnidadeConfig unidade,
    int minimo,
    int maximo, {
    bool dupla = false,
  }) =>
      ConfigDefinicao(
        chave: chave,
        descricao: descricao,
        unidade: unidade,
        minimo: minimo,
        maximo: maximo,
        exigeDuplaAprovacao: dupla,
      );

  static final _definicoes = [
    _def('taxa_bps', 'Taxa do Trato por serviço', UnidadeConfig.bps, 0, 2000, dupla: true),
    _def('taxa_minima_centavos', 'Taxa mínima por pedido', UnidadeConfig.centavos, 0, 5000, dupla: true),
    _def('taxa_progressiva_ativa', 'Tabela progressiva de taxa', UnidadeConfig.quantidade, 0, 1, dupla: true),
    _def('adiantamento_bps', 'Adiantamento ao iniciar o serviço', UnidadeConfig.bps, 0, 10000),
    _def('prazo_liberacao_dias', 'Prazo para liberar o repasse ao profissional', UnidadeConfig.dias, 0, 30, dupla: true),
    _def('janela_chargeback_dias', 'Janela de reclamação do cliente', UnidadeConfig.dias, 1, 30, dupla: true),
    _def('prazo_confirmacao_cliente_horas', 'Prazo para o cliente confirmar o serviço', UnidadeConfig.horas, 1, 720),
    _def('prazo_pagamento_pendente_horas', 'Prazo do pagamento pendente', UnidadeConfig.horas, 1, 72),
    _def('garantia_retrabalho_dias_padrao', 'Garantia de retrabalho (padrão)', UnidadeConfig.dias, 0, 365),
    _def('prazo_retrabalho_atendimento_dias', 'Prazo para atender o retrabalho', UnidadeConfig.dias, 1, 60),
    _def('prazo_resposta_disputa_horas', 'Prazo de resposta da disputa', UnidadeConfig.horas, 1, 720),
    _def('prazo_congelar_disputa_horas', 'Prazo para congelar o repasse na disputa', UnidadeConfig.horas, 1, 720),
    _def('prazo_decisao_disputa_dias_uteis', 'Prazo de decisão da disputa', UnidadeConfig.diasUteis, 1, 30),
    _def('limite_orcamentos_por_pedido', 'Máximo de orçamentos por pedido', UnidadeConfig.quantidade, 1, 20),
    _def('validade_pedido_horas', 'Validade do pedido aberto', UnidadeConfig.horas, 1, 720),
    _def('tolerancia_comparecimento_horas', 'Tolerância de comparecimento', UnidadeConfig.horas, 0, 24),
    _def('valor_minimo_servico_centavos', 'Valor mínimo do pedido', UnidadeConfig.centavos, 1000, 100000),
    _def('valor_maximo_servico_centavos', 'Teto de valor do pedido', UnidadeConfig.centavos, 10000, 1000000, dupla: true),
    _def('limite_valor_atipico_centavos', 'Limite de valor atípico', UnidadeConfig.centavos, 10000, 1000000, dupla: true),
  ];

  List<ConfigVersao> _versoesIniciais() {
    const vigente = {
      'taxa_bps': 750,
      'taxa_minima_centavos': 300,
      'taxa_progressiva_ativa': 0,
      'adiantamento_bps': 0,
      'prazo_liberacao_dias': 0,
      'janela_chargeback_dias': 7,
      'prazo_confirmacao_cliente_horas': 48,
      'prazo_pagamento_pendente_horas': 2,
      'garantia_retrabalho_dias_padrao': 30,
      'prazo_retrabalho_atendimento_dias': 7,
      'prazo_resposta_disputa_horas': 48,
      'prazo_congelar_disputa_horas': 72,
      'prazo_decisao_disputa_dias_uteis': 5,
      'limite_orcamentos_por_pedido': 5,
      'validade_pedido_horas': 48,
      'tolerancia_comparecimento_horas': 1,
      'valor_minimo_servico_centavos': 3000,
      'valor_maximo_servico_centavos': 100000,
      'limite_valor_atipico_centavos': 100000,
    };
    return [
      ConfigVersao(
        id: 'v3',
        numero: 3,
        status: StatusVersao.aguardandoAprovacao,
        motivo: 'volume alto de feriado',
        criadaPor: 'eq-financeiro',
        criadaPorNome: 'João Vitor Cardoso',
        criadaEm: _base.subtract(const Duration(hours: 2)),
        valores: {...vigente, 'prazo_resposta_disputa_horas': 72},
      ),
      ConfigVersao(
        id: 'v2',
        numero: 2,
        status: StatusVersao.vigente,
        motivo: 'Valores do piloto',
        criadaPor: 'eq-financeiro',
        criadaPorNome: 'Emanuel Cabral',
        aprovadaPor: 'eq-administrador',
        aprovadaPorNome: 'João Vitor Cardoso',
        criadaEm: _base.subtract(const Duration(days: 3)),
        valores: vigente,
      ),
      ConfigVersao(
        id: 'v1',
        numero: 1,
        status: StatusVersao.substituida,
        motivo: 'Valores iniciais',
        criadaPor: 'eq-financeiro',
        criadaPorNome: 'João Vitor Cardoso',
        aprovadaPor: 'eq-administrador',
        aprovadaPorNome: 'Emanuel Cabral',
        criadaEm: _base.subtract(const Duration(days: 20)),
        valores: {...vigente, 'taxa_bps': 800, 'valor_minimo_servico_centavos': 2000},
      ),
    ];
  }

  @override
  Future<ConfigAtual> carregarConfig() => _ler(
        () => ConfigAtual(definicoes: _definicoes, versoes: _versoes),
        const ConfigAtual(definicoes: [], versoes: []),
      );

  void _exigirFaixa(Map<String, int> valores) {
    for (final d in _definicoes) {
      final v = valores[d.chave];
      if (v == null) continue;
      if (v < d.minimo || v > d.maximo) {
        throw ErroApi('${d.descricao}: o valor precisa ficar entre ${d.minimo} e ${d.maximo}.');
      }
    }
  }

  @override
  Future<void> proporConfig(Map<String, int> valores, String motivo) async {
    await Future<void>.delayed(atraso);
    _exigirFaixa(valores);
    final vigente = _versoes.firstWhere((v) => v.status == StatusVersao.vigente);
    final numero = _versoes.first.numero + 1;
    _versoes = [
      ConfigVersao(
        id: 'v$numero',
        numero: numero,
        status: StatusVersao.aguardandoAprovacao,
        motivo: motivo,
        criadaPor: _eu?.id ?? '',
        criadaPorNome: _eu?.nome,
        criadaEm: _base.add(Duration(hours: numero)),
        valores: {...vigente.valores, ...valores},
      ),
      ..._versoes,
    ];
    _registrar('config.proposta', 'config:v$numero', motivo);
  }

  @override
  Future<void> aprovarConfig(String versaoId, String motivo) async {
    await Future<void>.delayed(atraso);
    final alvo = _versoes.firstWhere((v) => v.id == versaoId);
    if (alvo.criadaPor == _eu?.id) {
      throw const ErroApi('Quem propôs a mudança não pode aprová-la. Peça a outra pessoa.');
    }
    _versoes = [
      for (final v in _versoes)
        if (v.id == versaoId)
          v.comStatus(StatusVersao.vigente, aprovadaPor: _eu?.id, aprovadaPorNome: _eu?.nome)
        else if (v.status == StatusVersao.vigente)
          v.comStatus(StatusVersao.substituida)
        else
          v,
    ];
    _registrar('config.publicada', 'config:$versaoId', motivo);
  }

  @override
  Future<void> publicarConfig(String versaoId, String motivo) => aprovarConfig(versaoId, motivo);

  @override
  Future<void> recusarConfig(String versaoId, String motivo) async {
    await Future<void>.delayed(atraso);
    _versoes = [for (final v in _versoes) if (v.id != versaoId) v];
    _registrar('config.rascunho_descartado', 'config_versoes:$versaoId', motivo);
  }

  @override
  Future<void> reverterConfig(String versaoId, String motivo) async {
    await Future<void>.delayed(atraso);
    final antiga = _versoes.firstWhere((v) => v.id == versaoId);
    await proporConfig(antiga.valores, 'Reversão para a versão ${antiga.numero}: $motivo');
    _registrar('config.reversao_pedida', 'config:$versaoId', motivo);
  }

  // ---------- F7.6 ----------
  @override
  Future<PaginaAuditoria> listarAuditoria({
    String? acao,
    String? ator,
    String? entidade,
    DateTime? desde,
    DateTime? ate,
    int limite = 25,
    int deslocamento = 0,
  }) =>
      _ler(() {
        final a = acao?.trim().toLowerCase() ?? '';
        final p = ator?.trim().toLowerCase() ?? '';
        final todos = [
          for (final e in _auditoria.reversed)
            if ((a.isEmpty || e.acao.toLowerCase().contains(a)) &&
                (p.isEmpty || e.ator.toLowerCase().contains(p) || (e.atorNome ?? '').toLowerCase().contains(p)) &&
                (entidade == null || e.entidade.startsWith(entidade)))
              e,
        ];
        final fim = (deslocamento + limite).clamp(0, todos.length);
        return PaginaAuditoria(itens: todos.sublist(deslocamento.clamp(0, todos.length), fim), total: todos.length);
      }, const PaginaAuditoria(itens: [], total: 0));

  @override
  Future<ResultadoCadeia> verificarCadeia() async {
    await Future<void>.delayed(atraso);
    if (erro) throw const ErroApi('Não foi possível falar com o servidor.');
    _registrar('auditoria.cadeia_verificada', 'auditoria', null);
    final quebra = cadeiaQuebradaEm;
    return ResultadoCadeia(ok: quebra == null, verificadas: _auditoria.length, primeiraQuebraId: quebra);
  }

  // ---------- dados iniciais ----------
  List<EntradaAuditoria> _auditoriaInicial() => [
        EntradaAuditoria(
          id: 1,
          ocorridaEm: _base.subtract(const Duration(days: 1)),
          ator: 'eq-administrador',
          atorNome: 'Emanuel Cabral',
          acao: 'config.publicada',
          entidade: 'config_versoes:v2',
          entidadeNome: 'Versão 2',
          motivo: 'Valores do piloto',
          hash: 'a0001f3',
        ),
        EntradaAuditoria(
          id: 2,
          ocorridaEm: _base.subtract(const Duration(hours: 20)),
          ator: 'mediador@teste.local',
          atorNome: 'Mediador',
          acao: 'financeiro.disputa_decidida',
          entidade: 'pedidos:d-0',
          entidadeNome: 'PED-10455 · Pintura de sala',
          motivo: 'Cliente não comprovou o problema',
          hash: 'a0002b9',
        ),
      ];

  List<Verificacao> _verificacoesIniciais() => [
        Verificacao(
          id: 'ver-1',
          profissionalId: 'pro-1',
          profissional: 'Carlos Pereira',
          idPublico: 'PRO-2281',
          nivel: 'Verificado',
          categorias: const ['Eletricista', 'Pintor'],
          cidade: 'Belo Horizonte',
          enviadaEm: _base.subtract(const Duration(hours: 6)),
          cpfMascarado: '***.***.***-45',
          documentos: const ['Frente do documento', 'Verso do documento', 'Selfie'],
          enviosAnteriores: [
            EnvioVerificacao(
              enviadoEm: _base.subtract(const Duration(days: 9)),
              aprovado: false,
              motivo: 'Selfie não confere',
            ),
          ],
        ),
        Verificacao(
          id: 'ver-2',
          profissionalId: 'pro-2',
          profissional: 'Ana Ribeiro',
          idPublico: 'PRO-3307',
          nivel: 'Verificado',
          categorias: const ['Pintor'],
          cidade: 'Belo Horizonte',
          enviadaEm: _base.subtract(const Duration(days: 1)),
          documentos: const ['Frente do documento', 'Selfie'],
          status: StatusVerificacao.emAnalise,
        ),
        Verificacao(
          id: 'ver-3',
          profissionalId: 'pro-3',
          profissional: 'José Roberto Alves',
          idPublico: 'PRO-4410',
          nivel: 'Verificado',
          categorias: const ['Encanador'],
          cidade: 'Contagem',
          enviadaEm: _base.subtract(const Duration(days: 3)),
          cpfMascarado: '***.***.***-77',
          documentos: const ['Frente do documento', 'Verso do documento', 'Selfie'],
          status: StatusVerificacao.aprovada,
        ),
      ];

  List<Disputa> _disputasIniciais() => [
        Disputa(
          id: 'd-1',
          pedido: 'PED-10482',
          titulo: 'Pintura de sala e cozinha',
          respostaAte: _base.add(const Duration(hours: 20)),
          cliente: 'Marina Souza',
          profissional: 'Carlos Pereira',
          motivo: 'Serviço mal feito',
          descricao: 'A pintura ficou com manchas na parede da sala.',
          valorEmAnaliseCentavos: 240000,
          decisaoAte: _base.add(const Duration(days: 3)),
          evidencias: const [
            EvidenciaDisputa(autor: 'Marina Souza', tipo: 'relato', texto: 'Manchas visíveis com luz natural.'),
            EvidenciaDisputa(autor: 'Marina Souza', tipo: 'foto', texto: '3 fotos da parede (enviadas 28/10)'),
            EvidenciaDisputa(
              autor: 'Carlos Pereira',
              tipo: 'resposta',
              texto: 'A parede tinha umidade; avisei antes de começar.',
            ),
            EvidenciaDisputa(
              autor: 'Mediador',
              tipo: 'nota_interna',
              texto: 'Conferir se o aviso de umidade consta no chat.',
              nota: true,
            ),
          ],
          linhaDoTempo: [
            EventoDisputa(_base.subtract(const Duration(days: 5)), 'Sistema', 'Orçamento aceito e sinal confirmado'),
            EventoDisputa(_base.subtract(const Duration(days: 3)), 'Carlos Pereira', 'Serviço marcado como concluído'),
            EventoDisputa(_base.subtract(const Duration(days: 2)), 'Marina Souza', 'Problema relatado'),
            EventoDisputa(_base.subtract(const Duration(days: 1)), 'Carlos Pereira', 'Resposta enviada'),
          ],
        ),
        Disputa(
          id: 'd-2',
          pedido: 'PED-10471',
          titulo: 'Limpeza pós-obra',
          respostaAte: _base.add(const Duration(hours: 31)),
          cliente: 'Paulo Lima',
          profissional: 'Ana Ribeiro',
          motivo: 'Não compareceu',
          descricao: 'O profissional não apareceu no horário combinado.',
          valorEmAnaliseCentavos: 18000,
          decisaoAte: _base.add(const Duration(days: 5)),
          status: StatusDisputa.aguardandoProfissional,
          evidencias: const [
            EvidenciaDisputa(autor: 'Paulo Lima', tipo: 'relato', texto: 'Esperei das 9h às 11h.'),
          ],
          linhaDoTempo: [
            EventoDisputa(_base.subtract(const Duration(hours: 30)), 'Paulo Lima', 'Problema relatado'),
          ],
        ),
      ];

  List<CategoriaAdmin> _categoriasIniciais() => const [
        CategoriaAdmin(id: 'c-1', nome: 'Elétrica', ativa: true, profissionais: 14),
        CategoriaAdmin(id: 'c-2', nome: 'Pintura', ativa: true, profissionais: 22),
        CategoriaAdmin(id: 'c-3', nome: 'Jardinagem', ativa: false, profissionais: 3),
      ];

  // ===========================================================================
  // MÓDULOS 1 A 7 NA API FAKE
  // ===========================================================================

  @override
  Future<MetricasDashboard> metricasDashboard({int dias = 30, DateTime? inicio, DateTime? fim}) => _ler(
        () => const MetricasDashboard(
          gmvCentavos: 12540000,
          receitaTaxaCentavos: 1504800,
          pedidosTotal: 142,
          pedidosConcluidos: 98,
          pedidosEmAndamento: 24,
          pedidosAbertos: 16,
          pedidosDisputa: 4,
          clientesTotal: 340,
          profissionaisTotal: 85,
          profissionaisPendentes: 3,
          cidadesAtivas: 2,
          categoriasAtivas: 12,
          gmvAnteriorCentavos: 11160000,
          receitaTaxaAnteriorCentavos: 1370000,
          pedidosAtivos: 214,
          pedidosAtivosAnterior: 221,
          baseUsuarios: 3902,
          baseUsuariosAnterior: 3695,
          disputasAbertas: 2,
          alertasRiscoAbertos: 2,
        ),
        const MetricasDashboard(
          gmvCentavos: 0,
          receitaTaxaCentavos: 0,
          pedidosTotal: 0,
          pedidosConcluidos: 0,
          pedidosEmAndamento: 0,
          pedidosAbertos: 0,
          pedidosDisputa: 0,
          clientesTotal: 0,
          profissionaisTotal: 0,
          profissionaisPendentes: 0,
          cidadesAtivas: 0,
          categoriasAtivas: 0,
        ),
      );

  @override
  Future<SeriesDashboard> seriesDashboard({int dias = 30, DateTime? inicio, DateTime? fim}) => _ler(
        () => const SeriesDashboard(
          historicoDias: [
            PontoSerieDashboard(data: '2026-10-27', pedidos: 8, gmvCentavos: 96000),
            PontoSerieDashboard(data: '2026-10-28', pedidos: 12, gmvCentavos: 144000),
            PontoSerieDashboard(data: '2026-10-29', pedidos: 15, gmvCentavos: 210000),
            PontoSerieDashboard(data: '2026-10-30', pedidos: 11, gmvCentavos: 135000),
            PontoSerieDashboard(data: '2026-10-31', pedidos: 19, gmvCentavos: 280000),
            PontoSerieDashboard(data: '2026-11-01', pedidos: 22, gmvCentavos: 310000),
            PontoSerieDashboard(data: '2026-11-02', pedidos: 14, gmvCentavos: 185000),
          ],
          funil: [
            EtapaFunilDashboard(etapa: 'Pedidos criados', quantidade: 142, taxaConversaoPct: 100.0),
            EtapaFunilDashboard(etapa: 'Propostas recebidas', quantidade: 128, taxaConversaoPct: 90.1),
            EtapaFunilDashboard(etapa: 'Pedidos fechados', quantidade: 105, taxaConversaoPct: 73.9),
            EtapaFunilDashboard(etapa: 'Serviços concluídos', quantidade: 98, taxaConversaoPct: 69.0),
          ],
        ),
        const SeriesDashboard(historicoDias: [], funil: []),
      );

  final List<PerguntaCategoriaAdmin> _perguntas = [
    const PerguntaCategoriaAdmin(
      id: 'p-1',
      categoriaId: 'c-1',
      texto: 'Qual a voltagem do local?',
      tipo: 'escolha_unica',
      opcoes: ['110V', '220V', 'Bivolt'],
      obrigatoria: true,
      ordem: 1,
      ativa: true,
    ),
    const PerguntaCategoriaAdmin(
      id: 'p-2',
      categoriaId: 'c-1',
      texto: 'O imóvel possui escada disponível?',
      tipo: 'sim_nao',
      obrigatoria: false,
      ordem: 2,
      ativa: true,
    ),
  ];

  @override
  Future<List<PerguntaCategoriaAdmin>> listarPerguntasCategoria(String categoriaId) => _ler(
        () => _perguntas.where((p) => p.categoriaId == categoriaId).toList(),
        [],
      );

  @override
  Future<PerguntaCategoriaAdmin> criarPerguntaCategoria(
    String categoriaId, {
    required String texto,
    required String tipo,
    List<String>? opcoes,
    bool obrigatoria = false,
    int ordem = 0,
    required String motivo,
  }) async {
    final p = PerguntaCategoriaAdmin(
      id: 'p-${_perguntas.length + 1}',
      categoriaId: categoriaId,
      texto: texto,
      tipo: tipo,
      opcoes: opcoes,
      obrigatoria: obrigatoria,
      ordem: ordem,
      ativa: true,
    );
    _perguntas.add(p);
    _registrar('categoria.pergunta_criada', 'categoria_perguntas', motivo);
    return p;
  }

  @override
  Future<PerguntaCategoriaAdmin> editarPerguntaCategoria(
    String categoriaId,
    String perguntaId, {
    String? texto,
    String? tipo,
    List<String>? opcoes,
    bool? obrigatoria,
    int? ordem,
    bool? ativa,
    required String motivo,
  }) async {
    final idx = _perguntas.indexWhere((p) => p.id == perguntaId);
    if (idx < 0) throw const ErroApi('Pergunta não encontrada.');
    final anterior = _perguntas[idx];
    final atualizado = PerguntaCategoriaAdmin(
      id: anterior.id,
      categoriaId: anterior.categoriaId,
      texto: texto ?? anterior.texto,
      tipo: tipo ?? anterior.tipo,
      opcoes: opcoes ?? anterior.opcoes,
      obrigatoria: obrigatoria ?? anterior.obrigatoria,
      ordem: ordem ?? anterior.ordem,
      ativa: ativa ?? anterior.ativa,
    );
    _perguntas[idx] = atualizado;
    _registrar('categoria.pergunta_editada', 'categoria_perguntas', motivo);
    return atualizado;
  }

  @override
  Future<void> desativarPerguntaCategoria(String categoriaId, String perguntaId, {required String motivo}) async {
    final idx = _perguntas.indexWhere((p) => p.id == perguntaId);
    if (idx >= 0) {
      final p = _perguntas[idx];
      _perguntas[idx] = PerguntaCategoriaAdmin(
        id: p.id,
        categoriaId: p.categoriaId,
        texto: p.texto,
        tipo: p.tipo,
        opcoes: p.opcoes,
        obrigatoria: p.obrigatoria,
        ordem: p.ordem,
        ativa: false,
      );
      _registrar('categoria.pergunta_desativada', 'categoria_perguntas', motivo);
    }
  }

  List<AlertaRisco> _alertasRisco = [
    const AlertaRisco(
      id: 'r-1',
      usuarioId: 'u-101',
      usuarioNome: 'Paulo R.',
      usuarioTipo: 'cliente',
      usuarioStatus: 'ativo',
      pedido: 'PED-10498',
      tipo: 'valor_atipico',
      severidade: 'critica',
      detalhes: 'Pedido criado com valor de R\$ 3.000,00. O limite de atipicidade é R\$ 800,00 e o teto do pedido '
          'é R\$ 1.000,00, então a criação deveria ter sido barrada.',
      criadoEm: '2026-11-02T13:40:00Z',
    ),
    const AlertaRisco(
      id: 'r-2',
      usuarioId: 'u-102',
      usuarioNome: 'Marcos V.',
      usuarioTipo: 'profissional',
      usuarioStatus: 'ativo',
      pedido: 'PED-10482',
      tipo: 'varios_pedidos_em_pouco_tempo',
      severidade: 'alta',
      detalhes: '3 pedidos de valor alto em 2 horas.',
      status: 'em_analise',
      responsavel: 'Emanuel Cabral',
      criadoEm: '2026-11-02T10:15:00Z',
    ),
    const AlertaRisco(
      id: 'r-3',
      usuarioId: 'u-103',
      usuarioNome: 'Carla M.',
      usuarioTipo: 'profissional',
      usuarioStatus: 'ativo',
      tipo: 'troca_de_chave_pix',
      severidade: 'media',
      detalhes: 'Chave alterada 2 vezes em 24 horas.',
      criadoEm: '2026-11-01T14:30:00Z',
    ),
  ];

  @override
  Future<List<AlertaRisco>> listarAlertasRisco() => _ler(() => List.of(_alertasRisco), []);

  void _statusDoUsuario(String usuarioId, String status) {
    _alertasRisco = [for (final a in _alertasRisco) a.usuarioId == usuarioId ? a.comUsuarioStatus(status) : a];
  }

  @override
  Future<void> aplicarBloqueioPreventivo(String usuarioId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _statusDoUsuario(usuarioId, 'bloqueado');
    _registrar('risco.bloqueio_preventivo', 'usuarios', motivo);
  }

  @override
  Future<void> desbloquearConta(String usuarioId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _statusDoUsuario(usuarioId, 'ativo');
    _registrar('risco.desbloqueio', 'usuarios', motivo);
  }

  @override
  Future<void> travarSaque(String usuarioId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _statusDoUsuario(usuarioId, 'restrito');
    _registrar('risco.saque_travado', 'perfis_profissional', motivo);
  }

  @override
  Future<void> destravarSaque(String usuarioId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _statusDoUsuario(usuarioId, 'ativo');
    _registrar('risco.saque_destravado', 'perfis_profissional', motivo);
  }

  @override
  Future<void> assumirAlertaRisco(String alertaId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    _alertasRisco = [
      for (final a in _alertasRisco)
        if (a.id == alertaId)
          AlertaRisco(
            id: a.id,
            usuarioId: a.usuarioId,
            usuarioNome: a.usuarioNome,
            usuarioTipo: a.usuarioTipo,
            usuarioStatus: a.usuarioStatus,
            pedido: a.pedido,
            tipo: a.tipo,
            severidade: a.severidade,
            detalhes: a.detalhes,
            status: 'em_analise',
            responsavel: _eu?.nome,
            criadoEm: a.criadoEm,
          )
        else
          a,
    ];
    _registrar('risco.alerta_assumido', 'alertas_risco', motivo);
  }

  @override
  Future<void> resolverAlertaRisco(String alertaId, {required String resultado, required String motivo}) async {
    await Future<void>.delayed(atraso);
    _alertasRisco = [for (final a in _alertasRisco) a.id == alertaId ? a.comResolucao(resultado) : a];
    _registrar('risco.alerta_resolvido', 'alertas_risco', motivo);
  }

  final List<CampanhaNotificacao> _campanhas = [
    const CampanhaNotificacao(
      id: 'cmp-1',
      titulo: 'Bem-vindo ao Trato',
      mensagem: 'Peça orçamentos de profissionais verificados na sua região.',
      segmento: 'clientes',
      totalDestinatarios: 2410,
      criadoEm: '2026-10-28T16:00:00Z',
      autor: 'Emanuel Cabral',
      enviados: 2410,
      entregues: 2356,
      abertos: 612,
    ),
    const CampanhaNotificacao(
      id: 'cmp-2',
      titulo: 'Atualize seus documentos',
      mensagem: 'Documentos vencidos impedem novos pedidos.',
      segmento: 'profissionais',
      tipo: 'operacional',
      totalDestinatarios: 1040,
      criadoEm: '2026-10-21T16:00:00Z',
      autor: 'Emanuel Cabral',
      enviados: 1040,
      entregues: 1028,
      abertos: 497,
    ),
  ];

  @override
  Future<List<CampanhaNotificacao>> listarCampanhasNotificacao() => _ler(() => List.of(_campanhas), []);

  @override
  Future<EstimativaCampanha> estimarCampanhaNotificacao({
    required String segmento,
    required String tipo,
    String? categoriaId,
    String? cidadeId,
  }) async {
    await Future<void>.delayed(atraso);
    final base = switch (segmento) {
      'clientes' => 3000,
      'profissionais' => 902,
      'todos' => 3902,
      _ => 640,
    };
    final fora = tipo == 'marketing' ? 412 : 0;
    return EstimativaCampanha(destinatarios: base - fora, desativaram: fora);
  }

  @override
  Future<CampanhaNotificacao> dispararCampanhaNotificacao({
    required String titulo,
    required String mensagem,
    required String segmento,
    String tipo = 'marketing',
    String? categoriaId,
    String? cidadeId,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    final c = CampanhaNotificacao(
      id: 'cmp-${_campanhas.length + 1}',
      titulo: titulo,
      mensagem: mensagem,
      segmento: segmento,
      tipo: tipo,
      categoriaId: categoriaId,
      cidadeId: cidadeId,
      totalDestinatarios: 120,
      criadoEm: DateTime.now().toIso8601String(),
      autor: _eu?.nome,
      enviados: 120,
    );
    _campanhas.insert(0, c);
    _registrar('notificacao.campanha_disparada', 'campanhas_notificacao', motivo);
    return c;
  }

  final List<CupomAdmin> _cupons = [
    const CupomAdmin(
      id: 'cup-1',
      codigo: 'BEMVINDO10',
      tipo: 'percentual',
      valor: 10,
      valorMinimoCentavos: 5000,
      limiteUsos: 100,
      limitePorUsuario: 1,
      usosAtuais: 14,
      validoAte: '2026-12-31',
      campanha: 'Boas-vindas',
      ativo: true,
      criadoEm: '2026-10-29T10:00:00Z',
    ),
    const CupomAdmin(
      id: 'cup-2',
      codigo: 'PINTURA20',
      tipo: 'fixo',
      valor: 2000,
      valorMinimoCentavos: 15000,
      limiteUsos: 150,
      usosAtuais: 37,
      validoAte: '2026-11-30',
      campanha: 'Lançamento Pintor',
      ativo: true,
      criadoEm: '2026-10-30T10:00:00Z',
    ),
    const CupomAdmin(
      id: 'cup-3',
      codigo: 'TESTEJUNHO',
      tipo: 'percentual',
      valor: 5,
      valorMinimoCentavos: 0,
      limiteUsos: 50,
      usosAtuais: 0,
      ativo: false,
      criadoEm: '2026-10-31T10:00:00Z',
    ),
  ];

  @override
  Future<List<CupomAdmin>> listarCupons() => _ler(() => List.of(_cupons), []);

  @override
  Future<CupomAdmin> criarCupom({
    required String codigo,
    required String tipo,
    required int valor,
    int valorMinimoCentavos = 0,
    int? limiteUsos,
    int? limitePorUsuario,
    String? validoDesde,
    String? validoAte,
    String? campanha,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    if (_cupons.any((c) => c.codigo == codigo.toUpperCase())) {
      throw ErroApi("O cupom '${codigo.toUpperCase()}' já está cadastrado.");
    }
    final c = CupomAdmin(
      id: 'cup-${_cupons.length + 1}',
      codigo: codigo.toUpperCase(),
      tipo: tipo,
      valor: valor,
      valorMinimoCentavos: valorMinimoCentavos,
      limiteUsos: limiteUsos,
      limitePorUsuario: limitePorUsuario,
      usosAtuais: 0,
      validoDesde: validoDesde,
      validoAte: validoAte,
      campanha: campanha,
      ativo: true,
      criadoEm: DateTime.now().toIso8601String(),
    );
    _cupons.insert(0, c);
    _registrar('cupom.criado', 'cupons', motivo);
    return c;
  }

  @override
  Future<CupomAdmin> alterarStatusCupom(String cupomId, {required bool ativo, required String motivo}) async {
    await Future<void>.delayed(atraso);
    final idx = _cupons.indexWhere((c) => c.id == cupomId);
    if (idx < 0) throw const ErroApi('Cupom não encontrado.');
    _cupons[idx] = _cupons[idx].comAtivo(ativo);
    _registrar(ativo ? 'cupom.ativado' : 'cupom.desativado', 'cupons', motivo);
    return _cupons[idx];
  }

  @override
  Future<void> excluirCupom(String cupomId, {required String motivo}) async {
    _cupons.removeWhere((c) => c.id == cupomId);
    _registrar('cupom.excluido', 'cupons', motivo);
  }

  static const _tetos = {
    'administrador': 500000,
    'financeiro': 200000,
    'lider_suporte': 200000,
    'mediador': 50000,
    'atendente_n2': 50000,
    'atendente_n1': 30000,
  };

  List<MembroEquipeAdmin> _equipe = [
    const MembroEquipeAdmin(
      usuarioId: 'eq-1',
      nome: 'Emanuel Cabral',
      email: 'emanuel@feitolabs.com.br',
      papel: 'administrador',
      ativo: true,
      alcadaCentavos: 500000,
      criadoEm: '2026-10-29T09:00:00Z',
      ultimoAcesso: '2026-11-02T14:20:00Z',
      tetoPapelCentavos: 500000,
    ),
    const MembroEquipeAdmin(
      usuarioId: 'eq-2',
      nome: 'João Vitor Cardoso',
      email: 'joao.cardoso@feitolabs.com.br',
      papel: 'financeiro',
      ativo: true,
      alcadaCentavos: 200000,
      criadoEm: '2026-10-29T09:00:00Z',
      ultimoAcesso: '2026-11-01T18:02:00Z',
      tetoPapelCentavos: 200000,
    ),
    const MembroEquipeAdmin(
      usuarioId: 'eq-3',
      nome: 'Bruna Teixeira',
      email: 'bruna.teixeira@feitolabs.com.br',
      papel: 'atendente_n1',
      ativo: true,
      alcadaCentavos: 30000,
      criadoEm: '2026-10-30T09:00:00Z',
      ultimoAcesso: '2026-11-01T09:00:00Z',
      tetoPapelCentavos: 30000,
    ),
    const MembroEquipeAdmin(
      usuarioId: 'eq-4',
      nome: 'Larissa Prado',
      email: 'larissa.prado@feitolabs.com.br',
      papel: 'atendente_n1',
      ativo: true,
      alcadaCentavos: 0,
      criadoEm: '2026-10-31T09:00:00Z',
      status: 'convite_enviado',
      tetoPapelCentavos: 30000,
    ),
  ];

  @override
  Future<List<MembroEquipeAdmin>> listarEquipe() => _ler(() => List.of(_equipe), []);

  @override
  Future<Map<String, int>> tetosDosPapeis() async => Map.of(_tetos);

  void _validarConcessao(String papel, int alcada) {
    final teto = _tetos[papel] ?? 0;
    if (alcada > teto) throw const ErroApi('A alçada passa do teto do papel. Ajuste o valor.');
  }

  int _administradoresAtivos([String? exceto]) =>
      _equipe.where((m) => m.papel == 'administrador' && m.ativo && m.usuarioId != exceto).length;

  @override
  Future<MembroEquipeAdmin> adicionarMembroEquipe({
    required String nome,
    required String email,
    required String papel,
    int alcadaCentavos = 0,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    _validarConcessao(papel, alcadaCentavos);
    if (_equipe.any((m) => m.email.toLowerCase() == email.trim().toLowerCase() && m.ativo)) {
      throw const ErroApi('Este e-mail já tem acesso. Edite o colaborador existente.');
    }
    final m = MembroEquipeAdmin(
      usuarioId: 'eq-${_equipe.length + 1}',
      nome: nome,
      email: email,
      papel: papel,
      ativo: true,
      alcadaCentavos: alcadaCentavos,
      criadoEm: DateTime.now().toIso8601String(),
      status: 'convite_enviado',
      tetoPapelCentavos: _tetos[papel] ?? 0,
    );
    _equipe = [..._equipe, m];
    _registrar('equipe.membro_adicionado', 'equipe', motivo);
    return m;
  }

  MembroEquipeAdmin _copia(MembroEquipeAdmin m, {String? papel, int? alcada, bool? ativo}) => MembroEquipeAdmin(
        usuarioId: m.usuarioId,
        nome: m.nome,
        email: m.email,
        papel: papel ?? m.papel,
        ativo: ativo ?? m.ativo,
        alcadaCentavos: alcada ?? m.alcadaCentavos,
        criadoEm: m.criadoEm,
        status: (ativo ?? m.ativo) ? (m.status == 'revogado' ? 'ativo' : m.status) : 'revogado',
        ultimoAcesso: m.ultimoAcesso,
        tetoPapelCentavos: _tetos[papel ?? m.papel] ?? m.tetoPapelCentavos,
      );

  @override
  Future<MembroEquipeAdmin> editarMembroEquipe(
    String usuarioId, {
    String? papel,
    int? alcadaCentavos,
    bool? ativo,
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    final idx = _equipe.indexWhere((m) => m.usuarioId == usuarioId);
    if (idx < 0) throw const ErroApi('Membro da equipe não encontrado.');
    final ant = _equipe[idx];
    final novoPapel = papel ?? ant.papel;
    _validarConcessao(novoPapel, alcadaCentavos ?? ant.alcadaCentavos);
    final deixaDeSerAdmin = ant.papel == 'administrador' && ant.ativo && (novoPapel != 'administrador' || ativo == false);
    if (deixaDeSerAdmin && _administradoresAtivos(usuarioId) == 0) {
      throw const ErroApi('Este é o único Administrador ativo: não pode ser revogado nem rebaixado.');
    }
    final atualizado = _copia(ant, papel: papel, alcada: alcadaCentavos, ativo: ativo);
    _equipe = [for (var i = 0; i < _equipe.length; i++) i == idx ? atualizado : _equipe[i]];
    _registrar('equipe.membro_atualizado', 'equipe', motivo);
    return atualizado;
  }

  @override
  Future<void> revogarMembroEquipe(String usuarioId, {required String motivo}) async {
    await Future<void>.delayed(atraso);
    final idx = _equipe.indexWhere((m) => m.usuarioId == usuarioId);
    if (idx < 0) return;
    final ant = _equipe[idx];
    if (ant.papel == 'administrador' && ant.ativo && _administradoresAtivos(usuarioId) == 0) {
      throw const ErroApi('Este é o único Administrador ativo: não pode ser revogado nem rebaixado.');
    }
    _equipe = [for (var i = 0; i < _equipe.length; i++) i == idx ? _copia(ant, ativo: false) : _equipe[i]];
    _registrar('equipe.acesso_revogado', 'equipe', motivo);
  }

  @override
  Future<RelatorioPronto> solicitarRelatorio(
    String tipo, {
    DateTime? inicio,
    DateTime? fim,
    String? cidadeId,
    String formato = 'excel_br',
    required String motivo,
  }) async {
    await Future<void>.delayed(atraso);
    _registrar(
      'relatorio.exportado',
      'relatorios',
      motivo,
      detalhes: {
        'relatorio': tipo,
        'inicio': inicio?.toIso8601String().substring(0, 10),
        'fim': fim?.toIso8601String().substring(0, 10),
        'formato': formato,
      },
    );
    return RelatorioPronto(
      url: 'https://api.trato.local/v1/admin/relatorios/baixar/exemplo',
      nomeArquivo: 'trato_${tipo}_exemplo.csv',
      linhas: 128,
      colunas: tipo == 'financeiro' ? 15 : (tipo == 'pedidos' ? 10 : 11),
      comDadosPessoais: tipo == 'financeiro',
    );
  }
}
