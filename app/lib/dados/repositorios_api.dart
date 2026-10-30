import '../componentes/componentes.dart';
import '../dispositivo/servico_camera.dart';
import '../telas/carteira/modelos.dart' hide ResumoCarteira;
import '../telas/conclusao/dados_exemplo.dart';
import '../telas/orcamentos/modelos.dart';
import '../telas/pagamento/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/modelos.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_check_out.dart';
import '../telas/profissional/servico_orcamento.dart';
import '../telas/profissional_inicio/modelos.dart';
import 'cliente_api.dart';
import 'erros.dart';
import 'fila_offline.dart';
import 'modelos_api.dart';
import 'repositorios.dart';
import 'servico_upload.dart';

// IMPLEMENTAÇÕES QUE FALAM COM A API (modo `api`). Só pedem e mostram; o backend decide.
// Onde a rota ainda não existe no backend, a classe lança [ErroTrato.indisponivel] e o
// comentário diz qual rota falta. Ver `docs/app-ligacao.md`.

String _doisDigitos(int n) => n.toString().padLeft(2, '0');
String _dia(DateTime d) => '${_doisDigitos(d.day)}/${_doisDigitos(d.month)}';
String _hora(DateTime d) => '${d.hour}h${_doisDigitos(d.minute)}';

Map<String, dynamic> _mapa(Object? json) => json! as Map<String, dynamic>;
List<Map<String, dynamic>> _lista(Object? json) =>
    [for (final item in json! as List) item as Map<String, dynamic>];

const _estadosFinalizados = {'concluido', 'cancelado'};

/// Motivos da tela → motivos aceitos pelo backend (`MotivoDisputa`), na ordem da tela.
const _motivosDisputa = [
  'mal_feito',
  'diferente_do_combinado',
  'cobranca_extra',
  'dano',
  'abandono',
];

/// Textos e opções de tela que a API ainda não entrega. NÃO são regra de negócio.
class TextosPadraoTelas {
  const TextosPadraoTelas();

  List<String> get motivos => const [
        'O problema voltou ou não foi resolvido',
        'Qualidade abaixo do combinado',
        'Cobrança extra não combinada',
        'Dano no local',
        'Outro motivo',
      ];
  List<String> get solucoes =>
      const ['Retrabalho sem custo', 'Reembolso parcial', 'Reembolso total'];
  int get prazoRespostaHoras => 48;
  List<String> get criterios =>
      const ['Pontualidade', 'Qualidade', 'Limpeza', 'Comunicação', 'Preço justo'];
  List<int> get gorjetas => const [1000, 2000];
  String get garantiaCobre => 'Refazer o que está no orçamento, sem custo.';
  String get garantiaNaoCobre => 'Não cobre problemas novos nem serviços fora do orçamento.';
  int get prazoAtendimentoRetrabalhoDias => 7;
  List<String> get respostasRapidas =>
      const ['Tudo certo', 'Pode me mandar foto?', 'Que horas termina?'];
}

String _quandoRelativo(DateTime data, {DateTime? agora}) {
  final dif = (agora ?? DateTime.now()).difference(data.toLocal());
  if (dif.inMinutes < 1) return 'agora';
  if (dif.inMinutes < 60) return 'há ${dif.inMinutes} min';
  if (dif.inHours < 24) return 'há ${dif.inHours} h';
  if (dif.inDays == 1) return 'ontem';
  return 'há ${dif.inDays} dias';
}

String _iniciais(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  final primeira = partes.first[0].toUpperCase();
  return partes.length == 1 ? primeira : primeira + partes.last[0].toUpperCase();
}

class RepositorioPedidosApi implements RepositorioPedidos {
  RepositorioPedidosApi(this._api, {this.textos = const TextosPadraoTelas()});

  final ClienteApi _api;
  final TextosPadraoTelas textos;

  Future<PedidoApi> _pedido(String id) async =>
      PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$id')));

  Future<SaldoPedidoApi> _saldo(String id) async =>
      SaldoPedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$id/saldo')));

  @override
  Future<PedidosDoCliente> listar() async {
    final pedidos = [for (final j in _lista(await _api.get('/v1/pedidos'))) PedidoApi.deJson(j)];
    return PedidosDoCliente(
      emAndamento: [
        for (final p in pedidos)
          if (!_estadosFinalizados.contains(p.estado)) _resumo(p),
      ],
      finalizados: [
        for (final p in pedidos)
          if (_estadosFinalizados.contains(p.estado)) _resumo(p),
      ],
    );
  }

  PedidoResumo _resumo(PedidoApi p) {
    final (texto, tipo) = switch (p.estado) {
      'aberto' => ('Aguardando orçamentos', TipoStatus.info),
      'orcamento_aceito' => ('Aguardando pagamento', TipoStatus.alerta),
      'pago_e_retido' => ('Pagamento confirmado · a agendar', TipoStatus.info),
      'agendado' => ('Agendado', TipoStatus.info),
      'em_andamento' => ('Em execução · pagamento retido', TipoStatus.info),
      'em_confirmacao' => ('Em execução · aguardando sua confirmação', TipoStatus.info),
      'concluido' => ('Finalizado', TipoStatus.sucesso),
      'cancelado' => ('Cancelado', TipoStatus.alerta),
      'em_disputa' => ('Disputa aberta · valor congelado', TipoStatus.alerta),
      'retrabalho' => ('Retrabalho em andamento', TipoStatus.info),
      _ => (p.estadoNome, TipoStatus.info),
    };
    return PedidoResumo(
      id: p.id,
      estadoApi: p.estado,
      titulo: 'Pedido ${p.numero}',
      subtitulo: 'Aberto em ${_dia(p.abertoEm)}',
      statusTexto: texto,
      statusTipo: tipo,
    );
  }

  @override
  Future<String> criar(RascunhoPedido rascunho) async {
    // O backend só abre o pedido; os detalhes (serviços, descrição) ainda não têm campo na API.
    final criado = PedidoApi.deJson(_mapa(await _api.post('/v1/pedidos')));
    return criado.id;
  }

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async {
    final pedido = await _pedido(pedidoId);
    final eventos = [
      for (final j in _lista(await _api.get('/v1/pedidos/$pedidoId/eventos'))) EventoApi.deJson(j),
    ];
    const etapaDaAcao = {
      'aceitar_orcamento': 0,
      'confirmar_agenda': 1,
      'fazer_check_in': 3,
      'confirmar_conclusao': 4,
    };
    const etapaDoEstado = {
      'orcamento_aceito': 0,
      'pago_e_retido': 0,
      'agendado': 1,
      'em_andamento': 3,
      'em_confirmacao': 3,
      'concluido': 5,
    };
    const titulos = ['Contratado', 'A caminho', 'Chegou', 'Em execução', 'Finalizado'];
    final atual = etapaDoEstado[pedido.estado] ?? 0;
    final quando = <int, DateTime>{};
    for (final e in eventos) {
      final etapa = etapaDaAcao[e.acao];
      if (etapa != null) quando[etapa] = e.em.toLocal();
    }
    // O check-in cobre "Chegou" e "Em execução" no backend (uma ação só).
    final checkIn = quando[3];
    if (checkIn != null) quando[2] = checkIn;
    final etapas = [
      for (var i = 0; i < titulos.length; i++)
        EtapaLinhaDoTempo(
          titulo: titulos[i],
          detalhe: quando[i] != null ? '${_dia(quando[i]!)} · ${_hora(quando[i]!)}' : '',
          estado: i < atual
              ? EstadoEtapa.feita
              : i == atual
                  ? EstadoEtapa.atual
                  : EstadoEtapa.futura,
        ),
    ];
    return PedidoEmExecucao(
      numero: pedido.numero,
      titulo: 'Serviço em execução',
      etapas: etapas,
      fotos: const [],
      codigoInicio: pedido.codigoInicio,
    );
  }

  @override
  Future<ResumoConclusao> conclusao(String pedidoId) async {
    final pedido = await _pedido(pedidoId);
    final saldo = await _saldo(pedidoId);
    return ResumoConclusao(
      numeroPedido: pedido.numero,
      nomeProfissional: 'O profissional',
      legendaFotoAntes: 'Antes',
      legendaFotoDepois: 'Depois',
      orcamentoCentavos: saldo.clientePagouCentavos,
      aditivoCentavos: 0,
      codigo: pedido.codigoConclusao ?? '',
      avisoLiberacao: 'Depois da sua confirmação, a liberação segue as regras do pedido.',
    );
  }

  @override
  Future<void> confirmarConclusao(String pedidoId) async {
    await _api.post('/v1/pedidos/$pedidoId/acoes/confirmar_conclusao', corpo: <String, Object?>{});
  }

  @override
  Future<DadosRelatoProblema> dadosRelato(String pedidoId) async {
    final pedido = await _pedido(pedidoId);
    final saldo = await _saldo(pedidoId);
    return DadosRelatoProblema(
      titulo: 'Pedido ${pedido.numero}',
      valorCongeladoCentavos: saldo.retidoCentavos + saldo.aLiberarCentavos,
      motivos: textos.motivos,
      solucoes: textos.solucoes,
      prazoRespostaHoras: textos.prazoRespostaHoras,
      nomeProfissional: 'O profissional',
    );
  }

  @override
  Future<void> relatarProblema(String pedidoId, EnvioRelato relato) async {
    final indice = textos.motivos.indexOf(relato.motivo);
    await _api.post(
      '/v1/pedidos/$pedidoId/disputa',
      corpo: {
        'motivo': _motivosDisputa[indice < 0 ? 0 : indice],
        'descricao': '${relato.descricao}\n\nSolução que o cliente prefere: ${relato.solucao}',
        'fotos': <Object?>[],
      },
    );
  }

  /// `POST /v1/contratos/{id}/avaliacao`. A nota geral é a média das notas dadas por critério
  /// (arredondada, de 1 a 5). Gorjeta não tem rota: em vez de sumir em silêncio, recusa.
  @override
  Future<void> avaliar(String pedidoId, EnvioAvaliacao avaliacao) async {
    if (avaliacao.gorjetaCentavos > 0) {
      throw const ErroTrato(
        TipoErro.recusado,
        'A gorjeta ainda não está disponível. Envie a avaliação sem gorjeta.',
      );
    }
    final dadas = [for (final n in avaliacao.notas) if (n > 0) n];
    if (dadas.isEmpty) {
      throw const ErroTrato(TipoErro.recusado, 'Dê uma nota de 1 a 5 antes de enviar.');
    }
    final media = (dadas.reduce((a, b) => a + b) / dadas.length).round().clamp(1, 5);
    final comentario = avaliacao.comentario.trim();
    await _api.post(
      '/v1/contratos/$pedidoId/avaliacao',
      corpo: {'nota_geral': media, if (comentario.isNotEmpty) 'comentario': comentario},
    );
  }

  @override
  Future<DadosAvaliacao> dadosAvaliacao(String pedidoId) async {
    final saldo = await _saldo(pedidoId);
    return DadosAvaliacao(
      nomeProfissional: 'O profissional',
      valorLiberadoCentavos: saldo.clientePagouCentavos,
      criterios: textos.criterios,
      gorjetasCentavos: textos.gorjetas,
    );
  }

  /// `GET /v1/contratos/{id}/garantia`. Os dias e as datas são do backend; aqui só se mostra
  /// quanto falta até `fim_em`.
  @override
  Future<DadosGarantia> garantia(String pedidoId) async {
    final j = _mapa(await _api.get('/v1/contratos/$pedidoId/garantia'));
    if (j['iniciada'] != true) {
      throw const ErroTrato(
        TipoErro.recusado,
        'A garantia começa quando o serviço for concluído.',
      );
    }
    final fim = DateTime.parse(j['fim_em'] as String);
    final falta = fim.toLocal().difference(DateTime.now()).inDays;
    return DadosGarantia(
      titulo: 'Garantia do pedido ${PedidoApi.numeroDe(pedidoId)}',
      diasTotal: (j['dias'] as int?) ?? 0,
      diasRestantes: falta < 0 ? 0 : falta,
      fimEm: fim.toLocal(),
      cobre: textos.garantiaCobre,
      naoCobre: textos.garantiaNaoCobre,
      prazoAtendimentoDias: textos.prazoAtendimentoRetrabalhoDias,
    );
  }

  @override
  Future<void> pedirRetrabalho(String pedidoId, String descricao) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/retrabalho',
      corpo: {'descricao': descricao, 'fotos': <Object?>[]},
    );
  }
}

class RepositorioOrcamentosApi implements RepositorioOrcamentos {
  RepositorioOrcamentosApi(this._api);

  final ClienteApi _api;

  /// `GET /v1/pedidos/{id}/orcamentos` (do mais barato ao mais caro) e, para cada um,
  /// `GET /v1/orcamentos/{id}` (itens, validade, fora do escopo). Falha no detalhe de um
  /// orçamento não derruba a lista: ele só aparece sem detalhe.
  @override
  Future<OrcamentosDoPedido> listar(String pedidoId) async {
    final pedido = PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$pedidoId')));
    final brutos = _lista(await _api.get('/v1/pedidos/$pedidoId/orcamentos'));
    final detalhes = await Future.wait([
      for (final j in brutos) _detalhe(j['id'] as String),
    ]);
    return OrcamentosDoPedido(
      pedido: ResumoPedido(
        numero: PedidoApi.numeroDe(pedido.id).substring(1),
        titulo: 'Pedido ${pedido.numero}',
        recebidos: brutos.length,
        limite: brutos.length,
        tempoRestante: '',
      ),
      orcamentos: [
        for (var i = 0; i < brutos.length; i++) _orcamento(brutos[i], detalhes[i]),
      ],
    );
  }

  Future<DetalheOrcamento?> _detalhe(String id) async {
    try {
      final j = _mapa(await _api.get('/v1/orcamentos/$id'));
      final itens = [
        for (final i in (j['itens'] as List? ?? const []).cast<Map<String, dynamic>>())
          ItemOrcamento(
            descricao: i['descricao'] as String,
            centavos: i['total_centavos'] as int,
          ),
      ];
      final validade = j['validade_ate'] as String?;
      final garantia = j['garantia_dias'] as int?;
      final prazo = j['prazo_execucao_dias'] as int?;
      return DetalheOrcamento(
        validoAte: validade == null ? '' : _dia(DateTime.parse(validade).toLocal()),
        itens: itens,
        notaMaterial: _sinalMaterial(j['sinal_material_centavos'] as int?),
        agendaTitulo: prazo == null ? '' : 'Prazo de execução',
        agendaDetalhe: prazo == null ? '' : '$prazo ${prazo == 1 ? 'dia' : 'dias'}',
        garantiaTitulo: garantia == null ? '' : 'Garantia',
        garantiaDetalhe: garantia == null ? '' : '$garantia dias',
        foraDoEscopo: (j['fora_do_escopo'] as String?) ?? '',
        cancelamento: '',
      );
    } on ErroTrato catch (erro) {
      if (erro.tipo == TipoErro.sessaoExpirada) rethrow;
      return null;
    }
  }

  String _sinalMaterial(int? centavos) => centavos == null || centavos == 0
      ? ''
      : 'Sinal de material: R\$ ${(centavos ~/ 100)},${(centavos % 100).toString().padLeft(2, '0')}';

  Orcamento _orcamento(Map<String, dynamic> j, DetalheOrcamento? detalhe) {
    final nome = (j['profissional_nome'] as String?) ?? 'Profissional';
    final enviado = j['enviado_em'] as String?;
    final enviadoEm = enviado == null ? DateTime.now() : DateTime.parse(enviado);
    final garantia = j['garantia_dias'] as int?;
    return Orcamento(
      id: j['id'] as String,
      profissional: nome,
      iniciais: _iniciais(nome),
      // A API de orçamentos ainda não devolve selo, nota nem total de serviços do profissional.
      verificacao: '',
      totalCentavos: j['valor_centavos'] as int,
      nota: 0,
      notaResumo: '—',
      servicosResumo: '—',
      servicosConcluidos: 0,
      quando: _quandoRelativo(enviadoEm),
      inicio: enviadoEm,
      garantia: garantia == null ? '' : '$garantia dias',
      observacao: (j['observacoes'] as String?) ?? '',
      detalhe: detalhe,
    );
  }

  @override
  Future<void> aceitar(String pedidoId, String orcamentoId) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/acoes/aceitar_orcamento',
      corpo: {
        'prova': {'orcamento_id': orcamentoId},
      },
    );
  }
}

/// Pagamento. O app só pede a cobrança e consulta; "pago" é só o que o backend diz, depois do
/// webhook assinado do provedor (D13).
class RepositorioPagamentoApi implements RepositorioPagamento {
  RepositorioPagamentoApi(this._api);

  final ClienteApi _api;

  /// `GET /v1/pedidos/{id}/pagamento`: valor do contrato e meios disponíveis (`pix`, `cartao`).
  @override
  Future<DadosPagamento> dados(String pedidoId) async {
    final j = _mapa(await _api.get('/v1/pedidos/$pedidoId/pagamento'));
    final valor = j['valor_centavos'] as int?;
    if (valor == null) {
      throw const ErroTrato(TipoErro.recusado, 'Este pedido ainda não tem um valor a pagar.');
    }
    final meios = [for (final m in (j['meios_disponiveis'] as List)) m as String];
    return DadosPagamento(
      subtitulo: 'Pedido ${PedidoApi.numeroDe(pedidoId)}',
      valorAgoraCentavos: valor,
      opcoes: [
        if (meios.contains('pix'))
          const OpcaoPagamento(
            metodo: MetodoPagamento.pix,
            titulo: 'Pix',
            descricao: 'Você copia o código e paga no app do seu banco.',
          ),
        if (meios.contains('cartao'))
          const OpcaoPagamento(
            metodo: MetodoPagamento.cartao,
            titulo: 'Cartão',
            descricao: 'Pagamento seguro pelo provedor.',
          ),
      ],
    );
  }

  /// `POST /v1/contratos/{id}/cobranca` `{meio}`. Repetir devolve a mesma cobrança pendente.
  /// O segredo do cartão (`instrucao`) nunca vai para a tela.
  @override
  Future<Cobranca> criarCobranca(String pedidoId, MetodoPagamento metodo) async {
    final meio = metodo == MetodoPagamento.pix ? 'pix' : 'cartao';
    final j = _mapa(
      await _api.post(
        '/v1/contratos/$pedidoId/cobranca',
        corpo: {'meio': meio},
        chaveIdempotencia: 'cobranca-$pedidoId-$meio',
      ),
    );
    return Cobranca(
      id: j['cobranca_id'] as String,
      pixCopiaECola: j['tipo_instrucao'] == 'pix_copia_e_cola' ? j['instrucao'] as String? : null,
    );
  }

  /// `GET /v1/contratos/{id}/pagamento`. Só `pago: true` vira [StatusPagamento.pago].
  @override
  Future<StatusPagamento> status(String pedidoId) async {
    final j = _mapa(await _api.get('/v1/contratos/$pedidoId/pagamento'));
    if (j['pago'] == true) return StatusPagamento.pago;
    final estado = j['estado_pagamento'] as String?;
    if (estado == 'falhou' || estado == 'cancelada') return StatusPagamento.falhou;
    return StatusPagamento.aguardando;
  }
}

/// `GET/POST /v1/pedidos/{id}/mensagens`. Telefone e e-mail já saem mascarados do backend.
class RepositorioChatApi implements RepositorioChat {
  RepositorioChatApi(this._api, {this.textos = const TextosPadraoTelas()});

  final ClienteApi _api;
  final TextosPadraoTelas textos;

  @override
  Future<ConversaPedido> conversa(String pedidoId) async {
    final pedido = PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$pedidoId')));
    final mensagens = _lista(await _api.get('/v1/pedidos/$pedidoId/mensagens'));
    return ConversaPedido(
      nome: 'Pedido ${pedido.numero}',
      iniciais: '#',
      numeroPedido: pedido.numero,
      situacao: pedido.estadoNome,
      mensagens: [
        for (final m in mensagens)
          MensagemChat(
            tipo: TipoMensagem.texto,
            hora: _hora(DateTime.parse(m['enviada_em'] as String).toLocal()),
            texto: m['texto'] as String,
            minha: m['minha'] == true,
            lida: m['lida_em'] != null,
          ),
      ],
      respostasRapidas: textos.respostasRapidas,
    );
  }

  @override
  Future<void> enviar(String pedidoId, String texto) async {
    await _api.post('/v1/pedidos/$pedidoId/mensagens', corpo: {'texto': texto});
  }
}

/// `GET /v1/notificacoes`. Marcar como lida, preferências e registro do token de push não
/// têm rota no backend (`docs/app-divergencias.md`).
class RepositorioNotificacoesApi implements RepositorioNotificacoes {
  RepositorioNotificacoesApi(this._api);

  final ClienteApi _api;

  @override
  Future<List<Notificacao>> listar() async {
    final itens = _lista(await _api.get('/v1/notificacoes'));
    return [
      for (final n in itens)
        Notificacao(
          id: n['id'] as String,
          titulo: n['titulo'] as String,
          texto: (n['corpo'] as String?) ?? '',
          quando: _quandoRelativo(DateTime.parse(n['criada_em'] as String)),
          lida: n['lida'] == true,
          tipo: n['tipo'] as String?,
          destinoId: _destino(n['dados']),
        ),
    ];
  }

  String? _destino(Object? dados) {
    if (dados is! Map) return null;
    final id = dados['disputa_id'] ?? dados['pedido_id'];
    return id is String ? id : null;
  }
}

/// `GET` e `PATCH /v1/me`. O primeiro `GET /v1/me` depois do login cria o usuário no backend.
class RepositorioPerfilApi implements RepositorioPerfil {
  RepositorioPerfilApi(this._api);

  final ClienteApi _api;

  @override
  Future<PerfilCliente> carregar() async {
    final j = _mapa(await _api.get('/v1/me'));
    final nome = (j['nome'] as String?)?.trim();
    final nota = j['nota_publica'] as num?;
    final concluidos = j['servicos_concluidos'] as int?;
    final partes = [
      if (nota != null) 'Nota ${nota.toStringAsFixed(1).replaceAll('.', ',')}',
      if (concluidos != null) '$concluidos ${concluidos == 1 ? 'serviço' : 'serviços'}',
    ];
    return PerfilCliente(
      nome: (nome == null || nome.isEmpty) ? 'Sua conta' : nome,
      iniciais: _iniciais(nome ?? ''),
      resumo: partes.join(' · '),
      grupos: const [
        GrupoPerfil(
          titulo: 'SEGURANÇA E AVISOS',
          itens: [
            ItemPerfil(acao: AcaoPerfil.notificacoes, titulo: 'Notificações'),
            ItemPerfil(acao: AcaoPerfil.usarComoProfissional, titulo: 'Usar como profissional'),
          ],
        ),
        GrupoPerfil(
          titulo: 'PRIVACIDADE E AJUDA',
          itens: [
            ItemPerfil(acao: AcaoPerfil.meusDados, titulo: 'Meus dados (LGPD)'),
            ItemPerfil(acao: AcaoPerfil.centralAjuda, titulo: 'Central de ajuda'),
          ],
        ),
      ],
    );
  }

  /// `PATCH /v1/me` `{nome}` (2 a 120 caracteres). Devolve o nome salvo.
  Future<String?> atualizarNome(String nome) async {
    final j = _mapa(await _api.patch('/v1/me', corpo: {'nome': nome}));
    return j['nome'] as String?;
  }
}

class RepositorioProfissionalApi implements RepositorioProfissional {
  RepositorioProfissionalApi(
    this._api, {
    this.captura = const CapturaIndisponivel(),
    this.capturaDoPedido,
    this.upload,
    this.fila,
  });

  final ClienteApi _api;
  final CapturaCheckIn captura;

  /// Câmera e GPS ligados ao pedido (a foto sobe com o `pedido_id`). Sem ele vale [captura].
  final CapturaCheckIn Function(String pedidoId)? capturaDoPedido;
  final ServicoUpload? upload;
  final FilaOffline? fila;

  /// `GET /v1/profissional/pedidos-abertos`. O backend já filtra por categoria, cidade, bairro,
  /// faixa de preço e recusas; não vêm distância, nem quantos já orçaram.
  @override
  Future<List<PedidoAberto>> pedidosAbertos(FiltroPedidosAbertos filtro) async {
    final itens = _lista(await _api.get('/v1/profissional/pedidos-abertos', consulta: filtro.consulta));
    return [for (final j in itens) _pedidoAberto(j)];
  }

  PedidoAberto _pedidoAberto(Map<String, dynamic> j) {
    final prazo = j['prazo_desejado'] as String?;
    final urgente = j['urgente'] == true;
    return PedidoAberto(
      id: j['id'] as String,
      titulo: j['titulo'] as String,
      bairro: (j['bairro'] as String?) ?? '',
      prazo: urgente
          ? 'urgente'
          : prazo == null
              ? 'sem data'
              : 'até ${_dia(DateTime.parse(prazo))}',
      faixaMinCentavos: j['faixa_preco_min_centavos'] as int?,
      faixaMaxCentavos: j['faixa_preco_max_centavos'] as int?,
      urgente: urgente,
    );
  }

  /// Início = nome (`/v1/me`) + pedidos abertos + próximo atendimento (`/v1/pedidos`). A
  /// carteira da Início não tem rota (D15: só extrato): fica zerada.
  @override
  Future<InicioProfissional> inicio() async {
    final me = _mapa(await _api.get('/v1/me'));
    final abertos = await pedidosAbertos(const FiltroPedidosAbertos(limite: 20));
    ProximoAtendimento? proximo;
    try {
      final meus = [for (final j in _lista(await _api.get('/v1/pedidos'))) PedidoApi.deJson(j)];
      for (final p in meus) {
        if (const {'pago_e_retido', 'agendado', 'em_andamento'}.contains(p.estado)) {
          proximo = ProximoAtendimento(
            pedidoId: p.id,
            quando: p.estadoNome,
            titulo: 'Pedido ${p.numero}',
            endereco: '',
          );
          break;
        }
      }
    } on ErroTrato catch (erro) {
      if (erro.tipo == TipoErro.sessaoExpirada) rethrow;
    }
    return InicioProfissional(
      nome: ((me['nome'] as String?) ?? '').split(' ').first,
      disponivelAgora: true,
      carteira: const ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0),
      pedidos: abertos,
      proximo: proximo,
    );
  }

  /// Não há rota de detalhe do pedido aberto: o detalhe sai da própria lista.
  @override
  Future<DetalhePedido> detalhe(String pedidoId) async {
    final itens = _lista(await _api.get('/v1/profissional/pedidos-abertos'));
    final achado = itens.where((j) => j['id'] == pedidoId).toList();
    if (achado.isEmpty) {
      throw const ErroTrato(TipoErro.naoEncontrado, 'Este pedido não está mais disponível.');
    }
    final j = achado.first;
    final aberto = _pedidoAberto(j);
    return DetalhePedido(
      pedido: aberto,
      fechaEm: 'Aberto ${_quandoRelativo(DateTime.parse(j['aberto_em'] as String))}',
      clienteResumo: '',
      legendasFotos: const [],
      descricao: (j['descricao'] as String?) ?? '',
      linhas: [if (aberto.bairro.isNotEmpty) LinhaDetalhe('Bairro', aberto.bairro)],
    );
  }

  /// `POST /v1/pedidos/{id}/recusar` `{motivo}`. Não avisa o cliente; repetir é seguro.
  @override
  Future<void> recusar(String pedidoId, MotivoRecusa motivo) async {
    await _api.post('/v1/pedidos/$pedidoId/recusar', corpo: {'motivo': motivo.texto});
  }

  /// Extrato do ledger (D15). Cada lançamento vira uma linha; o app não soma nada.
  @override
  Future<List<ItemExtrato>> extrato() async {
    final json = _mapa(await _api.get('/v1/extrato', consulta: {'limite': '50'}));
    return [
      for (final l in ExtratoApi.deJson(json).itens)
        ItemExtrato(
          titulo: 'Pedido ${_curto(l.pedidoId)} · ${l.tipo.replaceAll('_', ' ')}',
          detalheData: _dia(l.data.toLocal()),
          brutoCentavos: l.valorCentavos,
          textoTaxa: l.estornoDe != null ? 'Estorno' : 'Lançamento do ledger',
          liquidoCentavos: l.valorCentavos,
          status: StatusExtrato.liberado,
        ),
    ];
  }

  String _curto(String id) => '#${id.substring(0, id.length < 4 ? id.length : 4).toUpperCase()}';

  @override
  ServicoOrcamento servicoOrcamento(String pedidoId) => ServicoOrcamentoApi(_api);

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId) =>
      ServicoCheckInApi(
        _api,
        pedidoId: pedidoId,
        captura: capturaDoPedido?.call(pedidoId) ?? captura,
        upload: upload,
        fila: fila,
      );
}

/// `POST /v1/orcamentos/resumo` `{valor_centavos}`. Taxa e líquido vêm do backend; o app não
/// calcula nada (a taxa em % não vem na resposta, então a tela mostra só "Taxa Trato").
class ServicoOrcamentoApi implements ServicoOrcamento {
  ServicoOrcamentoApi(this._api);

  final ClienteApi _api;

  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async {
    final j = _mapa(
      await _api.post('/v1/orcamentos/resumo', corpo: {'valor_centavos': totalCentavos}),
    );
    return ResumoOrcamento(
      totalCentavos: j['valor_centavos'] as int,
      taxaCentavos: j['taxa_centavos'] as int,
      liquidoCentavos: j['liquido_centavos'] as int,
    );
  }
}

/// Foto do check-in. Com [arquivoId] ela já está no armazenamento; sem ele (sem internet na
/// hora) o arquivo fica em [local] e é enviado depois.
class FotoCapturada {
  const FotoCapturada({this.arquivoId, required this.tiradaEm, this.local});

  final String? arquivoId;

  /// Relógio do aparelho; a hora válida é a do servidor.
  final DateTime tiradaEm;
  final ArquivoCapturado? local;

  bool get pendente => arquivoId == null;
}

class PosicaoCapturada {
  const PosicaoCapturada(this.latitude, this.longitude, {this.distanciaMetros});

  final double latitude;
  final double longitude;

  /// Distância até o endereço, só para mostrar. Quem confere é o backend.
  final int? distanciaMetros;
}

/// Câmera e GPS do aparelho. O app captura e envia; o backend valida a prova.
abstract interface class CapturaCheckIn {
  Future<FotoCapturada?> foto();
  Future<PosicaoCapturada?> posicao();
}

/// Sem câmera e GPS (demonstração): nada é capturado.
class CapturaIndisponivel implements CapturaCheckIn {
  const CapturaIndisponivel();

  @override
  Future<FotoCapturada?> foto() async => null;

  @override
  Future<PosicaoCapturada?> posicao() async => null;
}

class ServicoCheckInApi implements ServicoCheckIn {
  ServicoCheckInApi(
    this._api, {
    required this.pedidoId,
    required this.captura,
    this.upload,
    this.fila,
  });

  final ClienteApi _api;
  final String pedidoId;
  final CapturaCheckIn captura;

  /// Necessário para enviar foto capturada sem internet.
  final ServicoUpload? upload;

  /// Se houver, check-in e check-out feitos sem internet ficam guardados e saem depois.
  final FilaOffline? fila;
  FotoCapturada? _foto;
  PosicaoCapturada? _posicao;

  @override
  Future<FotoChegada?> tirarFoto() async {
    final foto = _foto = await captura.foto();
    return foto == null ? null : FotoChegada(hora: _hora(foto.tiradaEm.toLocal()));
  }

  /// A conferência é do backend; a distância aqui, quando existe, é só informativa.
  @override
  Future<int?> localizar() async {
    final posicao = _posicao = await captura.posicao();
    return posicao?.distanciaMetros;
  }

  // Sem rota no backend: mensagens rápidas e aviso de cliente ausente.
  @override
  Future<void> enviarMensagemRapida(String mensagem) async => throw ErroTrato.indisponivel;

  @override
  Future<void> avisarClienteAusente() async => throw ErroTrato.indisponivel;

  Map<String, Object?> _fotoJson(FotoCapturada f) =>
      {'arquivo_id': f.arquivoId, 'tirada_em': f.tiradaEm.toUtc().toIso8601String()};

  Future<FotoCapturada> _enviada(FotoCapturada f, FinalidadeArquivo finalidade) async {
    if (!f.pendente) return f;
    final envio = upload;
    final arquivo = f.local;
    if (envio == null || arquivo == null) throw ErroTrato.semInternet;
    final r = await envio.enviar(arquivo, finalidade, pedidoId: pedidoId);
    return FotoCapturada(arquivoId: r.arquivoId, tiradaEm: f.tiradaEm);
  }

  Future<void> _postar(AcaoOffline a, {required bool tardio}) async {
    final fin =
        a.tipo == TipoAcaoOffline.checkIn ? FinalidadeArquivo.checkIn : FinalidadeArquivo.checkOut;
    final foto = await _enviada(a.foto, fin);
    final posicao = a.posicao;
    final Map<String, Object?> prova = a.tipo == TipoAcaoOffline.checkIn
        ? {
            'foto': _fotoJson(foto),
            'localizacao': {'latitude': posicao!.latitude, 'longitude': posicao.longitude},
            'codigo_inicio': a.codigo,
          }
        : {'foto_final': _fotoJson(foto), 'codigo_conclusao': a.codigo};
    // Quando a prova foi feita sem internet, o servidor recebe a hora do aparelho como dica
    // (`offline_capturada_em`). A hora que vale é sempre a do servidor.
    if (tardio || a.foto.pendente) {
      prova['offline_capturada_em'] = a.foto.tiradaEm.toUtc().toIso8601String();
    }
    final acao = a.tipo == TipoAcaoOffline.checkIn ? 'fazer_check_in' : 'fazer_check_out';
    await _api.post('/v1/pedidos/$pedidoId/acoes/$acao', corpo: {'prova': prova});
  }

  /// Guarda para enviar depois, se houver fila. Devolve se guardou.
  bool _guardar(AcaoOffline a) {
    final f = fila;
    if (f == null) return false;
    f.guardar(a);
    return true;
  }

  @override
  Future<ResultadoInicio> iniciarServico(String codigo) async {
    final foto = _foto;
    final posicao = _posicao;
    if (foto == null || posicao == null) {
      throw const ErroTrato(
        TipoErro.recusado,
        'Tire a foto de chegada e permita a localização antes de iniciar.',
      );
    }
    final acao = AcaoOffline(
      pedidoId: pedidoId,
      tipo: TipoAcaoOffline.checkIn,
      codigo: codigo,
      foto: foto,
      posicao: posicao,
    );
    try {
      await _postar(acao, tardio: false);
      return ResultadoInicio.iniciado;
    } on ErroTrato catch (erro) {
      if (erro.tipo == TipoErro.semInternet && _guardar(acao)) {
        return ResultadoInicio.guardadoOffline;
      }
      // O backend recusou a prova (código errado, longe do local...): o app não decide.
      if (erro.tipo == TipoErro.recusado) {
        return ResultadoInicio.codigoIncorreto;
      }
      rethrow;
    }
  }

  /// Check-out: foto final e código de conclusão que o cliente informa. Devolve `false` se
  /// ficou guardado para enviar quando a internet voltar.
  Future<bool> fazerCheckOut({required FotoCapturada fotoFinal, required String codigo}) async {
    final acao = AcaoOffline(
      pedidoId: pedidoId,
      tipo: TipoAcaoOffline.checkOut,
      codigo: codigo,
      foto: fotoFinal,
    );
    try {
      await _postar(acao, tardio: false);
      return true;
    } on ErroTrato catch (erro) {
      if (erro.tipo == TipoErro.semInternet && _guardar(acao)) return false;
      rethrow;
    }
  }

  /// Tenta enviar o que ficou guardado deste pedido. Devolve quantas ações saíram. Chamar ao
  /// abrir a tela e quando a conexão voltar. Ação recusada pelo backend sai da fila.
  Future<int> reenviarPendentes() async {
    final f = fila;
    if (f == null) return 0;
    var enviadas = 0;
    for (final a in f.pendentes.where((a) => a.pedidoId == pedidoId).toList()) {
      try {
        await _postar(a, tardio: true);
        f.remover(a);
        enviadas++;
      } on ErroTrato catch (erro) {
        if (erro.tipo == TipoErro.semInternet) break;
        if (erro.tipo == TipoErro.recusado) f.remover(a);
        if (erro.tipo != TipoErro.recusado) rethrow;
      }
    }
    return enviadas;
  }
}

/// Check-out: foto final + código de conclusão. O app envia; o backend confere.
class ServicoCheckOutApi implements ServicoCheckOut {
  ServicoCheckOutApi(this._checkIn, this._captura);

  final ServicoCheckInApi _checkIn;
  final CapturaCheckIn _captura;
  FotoCapturada? _foto;

  @override
  Future<FotoChegada?> tirarFotoFinal() async {
    final foto = _foto = await _captura.foto();
    return foto == null ? null : FotoChegada(hora: _hora(foto.tiradaEm.toLocal()));
  }

  @override
  Future<ResultadoFim> finalizar(String codigo) async {
    final foto = _foto;
    if (foto == null) {
      throw const ErroTrato(TipoErro.recusado, 'Tire a foto final antes de concluir.');
    }
    try {
      final enviado = await _checkIn.fazerCheckOut(fotoFinal: foto, codigo: codigo);
      return enviado ? ResultadoFim.concluido : ResultadoFim.guardadoOffline;
    } on ErroTrato catch (erro) {
      if (erro.tipo == TipoErro.recusado) return ResultadoFim.codigoIncorreto;
      rethrow;
    }
  }
}
