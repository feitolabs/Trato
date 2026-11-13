import '../dispositivo/servico_localizacao.dart';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../componentes/componentes.dart';
import '../dispositivo/servico_camera.dart';
import '../telas/carteira/modelos.dart' hide ResumoCarteira;
import '../telas/conclusao/modelos.dart';
import '../telas/orcamentos/modelos.dart';
import '../telas/pagamento/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/pedidos/modelos.dart';
import '../telas/perfil_cliente/modelos.dart';
import '../telas/profissional/dinheiro.dart';
import '../telas/profissional/servico_check_in.dart';
import '../telas/profissional/servico_check_out.dart';
import '../telas/profissional/servico_orcamento.dart';
import '../telas/profissional_inicio/modelos.dart';
import '../telas/comuns/formato_aparelho.dart';
import 'cliente_api.dart';
import 'erros.dart';
import 'fila_offline.dart';
import 'modelos_api.dart';
import 'repositorios.dart';
import 'servico_upload.dart';
import 'paralelo.dart';

// IMPLEMENTAÇÕES QUE FALAM COM A API (modo `api`). Só pedem e mostram; o backend decide.
// Onde a rota ainda não existe no backend, a classe lança [ErroTrato.indisponivel] e o
// comentário diz qual rota falta. Ver `docs/app-ligacao.md`.

String _doisDigitos(int n) => n.toString().padLeft(2, '0');
String _dia(DateTime d) => '${_doisDigitos(d.day)}/${_doisDigitos(d.month)}';
String _hora(DateTime d) => horaDoAparelho(d);

Map<String, dynamic> _mapa(Object? json) =>
    json is Map<String, dynamic> ? json : (json is Map ? Map<String, dynamic>.from(json) : const <String, dynamic>{});
List<Map<String, dynamic>> _lista(Object? json) => [
      for (final item in (json is List ? json : const []))
        if (item is Map) Map<String, dynamic>.from(item)
    ];

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
  RepositorioPedidosApi(
    this._api, {
    this.textos = const TextosPadraoTelas(),
    this.upload,
    this.posicao,
  });

  /// Posição aproximada do aparelho (nula se o cliente negou o GPS). Vai no pedido para o
  /// profissional ver a distância.
  final Future<PosicaoAtual?> Function()? posicao;

  final ClienteApi _api;
  final TextosPadraoTelas textos;
  final ServicoUpload? upload;

  Future<PedidoApi> _pedido(String id) async =>
      PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$id')));

  static DadosDoPedido _dadosDeJson(Map<String, dynamic> j) {
    final e = j['endereco'] as Map<String, dynamic>?;
    return DadosDoPedido(
      titulo: j['titulo'] as String,
      descricao: j['descricao'] as String,
      faixaMaxCentavos: j['faixa_preco_max_centavos'] as int?,
      logradouro: e?['logradouro'] as String?,
      numero: e?['numero'] as String?,
      bairro: e?['bairro'] as String?,
      complemento: e?['complemento'] as String?,
    );
  }

  @override
  Future<DadosDoPedido> dados(String pedidoId) async =>
      _dadosDeJson(_mapa(await _api.get('/v1/pedidos/$pedidoId/dados')));

  @override
  Future<DadosDoPedido> editar(
    String pedidoId, {
    String? descricao,
    int? faixaMaxCentavos,
    String? logradouro,
    String? numero,
    String? bairro,
    String? complemento,
  }) async {
    final corpo = <String, Object?>{
      if (descricao != null) 'descricao': descricao,
      if (faixaMaxCentavos != null) 'faixa_preco_max_centavos': faixaMaxCentavos,
      if (logradouro != null && logradouro.trim().isNotEmpty)
        'endereco': {
          'logradouro': logradouro.trim(),
          if (numero != null && numero.trim().isNotEmpty) 'numero': numero.trim(),
          if (bairro != null && bairro.trim().isNotEmpty) 'bairro': bairro.trim(),
          if (complemento != null && complemento.trim().isNotEmpty)
            'complemento': complemento.trim(),
        },
    };
    return _dadosDeJson(_mapa(await _api.patch('/v1/pedidos/$pedidoId', corpo: corpo)));
  }

  Future<SaldoPedidoApi> _saldo(String id) async =>
      SaldoPedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$id/saldo')));

  /// `GET /v1/pedidos/{id}/fotos`: URLs assinadas e curtas das fotos do serviço. "antes" é a foto
  /// de chegada (ou "antes"), "depois" a foto final (ou "depois"). Falha de rede = sem fotos.
  Future<Map<String, String>> _fotosDoServico(String pedidoId) async {
    final porFinalidade = <String, String>{};
    try {
      for (final f in _lista(await _api.get('/v1/pedidos/$pedidoId/fotos'))) {
        final url = f['url'];
        if (url is! String) continue;
        switch (f['finalidade']) {
          case 'checkin' || 'antes':
            porFinalidade.putIfAbsent('antes', () => url);
          case 'checkout' || 'depois':
            porFinalidade['depois'] = url;
        }
      }
    } catch (_) {}
    return porFinalidade;
  }

  /// Nome do profissional do pedido (`GET /v1/profissionais/{id}`). Sem nome, "o profissional":
  /// as frases das telas funcionam com os dois (início de frase ganha maiúscula).
  Future<String> _nomeDoProfissional(PedidoApi pedido) async {
    final id = pedido.profissionalId;
    if (id == null) return 'o profissional';
    try {
      final nome = (_mapa(await _api.get('/v1/profissionais/$id'))['nome'] as String?)?.trim();
      return (nome == null || nome.isEmpty) ? 'o profissional' : nome;
    } catch (_) {
      return 'o profissional';
    }
  }

  @override
  Future<PedidosDoCliente> listar() async {
    final pedidos = [
      for (final j in _lista(await _api.get('/v1/pedidos', consulta: const {'como': 'cliente'})))
        PedidoApi.deJson(j)
    ];
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
    final categoriaId = rascunho.categoriaId;
    final cidadeId = rascunho.cidadeId;
    if (categoriaId == null || cidadeId == null) {
      throw const ErroTrato(TipoErro.recusado, 'Escolha a categoria e a cidade do serviço.');
    }
    final onde = await posicao?.call();
    final corpo = <String, dynamic>{
      'categoria_id': categoriaId,
      'cidade_id': cidadeId,
      // Arredondado a ~1 km: o profissional vê a região, nunca o ponto exato.
      if (onde != null) 'local_aprox_lat': double.parse(onde.latitude.toStringAsFixed(2)),
      if (onde != null) 'local_aprox_lng': double.parse(onde.longitude.toStringAsFixed(2)),
      if (rascunho.bairro != null && rascunho.bairro!.isNotEmpty) 'bairro': rascunho.bairro,
      if (rascunho.prazoDesejado != null)
        'prazo_desejado': rascunho.prazoDesejado!.toIso8601String().substring(0, 10),
      'titulo': rascunho.servicos.isNotEmpty ? rascunho.servicos.join(', ') : 'Pedido de serviço',
      'descricao': rascunho.descricao.trim().isNotEmpty
          ? rascunho.descricao.trim()
          : 'Serviço solicitado pelo cliente',
      'faixa_preco_min_centavos': rascunho.faixa.minimoCentavos,
      'faixa_preco_max_centavos': rascunho.faixa.maximoCentavos,
      'respostas': [
        if (rascunho.servicos.isNotEmpty)
          {'pergunta_id': 'servicos', 'resposta': rascunho.servicos.join(', ')},
        if (rascunho.quantidade > 0)
          {'pergunta_id': 'quantidade', 'resposta': rascunho.quantidade.toString()},
        if (rascunho.voltagem.isNotEmpty)
          {'pergunta_id': 'voltagem', 'resposta': rascunho.voltagem},
        if (rascunho.prazo.isNotEmpty)
          {'pergunta_id': 'prazo', 'resposta': rascunho.prazo},
      ],
    };
    // Só ASCII: a chave vai num cabeçalho HTTP e o nome do serviço tem acento ("Orçamento geral").
    final chaveIdemp =
        'pedido-${DateTime.now().millisecondsSinceEpoch}-${rascunho.servicos.join('|').hashCode.abs()}-${rascunho.descricao.hashCode.abs()}';
    final criado = PedidoApi.deJson(
      _mapa(await _api.post('/v1/pedidos', corpo: corpo, chaveIdempotencia: chaveIdemp)),
    );
    final up = upload;
    if (up != null && rascunho.fotos.isNotEmpty) {
      await Future.wait(
        rascunho.fotos.map((ref) async {
          try {
            final bytes = obterBytesImagem(ref);
            if (bytes != null && bytes.isNotEmpty) {
              final cap = ArquivoCapturado(
                bytes: bytes,
                sha256: crypto.sha256.convert(bytes).toString(),
                capturadaEm: DateTime.now().toUtc(),
              );
              await up.enviar(cap, FinalidadeArquivo.fotoPedido, pedidoId: criado.id);
            } else if (temArquivoImagem(ref)) {
              final caminho = obterCaminhoImagem(ref) ?? ref;
              final f = File(caminho);
              if (f.existsSync()) {
                final b = await f.readAsBytes();
                final cap = ArquivoCapturado(
                  bytes: b,
                  sha256: crypto.sha256.convert(b).toString(),
                  capturadaEm: DateTime.now().toUtc(),
                );
                await up.enviar(cap, FinalidadeArquivo.fotoPedido, pedidoId: criado.id);
              }
            }
          } catch (_) {
            // Erro no upload de foto secundária não impede a criação do pedido
          }
        }),
      );
    }
    return criado.id;
  }

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async {
    // Em paralelo: pedido e histórico não dependem um do outro.
    final (pedido, eventosBrutos) =
        await emParalelo2(_pedido(pedidoId), _api.get('/v1/pedidos/$pedidoId/eventos'));
    final eventos = [
      for (final j in _lista(eventosBrutos)) EventoApi.deJson(j),
    ];
    // Etapas da linha do tempo (índice = posição). O check-in cobre "Chegou" e "Em execução".
    const etapaDaAcao = {
      'aceitar_orcamento': 0,
      'confirmar_agenda': 1,
      'fazer_check_in': 3,
      'fazer_check_out': 4,
      'confirmar_conclusao': 5,
    };
    const etapaDoEstado = {
      'orcamento_aceito': 0,
      'pago_e_retido': 0,
      'agendado': 1,
      'em_andamento': 3,
      'em_confirmacao': 4,
      'concluido': 6,
    };
    const titulos = [
      'Contratado',
      'Visita marcada',
      'Chegou',
      'Em execução',
      'Aguardando sua confirmação',
      'Finalizado',
    ];
    final atual = etapaDoEstado[pedido.estado] ?? 0;
    final quando = <int, DateTime>{};
    for (final e in eventos) {
      final etapa = etapaDaAcao[e.acao];
      if (etapa != null) quando[etapa] = e.em.toLocal();
    }
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
      // O código de início só serve até o profissional chegar.
      codigoInicio: const {'em_andamento', 'em_confirmacao', 'concluido'}.contains(pedido.estado)
          ? null
          : pedido.codigoInicio,
    );
  }

  @override
  Future<ResumoConclusao> conclusao(String pedidoId) async {
    final (pedido, saldo, fotos) =
        await emParalelo3(_pedido(pedidoId), _saldo(pedidoId), _fotosDoServico(pedidoId));
    return ResumoConclusao(
      numeroPedido: pedido.numero,
      nomeProfissional: await _nomeDoProfissional(pedido),
      fotoAntes: fotos['antes'],
      fotoDepois: fotos['depois'],
      fotosCarregadas: true,
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
    final (pedido, saldo) = await emParalelo2(_pedido(pedidoId), _saldo(pedidoId));
    return DadosRelatoProblema(
      titulo: 'Pedido ${pedido.numero}',
      valorCongeladoCentavos: saldo.retidoCentavos + saldo.aLiberarCentavos,
      motivos: textos.motivos,
      solucoes: textos.solucoes,
      prazoRespostaHoras: textos.prazoRespostaHoras,
      nomeProfissional: await _nomeDoProfissional(pedido),
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
    final (saldo, pedido) = await emParalelo2(_saldo(pedidoId), _pedido(pedidoId));
    return DadosAvaliacao(
      nomeProfissional: await _nomeDoProfissional(pedido),
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

  /// `POST /v1/pedidos/{id}/orcamentos/{orc}/contraproposta` `{valor_centavos, mensagem?}`.
  @override
  Future<void> contraproporValor(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    String? mensagem,
  }) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/orcamentos/$orcamentoId/contraproposta',
      corpo: {
        'valor_centavos': valorCentavos,
        if (mensagem != null && mensagem.trim().isNotEmpty) 'mensagem': mensagem.trim(),
      },
    );
  }

  /// `POST .../contraproposta/aceitar` `{valor_centavos}`: nova versão do orçamento.
  @override
  Future<void> aceitarContraproposta(
      String pedidoId, String orcamentoId, int valorCentavos) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/orcamentos/$orcamentoId/contraproposta/aceitar',
      corpo: {'valor_centavos': valorCentavos},
    );
  }

  /// `GET /v1/pedidos/{id}/orcamentos` (do mais barato ao mais caro) e, para cada um,
  /// `GET /v1/orcamentos/{id}` (itens, validade, fora do escopo). Falha no detalhe de um
  /// orçamento não derruba a lista: ele só aparece sem detalhe.
  @override
  Future<OrcamentosDoPedido> listar(String pedidoId) async {
    final (pedidoBruto, orcamentosBrutos) = await emParalelo2(
      _api.get('/v1/pedidos/$pedidoId'),
      _api.get('/v1/pedidos/$pedidoId/orcamentos'),
    );
    final pedido = PedidoApi.deJson(_mapa(pedidoBruto));
    final brutos = _lista(orcamentosBrutos);
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
          // Item de hora com valor zero é só a informação das horas (numa contraproposta aceita,
          // o preço já está no valor combinado): vai no bloco de horas, não numa linha de R$ 0,00.
          if (!(const {'horas', 'deslocamento'}.contains(i['tipo']) && i['total_centavos'] == 0))
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
        totalHoras: _horasTexto(j['total_horas']),
        horasDeslocamento: _horasTexto(j['horas_deslocamento']),
        horasTrabalhadas: _horasTexto(j['horas_trabalhadas']),
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

  /// "5.5" -> "5,5 h"; "3" -> "3 h"; nulo -> "".
  static String _horasTexto(Object? bruto) {
    final horas = double.tryParse('${bruto ?? ''}');
    if (horas == null || horas <= 0) return '';
    return Dinheiro.formatarHoras((horas * 10).round());
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
      profissionalId: j['profissional_id'] as String?,
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
      valorAgoraCentavos: (j['total_a_pagar_centavos'] as int?) ?? valor,
      parcelamento: [
        for (final o in (j['opcoes_parcelamento'] as List? ?? const []))
          OpcaoParcelamento(
            parcelas: (o as Map)['parcelas'] as int,
            custoCentavos: o['custo_centavos'] as int,
            totalCentavos: o['total_centavos'] as int,
            valorParcelaCentavos: o['valor_parcela_centavos'] as int,
          ),
      ],
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
      segredoCartao:
          j['tipo_instrucao'] == 'cartao_segredo_do_cliente' ? j['instrucao'] as String? : null,
      clienteCartaoId: j['cliente_externo_id'] as String?,
      chaveEfemera: j['chave_efemera'] as String?,
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
  RepositorioChatApi(this._api, {this.textos = const TextosPadraoTelas(), this.upload});

  final ClienteApi _api;
  final TextosPadraoTelas textos;

  /// Sobe a foto do chat. Sem ele (testes, demonstração), a referência segue como veio.
  final ServicoUpload? upload;

  /// A mensagem de foto leva `[Foto:<id da mídia>]`; a imagem abre por URL assinada curta.
  static final _marcadorFoto = RegExp(r'^\[Foto:([0-9a-fA-F-]{16,40})\]$');

  /// URL curta da foto por mídia (vale 4 min; a do backend expira em 5).
  final Map<String, (DateTime, String?)> _urlsDeFotos = {};

  Future<String?> _urlDaFoto(String pedidoId, String midiaId) async {
    final guardada = _urlsDeFotos[midiaId];
    if (guardada != null && DateTime.now().difference(guardada.$1).inMinutes < 4) {
      return guardada.$2;
    }
    String? url;
    try {
      url = _mapa(await _api.get('/v1/pedidos/$pedidoId/anexos-chat/$midiaId'))['url'] as String?;
    } on Object {
      url = null; // sem rede ou sem a foto: a conversa abre, a imagem fica como "Foto"
    }
    if (url != null) _urlsDeFotos[midiaId] = (DateTime.now(), url);
    return url;
  }

  static bool ehMensagemFoto(String texto) {
    final t = texto.trim();
    return t.startsWith('[Foto') ||
        t.startsWith('midia://') ||
        t.startsWith('arq-') ||
        t.startsWith('up-') ||
        ehUrlImagem(t) ||
        temArquivoImagem(t);
  }

  static MensagemChat _mensagem(Map<String, dynamic> m) {
    final bruto = (m['texto'] as String?) ?? '';
    final (contra, texto) = ContrapropostaChat.ler(bruto);
    return MensagemChat(
      tipo: contra == null && ehMensagemFoto(bruto) ? TipoMensagem.foto : TipoMensagem.texto,
      hora: _hora(DateTime.parse(m['enviada_em'] as String).toLocal()),
      texto: texto,
      minha: m['minha'] == true,
      lida: m['lida_em'] != null,
      contraproposta: contra,
    );
  }

  static String _iniciaisDe(String nome) {
    final partes = nome.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '#';
    final primeira = partes.first[0].toUpperCase();
    return partes.length == 1 ? primeira : '$primeira${partes.last[0].toUpperCase()}';
  }

  Map<String, String>? _consulta(String? profissionalId) =>
      profissionalId == null || profissionalId.isEmpty
          ? null
          : {'profissional_id': profissionalId};

  @override
  Future<ConversaPedido> conversa(String pedidoId, {String? profissionalId}) async {
    final mensagens = _lista(
      await _api.get(
        '/v1/pedidos/$pedidoId/mensagens',
        consulta: _consulta(profissionalId),
      ),
    );
    // Antes de ser contratado, o profissional conversa mas não é parte do pedido: o backend
    // responde 404 em `GET /v1/pedidos/{id}`. O chat segue, só sem a situação do pedido.
    final numero = PedidoApi.numeroDe(pedidoId);
    var situacao = 'Pedido aberto';
    try {
      situacao = PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$pedidoId'))).estadoNome;
    } on ErroTrato catch (erro) {
      if (erro.tipo != TipoErro.naoEncontrado) rethrow;
    }
    // Quem está do outro lado (nome curto). Se falhar, o chat segue com o número do pedido.
    var nome = 'Pedido $numero';
    var iniciais = '#';
    String? outroId;
    try {
      final o = _mapa(await _api.get(
        '/v1/pedidos/$pedidoId/interlocutor',
        consulta: _consulta(profissionalId),
      ));
      final n = ((o['nome'] as String?) ?? '').trim();
      if (n.isNotEmpty) {
        nome = n;
        iniciais = _iniciaisDe(n);
        outroId = o['id'] as String?;
      }
    } on ErroTrato {
      // mantém o título pelo número do pedido
    }
    return ConversaPedido(
      usuarioId: outroId,
      nome: nome,
      iniciais: iniciais,
      numeroPedido: numero,
      situacao: situacao,
      mensagens: [
        for (final m in await _comFotos(pedidoId, mensagens)) _mensagem(m),
      ],
      respostasRapidas: textos.respostasRapidas,
    );
  }

  /// Troca `[Foto:<id>]` pela URL da imagem (em paralelo). Sem URL, vira o texto "Foto".
  Future<List<Map<String, dynamic>>> _comFotos(
    String pedidoId,
    List<Map<String, dynamic>> brutas,
  ) async {
    return Future.wait([
      for (final m in brutas)
        () async {
          final texto = ((m['texto'] as String?) ?? '').trim();
          final achou = _marcadorFoto.firstMatch(texto);
          if (achou == null) return m;
          final url = await _urlDaFoto(pedidoId, achou.group(1)!);
          return {...m, 'texto': url ?? '[Foto indisponível]'};
        }(),
    ]);
  }

  @override
  Future<void> enviar(String pedidoId, String texto, {String? profissionalId}) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/mensagens',
      consulta: _consulta(profissionalId),
      corpo: {'texto': texto},
    );
  }

  @override
  Future<void> enviarFoto(String pedidoId, String referencia, {String? profissionalId}) async {
    var texto = referencia;
    final servico = upload;
    // Foto tirada agora: sobe como anexo de chat e a mensagem leva só o id. Antes, o app mandava
    // o CAMINHO do arquivo no celular de quem enviou, que não abre em outro aparelho.
    if (servico != null && _ehArquivoLocal(referencia)) {
      final bytes = await File(referencia).readAsBytes();
      final enviado = await servico.enviar(
        ArquivoCapturado(
          bytes: bytes,
          sha256: crypto.sha256.convert(bytes).toString(),
          capturadaEm: DateTime.now().toUtc(),
        ),
        FinalidadeArquivo.chat,
        pedidoId: pedidoId,
      );
      texto = '[Foto:${enviado.arquivoId}]';
    }
    await _api.post(
      '/v1/pedidos/$pedidoId/mensagens',
      consulta: _consulta(profissionalId),
      corpo: {'texto': texto},
    );
  }

  static bool _ehArquivoLocal(String referencia) {
    if (referencia.startsWith('[') || referencia.startsWith('http')) return false;
    try {
      return File(referencia).existsSync();
    } on Object {
      return false;
    }
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
  RepositorioPerfilApi(this._api, {this.upload});

  final ClienteApi _api;
  final ServicoUpload? upload;
  String? _ultimoNome;
  String? _meuId;

  /// URL curta da foto por usuário; vale 45 s (a URL do backend expira em 5). Curto de propósito:
  /// quem troca a foto aparece com a nova na lista de mensagens e no perfil quase na hora.
  final Map<String, (DateTime, Future<String?>)> _fotos = {};

  @override
  Future<String?> fotoDe(String usuarioId) {
    final guardada = _fotos[usuarioId];
    if (guardada != null && DateTime.now().difference(guardada.$1).inSeconds < 45) {
      return guardada.$2;
    }
    final busca = () async {
      try {
        final j = _mapa(await _api.get('/v1/usuarios/$usuarioId/foto'));
        return j['url'] as String?;
      } on Object {
        return null; // sem foto, sem rede ou erro: as iniciais bastam (nunca derruba a tela)
      }
    }();
    _fotos[usuarioId] = (DateTime.now(), busca);
    return busca;
  }

  @override
  Future<void> enviarFoto(String caminhoLocal) async {
    final servico = upload;
    if (servico == null) return;
    final bytes = await File(caminhoLocal).readAsBytes();
    await servico.enviar(
      ArquivoCapturado(
        bytes: bytes,
        sha256: crypto.sha256.convert(bytes).toString(),
        capturadaEm: DateTime.now().toUtc(),
      ),
      FinalidadeArquivo.avatar,
    );
    final id = _meuId;
    if (id != null) _fotos.remove(id);
  }

  @override
  String? get nomeSalvo => _ultimoNome;

  @override
  Future<PerfilCliente> carregar() async {
    final j = _mapa(await _api.get('/v1/me'));
    final nome = (j['nome'] as String?)?.trim();
    if (nome != null && nome.isNotEmpty && nome != 'Sua conta') {
      _ultimoNome = nome;
    }
    _meuId = j['id'] as String?;
    final foto = _meuId == null ? null : await fotoDe(_meuId!);
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
      fotoReferencia: foto,
      grupos: const [
        GrupoPerfil(
          titulo: 'CONTA',
          itens: [
            ItemPerfil(acao: AcaoPerfil.dadosPessoais, titulo: 'Dados pessoais'),
            ItemPerfil(acao: AcaoPerfil.enderecos, titulo: 'Endereços salvos'),
            ItemPerfil(acao: AcaoPerfil.favoritos, titulo: 'Profissionais favoritos'),
          ],
        ),
        GrupoPerfil(
          titulo: 'SEGURANÇA E AVISOS',
          itens: [
            ItemPerfil(acao: AcaoPerfil.contatosConfianca, titulo: 'Contatos de confiança'),
            ItemPerfil(acao: AcaoPerfil.notificacoes, titulo: 'Notificações'),
            ItemPerfil(acao: AcaoPerfil.usarComoProfissional, titulo: 'Usar como profissional'),
          ],
        ),
        GrupoPerfil(
          titulo: 'PRIVACIDADE E AJUDA',
          itens: [
            ItemPerfil(acao: AcaoPerfil.meusDados, titulo: 'Meus dados (LGPD)'),
            ItemPerfil(acao: AcaoPerfil.centralAjuda, titulo: 'Central de ajuda'),
            ItemPerfil(acao: AcaoPerfil.termos, titulo: 'Termos e políticas'),
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
    this.capturaFinalDoPedido,
    this.upload,
    this.fila,
    this.posicao,
  });

  /// Onde o profissional está agora (para calcular a distância dos pedidos). Pode ser nula.
  final Future<PosicaoAtual?> Function()? posicao;

  final ClienteApi _api;
  final CapturaCheckIn captura;

  /// Câmera e GPS ligados ao pedido (a foto sobe com o `pedido_id`). Sem ele vale [captura].
  final CapturaCheckIn Function(String pedidoId)? capturaDoPedido;

  /// Igual à de cima, mas a foto sobe com a finalidade `checkout` (foto final do serviço).
  final CapturaCheckIn Function(String pedidoId)? capturaFinalDoPedido;
  final ServicoUpload? upload;
  final FilaOffline? fila;

  /// `GET /v1/profissional/pedidos-abertos`. O backend já filtra por categoria, cidade, bairro,
  /// faixa de preço e recusas; não vêm distância, nem quantos já orçaram.
  @override
  Future<List<PedidoAberto>> pedidosAbertos(FiltroPedidosAbertos filtro) async {
    final onde = await posicao?.call();
    final consulta = {
      ...filtro.consulta,
      if (onde != null) 'lat': '${onde.latitude}',
      if (onde != null) 'lng': '${onde.longitude}',
    };
    final itens = _lista(await _api.get('/v1/profissional/pedidos-abertos', consulta: consulta));
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
      distanciaKm: (j['distancia_km'] as num?)?.toDouble(),
      latitude: (j['local_aprox_lat'] as num?)?.toDouble(),
      longitude: (j['local_aprox_lng'] as num?)?.toDouble(),
      clienteId: j['cliente_id'] as String?,
      clienteNome: j['cliente_nome'] as String?,
    );
  }

  /// Início = nome (`/v1/me`) + pedidos abertos + próximo atendimento (`/v1/pedidos`) + carteira
  /// (`/v1/profissionais/me/saldo`). Se TUDO falhar, o erro sobe para a tela mostrar "tentar de
  /// novo"; falha parcial mostra o que deu certo.
  @override
  Future<InicioProfissional> inicio() async {
    Object? primeiroErro;
    T? tentar<T>(T? Function() ler) {
      try {
        return ler();
      } catch (e) {
        primeiroErro ??= e;
        return null;
      }
    }

    Map<String, dynamic> me = const {};
    var abertos = <PedidoAberto>[];
    ProximoAtendimento? proximo;
    var contratados = <PedidoContratado>[];
    var carteira = const ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0);
    var deuCerto = false;
    try {
      me = _mapa(await _api.get('/v1/me'));
      deuCerto = true;
    } catch (e) {
      primeiroErro ??= e;
    }
    try {
      abertos = await pedidosAbertos(const FiltroPedidosAbertos(limite: 20));
      deuCerto = true;
    } catch (e) {
      // 403: cadastro ainda em análise. A tela mostra o motivo, não uma lista vazia.
      if (e is ErroTrato && e.codigoHttp == 403) rethrow;
      primeiroErro ??= e;
    }
    try {
      final saldo = _mapa(await _api.get('/v1/profissionais/me/saldo'));
      carteira = ResumoCarteira(
        retidoCentavos: (saldo['a_liberar_centavos'] as num?)?.toInt() ?? 0,
        paraSacarCentavos: (saldo['liberado_centavos'] as num?)?.toInt() ?? 0,
      );
      deuCerto = true;
    } catch (e) {
      primeiroErro ??= e;
    }
    try {
      final itensBrutos =
          _lista(await _api.get('/v1/pedidos', consulta: const {'como': 'profissional'}));
      final meus = <PedidoApi>[];
      for (final j in itensBrutos) {
        final p = tentar(() => PedidoApi.deJson(j));
        if (p != null) meus.add(p);
      }
      contratados = [
        for (final p in meus)
          if (_estadosDoProfissional.contains(p.estado)) _contratado(p),
      ];
      for (final p in meus) {
        if (const {'pago_e_retido', 'agendado', 'em_andamento'}.contains(p.estado)) {
          proximo = ProximoAtendimento(
            pedidoId: p.id,
            // Data e hora combinadas; antes de marcar a visita, diz isso em vez do nome do estado.
            quando: p.janelaRotulo ?? 'Data da visita ainda não marcada',
            titulo: 'Pedido ${p.numero}',
            endereco: '',
            janelaInicio: p.janelaInicio?.toLocal(),
            emAndamento: p.estado == 'em_andamento',
          );
          break;
        }
      }
      deuCerto = true;
    } catch (e) {
      primeiroErro ??= e;
    }
    if (!deuCerto && primeiroErro != null) throw primeiroErro!;
    final nomeMe = ((me['nome'] as String?) ?? '').trim();
    final primeiroNome = nomeMe.isNotEmpty ? nomeMe.split(' ').first : 'Profissional';
    return InicioProfissional(
      nome: primeiroNome.isEmpty ? 'Profissional' : primeiroNome,
      disponivelAgora: true,
      carteira: carteira,
      pedidos: abertos,
      proximo: proximo,
      contratados: contratados,
    );
  }

  /// Estados em que o pedido já é do profissional e ainda pede atenção dele. `concluido`,
  /// `cancelado` e o resto saem: o histórico fica na carteira e no perfil.
  static const _estadosDoProfissional = {
    'orcamento_aceito',
    'aguardando_confirmacao',
    'pago_e_retido',
    'agendado',
    'em_andamento',
    'em_confirmacao',
    'em_disputa',
    'retrabalho',
  };

  PedidoContratado _contratado(PedidoApi p) {
    final situacao = switch (p.estado) {
      'orcamento_aceito' => 'Orçamento aceito · aguardando o pagamento do cliente',
      'aguardando_confirmacao' => 'Pagamento sendo confirmado pelo parceiro',
      'pago_e_retido' => 'Pago · marque a data da visita',
      'agendado' => 'Agendado',
      'em_andamento' => 'Em execução',
      'em_confirmacao' => 'Aguardando a confirmação do cliente',
      'em_disputa' => 'Em análise (reclamação aberta)',
      'retrabalho' => 'Retrabalho em andamento',
      _ => p.estadoNome,
    };
    return PedidoContratado(
      pedidoId: p.id,
      titulo: 'Pedido ${p.numero}',
      situacao: situacao,
      estadoApi: p.estado,
      quando: p.janelaRotulo,
      janelaInicio: p.janelaInicio?.toLocal(),
    );
  }

  /// `POST /v1/pedidos/{id}/acoes/confirmar_agenda`: tira o pedido pago de `pago_e_retido` e
  /// libera o check-in. O backend confere a janela e gera o código de início do cliente.
  @override
  Future<void> confirmarAgenda(String pedidoId, DateTime inicio, DateTime fim) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/acoes/confirmar_agenda',
      corpo: {
        'prova': {
          'janela': {
            'inicio': inicio.toUtc().toIso8601String(),
            'fim': fim.toUtc().toIso8601String(),
          },
        },
      },
    );
  }

  /// `GET /v1/profissional/pedidos-abertos/{id}`: pedido que não está mais disponível responde 404.
  @override
  Future<DetalhePedido> detalhe(String pedidoId) async {
    final Map<String, dynamic> j;
    try {
      j = _mapa(await _api.get('/v1/profissional/pedidos-abertos/$pedidoId'));
    } on ErroTrato catch (e) {
      if (e.tipo == TipoErro.naoEncontrado) {
        throw const ErroTrato(TipoErro.naoEncontrado, 'Este pedido não está mais disponível.');
      }
      rethrow;
    }
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
    try {
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
    } catch (_) {
      return const [];
    }
  }

  String _curto(String id) => '#${id.substring(0, id.length < 4 ? id.length : 4).toUpperCase()}';

  @override
  ServicoOrcamento servicoOrcamento(String pedidoId) =>
      ServicoOrcamentoApi(_api, pedidoId: pedidoId);

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId) =>
      ServicoCheckInApi(
        _api,
        pedidoId: pedidoId,
        captura: capturaDoPedido?.call(pedidoId) ?? captura,
        upload: upload,
        fila: fila,
      );

  @override
  ServicoCheckOut servicoCheckOut(String pedidoId) {
    final captura = capturaFinalDoPedido?.call(pedidoId) ?? this.captura;
    final checkIn = ServicoCheckInApi(
      _api,
      pedidoId: pedidoId,
      captura: captura,
      upload: upload,
      fila: fila,
    );
    return ServicoCheckOutApi(checkIn, captura);
  }
}

/// `POST /v1/orcamentos/resumo` `{valor_centavos}` e `POST /v1/pedidos/{pedido_id}/orcamentos`.
/// Taxa e líquido vêm do backend; o app não calcula nada.
class ServicoOrcamentoApi implements ServicoOrcamento {
  ServicoOrcamentoApi(this._api, {this.pedidoId});

  final ClienteApi _api;
  final String? pedidoId;

  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async {
    final j = _mapa(
      await _api.post('/v1/orcamentos/resumo', corpo: {'valor_centavos': totalCentavos}),
    );
    return ResumoOrcamento(
      totalCentavos: j['valor_centavos'] as int,
      taxaCentavos: j['taxa_centavos'] as int,
      taxaBps: j['taxa_bps'] as int?,
      liquidoCentavos: j['liquido_centavos'] as int,
      clientePagaCentavos: j['total_cliente_centavos'] as int?,
    );
  }

  @override
  Future<void> enviar(OrcamentoPronto pronto) async {
    final id = pedidoId;
    if (id == null || id.isEmpty) {
      throw const ErroTrato(
        TipoErro.recusado,
        'Identificador do pedido obrigatório para enviar orçamento',
      );
    }

    final itens = <Map<String, dynamic>>[];
    // Por hora: a quantidade é o número de horas e o valor unitário é o valor da hora. Assim o
    // cliente vê as horas (deslocamento e trabalhadas) e o backend soma o total.
    if (pronto.decimosDeslocamento > 0 && pronto.valorHoraCentavos > 0) {
      itens.add({
        'tipo': 'deslocamento',
        'descricao': 'Horas de deslocamento',
        'quantidade': pronto.decimosDeslocamento / 10,
        'valor_unitario_centavos': pronto.valorHoraCentavos,
      });
    }
    if (pronto.decimosDeHora > 0 && pronto.valorHoraCentavos > 0) {
      itens.add({
        'tipo': 'horas',
        'descricao': 'Horas trabalhadas',
        'quantidade': pronto.decimosDeHora / 10,
        'valor_unitario_centavos': pronto.valorHoraCentavos,
      });
    }
    if (pronto.materialPorMim) {
      for (final item in pronto.itens) {
        if (item.centavos > 0) {
          itens.add({
            'tipo': 'material',
            'descricao': item.nome,
            'quantidade': 1,
            'valor_unitario_centavos': item.centavos,
          });
        }
      }
    }
    if (itens.isEmpty && pronto.totalCentavos > 0) {
      itens.add({
        'tipo': 'outro',
        'descricao': 'Serviço',
        'quantidade': 1,
        'valor_unitario_centavos': pronto.totalCentavos,
      });
    }

    final totalMaterial = pronto.materialPorMim
        ? pronto.itens.fold(0, (s, i) => s + i.centavos)
        : 0;
    final sinal = pronto.pedirSinalMaterial ? totalMaterial : 0;

    await _api.post(
      '/v1/pedidos/$id/orcamentos',
      corpo: {
        'itens': itens,
        'prazo_execucao_dias': 3,
        'validade_ate': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
        'sinal_material_centavos': sinal,
        'garantia_dias': pronto.garantiaDias,
      },
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
    return foto == null
        ? null
        : FotoChegada(
            hora: _hora(foto.tiradaEm.toLocal()),
            referencia: foto.arquivoId ?? foto.local?.sha256,
          );
  }

  /// A conferência é do backend; a distância aqui, quando existe, é só informativa.
  @override
  Future<int?> localizar() async {
    final posicao = _posicao = await captura.posicao();
    if (posicao == null) return null;
    return posicao.distanciaMetros ?? distanciaDesconhecidaMetros;
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
    return foto == null
        ? null
        : FotoChegada(
            hora: _hora(foto.tiradaEm.toLocal()),
            referencia: foto.arquivoId ?? foto.local?.sha256,
          );
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
