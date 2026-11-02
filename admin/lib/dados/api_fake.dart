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

  void _registrar(String acao, String entidade, String? motivo) {
    final id = _auditoria.length + 1;
    _auditoria.add(EntradaAuditoria(
      id: id,
      ocorridaEm: _base.add(Duration(minutes: 30 + id)),
      ator: _eu?.email ?? 'sistema',
      acao: acao,
      entidade: entidade,
      motivo: motivo,
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
  @override
  Future<ResumoConciliacao> resumoConciliacao() => _ler(
        () => ResumoConciliacao(
          confirmadoCentavos: 1284500,
          estornadoCentavos: 12000,
          emAndamentoCentavos: 96000,
          divergencias: 1,
          atualizadoEm: _base,
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
  Future<List<LancamentoEspelho>> extrato() => _ler(
        () => [
          LancamentoEspelho(
            id: 'l-1',
            data: _base,
            descricao: 'Sinal do orçamento',
            valorCentavos: 36000,
            status: StatusProvedor.confirmado,
            pedido: 'PED-1042',
            refProvedor: 'pi_exemplo_001',
          ),
          LancamentoEspelho(
            id: 'l-2',
            data: _base.subtract(const Duration(hours: 5)),
            descricao: 'Pagamento final',
            valorCentavos: 84000,
            status: StatusProvedor.aguardandoConfirmacao,
            pedido: 'PED-1042',
            refProvedor: 'pi_exemplo_002',
          ),
          LancamentoEspelho(
            id: 'l-3',
            data: _base.subtract(const Duration(days: 1)),
            descricao: 'Reembolso decidido em disputa',
            valorCentavos: -12000,
            status: StatusProvedor.reembolsado,
            pedido: 'PED-0987',
            refProvedor: 're_exemplo_003',
          ),
          LancamentoEspelho(
            id: 'l-4',
            data: _base.subtract(const Duration(days: 2)),
            descricao: 'Pagamento recusado pelo cartão',
            valorCentavos: 15000,
            status: StatusProvedor.falhou,
            pedido: 'PED-1010',
            refProvedor: 'pi_exemplo_004',
            divergente: true,
          ),
        ],
        const [],
      );

  // ---------- F7.4 ----------
  @override
  Future<List<UsuarioBusca>> buscarUsuarios(String termo) => _ler(() {
        const todos = [
          UsuarioBusca(
            id: 'u-1',
            nome: 'Marina Souza',
            tipo: 'Cliente',
            status: 'ativo',
            emailMascarado: 'm*****@exemplo.com',
            cpfMascarado: '***.***.***-12',
          ),
          UsuarioBusca(
            id: 'u-2',
            nome: 'Carlos Pereira',
            tipo: 'Profissional',
            status: 'ativo',
            emailMascarado: 'c*****@exemplo.com',
            cpfMascarado: '***.***.***-45',
          ),
          UsuarioBusca(
            id: 'u-3',
            nome: 'Paulo Lima',
            tipo: 'Profissional',
            status: 'suspenso',
            emailMascarado: 'p****@exemplo.com',
            cpfMascarado: '***.***.***-78',
          ),
        ];
        final t = termo.trim().toLowerCase();
        return [for (final u in todos) if (t.isEmpty || u.nome.toLowerCase().contains(t)) u];
      }, const []);

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
            id: 'PED-1042',
            titulo: 'Troca de chuveiro',
            cliente: 'Marina Souza',
            status: 'em execução',
            valorCentavos: 120000,
          ),
          PedidoBusca(
            id: 'PED-0987',
            titulo: 'Pintura de sala',
            cliente: 'Marina Souza',
            status: 'disputa aberta',
            valorCentavos: 240000,
          ),
        ];
        final t = termo.trim().toLowerCase();
        return [
          for (final p in todos)
            if (t.isEmpty || p.id.toLowerCase().contains(t) || p.titulo.toLowerCase().contains(t)) p,
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
          ),
          Chamado(
            id: 'CH-30',
            assunto: 'Dúvida sobre o orçamento',
            solicitante: 'Marina Souza',
            status: 'em atendimento',
            aberto: _base.subtract(const Duration(days: 1)),
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
  static const _definicoes = [
    ConfigDefinicao(
      chave: 'taxa_base_bps',
      descricao: 'Taxa do Trato (base)',
      unidade: UnidadeConfig.bps,
      minimo: 100,
      maximo: 2000,
      exigeDuplaAprovacao: true,
    ),
    ConfigDefinicao(
      chave: 'taxa_minima_bps',
      descricao: 'Taxa mínima do Trato',
      unidade: UnidadeConfig.bps,
      minimo: 0,
      maximo: 1500,
      exigeDuplaAprovacao: true,
    ),
    ConfigDefinicao(
      chave: 'sinal_bps',
      descricao: 'Sinal pago ao aceitar o orçamento',
      unidade: UnidadeConfig.bps,
      minimo: 1000,
      maximo: 5000,
      exigeDuplaAprovacao: true,
    ),
    ConfigDefinicao(
      chave: 'prazo_confirmacao_horas',
      descricao: 'Prazo para o cliente confirmar o serviço',
      unidade: UnidadeConfig.horas,
      minimo: 24,
      maximo: 96,
      exigeDuplaAprovacao: true,
    ),
    ConfigDefinicao(
      chave: 'prazo_contestacao_dias',
      descricao: 'Prazo do cliente para reclamar',
      unidade: UnidadeConfig.dias,
      minimo: 3,
      maximo: 30,
      exigeDuplaAprovacao: true,
    ),
    ConfigDefinicao(
      chave: 'prazo_resposta_disputa_horas',
      descricao: 'Prazo de resposta do profissional na disputa',
      unidade: UnidadeConfig.horas,
      minimo: 12,
      maximo: 120,
      exigeDuplaAprovacao: false,
    ),
    ConfigDefinicao(
      chave: 'alcada_disputa_centavos',
      descricao: 'Alçada de decisão sem segunda pessoa',
      unidade: UnidadeConfig.centavos,
      minimo: 0,
      maximo: 1000000,
      exigeDuplaAprovacao: true,
    ),
    ConfigDefinicao(
      chave: 'garantia_dias_padrao',
      descricao: 'Prazo de garantia padrão do serviço',
      unidade: UnidadeConfig.dias,
      minimo: 0,
      maximo: 180,
      exigeDuplaAprovacao: false,
    ),
  ];

  List<ConfigVersao> _versoesIniciais() {
    const vigente = {
      'taxa_base_bps': 750,
      'taxa_minima_bps': 300,
      'sinal_bps': 3000,
      'prazo_confirmacao_horas': 48,
      'prazo_contestacao_dias': 7,
      'prazo_resposta_disputa_horas': 48,
      'alcada_disputa_centavos': 50000,
      'garantia_dias_padrao': 30,
    };
    return [
      ConfigVersao(
        id: 'v3',
        numero: 3,
        status: StatusVersao.aguardandoAprovacao,
        motivo: 'Ajuste do prazo de confirmação depois da revisão jurídica',
        criadaPor: 'eq-financeiro',
        criadaEm: _base.subtract(const Duration(hours: 2)),
        valores: {...vigente, 'prazo_confirmacao_horas': 72},
      ),
      ConfigVersao(
        id: 'v2',
        numero: 2,
        status: StatusVersao.vigente,
        motivo: 'Valores do piloto',
        criadaPor: 'eq-financeiro',
        aprovadaPor: 'eq-administrador',
        criadaEm: _base.subtract(const Duration(days: 3)),
        valores: vigente,
      ),
      ConfigVersao(
        id: 'v1',
        numero: 1,
        status: StatusVersao.substituida,
        motivo: 'Valores iniciais',
        criadaPor: 'eq-financeiro',
        aprovadaPor: 'eq-administrador',
        criadaEm: _base.subtract(const Duration(days: 20)),
        valores: {...vigente, 'taxa_base_bps': 800},
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
      if (v == null || v < d.minimo || v > d.maximo) {
        throw ErroApi('${d.descricao}: o valor precisa ficar entre ${d.minimo} e ${d.maximo}.');
      }
    }
  }

  @override
  Future<void> proporConfig(Map<String, int> valores, String motivo) async {
    await Future<void>.delayed(atraso);
    _exigirFaixa(valores);
    final numero = _versoes.first.numero + 1;
    _versoes = [
      ConfigVersao(
        id: 'v$numero',
        numero: numero,
        status: StatusVersao.aguardandoAprovacao,
        motivo: motivo,
        criadaPor: _eu?.id ?? '',
        criadaEm: _base.add(Duration(hours: numero)),
        valores: valores,
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
          v.comStatus(StatusVersao.vigente, aprovadaPor: _eu?.id)
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
  Future<void> reverterConfig(String versaoId, String motivo) async {
    await Future<void>.delayed(atraso);
    final antiga = _versoes.firstWhere((v) => v.id == versaoId);
    await proporConfig(antiga.valores, 'Reversão para a versão ${antiga.numero}: $motivo');
    _registrar('config.reversao_pedida', 'config:$versaoId', motivo);
  }

  // ---------- F7.6 ----------
  @override
  Future<List<EntradaAuditoria>> listarAuditoria({String? acao, String? ator}) => _ler(() {
        final a = acao?.trim().toLowerCase() ?? '';
        final p = ator?.trim().toLowerCase() ?? '';
        return [
          for (final e in _auditoria.reversed)
            if ((a.isEmpty || e.acao.toLowerCase().contains(a)) && (p.isEmpty || e.ator.toLowerCase().contains(p))) e,
        ];
      }, const []);

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
          acao: 'config.publicada',
          entidade: 'config:v2',
          motivo: 'Valores do piloto',
          hash: 'a0001f3',
        ),
        EntradaAuditoria(
          id: 2,
          ocorridaEm: _base.subtract(const Duration(hours: 20)),
          ator: 'mediador@teste.local',
          acao: 'disputa.decidida',
          entidade: 'disputa:d-0',
          motivo: 'Cliente não comprovou o problema',
          hash: 'a0002b9',
        ),
      ];

  List<Verificacao> _verificacoesIniciais() => [
        Verificacao(
          id: 'ver-1',
          profissional: 'Carlos Pereira',
          categoria: 'Elétrica',
          cidade: 'Belo Horizonte',
          enviadaEm: _base.subtract(const Duration(hours: 6)),
          cpfMascarado: '***.***.***-45',
          documentos: const ['Documento (frente)', 'Documento (verso)', 'Selfie'],
        ),
        Verificacao(
          id: 'ver-2',
          profissional: 'Ana Ribeiro',
          categoria: 'Pintura',
          cidade: 'Belo Horizonte',
          enviadaEm: _base.subtract(const Duration(days: 1)),
          cpfMascarado: '***.***.***-90',
          documentos: const ['Documento (frente)', 'Selfie'],
          status: StatusVerificacao.emAnalise,
        ),
      ];

  List<Disputa> _disputasIniciais() => [
        Disputa(
          id: 'd-1',
          pedido: 'PED-0987',
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
          pedido: 'PED-1021',
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
  Future<MetricasDashboard> metricasDashboard() => _ler(
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
  Future<SeriesDashboard> seriesDashboard({int dias = 7}) => _ler(
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
            EtapaFunilDashboard(etapa: '1. Pedidos Criados', quantidade: 142, taxaConversaoPct: 100.0),
            EtapaFunilDashboard(etapa: '2. Propostas Recebidas', quantidade: 128, taxaConversaoPct: 90.1),
            EtapaFunilDashboard(etapa: '3. Pedidos Fechados', quantidade: 105, taxaConversaoPct: 73.9),
            EtapaFunilDashboard(etapa: '4. Serviços Concluídos', quantidade: 98, taxaConversaoPct: 69.0),
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

  final List<AlertaRisco> _alertasRisco = [
    const AlertaRisco(
      id: 'r-1',
      usuarioId: 'u-101',
      usuarioNome: 'Lucas Santos',
      tipo: 'taxa_cancelamento',
      severidade: 'alta',
      detalhes: 'Profissional cancelou 4 dos últimos 10 pedidos aceitos.',
      resolvido: false,
      criadoEm: '2026-11-01T14:30:00Z',
    ),
    const AlertaRisco(
      id: 'r-2',
      usuarioId: 'u-204',
      usuarioNome: 'Mariana Lima',
      tipo: 'disputas_frequentes',
      severidade: 'media',
      detalhes: 'Cliente abriu disputa em 2 pedidos consecutivos.',
      resolvido: false,
      criadoEm: '2026-11-02T10:15:00Z',
    ),
  ];

  @override
  Future<List<AlertaRisco>> listarAlertasRisco() => _ler(() => List.of(_alertasRisco), []);

  @override
  Future<void> aplicarBloqueioPreventivo(String usuarioId, {required String motivo}) async {
    _registrar('risco.bloqueio_preventivo', 'usuarios', motivo);
  }

  @override
  Future<void> travarSaque(String usuarioId, {required String motivo}) async {
    _registrar('risco.saque_travado', 'perfis_profissional', motivo);
  }

  @override
  Future<void> resolverAlertaRisco(String alertaId, {required String motivo}) async {
    final idx = _alertasRisco.indexWhere((a) => a.id == alertaId);
    if (idx >= 0) {
      final a = _alertasRisco[idx];
      _alertasRisco[idx] = AlertaRisco(
        id: a.id,
        usuarioId: a.usuarioId,
        usuarioNome: a.usuarioNome,
        tipo: a.tipo,
        severidade: a.severidade,
        detalhes: a.detalhes,
        resolvido: true,
        criadoEm: a.criadoEm,
      );
      _registrar('risco.alerta_resolvido', 'alertas_risco', motivo);
    }
  }

  final List<CampanhaNotificacao> _campanhas = [
    const CampanhaNotificacao(
      id: 'cmp-1',
      titulo: 'Alta demanda em Campinas!',
      mensagem: 'Muitos clientes buscando eletricistas e pintores agora.',
      segmento: 'profissionais',
      totalDestinatarios: 85,
      criadoEm: '2026-11-01T16:00:00Z',
    ),
  ];

  @override
  Future<List<CampanhaNotificacao>> listarCampanhasNotificacao() => _ler(() => List.of(_campanhas), []);

  @override
  Future<CampanhaNotificacao> dispararCampanhaNotificacao({
    required String titulo,
    required String mensagem,
    required String segmento,
    String? categoriaId,
    String? cidadeId,
    required String motivo,
  }) async {
    final c = CampanhaNotificacao(
      id: 'cmp-${_campanhas.length + 1}',
      titulo: titulo,
      mensagem: mensagem,
      segmento: segmento,
      categoriaId: categoriaId,
      cidadeId: cidadeId,
      totalDestinatarios: 120,
      criadoEm: DateTime.now().toIso8601String(),
    );
    _campanhas.insert(0, c);
    _registrar('notificacao.campanha_disparada', 'campanhas_notificacao', motivo);
    return c;
  }

  final List<CupomAdmin> _cupons = [
    const CupomAdmin(
      id: 'cup-1',
      codigo: 'PRIMEIRACOMPRA',
      tipo: 'percentual',
      valor: 10,
      valorMinimoCentavos: 0,
      limiteUsos: 100,
      usosAtuais: 14,
      ativo: true,
      criadoEm: '2026-10-29T10:00:00Z',
    ),
    const CupomAdmin(
      id: 'cup-2',
      codigo: 'BEMVINDO20',
      tipo: 'fixo',
      valor: 2000,
      valorMinimoCentavos: 5000,
      limiteUsos: 200,
      usosAtuais: 35,
      ativo: true,
      criadoEm: '2026-10-30T10:00:00Z',
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
    String? validoAte,
    required String motivo,
  }) async {
    final c = CupomAdmin(
      id: 'cup-${_cupons.length + 1}',
      codigo: codigo.toUpperCase(),
      tipo: tipo,
      valor: valor,
      valorMinimoCentavos: valorMinimoCentavos,
      limiteUsos: limiteUsos,
      usosAtuais: 0,
      validoAte: validoAte,
      ativo: true,
      criadoEm: DateTime.now().toIso8601String(),
    );
    _cupons.insert(0, c);
    _registrar('cupom.criado', 'cupons', motivo);
    return c;
  }

  @override
  Future<CupomAdmin> alterarStatusCupom(String cupomId, {required bool ativo, required String motivo}) async {
    final idx = _cupons.indexWhere((c) => c.id == cupomId);
    if (idx < 0) throw const ErroApi('Cupom não encontrado.');
    final c = _cupons[idx];
    final novo = CupomAdmin(
      id: c.id,
      codigo: c.codigo,
      tipo: c.tipo,
      valor: c.valor,
      valorMinimoCentavos: c.valorMinimoCentavos,
      limiteUsos: c.limiteUsos,
      usosAtuais: c.usosAtuais,
      validoAte: c.validoAte,
      ativo: ativo,
      criadoEm: c.criadoEm,
    );
    _cupons[idx] = novo;
    _registrar(ativo ? 'cupom.ativado' : 'cupom.desativado', 'cupons', motivo);
    return novo;
  }

  @override
  Future<void> excluirCupom(String cupomId, {required String motivo}) async {
    _cupons.removeWhere((c) => c.id == cupomId);
    _registrar('cupom.excluido', 'cupons', motivo);
  }

  final List<MembroEquipeAdmin> _equipe = [
    const MembroEquipeAdmin(
      usuarioId: 'eq-1',
      nome: 'João Vitor Cardoso',
      email: 'cardosojoaovitor47@gmail.com',
      papel: 'administrador',
      ativo: true,
      alcadaCentavos: 10000000000,
      criadoEm: '2026-10-29T09:00:00Z',
    ),
    const MembroEquipeAdmin(
      usuarioId: 'eq-2',
      nome: 'Emanoel Cabral',
      email: 'emanoel.cabral@trato.feitolabs.com.br',
      papel: 'administrador',
      ativo: true,
      alcadaCentavos: 10000000000,
      criadoEm: '2026-10-29T09:00:00Z',
    ),
    const MembroEquipeAdmin(
      usuarioId: 'eq-3',
      nome: 'Gabriel Victor',
      email: 'gabriel.victor@trato.feitolabs.com.br',
      papel: 'administrador',
      ativo: true,
      alcadaCentavos: 10000000000,
      criadoEm: '2026-10-29T09:00:00Z',
    ),
  ];

  @override
  Future<List<MembroEquipeAdmin>> listarEquipe() => _ler(() => List.of(_equipe), []);

  @override
  Future<MembroEquipeAdmin> adicionarMembroEquipe({
    required String nome,
    required String email,
    required String papel,
    int alcadaCentavos = 0,
    required String motivo,
  }) async {
    final m = MembroEquipeAdmin(
      usuarioId: 'eq-${_equipe.length + 1}',
      nome: nome,
      email: email,
      papel: papel,
      ativo: true,
      alcadaCentavos: alcadaCentavos,
      criadoEm: DateTime.now().toIso8601String(),
    );
    _equipe.add(m);
    _registrar('equipe.membro_adicionado', 'equipe', motivo);
    return m;
  }

  @override
  Future<MembroEquipeAdmin> editarMembroEquipe(
    String usuarioId, {
    String? papel,
    int? alcadaCentavos,
    bool? ativo,
    required String motivo,
  }) async {
    final idx = _equipe.indexWhere((m) => m.usuarioId == usuarioId);
    if (idx < 0) throw const ErroApi('Membro da equipe não encontrado.');
    final ant = _equipe[idx];
    final atualizado = MembroEquipeAdmin(
      usuarioId: ant.usuarioId,
      nome: ant.nome,
      email: ant.email,
      papel: papel ?? ant.papel,
      ativo: ativo ?? ant.ativo,
      alcadaCentavos: alcadaCentavos ?? ant.alcadaCentavos,
      criadoEm: ant.criadoEm,
    );
    _equipe[idx] = atualizado;
    _registrar('equipe.membro_atualizado', 'equipe', motivo);
    return atualizado;
  }

  @override
  Future<void> revogarMembroEquipe(String usuarioId, {required String motivo}) async {
    final idx = _equipe.indexWhere((m) => m.usuarioId == usuarioId);
    if (idx >= 0) {
      final ant = _equipe[idx];
      _equipe[idx] = MembroEquipeAdmin(
        usuarioId: ant.usuarioId,
        nome: ant.nome,
        email: ant.email,
        papel: ant.papel,
        ativo: false,
        alcadaCentavos: ant.alcadaCentavos,
        criadoEm: ant.criadoEm,
      );
      _registrar('equipe.acesso_revogado', 'equipe', motivo);
    }
  }

  @override
  String urlRelatorioFinanceiroCsv() => 'https://api.trato.local/v1/admin/relatorios/financeiro';

  @override
  String urlRelatorioPedidosCsv() => 'https://api.trato.local/v1/admin/relatorios/pedidos';

  @override
  String urlRelatorioRepassesCsv() => 'https://api.trato.local/v1/admin/relatorios/repasses';
}
