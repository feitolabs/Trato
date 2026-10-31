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
import 'repositorios_catalogo_fake.dart';

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

/// Catálogo. Só `GET /v1/profissionais/{id}` existe no backend; categorias, lista por
/// categoria, busca e perguntas do pedido ainda não têm rota e usam [demo].
class RepositorioCatalogoApi implements RepositorioCatalogo {
  RepositorioCatalogoApi(this._api, {RepositorioCatalogo? demo})
      : _demo = demo ?? RepositorioCatalogoFake();

  final ClienteApi _api;
  final RepositorioCatalogo _demo;

  @override
  Future<List<CategoriaServico>> categorias() => _demo.categorias();

  @override
  Future<List<Profissional>> profissionais(String categoriaId, FiltroProfissionais filtro) =>
      _demo.profissionais(categoriaId, filtro);

  @override
  Future<List<Profissional>> buscar(String termo) => _demo.buscar(termo);

  @override
  Future<FormularioPedido> formulario(String categoriaId) => _demo.formulario(categoriaId);

  @override
  Future<Profissional> perfil(String profissionalId) async {
    // Os profissionais de demonstração têm id "prof-...": não existem no backend.
    if (profissionalId.startsWith('prof-')) return _demo.perfil(profissionalId);
    final j = _mapa(await _api.get('/v1/profissionais/$profissionalId'));
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
      especialidade: [for (final c in (j['categorias'] as List? ?? const [])) '$c'].join(', '),
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
    final agora = DateTime.now();
    return [
      Agendamento(
        id: proximo.pedidoId ?? 'proximo',
        pedidoId: proximo.pedidoId ?? 'demo',
        dia: DateTime(agora.year, agora.month, agora.day),
        horario: proximo.quando,
        titulo: proximo.titulo,
        local: proximo.endereco,
      ),
    ];
  }
}
