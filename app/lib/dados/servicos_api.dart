import '../componentes/imagem_trato.dart';
import '../dispositivo/servico_camera.dart';
import '../telas/aditivo/aditivo.dart';
import '../telas/disputa_profissional/disputa.dart';
import '../telas/nota_material/nota_material.dart';
import '../telas/perfil_publico/perfil_publico.dart';
import '../telas/profissional_cadastro/cadastro.dart';
import '../telas/verificacao/verificacao.dart';
import 'cliente_api.dart';
import 'erros.dart';
import 'servico_upload.dart';

// Serviços das telas de aditivo, nota de materiais, disputa e verificação, falando com a API.
// Só pedem e mostram: o total da nota, o estado do aditivo e a cobrança são do backend.

Map<String, dynamic> _mapa(Object? json) => json! as Map<String, dynamic>;
List<Map<String, dynamic>> _lista(Object? json) =>
    [for (final item in json! as List) item as Map<String, dynamic>];

/// Aditivo do contrato. As telas ainda passam o **id do pedido** no lugar do id do aditivo
/// (na demonstração não havia id próprio): aqui o id recebido é o do contrato e o aditivo
/// aberto (`proposto`) dele é o que se mostra e responde.
class ServicoAditivoApi implements ServicoAditivo {
  ServicoAditivoApi(this._api, {this.tituloPedido = 'Pedido', this.nomeProfissional = ''});

  final ClienteApi _api;
  final String tituloPedido;
  final String nomeProfissional;

  /// `POST /v1/contratos/{id}/aditivos` `{descricao, valor_centavos}`. Nada é cobrado aqui.
  @override
  Future<void> criar(NovoAditivo aditivo) async {
    await _api.post(
      '/v1/contratos/${aditivo.pedidoId}/aditivos',
      corpo: {'descricao': aditivo.motivo, 'valor_centavos': aditivo.valorCentavos},
    );
  }

  Future<Map<String, dynamic>?> _aberto(String contratoId) async {
    final todos = _lista(await _api.get('/v1/contratos/$contratoId/aditivos'));
    for (final a in todos) {
      if (a['estado'] == 'proposto') return a;
    }
    return null;
  }

  /// `GET /v1/contratos/{id}/aditivos`: o aditivo proposto, ou `null` se não há nenhum.
  @override
  Future<DetalheAditivo?> carregar(String aditivoId) async {
    final a = await _aberto(aditivoId);
    if (a == null) return null;
    return DetalheAditivo(
      id: a['id'] as String,
      pedidoTitulo: tituloPedido,
      profissional: nomeProfissional,
      motivo: a['descricao'] as String,
      valorCentavos: a['valor_centavos'] as int,
    );
  }

  /// `POST .../aditivos/{aditivo_id}/aprovar` (a cobrança nasce `aguardando_confirmacao`) ou
  /// `.../recusar`. Só o cliente decide; o profissional recebe 403.
  @override
  Future<void> responder(String aditivoId, {required bool aprovar}) async {
    final a = await _aberto(aditivoId);
    if (a == null) {
      throw const ErroTrato(TipoErro.naoEncontrado, 'Este aditivo já foi respondido.');
    }
    final acao = aprovar ? 'aprovar' : 'recusar';
    await _api.post(
      '/v1/contratos/$aditivoId/aditivos/${a['id']}/$acao',
      corpo: aprovar ? {'meio': 'pix'} : null,
    );
  }
}

/// Nota de materiais. O total sai do backend (quantidade × unitário); o app não soma.
class ServicoNotaMaterialApi implements ServicoNotaMaterial {
  ServicoNotaMaterialApi(this._api, {this.tituloPedido = 'Pedido', this.nomeProfissional = ''});

  final ClienteApi _api;
  final String tituloPedido;
  final String nomeProfissional;

  /// `GET /v1/contratos/{id}/notas-material`: a nota mais recente, ou `null`.
  @override
  Future<NotaMaterial?> carregar(String pedidoId) async {
    final notas = _lista(await _api.get('/v1/contratos/$pedidoId/notas-material'));
    if (notas.isEmpty) return null;
    notas.sort((a, b) => (a['enviada_em'] as String).compareTo(b['enviada_em'] as String));
    final n = notas.last;
    return NotaMaterial(
      pedidoTitulo: tituloPedido,
      profissional: nomeProfissional,
      enviadaEm: DateTime.parse(n['enviada_em'] as String).toLocal(),
      itens: [
        for (final i in (n['itens'] as List).cast<Map<String, dynamic>>())
          ItemNota(descricao: i['descricao'] as String, centavos: i['total_centavos'] as int),
      ],
    );
  }

  /// `POST /v1/contratos/{id}/notas-material`. A tela informa descrição e valor de cada item;
  /// a quantidade vai como 1 e o valor como unitário.
  @override
  Future<void> enviar(EnvioNota envio) async {
    await _api.post(
      '/v1/contratos/${envio.pedidoId}/notas-material',
      corpo: {
        'foto_storage_path': envio.fotoNota,
        'itens': [
          for (final i in envio.itens)
            {'descricao': i.descricao, 'quantidade': 1, 'valor_unitario_centavos': i.centavos},
        ],
      },
    );
  }
}

/// Verificação do profissional (documento e selfie). As fotos sobem antes, por URL assinada
/// ([CapturaVerificacao]); aqui só se manda a referência (`upload_id`) de cada uma.
class ServicoVerificacaoApi implements ServicoVerificacao {
  ServicoVerificacaoApi(this._api);

  final ClienteApi _api;
  List<Map<String, dynamic>>? _cache;

  Future<List<Map<String, dynamic>>> _todas() async =>
      _cache = _lista(await _api.get('/v1/profissional/verificacao'));

  /// `GET /v1/profissional/verificacao`: a mais recente manda.
  @override
  Future<SituacaoVerificacao> carregarSituacao() async {
    final todas = await _todas();
    if (todas.isEmpty) return const SituacaoVerificacao(status: StatusVerificacao.naoEnviada);
    todas.sort((a, b) => (a['enviada_em'] as String).compareTo(b['enviada_em'] as String));
    final v = todas.last;
    final status = switch (v['status_app']) {
      'aprovado' => StatusVerificacao.aprovada,
      'pendente' => StatusVerificacao.pendente,
      _ => StatusVerificacao.emAnalise,
    };
    return SituacaoVerificacao(
      status: status,
      motivo: v['motivo'] as String?,
      atualizadaEm: DateTime.parse(v['enviada_em'] as String).toLocal(),
    );
  }

  /// Finalidade e retenção vêm do backend quando já há uma verificação; antes do primeiro
  /// envio a rota não devolve o texto, então vale o texto provisório da tela.
  @override
  Future<TextoLgpd> carregarTextoLgpd() async {
    final todas = _cache ?? await _todas();
    if (todas.isEmpty) return textoLgpdExemplo;
    final v = todas.last;
    return TextoLgpd(
      finalidade: v['finalidade'] as String,
      retencao: 'Guardamos por ${v['retencao_dias']} dias e depois apagamos.',
      quemVe: textoLgpdExemplo.quemVe,
    );
  }

  /// `POST /v1/profissional/verificacao`. [EnvioVerificacao.documento] e `.selfie` são os
  /// `upload_id` devolvidos por [CapturaVerificacao]. O envio só acontece depois de a tela
  /// mostrar o aviso de privacidade (LGPD) e a pessoa tocar em enviar.
  @override
  Future<void> enviar(EnvioVerificacao envio) async {
    await _api.post(
      '/v1/profissional/verificacao',
      corpo: {
        'nivel_solicitado': 'verificado',
        'consentimento_lgpd': true,
        'documentos': [
          {'tipo': 'documento_frente', 'upload_id': envio.documento},
          {'tipo': 'selfie', 'upload_id': envio.selfie},
        ],
      },
    );
  }
}

/// Câmera + upload da verificação: tira a foto, envia por URL assinada e devolve o `upload_id`,
/// que a tela guarda como referência (é o que `CapturarFoto` espera). Retorna `null` se a
/// pessoa cancelou a câmera.
class CapturaVerificacao {
  CapturaVerificacao(this._camera, this._upload);

  final ServicoCamera _camera;
  final ServicoUpload _upload;

  Future<String?> documento() async {
    final foto = await _camera.tirarFoto();
    if (foto == null) return null;
    final enviado = await _upload.enviar(foto, FinalidadeArquivo.documento);
    registrarImagemEmMemoria(enviado.arquivoId, bytes: foto.bytes);
    return enviado.arquivoId;
  }

  Future<String?> selfie() async {
    final foto = await _camera.tirarFoto(frontal: true);
    if (foto == null) return null;
    final enviado = await _upload.enviar(foto, FinalidadeArquivo.selfie);
    registrarImagemEmMemoria(enviado.arquivoId, bytes: foto.bytes);
    return enviado.arquivoId;
  }
}

String _iniciaisNome(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  final primeira = partes.first[0].toUpperCase();
  return partes.length == 1 ? primeira : primeira + partes.last[0].toUpperCase();
}

/// Cadastro e edição de perfil do profissional falando com a API real:
/// `GET /v1/catalogo/categorias`, `GET /v1/catalogo/cidades`, `PATCH /v1/me`,
/// `POST /v1/profissional/cadastro` e `PATCH /v1/profissional/perfil`.
class ServicoCadastroProfissionalApi implements ServicoCadastroProfissional {
  ServicoCadastroProfissionalApi(this._api);

  final ClienteApi _api;
  Map<String, String> _idPorNomeCategoria = {};
  Map<String, String> _idPorNomeCidade = {};

  static const _diaParaIndice = {
    'Seg': 0,
    'Ter': 1,
    'Qua': 2,
    'Qui': 3,
    'Sex': 4,
    'Sáb': 5,
    'Dom': 6,
  };

  static const _periodoParaJanela = {
    'Manhã': ('08:00', '12:00'),
    'Tarde': ('13:00', '18:00'),
    'Noite': ('18:00', '22:00'),
  };

  @override
  Future<OpcoesCadastro> carregarOpcoes() async {
    try {
      final cats = _lista(await _api.get('/v1/catalogo/categorias'));
      _idPorNomeCategoria = {
        for (final c in cats)
          if (c['nome'] is String && c['id'] is String)
            (c['nome'] as String): (c['id'] as String),
      };
      try {
        final cids = _lista(await _api.get('/v1/catalogo/cidades'));
        _idPorNomeCidade = {
          for (final c in cids)
            if (c['nome'] is String && c['id'] is String)
              (c['nome'] as String).toLowerCase(): (c['id'] as String),
        };
      } on Object {
        // Segue com mapeamento padrão de cidade se a rota falhar.
      }
      final nomes = _idPorNomeCategoria.keys.toList();
      if (nomes.isNotEmpty) {
        return OpcoesCadastro(
          categorias: nomes,
          raiosKm: opcoesCadastroExemplo.raiosKm,
          dias: opcoesCadastroExemplo.dias,
          periodos: opcoesCadastroExemplo.periodos,
        );
      }
    } on Object {
      // Sem rede ou módulo ainda não inicializado: usa opções padrão.
    }
    return opcoesCadastroExemplo;
  }

  String _resolverCategoriaId(String nome) {
    final direto = _idPorNomeCategoria[nome];
    if (direto != null) return direto;
    final limpo = nome.toLowerCase();
    for (final entry in _idPorNomeCategoria.entries) {
      final k = entry.key.toLowerCase();
      if (limpo.contains(k) || k.contains(limpo)) return entry.value;
    }
    return _idPorNomeCategoria.values.firstOrNull ?? 'eletrica';
  }

  String _resolverCidadeId(String cidade) {
    final limpo = cidade.trim().toLowerCase();
    final direto = _idPorNomeCidade[limpo];
    if (direto != null) return direto;
    for (final entry in _idPorNomeCidade.entries) {
      if (limpo.contains(entry.key) || entry.key.contains(limpo)) return entry.value;
    }
    return _idPorNomeCidade.values.firstOrNull ?? 'de470309-afb7-49ac-9471-54e8387d4a88';
  }

  @override
  Future<void> salvar(DadosCadastroProfissional dados) async {
    final nomeTrim = dados.nome.trim();
    if (nomeTrim.length >= 2) {
      await _api.patch('/v1/me', corpo: {'nome': nomeTrim});
    }
    final categoriasIds = [
      for (final c in dados.categorias) _resolverCategoriaId(c),
    ];
    final cidadeId = _resolverCidadeId(dados.cidade);
    final bairroNome = dados.cidade.trim();
    final regioes = [
      {
        'cidade_id': cidadeId,
        if (bairroNome.isNotEmpty) 'bairro': bairroNome,
      },
    ];
    final disponibilidade = <Map<String, Object>>[
      for (final d in dados.dias)
        if (_diaParaIndice.containsKey(d))
          for (final p in dados.periodos)
            if (_periodoParaJanela.containsKey(p))
              {
                'dia_semana': _diaParaIndice[d]!,
                'inicio': _periodoParaJanela[p]!.$1,
                'fim': _periodoParaJanela[p]!.$2,
              },
    ];
    final portfolio = [
      for (var i = 0; i < dados.portfolio.length; i++)
        {
          'titulo': 'Trabalho ${i + 1}',
          'descricao': dados.portfolio[i],
        },
    ];
    final padraoCat = _idPorNomeCategoria.values.firstOrNull ?? 'eletrica';
    final corpo = <String, Object?>{
      'categorias': categoriasIds.isEmpty ? [padraoCat] : categoriasIds,
      'regioes': regioes,
      'disponibilidade': disponibilidade,
      'bio': dados.sobre.trim(),
      'portfolio': portfolio,
    };
    try {
      await _api.post('/v1/profissional/cadastro', corpo: corpo);
    } on ErroTrato catch (e) {
      if (e.tipo == TipoErro.recusado) {
        await _api.patch('/v1/profissional/perfil', corpo: corpo);
      } else {
        rethrow;
      }
    }
  }
}

/// Perfil público do próprio profissional (`GET /v1/me` + `GET /v1/profissional/perfil`
/// + `GET /v1/profissionais/{id}`).
class ServicoPerfilPublicoApi implements ServicoPerfilPublico {
  ServicoPerfilPublicoApi(this._api);

  final ClienteApi _api;

  @override
  Future<PerfilPublico> carregarPerfil() async {
    final me = _mapa(await _api.get('/v1/me'));
    final usuarioId = (me['id'] as String?) ?? '';
    final nome = ((me['nome'] as String?) ?? '').trim();
    final nomeExibicao = nome.isEmpty ? 'Profissional' : nome;
    final nota = (me['nota_publica'] as num?)?.toDouble() ?? 0.0;
    final concluidos = (me['servicos_concluidos'] as int?) ?? 0;

    Map<String, dynamic>? prof;
    try {
      prof = _mapa(await _api.get('/v1/profissional/perfil'));
    } on ErroTrato {
      prof = null;
    }

    var avaliacoes = <Avaliacao>[];
    var cidades = <String>[];
    var noTratoDesde = DateTime.now().year;
    if (usuarioId.isNotEmpty) {
      try {
        final pub = _mapa(await _api.get('/v1/profissionais/$usuarioId'));
        if (pub['no_trato_desde'] is String) {
          noTratoDesde = DateTime.parse(pub['no_trato_desde'] as String).year;
        }
        cidades = [for (final c in (pub['cidades'] as List? ?? const [])) '$c'];
        avaliacoes = _converterAvaliacoes(pub['avaliacoes'] as List? ?? const []);
      } on ErroTrato {
        // Perfil ainda em análise (não aprovado publicamente): usa dados privados de /v1/profissional/perfil.
      }
    }

    final categorias = [for (final c in (prof?['categorias'] as List? ?? const [])) '$c'];
    final portfolioBruto = (prof?['portfolio'] as List? ?? const []).cast<Map<String, dynamic>>();
    final fotosPortfolio = [
      for (final item in portfolioBruto)
        ((item['descricao'] as String?)?.isNotEmpty == true
            ? item['descricao'] as String
            : (item['titulo'] as String? ?? 'Foto')),
    ];
    final nivel = (prof?['nivel_verificacao'] as String?) ?? '';
    final verificacao = nivel.isEmpty
        ? null
        : (nivel.contains('plus') ? 'Identidade e antecedentes conferidos' : 'Identidade conferida');

    return PerfilPublico(
      nome: nomeExibicao,
      iniciais: _iniciaisNome(nomeExibicao),
      categoria: categorias.isEmpty ? 'Profissional' : categorias.join(' · '),
      verificacao: verificacao,
      noTratoDesde: noTratoDesde,
      nota: nota,
      totalAvaliacoes: avaliacoes.length,
      servicosConcluidos: concluidos,
      sobre: (prof?['bio'] as String?) ?? 'Perfil profissional cadastrado no Trato.',
      cidade: cidades.isNotEmpty ? cidades.first : 'Belo Horizonte',
      fotosPortfolio: fotosPortfolio.length,
      ultimasAvaliacoes: avaliacoes,
      listaFotosPortfolio: fotosPortfolio,
    );
  }

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async {
    final perfil = await carregarPerfil();
    return perfil.ultimasAvaliacoes;
  }

  List<Avaliacao> _converterAvaliacoes(List<dynamic> brutas) => [
        for (final a in brutas)
          if (a is Map)
            Avaliacao(
              cliente: 'Cliente',
              servico: 'Serviço concluído',
              nota: (a['nota_geral'] as num).toDouble(),
              comentario: (a['comentario'] as String?) ?? '',
              detalhes: [for (final e in (a['etiquetas'] as List? ?? const [])) '$e'].join(' · '),
            ),
      ];
}

/// Disputa e retrabalho do lado do profissional falando com a API.
class ServicoDisputaProfissionalApi implements ServicoDisputaProfissional {
  ServicoDisputaProfissionalApi(this._api);

  final ClienteApi _api;

  @override
  Future<DetalheDisputa?> carregarDisputa(String disputaId) async {
    try {
      final j = _mapa(await _api.get('/v1/pedidos/$disputaId/disputa'));
      return DetalheDisputa(
        id: disputaId,
        titulo:
            'Disputa do pedido #${disputaId.substring(0, disputaId.length < 6 ? disputaId.length : 6).toUpperCase()}',
        cliente: 'Cliente',
        motivo: (j['motivo'] as String?) ?? 'Disputa',
        descricao: (j['descricao'] as String?) ?? '',
        solucaoPedida: 'Análise do suporte',
        prazoRespostaHoras: 48,
        valorCongeladoCentavos: (j['valor_congelado_centavos'] as int?) ?? 0,
      );
    } on ErroTrato catch (e) {
      if (e.tipo == TipoErro.naoEncontrado) return null;
      rethrow;
    }
  }

  @override
  Future<void> responder(RespostaDisputa resposta) async {
    await _api.post('/v1/pedidos/${resposta.disputaId}/disputa/resposta');
  }

  @override
  Future<DadosRetrabalho?> carregarRetrabalho(String disputaId) async {
    try {
      final lista = _lista(await _api.get('/v1/pedidos/$disputaId/retrabalho'));
      if (lista.isEmpty) return null;
      final ultimo = lista.last;
      return DadosRetrabalho(
        disputaId: disputaId,
        titulo:
            'Retrabalho do pedido #${disputaId.substring(0, disputaId.length < 6 ? disputaId.length : 6).toUpperCase()}',
        descricaoProblema: (ultimo['descricao'] as String?) ?? 'Retrabalho solicitado',
        prazoAtendimentoDias: 7,
        opcoesHorario: const ['Manhã', 'Tarde'],
      );
    } on ErroTrato catch (e) {
      if (e.tipo == TipoErro.naoEncontrado) return null;
      rethrow;
    }
  }

  @override
  Future<void> agendarRetrabalho(AgendamentoRetrabalho agendamento) async {
    await _api.post(
      '/v1/pedidos/${agendamento.disputaId}/retrabalho/atender',
      corpo: {'etapa': 'aceitar'},
    );
  }
}
