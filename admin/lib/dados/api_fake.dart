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
    final papel = Papel.doCodigo(nome.split('@').first);
    if (papel == null) {
      throw const ErroApi('Esta conta não tem papel na equipe.', proibido: true);
    }
    _eu = UsuarioEquipe(
      id: 'eq-${papel.codigo}',
      nome: papel.rotulo,
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
  Future<void> revelarDocumento(String verificacaoId, String documento, String motivo) async {
    await Future<void>.delayed(atraso);
    _registrar('dado_pessoal.revelado', 'verificacao:$verificacaoId', motivo);
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
    String? segundaPessoaEmail,
  }) async {
    await Future<void>.delayed(atraso);
    final d = _disputas.firstWhere((x) => x.id == id);
    final valor = switch (decisao) {
      DecisaoDisputa.reembolsoTotal => d.valorEmAnaliseCentavos,
      DecisaoDisputa.reembolsoParcial => valorReembolsoCentavos,
      _ => null,
    };
    final acima = (valor ?? 0) > (_eu?.alcadaCentavos ?? 0);
    if (acima && (segundaPessoaEmail == null || segundaPessoaEmail.isEmpty)) {
      throw const ErroApi('Valor acima da alçada: informe a segunda pessoa.');
    }
    final novo = acima ? StatusDisputa.aguardandoSegundaPessoa : StatusDisputa.decidida;
    _disputas = [for (final x in _disputas) x.id == id ? x.comDecisao(novo, decisao, valor) : x];
    _registrar('disputa.decidida', 'disputa:$id', justificativa);
    return ResultadoDecisao(
      status: novo,
      mensagem: acima ? 'Enviada para $segundaPessoaEmail aprovar.' : 'Decisão registrada.',
    );
  }

  // ---------- F7.3 ----------
  @override
  Future<ResumoConciliacao> resumoConciliacao() => _ler(
        () => ResumoConciliacao(
          confirmadoCentavos: 1284500,
          aguardandoCentavos: 96000,
          divergencias: 1,
          atualizadoEm: _base,
        ),
        ResumoConciliacao(confirmadoCentavos: 0, aguardandoCentavos: 0, divergencias: 0, atualizadoEm: _base),
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
  Future<void> alterarCategoria(String id, {required bool ativa, required String motivo}) async {
    await Future<void>.delayed(atraso);
    _categorias = [for (final c in _categorias) c.id == id ? c.comAtiva(ativa) : c];
    _registrar(ativa ? 'categoria.ativada' : 'categoria.desativada', 'categoria:$id', motivo);
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
        criadaPor: 'financeiro@teste.local',
        criadaEm: _base.subtract(const Duration(hours: 2)),
        valores: {...vigente, 'prazo_confirmacao_horas': 72},
      ),
      ConfigVersao(
        id: 'v2',
        numero: 2,
        status: StatusVersao.vigente,
        motivo: 'Valores do piloto',
        criadaPor: 'financeiro@teste.local',
        aprovadaPor: 'administrador@teste.local',
        criadaEm: _base.subtract(const Duration(days: 3)),
        valores: vigente,
      ),
      ConfigVersao(
        id: 'v1',
        numero: 1,
        status: StatusVersao.substituida,
        motivo: 'Valores iniciais',
        criadaPor: 'financeiro@teste.local',
        aprovadaPor: 'administrador@teste.local',
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
        criadaPor: _eu?.email ?? '',
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
    if (alvo.criadaPor == _eu?.email) {
      throw const ErroApi('Quem propôs a mudança não pode aprová-la. Peça a outra pessoa.');
    }
    _versoes = [
      for (final v in _versoes)
        if (v.id == versaoId)
          v.comStatus(StatusVersao.vigente, aprovadaPor: _eu?.email)
        else if (v.status == StatusVersao.vigente)
          v.comStatus(StatusVersao.substituida)
        else
          v,
    ];
    _registrar('config.publicada', 'config:$versaoId', motivo);
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
          ator: 'administrador@teste.local',
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
}
