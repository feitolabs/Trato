import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../telas/agenda/modelos.dart';
import '../telas/cliente/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/servicos/modelos.dart';
import 'cliente_api.dart';
import 'erros.dart';
import 'modelos_api.dart';
import 'repositorios.dart';
import 'repositorios_catalogo.dart';

// IMPLEMENTAÇÕES QUE FALAM COM A API (modo `api`) do catálogo, dos serviços e da agenda.
// Só o que o backend já tem sai da API; o resto segue em demonstração e está listado em
// `docs/app-ligacao.md`.

String _doisDigitos(int n) => n.toString().padLeft(2, '0');
String _dia(DateTime d) => '${_doisDigitos(d.day)}/${_doisDigitos(d.month)}';

Map<String, dynamic> _mapa(Object? json) => json! as Map<String, dynamic>;

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

  /// Ícone de cada categoria do banco, pelo `slug`. É só apresentação.
  static const _icones = <String, IconData>{
    'limpeza-residencial': Icons.auto_awesome_outlined,
    'montagem-de-moveis': Icons.inventory_2_outlined,
    'pintura-interna': Icons.format_paint_outlined,
    'eletricista': Icons.bolt,
    'encanador': Icons.water_drop_outlined,
    'reparos-gerais': Icons.handyman_outlined,
    'ar-condicionado': Icons.ac_unit,
    'eletrodomesticos': Icons.kitchen_outlined,
    'chaveiro': Icons.vpn_key_outlined,
    'jardinagem': Icons.grass_outlined,
    'diarista': Icons.cleaning_services_outlined,
    'marcenaria': Icons.carpenter_outlined,
    'vidraceiro': Icons.window_outlined,
    'serralheria': Icons.fence_outlined,
    'gesso-drywall': Icons.layers_outlined,
    'pisos-revestimentos': Icons.grid_on_outlined,
    'impermeabilizacao': Icons.umbrella_outlined,
    'cameras-seguranca': Icons.videocam_outlined,
    'informatica-redes': Icons.wifi,
    'mudanca-frete': Icons.local_shipping_outlined,
    'cortinas-persianas': Icons.blinds_outlined,
    'limpeza-especial': Icons.chair_outlined,
  };

  /// Só o que está no banco. Sem rede, o erro vai para a tela ("Tentar de novo").
  @override
  Future<List<CategoriaServico>> categorias() async {
    final resposta = await _api.get('/v1/catalogo/categorias');
    return [
      for (final item in (resposta as List? ?? const []).cast<Map<String, dynamic>>())
        CategoriaServico(
          item['nome'] as String,
          _icones[item['slug']] ?? Icons.home_repair_service_outlined,
          id: item['id'] as String,
        ),
    ];
  }

  Map<String, String>? _nomesCategorias;

  /// A API devolve as categorias do profissional como id; a tela mostra o nome.
  Future<void> _carregarNomesCategorias() async {
    if (_nomesCategorias != null) return;
    try {
      final resposta = await _api.get('/v1/catalogo/categorias');
      if (resposta is List) {
        _nomesCategorias = {
          for (final c in resposta)
            if (c is Map && c['id'] is String && c['nome'] is String)
              c['id'] as String: c['nome'] as String,
        };
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
    return Profissional(
      id: id,
      nome: nome,
      iniciais: _iniciais(nome),
      verificacao: nivel.contains('plus') ? 'Verificado Plus' : 'Verificado',
      especialidade: _especialidade(categorias),
      servicosConcluidos: servicosConcluidos,
      nota: notaPublica,
      distanciaKm: 0,
      regiao: '',
    );
  }

  @override
  Future<List<Profissional>> profissionais(String categoriaId, FiltroProfissionais filtro) async {
    final consulta = <String, String>{
      'categoria_id': categoriaId,
      if (filtro.bairro != null && filtro.bairro!.isNotEmpty) 'bairro': filtro.bairro!,
    };
    final resposta = _mapa(await _api.get('/v1/profissionais', consulta: consulta));
    await _carregarNomesCategorias();
    return [
      for (final item in (resposta['itens'] as List? ?? const []))
        _converterBusca(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<Profissional>> buscar(String termo) async {
    final limpo = termo.trim();
    final consulta = <String, String>{
      if (limpo.length >= 2) 'servico': limpo,
    };
    final resposta = _mapa(
      await _api.get('/v1/profissionais', consulta: consulta.isEmpty ? null : consulta),
    );
    await _carregarNomesCategorias();
    return [
      for (final item in (resposta['itens'] as List? ?? const []))
        _converterBusca(item as Map<String, dynamic>),
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
    final base = await _formularioBase(categoriaId);
    // Sem a lista de cidades não dá para abrir o pedido: o erro vira "Tentar de novo".
    final cidades = await _cidades();
    if (cidades.isEmpty) {
      throw const ErroTrato(
        TipoErro.indisponivel,
        'Ainda não atendemos nenhuma cidade. Volte daqui a pouco.',
      );
    }
    return base.comCidades(cidades);
  }

  Future<FormularioPedido> _formularioBase(String categoriaId) async {
    final c = (await categorias()).where((x) => x.id == categoriaId).firstOrNull;
    if (c == null) {
      throw const ErroTrato(TipoErro.naoEncontrado, 'Esta categoria não está mais disponível.');
    }
    return FormularioPedido(
      categoriaId: c.id,
      icone: c.icone,
      categoria: c.nome,
      servicos: const ['Orçamento geral'],
      servicosIniciais: const {},
      perguntaQuantidade: 'Quantos itens ou ambientes?',
      dicaQuantidade: 'Uma estimativa já ajuda',
      quantidadeInicial: 1,
      perguntaVoltagem: '',
      voltagens: const [],
      voltagemInicial: '',
      descricaoInicial: '',
      fotos: const [],
      prazos: const ['Esta semana', 'Sem pressa'],
      faixas: const [
        FaixaPreco(minimoCentavos: 20000, maximoCentavos: 50000),
        FaixaPreco(minimoCentavos: 0, maximoCentavos: 20000),
        FaixaPreco(minimoCentavos: 50000, maximoCentavos: 100000),
      ],
      endereco: 'Combine o endereço depois da contratação',
      avisoEndereco: 'O endereço completo só aparece para o profissional que você contratar.',
      avisoPrazo: 'Você recebe até 5 orçamentos em 48 horas. Avisamos quando o prazo terminar.',
    );
  }

  @override
  Future<Profissional> perfil(String profissionalId) async {
    final j = _mapa(await _api.get('/v1/profissionais/$profissionalId'));
    await _carregarNomesCategorias();
    final nome = (j['nome'] as String?) ?? 'Profissional';
    final nivel = (j['nivel_verificacao'] as String?) ?? '';
    final avaliacoes = [
      for (final a in (j['avaliacoes'] as List? ?? const []))
        Avaliacao(
          cliente: 'Cliente',
          servico: 'serviço',
          nota: ((a as Map)['nota_geral'] as num).toDouble(),
          comentario: (a['comentario'] as String?) ?? '',
          detalhes: [for (final e in (a['etiquetas'] as List? ?? const [])) '$e'].join(' · '),
        ),
    ];
    final portfolio = [
      for (final p in (j['portfolio'] as List? ?? const [])) (p as Map)['titulo'] as String,
    ];
    final regioes = [
      for (final r in (j['regioes'] as List? ?? const []))
        ((r as Map)['bairro'] ?? r['cidade'] ?? '') as String,
    ].where((r) => r.isNotEmpty).toList();
    final notaPublica = (j['nota_publica'] as num?)?.toDouble();
    return Profissional(
      id: profissionalId,
      nome: nome,
      iniciais: _iniciais(nome),
      verificacao: nivel.contains('plus') ? 'Verificado Plus' : 'Verificado',
      especialidade: _especialidade((j['categorias'] as List?) ?? const <Object?>[]),
      servicosConcluidos: (j['servicos_concluidos'] as int?) ?? 0,
      nota: notaPublica ?? 0,
      distanciaKm: 0,
      regiao: regioes.join(', '),
      detalhe: DetalhePerfil(
        noTratoDesde: DateTime.now().year,
        totalAvaliacoes: avaliacoes.length,
        taxaConclusao: 0,
        respondeEm: '',
        verificacoes: const [],
        avaliacoes: avaliacoes,
        bio: j['bio'] as String?,
        servicos: portfolio,
        trabalhos: portfolio,
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

  @override
  Future<List<ServicoRecente>> recentes() async {
    final todos = await _pedidos.listar();
    return [
      for (final p in [...todos.finalizados, ...todos.emAndamento])
        if (p.id != null)
          ServicoRecente(
            pedidoId: p.id,
            titulo: p.titulo,
            profissional: '',
            data: p.subtitulo,
            statusTexto: p.statusTexto,
          ),
    ];
  }

  @override
  Future<PedidoEmAndamento?> emAndamento() async {
    final todos = await _pedidos.listar();
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
    final etapas = antesDaContratacao
        ? const [
            EtapaLinhaDoTempo(
              titulo: 'Pedido enviado',
              detalhe: '',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Orçamentos',
              detalhe: 'Você recebe até 5 em 48 horas',
              estado: EstadoEtapa.atual,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Contratação',
              detalhe: 'Você escolhe e aceita um orçamento',
              estado: EstadoEtapa.futura,
            ),
          ]
        : (await _pedidos.acompanhar(pedidoId)).etapas;
    var valores = <LinhaValor>[];
    if (!antesDaContratacao && pedido.estado != 'cancelado') {
      try {
        final s = SaldoPedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$pedidoId/saldo')));
        valores = [
          if (s.clientePagouCentavos > 0) LinhaValor('Total pago', s.clientePagouCentavos, destaque: true),
          if (s.liberadoCentavos > 0) LinhaValor('Já liberado ao profissional', s.liberadoCentavos),
        ];
      } on ErroTrato {
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
    return DetalheServico(
      pedidoId: pedido.id,
      numero: pedido.numero,
      titulo: 'Pedido ${pedido.numero}',
      estadoApi: pedido.estado,
      statusTexto: texto,
      statusTipo: tipo,
      abertoEm: 'Aberto em ${_dia(pedido.abertoEm.toLocal())}',
      etapas: etapas,
      profissional: pedido.profissionalId == null
          ? null
          : ProfissionalDoServico(
              id: pedido.profissionalId,
              nome: 'Profissional contratado',
              iniciais: 'PC',
            ),
      valores: valores,
      avisoValores: valores.isEmpty ? null : 'Valores informados pelo sistema.',
    );
  }
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
    final proximo = inicio.proximo;
    if (proximo == null) return const [];
    // O dia vem da visita marcada; sem visita marcada, fica em "hoje" com o aviso no horário.
    final base = proximo.janelaInicio ?? DateTime.now();
    return [
      Agendamento(
        id: proximo.pedidoId ?? 'proximo',
        pedidoId: proximo.pedidoId ?? 'demo',
        dia: DateTime(base.year, base.month, base.day),
        horario: proximo.quando,
        titulo: proximo.titulo,
        local: proximo.endereco,
        estado: proximo.emAndamento ? EstadoAgendamento.emAndamento : EstadoAgendamento.agendado,
      ),
    ];
  }
}
