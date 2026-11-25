import 'package:flutter/material.dart';

import '../auth/servico_auth.dart';
import '../componentes/componentes.dart';
import '../telas/agenda/modelos.dart';
import '../telas/cliente/modelos.dart';
import '../telas/comuns/foco_rolagem.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/servicos/modelos.dart';
import 'cliente_api.dart';
import 'config_publica.dart';
import 'erros.dart';
import 'modelos_api.dart';
import 'repositorios.dart';
import 'repositorios_api.dart' show RepositorioPedidosApi, seloDeVerificacao;
import 'repositorios_catalogo.dart';
import 'servicos_api.dart' show servicoDaAvaliacao;
import 'paralelo.dart';

// IMPLEMENTAÇÕES QUE FALAM COM A API (modo `api`) do catálogo, dos serviços e da agenda.
// Só o que o backend já tem sai da API; o resto segue em demonstração e está listado em
// `docs/app-ligacao.md`.

String _doisDigitos(int n) => n.toString().padLeft(2, '0');
String _dia(DateTime d) => '${_doisDigitos(d.day)}/${_doisDigitos(d.month)}';

Map<String, dynamic> _mapa(Object? json) => json! as Map<String, dynamic>;
List<Map<String, dynamic>> _lista(Object? json) =>
    [for (final item in (json as List? ?? const [])) item as Map<String, dynamic>];

/// Ícone de cada categoria pelo slug (o backend não manda ícone). Categoria nova usa o genérico.
/// Os slugs são os de `public.categorias`; os curtos antigos ficam para não quebrar dados velhos.
IconData iconeDaCategoria(String? slug) => switch (slug) {
      'eletricista' || 'eletrica' => Icons.bolt,
      'encanador' || 'hidraulica' => Icons.water_drop_outlined,
      'pintura-interna' || 'pintura' => Icons.format_paint_outlined,
      'montagem-de-moveis' || 'montagem' => Icons.chair_outlined,
      'limpeza-residencial' || 'limpeza' => Icons.cleaning_services_outlined,
      'diarista' => Icons.home_outlined,
      'limpeza-especial' => Icons.weekend_outlined,
      'ar-condicionado' => Icons.ac_unit,
      'chaveiro' => Icons.vpn_key_outlined,
      'jardinagem' => Icons.yard_outlined,
      'reparos-gerais' => Icons.handyman_outlined,
      'reformas' => Icons.construction_outlined,
      'cameras-seguranca' => Icons.videocam_outlined,
      'cortinas-persianas' => Icons.blinds_outlined,
      'gesso-drywall' => Icons.view_quilt_outlined,
      'impermeabilizacao' => Icons.umbrella_outlined,
      'informatica-redes' => Icons.router_outlined,
      'eletrodomesticos' => Icons.kitchen_outlined,
      'marcenaria' => Icons.carpenter_outlined,
      'mudanca-frete' => Icons.local_shipping_outlined,
      'pisos-revestimentos' => Icons.grid_on_outlined,
      'serralheria' => Icons.hardware_outlined,
      'vidraceiro' => Icons.window_outlined,
      _ => Icons.home_repair_service_outlined,
    };

String _iniciais(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  final primeira = partes.first[0].toUpperCase();
  return partes.length == 1 ? primeira : primeira + partes.last[0].toUpperCase();
}

/// Catálogo ligado à API real (`GET /v1/catalogo/categorias`, `GET /v1/profissionais` e
/// `GET /v1/profissionais/{id}`).
class RepositorioCatalogoApi implements RepositorioCatalogo {
  RepositorioCatalogoApi(this._api);

  final ClienteApi _api;
  Future<List<CategoriaServico>>? _categoriasEmVoo;

  /// Só o que está no banco, em ordem alfabética PT-BR. Sem rede, o erro vai para a tela ("Tentar de novo").
  @override
  Future<List<CategoriaServico>> categorias() {
    final ativo = _categoriasEmVoo;
    if (ativo != null) return ativo;
    final busca = _carregarCategorias();
    _categoriasEmVoo = busca;
    return busca.whenComplete(() {
      if (identical(_categoriasEmVoo, busca)) _categoriasEmVoo = null;
    });
  }

  Future<List<CategoriaServico>> _carregarCategorias() async {
    final resposta = await _api.get('/v1/catalogo/categorias');
    final itens = (resposta as List? ?? const []).cast<Map<String, dynamic>>();
    _nomesCategorias = {
      for (final c in itens)
        if (c['id'] is String && c['nome'] is String) c['id'] as String: c['nome'] as String,
    };
    _nomesCarregadosEm = DateTime.now();
    final lista = [
      for (final item in itens)
        CategoriaServico(
          (item['nome'] as String?) ?? 'Serviço',
          iconeDaCategoria((item['slug'] as String?) ?? (item['id'] as String?)),
          id: (item['id'] as String?) ?? (item['slug'] as String?) ?? '',
          aceitaRemoto: item['aceita_remoto'] == true,
        ),
    ];
    lista.sort((a, b) => compararAlfabeticoPtBr(a.nome, b.nome));
    return lista;
  }

  Map<String, String>? _nomesCategorias;
  DateTime? _nomesCarregadosEm;

  /// A API devolve as categorias do profissional como id; a tela mostra o nome (cache com TTL de 2 min).
  Future<void> _carregarNomesCategorias() async {
    final ultima = _nomesCarregadosEm;
    if (_nomesCategorias != null &&
        ultima != null &&
        DateTime.now().difference(ultima) < const Duration(minutes: 2)) {
      return;
    }
    try {
      final resposta = await _api.get('/v1/catalogo/categorias');
      if (resposta is List) {
        _nomesCategorias = {
          for (final c in resposta)
            if (c is Map && c['id'] is String && c['nome'] is String)
              c['id'] as String: c['nome'] as String,
        };
        _nomesCarregadosEm = DateTime.now();
      }
    } on ErroTrato {
      // Sem os nomes, a especialidade só fica em branco; a lista continua.
    }
  }

  String _especialidade(List<Object?> ids) => [
        for (final c in ids)
          if (_nomesCategorias?[c] != null) _nomesCategorias![c]!,
      ].join(', ');

  Profissional _converterBusca(Map<String, dynamic> j) {
    final id = (j['id'] as String?) ?? '';
    final nome = (j['nome'] as String?) ?? 'Profissional';
    final nivel = (j['nivel_verificacao'] as String?) ?? '';
    final categorias = (j['categorias'] as List?) ?? const <Object?>[];
    final notaPublica = (j['nota_publica'] as num?)?.toDouble() ?? 0.0;
    final servicosConcluidos = (j['servicos_concluidos'] as int?) ?? 0;
    final cidades = [for (final c in (j['cidades'] as List? ?? const [])) '$c']
        .where((c) => c.trim().isNotEmpty)
        .toList();
    final bairros = [for (final b in (j['bairros'] as List? ?? const [])) '$b']
        .where((b) => b.trim().isNotEmpty)
        .toList();
    final atendeRemoto = j['atende_remoto'] == true;
    final regiao = [
      if (bairros.isNotEmpty) bairros.first,
      if (cidades.isNotEmpty) cidades.first,
      if (bairros.isEmpty && cidades.isEmpty && atendeRemoto) 'Atende remoto',
    ].join(' · ');
    return Profissional(
      id: id,
      nome: nome,
      iniciais: _iniciais(nome),
      verificacao: seloDeVerificacao(nivel),
      especialidade: _especialidade(categorias),
      servicosConcluidos: servicosConcluidos,
      nota: notaPublica,
      distanciaKm: 0,
      regiao: regiao.isEmpty ? null : regiao,
      categoriaId: categorias.isEmpty ? null : '${categorias.first}',
      categoriasIds: [for (final c in categorias) '$c'],
    );
  }

  @override
  Future<List<Profissional>> profissionais(String categoriaId, FiltroProfissionais filtro) async {
    final consulta = <String, String>{
      'categoria_id': categoriaId,
      if (filtro.bairro != null && filtro.bairro!.isNotEmpty) 'bairro': filtro.bairro!,
      if (filtro.notaMinima != null) 'nota_minima': filtro.notaMinima!.toString(),
      if (filtro.soDisponiveisHoje) 'atende_hoje': 'true',
    };
    final (bruto, _) = await emParalelo2(
      _api.get('/v1/profissionais', consulta: consulta),
      _carregarNomesCategorias(),
    );
    final resposta = _mapa(bruto);
    final meuId = ServicoAuthPadrao.atual.sessaoAtual?.id;
    return [
      for (final item in (resposta['itens'] as List? ?? const []))
        if (item is Map<String, dynamic> && (meuId == null || item['id'] != meuId))
          _converterBusca(item),
    ];
  }

  @override
  Future<List<Profissional>> buscar(String termo, {bool disponivelAgora = false}) async {
    final limpo = termo.trim();
    if (limpo.length < 2) return const [];
    final (bruto, _) = await emParalelo2(
      _api.get('/v1/profissionais', consulta: {
        'q': limpo,
        if (disponivelAgora) 'disponivel_agora': 'true',
      }),
      _carregarNomesCategorias(),
    );
    final resposta = _mapa(bruto);
    final meuId = ServicoAuthPadrao.atual.sessaoAtual?.id;
    return [
      for (final item in (resposta['itens'] as List? ?? const []))
        if (item is Map<String, dynamic> && (meuId == null || item['id'] != meuId))
          _converterBusca(item),
    ];
  }

  /// `GET /v1/catalogo/cidades`. Sem cidades, o pedido não tem onde ser aberto.
  Future<List<CidadeOpcao>> _cidades() async {
    final brutas = await _api.get('/v1/catalogo/cidades');
    return [
      for (final c in (brutas as List? ?? const []))
        if (c is Map && c['id'] is String && c['nome'] is String)
          CidadeOpcao(
            id: c['id'] as String,
            nome: c['nome'] as String,
            uf: (c['uf'] as String?) ?? '',
          ),
    ];
  }

  @override
  Future<FormularioPedido> formulario(String categoriaId) async {
    // Em paralelo. Sem a lista de cidades não dá para abrir o pedido: o erro vira "Tentar de novo".
    final (base, cidades, perguntas) = await emParalelo3(
      _formularioBase(categoriaId),
      _cidades(),
      _perguntas(categoriaId),
    );
    if (cidades.isEmpty) {
      throw const ErroTrato(
        TipoErro.indisponivel,
        'Ainda não atendemos nenhuma cidade. Volte daqui a pouco.',
      );
    }
    return base.comCidades(cidades).comPerguntas(perguntas);
  }

  /// `GET /v1/catalogo/categorias/{id}/perguntas`: as perguntas que o admin configurou.
  /// Sem a rota ou sem rede, o formulário segue com as perguntas genéricas.
  Future<List<PerguntaPedido>> _perguntas(String categoriaId) async {
    try {
      return [
        for (final j in _lista(await _api.get('/v1/catalogo/categorias/$categoriaId/perguntas')))
          PerguntaPedido.deJson(j),
      ];
    } on ErroTrato {
      return const [];
    }
  }

  Future<FormularioPedido> _formularioBase(String categoriaId) async {
    final cats = await categorias();
    final c = cats.where((x) => x.id == categoriaId).firstOrNull;
    return FormularioPedido(
      categoriaId: categoriaId,
      icone: c?.icone ?? Icons.handyman_outlined,
      categoria: c?.nome ?? 'Serviço solicitado',
      servicos: (c?.servicos.isEmpty ?? true) ? const ['Orçamento geral'] : c!.servicos,
      servicosIniciais: {(c?.servicos.isEmpty ?? true) ? 'Orçamento geral' : c!.servicos.first},
      perguntaQuantidade: 'Quantos itens ou ambientes?',
      dicaQuantidade: 'Uma estimativa já ajuda',
      quantidadeInicial: 1,
      perguntaVoltagem: 'Voltagem',
      voltagens: const [],
      voltagemInicial: '',
      descricaoInicial: '',
      fotos: const [],
      prazos: const ['Esta semana', 'Sem pressa'],
      faixas: const [
        FaixaPreco(minimoCentavos: 10000, maximoCentavos: 30000),
        FaixaPreco(minimoCentavos: 30000, maximoCentavos: 80000),
      ],
      endereco: 'Seu endereço atual',
      avisoEndereco: 'O endereço completo só aparece para o profissional contratado.',
      avisoPrazo: 'Você recebe até ${ConfigPublica.atual.limiteOrcamentos} orçamentos em '
          '${ConfigPublica.horas(ConfigPublica.atual.validadePedidoHoras)}.',
      aceitaRemoto: c?.aceitaRemoto ?? false,
    );
  }

  Future<String?> _urlDaFotoDeTrabalho(String profissionalId, Object? descricao) async {
    final achou = RegExp(r'^\[Foto:([^\]]+)\]$').firstMatch('${descricao ?? ''}');
    if (achou == null) return null;
    try {
      final r = _mapa(
        await _api.get('/v1/usuarios/$profissionalId/portfolio/${achou.group(1)}/foto'),
      );
      return r['url'] as String?;
    } on Object {
      return null;
    }
  }

  @override
  Future<Profissional> perfil(String profissionalId) async {
    final (bruto, _) = await emParalelo2(
      _api.get('/v1/profissionais/$profissionalId'),
      _carregarNomesCategorias(),
    );
    final j = _mapa(bruto);
    final nome = (j['nome'] as String?) ?? 'Profissional';
    final nivel = (j['nivel_verificacao'] as String?) ?? '';
    final avaliacoes = [
      for (final a in (j['avaliacoes'] as List? ?? const []))
        () {
          final mapa = a as Map;
          final criterios = Avaliacao.lerCriterios(mapa['criterios']);
          return Avaliacao(
            id: mapa['id'] as String?,
            cliente: (mapa['cliente_nome'] as String?) ?? 'Cliente',
            servico: servicoDaAvaliacao(mapa),
            nota: (mapa['nota_decimal'] is num
                    ? mapa['nota_decimal'] as num
                    : mapa['nota_geral'] as num)
                .toDouble(),
            comentario: (mapa['comentario'] as String?) ?? '',
            detalhes: Avaliacao.formatarCriterios(criterios),
            criterios: criterios,
            etiquetas: [for (final e in (mapa['etiquetas'] as List? ?? const [])) '$e'],
            resposta: mapa['resposta'] as String?,
          );
        }(),
    ];
    final itensPortfolio = [
      for (final p in (j['portfolio'] as List? ?? const [])) p as Map,
    ];
    final portfolio = [for (final p in itensPortfolio) p['titulo'] as String];
    // Foto de cada trabalho em paralelo: `[Foto:<id>]` vira URL assinada.
    final fotosUrls = await Future.wait([
      for (final p in itensPortfolio) _urlDaFotoDeTrabalho(profissionalId, p['descricao']),
    ]);
    final regioes = [
      for (final r in (j['regioes'] as List? ?? const []))
        ((r as Map)['bairro'] ?? r['cidade'] ?? '') as String,
    ].where((r) => r.isNotEmpty).toList();
    // Sem bairro, as cidades em texto ("Divinópolis/MG") que o servidor manda.
    if (regioes.isEmpty) {
      regioes.addAll([for (final c in (j['cidades'] as List? ?? const [])) '$c']);
    }
    final desde = DateTime.tryParse('${j['no_trato_desde']}');
    final notaPublica = (j['nota_publica'] as num?)?.toDouble();
    final categoriasIds = (j['categorias'] as List?) ?? const <Object?>[];
    return Profissional(
      id: profissionalId,
      nome: nome,
      iniciais: _iniciais(nome),
      verificacao: seloDeVerificacao(nivel),
      especialidade: _especialidade(categoriasIds),
      servicosConcluidos: (j['servicos_concluidos'] as int?) ?? 0,
      nota: notaPublica ?? 0,
      distanciaKm: 0,
      regiao: regioes.join(', '),
      categoriaId: categoriasIds.isEmpty ? null : '${categoriasIds.first}',
      categoriasIds: [for (final c in categoriasIds) '$c'],
      detalhe: DetalhePerfil(
        noTratoDesde: (desde ?? DateTime.now()).year,
        totalAvaliacoes: avaliacoes.length,
        taxaConclusao: (j['taxa_conclusao'] as num?)?.toInt() ?? 0,
        temHistorico: j['taxa_conclusao'] != null,
        respondeEmFaixa: DetalhePerfil.lerFaixaResposta(j['responde_em_faixa']),
        verificacoes: [
          if (nivel == 'verificado' || nivel == 'verificado_plus') 'Identidade conferida',
          if (nivel == 'verificado_plus') 'Antecedentes conferidos',
        ],
        avaliacoes: avaliacoes,
        etiquetasTop: EtiquetaTop.listaDeJson(j['etiquetas_top']),
        bio: j['bio'] as String?,
        servicos: portfolio,
        trabalhos: portfolio,
        fotosUrls: fotosUrls,
        fotosTrabalhos: portfolio.isEmpty ? 0 : (portfolio.length > 3 ? 3 : portfolio.length),
      ),
    );
  }
}

/// Serviços do cliente: lista a partir de `GET /v1/pedidos` e detalhe a partir de
/// `GET /v1/pedidos/{id}`, `/saldo` e `/eventos`. Valores e estado são do backend.
class RepositorioServicosClienteApi implements RepositorioServicosCliente {
  RepositorioServicosClienteApi(this._api, this._pedidos);

  final ClienteApi _api;
  final RepositorioPedidos _pedidos;

  /// `recentes()` e `emAndamento()` saem da mesma lista. Chamados juntos (tela inicial),
  /// dividem UM `GET /v1/pedidos` em voo em vez de fazer dois. Não guarda resultado:
  /// terminada a chamada, a próxima busca de novo (dados sempre atuais).
  Future<PedidosDoCliente>? _listaEmVoo;

  Future<PedidosDoCliente> _listar() {
    final emVoo = _listaEmVoo;
    if (emVoo != null) return emVoo;
    final nova = _pedidos.listar();
    _listaEmVoo = nova;
    nova.whenComplete(() {
      if (identical(_listaEmVoo, nova)) _listaEmVoo = null;
    }).ignore();
    return nova;
  }

  @override
  Future<List<ServicoRecente>> recentes() async {
    final todos = await _listar();
    return [
      for (final p in [...todos.finalizados, ...todos.emAndamento])
        if (p.id != null)
          ServicoRecente(
            pedidoId: p.id,
            titulo: p.titulo,
            profissional: p.profissionalNome,
            data: p.subtitulo,
            statusTexto: p.statusTexto,
          ),
    ];
  }

  @override
  Future<PedidoEmAndamento?> emAndamento() async {
    final todos = await _listar();
    final p = todos.emAndamento.where((x) => x.id != null).firstOrNull;
    if (p == null) return null;
    return PedidoEmAndamento(
      pedidoId: p.id,
      titulo: p.titulo,
      situacao: p.subtitulo,
      aviso: p.statusTexto,
    );
  }

  @override
  Future<DetalheServico> detalhe(String pedidoId) async {
    final pedido = PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$pedidoId')));
    final antesDaContratacao = pedido.estado == 'aberto';
    final cfg = ConfigPublica.atual;
    final etapas = antesDaContratacao
        ? [
            const EtapaLinhaDoTempo(
              titulo: 'Pedido enviado',
              detalhe: '',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Orçamentos',
              detalhe: 'Você recebe até ${cfg.limiteOrcamentos} em '
                  '${ConfigPublica.horas(cfg.validadePedidoHoras)}',
              estado: EstadoEtapa.atual,
            ),
            const EtapaLinhaDoTempo(
              titulo: 'Contratação',
              detalhe: 'Você escolhe e aceita um orçamento',
              estado: EstadoEtapa.futura,
            ),
          ]
        : (await _pedidos.acompanhar(pedidoId)).etapas;
    var valores = <LinhaValor>[];
    if (!antesDaContratacao && pedido.estado != 'cancelado') {
      try {
        final (sBruto, aditivosBruto, notasBruto) = await emParalelo3(
          _api.get('/v1/pedidos/$pedidoId/saldo'),
          _api
              .get('/v1/contratos/$pedidoId/aditivos')
              .then<Object?>((v) => v)
              .catchError((Object _) => null),
          _api
              .get('/v1/contratos/$pedidoId/notas-material')
              .then<Object?>((v) => v)
              .catchError((Object _) => null),
        );
        final s = SaldoPedidoApi.deJson(_mapa(sBruto));
        var aditivosPagos = 0;
        var aditivosAprovados = 0;
        var aditivosPendentes = 0;
        if (aditivosBruto is List) {
          for (final raw in aditivosBruto) {
            if (raw is! Map) continue;
            final v = (raw['valor_centavos'] as num?)?.toInt() ?? 0;
            switch (raw['estado']) {
              case 'pago':
                aditivosPagos += v;
              case 'aprovado':
                aditivosAprovados += v;
              case 'proposto':
                aditivosPendentes += v;
            }
          }
        }
        var totalNotas = 0;
        if (notasBruto is List) {
          for (final raw in notasBruto) {
            if (raw is! Map) continue;
            totalNotas += (raw['total_centavos'] as num?)?.toInt() ?? 0;
          }
        }
        final orcamentoInicial = s.clientePagouCentavos >= aditivosPagos
            ? s.clientePagouCentavos - aditivosPagos
            : s.clientePagouCentavos;
        final temExtras =
            aditivosPagos > 0 || aditivosAprovados > 0 || aditivosPendentes > 0 || totalNotas > 0;
        valores = [
          if (s.clientePagouCentavos > 0 && temExtras)
            LinhaValor('Orçamento inicial', orcamentoInicial),
          if (aditivosPagos + aditivosAprovados > 0)
            LinhaValor('Aditivos aprovados/pagos', aditivosPagos + aditivosAprovados),
          if (aditivosPendentes > 0) LinhaValor('Aditivos pendentes', aditivosPendentes),
          if (totalNotas > 0) LinhaValor('Notas de materiais', totalNotas),
          if (s.clientePagouCentavos > 0)
            LinhaValor('Total pago', s.clientePagouCentavos, destaque: true),
          if (s.liberadoCentavos > 0) LinhaValor('Já liberado ao profissional', s.liberadoCentavos),
        ];
      } on Object {
        // Sem saldo (ainda sem pagamento): mostra o pedido sem valores.
      }
    }
    final (texto, tipo) = switch (pedido.estado) {
      'aberto' => ('Aguardando orçamentos', TipoStatus.info),
      'orcamento_aceito' => ('Aguardando pagamento', TipoStatus.alerta),
      'pago_e_retido' => ('Pagamento confirmado · a agendar', TipoStatus.info),
      'agendado' => ('Agendado', TipoStatus.info),
      'em_andamento' => ('Em execução', TipoStatus.info),
      'em_confirmacao' => ('Em execução · aguardando sua confirmação', TipoStatus.info),
      'concluido' => ('Finalizado', TipoStatus.sucesso),
      'cancelado' => ('Cancelado', TipoStatus.alerta),
      'em_disputa' => ('Disputa aberta · em análise', TipoStatus.alerta),
      'retrabalho' => ('Retrabalho em andamento', TipoStatus.info),
      _ => (pedido.estadoNome, TipoStatus.info),
    };
    // Nome curto de quem foi contratado ("Gabriel L."); sem ele (falha de rede), o rótulo genérico.
    String? nomeProfissional;
    if (pedido.profissionalId != null) {
      try {
        final o = await _api.get('/v1/pedidos/${pedido.id}/interlocutor');
        final nome = (o is Map ? (o['nome'] as String?) : null)?.trim();
        if (nome != null && nome.isNotEmpty) nomeProfissional = nome;
      } on Object {
        nomeProfissional = null;
      }
    }
    // Local do serviço (o cliente vê o próprio endereço). Sem rede: o pedido abre sem o local.
    String? local;
    if (!pedido.remoto) {
      try {
        local = RepositorioPedidosApi.dadosDeJson(
          _mapa(await _api.get('/v1/pedidos/${pedido.id}/dados')),
        ).enderecoCompleto;
      } on Object {
        local = null;
      }
    }
    return DetalheServico(
      remoto: pedido.remoto,
      jaAvaliou: pedido.jaAvaliou,
      local: local,
      codigoInicio:
          const {'pago_e_retido', 'agendado'}.contains(pedido.estado) ? pedido.codigoInicio : null,
      codigoConclusao: pedido.estado == 'em_andamento' ? pedido.codigoConclusao : null,
      pedidoId: pedido.id,
      numero: pedido.numero,
      titulo: pedido.rotulo,
      estadoApi: pedido.estado,
      statusTexto: texto,
      statusTipo: tipo,
      abertoEm: 'Aberto em ${_dia(pedido.abertoEm.toLocal())}',
      etapas: etapas,
      profissional: pedido.profissionalId == null
          ? null
          : ProfissionalDoServico(
              id: pedido.profissionalId,
              nome: nomeProfissional ?? 'Profissional contratado',
              iniciais: _iniciaisDe(nomeProfissional) ?? 'PC',
            ),
      valores: valores,
      avisoValores: valores.isEmpty ? null : 'Valores informados pelo sistema.',
    );
  }
}

/// "Gabriel L." -> "GL"; "Ana" -> "A". Nulo se não há nome.
String? _iniciaisDe(String? nome) {
  final partes = (nome ?? '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return null;
  final primeira = partes.first[0].toUpperCase();
  return partes.length == 1 ? primeira : '$primeira${partes.last[0].toUpperCase()}';
}

/// Agenda do profissional. O backend ainda não tem a lista de agendamentos: usa o próximo
/// atendimento do início (`GET /v1/profissional/pedidos-abertos` não traz agenda). Falta a rota
/// de agenda (`docs/app-divergencias.md`).
class RepositorioAgendaApi implements RepositorioAgenda {
  RepositorioAgendaApi(this._profissional);

  final RepositorioProfissional _profissional;

  @override
  Future<List<Agendamento>> listar() async {
    final inicio = await _profissional.inicio();
    // Todos os atendimentos pagos, não só o primeiro. O dia vem da visita marcada; sem visita
    // marcada, fica em "Sem data marcada" (não em "hoje").
    return [
      for (final c in inicio.contratados)
        if (c.naAgenda)
          Agendamento(
            id: c.pedidoId,
            pedidoId: c.pedidoId,
            dia: DateTime(
              (c.janelaInicio ?? DateTime.now()).year,
              (c.janelaInicio ?? DateTime.now()).month,
              (c.janelaInicio ?? DateTime.now()).day,
            ),
            horario: c.quando ?? 'Data da visita ainda não marcada',
            semData: c.janelaInicio == null,
            cliente: c.cliente,
            titulo: c.titulo,
            local: c.remoto ? 'Atendimento remoto' : (c.endereco ?? ''),
            remoto: c.remoto,
            consultaMapa: c.consultaMapa,
            estado: c.emAndamento ? EstadoAgendamento.emAndamento : EstadoAgendamento.agendado,
          ),
    ];
  }
}
