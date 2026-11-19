import '../dispositivo/servico_localizacao.dart';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../auth/servico_auth.dart';
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
import 'config_publica.dart';
import 'envio_fotos.dart';
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
  'nao_compareceu',
];

/// Textos e opções de tela que a API ainda não entrega. NÃO são regra de negócio.
class TextosPadraoTelas {
  const TextosPadraoTelas();

  List<String> get motivos => const [
        'O problema voltou ou não foi resolvido',
        'Qualidade abaixo do combinado',
        'Cobrança extra não combinada',
        'Dano no local',
        'O profissional abandonou o serviço',
        'O profissional não compareceu',
      ];
  List<String> get solucoes =>
      const ['Retrabalho sem custo', 'Reembolso parcial', 'Reembolso total'];
  int get prazoRespostaHoras => ConfigPublica.atual.prazoRespostaDisputaHoras;
  List<String> get criterios =>
      const ['Pontualidade', 'Qualidade', 'Limpeza', 'Comunicação', 'Preço justo'];
  List<int> get gorjetas => const [1000, 2000];
  String get garantiaCobre => 'Refazer o que está no orçamento, sem custo.';
  String get garantiaNaoCobre => 'Não cobre problemas novos nem serviços fora do orçamento.';
  int get prazoAtendimentoRetrabalhoDias => ConfigPublica.atual.prazoRetrabalhoDias;
  List<String> get respostasRapidas =>
      const ['Tudo certo', 'Pode me mandar foto?', 'Que horas termina?'];
}

/// Selo do nível de verificação: vazio no nível básico (a tela esconde o selo).
String seloDeVerificacao(String? nivel) => switch (nivel) {
      'verificado_plus' => 'Verificado Plus',
      'verificado' => 'Verificado',
      _ => '',
    };

/// "12 horas", "40 minutos" até [fim]; vazio se já passou.
String _tempoRestante(DateTime fim, {DateTime? agora}) {
  final falta = fim.toLocal().difference((agora ?? DateTime.now()).toLocal());
  if (falta.inMinutes <= 0) return '';
  if (falta.inHours >= 1) return ConfigPublica.horas(falta.inHours);
  return '${falta.inMinutes} ${falta.inMinutes == 1 ? 'minuto' : 'minutos'}';
}

/// Resposta do cliente em texto: "Sim"/"Não", lista separada por vírgula, número ou texto.
String textoDaResposta(Object? r) => switch (r) {
      true => 'Sim',
      false => 'Não',
      final List<dynamic> l => l.join(', '),
      null => '—',
      _ => '$r',
    };

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

  static DadosDoPedido dadosDeJson(Map<String, dynamic> j) => _dadosDeJson(j);

  static DadosDoPedido _dadosDeJson(Map<String, dynamic> j) {
    final e = j['endereco'] as Map<String, dynamic>?;
    return DadosDoPedido(
      titulo: j['titulo'] as String,
      descricao: j['descricao'] as String,
      faixaMinCentavos: j['faixa_preco_min_centavos'] as int?,
      faixaMaxCentavos: j['faixa_preco_max_centavos'] as int?,
      logradouro: e?['logradouro'] as String?,
      numero: e?['numero'] as String?,
      bairro: e?['bairro'] as String?,
      complemento: e?['complemento'] as String?,
      cep: e?['cep'] as String?,
      referencia: e?['referencia'] as String?,
      modalidade: (j['modalidade'] as String?) ?? 'presencial',
      fotos: [
        for (final u in (j['fotos_urls'] as List? ?? const []))
          if (u is String && u.isNotEmpty) u,
      ],
      profissionalConvidadoId: j['profissional_convidado_id'] as String?,
    );
  }

  Future<List<String>> fotosDoPedidoAberto(String pedidoId) async {
    try {
      final itens = _lista(
        await _api.get('/v1/pedidos/$pedidoId/fotos', consulta: const {'finalidade': 'pedido'}),
      );
      return [
        for (final f in itens)
          if (f['url'] is String && (f['url'] as String).isNotEmpty) f['url'] as String,
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<DadosDoPedido> dados(String pedidoId) async =>
      _dadosDeJson(_mapa(await _api.get('/v1/pedidos/$pedidoId/dados')));

  @override
  Future<DadosDoPedido> editar(
    String pedidoId, {
    String? descricao,
    int? faixaMinCentavos,
    int? faixaMaxCentavos,
    String? cep,
    String? logradouro,
    String? numero,
    String? bairro,
    String? complemento,
  }) async {
    final cepLimpo = cep?.replaceAll(RegExp(r'\D'), '');
    final corpo = <String, Object?>{
      if (descricao != null) 'descricao': descricao,
      if (faixaMinCentavos != null) 'faixa_preco_min_centavos': faixaMinCentavos,
      if (faixaMaxCentavos != null) 'faixa_preco_max_centavos': faixaMaxCentavos,
      if (logradouro != null && logradouro.trim().isNotEmpty)
        'endereco': {
          if (cepLimpo != null && cepLimpo.length == 8) 'cep': cepLimpo,
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
      profissionalNome: p.profissionalNome ?? '',
      titulo: p.rotulo,
      subtitulo: p.rotulo == 'Pedido ${p.numero}'
          ? 'Aberto em ${_dia(p.abertoEm)}'
          : 'Pedido ${p.numero} · aberto em ${_dia(p.abertoEm)}',
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
      if (rascunho.endereco != null && rascunho.modalidade == Modalidade.presencial)
        'bairro': rascunho.endereco!.bairro.trim()
      else if (rascunho.bairro != null && rascunho.bairro!.isNotEmpty)
        'bairro': rascunho.bairro,
      'modalidade': rascunho.modalidade.codigo,
      // Presencial leva o endereço completo (o profissional só o vê depois de contratado).
      if (rascunho.modalidade == Modalidade.presencial && rascunho.endereco != null)
        'endereco': rascunho.endereco!.paraJson(),
      if (rascunho.prazoDesejado != null)
        'prazo_desejado': rascunho.prazoDesejado!.toIso8601String().substring(0, 10),
      'titulo': rascunho.servicos.isNotEmpty ? rascunho.servicos.join(', ') : 'Pedido de serviço',
      'descricao': rascunho.descricao.trim().isNotEmpty
          ? rascunho.descricao.trim()
          : 'Serviço solicitado pelo cliente',
      'faixa_preco_min_centavos': rascunho.faixa.minimoCentavos,
      'faixa_preco_max_centavos': rascunho.faixa.maximoCentavos,
      'urgente': rascunho.urgente,
      if ((rascunho.profissionalConvidadoId ?? '').trim().isNotEmpty)
        'profissional_convidado_id': rascunho.profissionalConvidadoId!.trim(),
      'respostas': [
        for (final e in rascunho.respostas.entries)
          {'pergunta_id': e.key, 'resposta': e.value},
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
    // Em paralelo: pedido, eventos, saldo, aditivos e notas de materiais.
    final ((pedido, eventosBrutos), (saldo, (aditivosBruto, notasBruto))) =
        await emParalelo2(
      emParalelo2(
        _pedido(pedidoId),
        _api.get('/v1/pedidos/$pedidoId/eventos'),
      ),
      emParalelo2(
        _saldo(pedidoId).then<SaldoPedidoApi?>((v) => v).catchError((Object _) => null),
        emParalelo2(
          _api
              .get('/v1/contratos/$pedidoId/aditivos')
              .then<Object?>((v) => v)
              .catchError((Object _) => null),
          _api
              .get('/v1/contratos/$pedidoId/notas-material')
              .then<Object?>((v) => v)
              .catchError((Object _) => null),
        ),
      ),
    );
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
    final etapaMapeada = etapaDoEstado[pedido.estado];
    final quando = <int, DateTime>{};
    for (final e in eventos) {
      final etapa = etapaDaAcao[e.acao];
      if (etapa != null) quando[etapa] = e.em.toLocal();
    }
    final checkIn = quando[3];
    if (checkIn != null) quando[2] = checkIn;
    var maiorRegistrada = -1;
    for (final k in quando.keys) {
      if (k > maiorRegistrada) maiorRegistrada = k;
    }
    final etapas = [
      for (var i = 0; i < titulos.length; i++)
        EtapaLinhaDoTempo(
          titulo: titulos[i],
          detalhe: quando[i] != null ? '${_dia(quando[i]!)} · ${_hora(quando[i]!)}' : '',
          estado: etapaMapeada != null
              ? (i < etapaMapeada
                  ? EstadoEtapa.feita
                  : i == etapaMapeada
                      ? EstadoEtapa.atual
                      : EstadoEtapa.futura)
              : pedido.estado == 'cancelado'
                  ? (quando.containsKey(i) ? EstadoEtapa.feita : EstadoEtapa.futura)
                  : quando.containsKey(5)
                      ? EstadoEtapa.feita
                      : (i < maiorRegistrada
                          ? EstadoEtapa.feita
                          : i == maiorRegistrada
                              ? EstadoEtapa.atual
                              : EstadoEtapa.futura),
        ),
    ];
    Aditivo? aditivoPendente;
    final aditivos = <ItemResumoAditivo>[];
    var aditivosPagos = 0;
    var aditivosAprovados = 0;
    if (aditivosBruto is List) {
      for (final a in _lista(aditivosBruto)) {
        final estado = (a['estado'] as String?) ?? 'proposto';
        final valor = (a['valor_centavos'] as num?)?.toInt() ?? 0;
        final desc = (a['descricao'] as String?) ?? '';
        if (estado == 'proposto' && aditivoPendente == null) {
          aditivoPendente = Aditivo(
            titulo: 'Aditivo proposto',
            valorCentavos: valor,
            descricao: desc,
            mostrarFoto: false,
          );
        }
        if (estado == 'pago') aditivosPagos += valor;
        if (estado == 'aprovado') aditivosAprovados += valor;
        aditivos.add(
          ItemResumoAditivo(
            id: (a['id'] as String?) ?? '',
            descricao: desc,
            valorCentavos: valor,
            estado: estado,
            estadoTexto: switch (estado) {
              'aprovado' => 'Aprovado',
              'pago' => 'Pago',
              'recusado' => 'Recusado',
              _ => 'Aguardando aprovação',
            },
          ),
        );
      }
    }
    final notas = <ItemResumoNota>[];
    var totalNotas = 0;
    if (notasBruto is List) {
      final notasLista = _lista(notasBruto)
        ..sort((a, b) => ((a['enviada_em'] as String?) ?? '')
            .compareTo((b['enviada_em'] as String?) ?? ''));
      for (var i = 0; i < notasLista.length; i++) {
        final n = notasLista[i];
        final valor = (n['total_centavos'] as num?)?.toInt() ?? 0;
        totalNotas += valor;
        final itens = [
          for (final item in (n['itens'] as List? ?? const []))
            if (item is Map && item['descricao'] is String)
              (item['descricao'] as String).trim(),
        ].where((s) => s.isNotEmpty).toList();
        final enviadaRaw = n['enviada_em'] as String?;
        notas.add(
          ItemResumoNota(
            numero: i + 1,
            totalCentavos: valor,
            itensResumo: itens.join(', '),
            enviadaEm: enviadaRaw == null
                ? DateTime.now()
                : DateTime.parse(enviadaRaw).toLocal(),
          ),
        );
      }
    }
    int? orcamentoCentavos;
    int? totalAtualizadoCentavos;
    if (saldo != null && saldo.clientePagouCentavos > 0) {
      final base = saldo.clientePagouCentavos >= aditivosPagos
          ? saldo.clientePagouCentavos - aditivosPagos
          : saldo.clientePagouCentavos;
      orcamentoCentavos = base;
      totalAtualizadoCentavos = base + aditivosPagos + aditivosAprovados;
    }
    return PedidoEmExecucao(
      numero: pedido.numero,
      titulo: switch (pedido.estado) {
        'orcamento_aceito' => 'Aguardando o pagamento',
        'pago_e_retido' => 'Pagamento confirmado',
        'agendado' => 'Visita marcada',
        'em_andamento' => 'Serviço em execução',
        'em_confirmacao' => 'Confirme o serviço',
        'concluido' => 'Serviço finalizado',
        'em_disputa' => 'Reclamação em análise',
        'retrabalho' => 'Retrabalho em andamento',
        'cancelado' => 'Pedido cancelado',
        _ => 'Seu pedido',
      },
      podeVerConclusao: const {'em_confirmacao', 'concluido'}.contains(pedido.estado),
      pagamentoConfirmado: pedido.pagamentoConfirmado,
      estadoApi: pedido.estado,
      etapas: etapas,
      aditivo: aditivoPendente,
      aditivos: aditivos,
      notas: notas,
      orcamentoCentavos: orcamentoCentavos,
      totalAtualizadoCentavos: totalAtualizadoCentavos,
      totalNotasCentavos: notas.isEmpty ? null : totalNotas,
      fotos: const [],
      // O código de conclusão é o que o cliente passa ao profissional para encerrar o serviço.
      codigoConclusao: pedido.estado == 'em_andamento' && (pedido.codigoConclusao ?? '').isNotEmpty
          ? pedido.codigoConclusao
          : null,
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
    // Aditivos já pagos: saem do total para a linha "Orçamento" mostrar só o combinado.
    var aditivosPagos = 0;
    try {
      for (final a in _lista(await _api.get('/v1/contratos/$pedidoId/aditivos'))) {
        if (a['estado'] == 'pago') aditivosPagos += (a['valor_centavos'] as num).toInt();
      }
    } on ErroTrato {
      aditivosPagos = 0;
    }
    if (aditivosPagos > saldo.clientePagouCentavos) aditivosPagos = 0;
    return ResumoConclusao(
      numeroPedido: pedido.numero,
      nomeProfissional: await _nomeDoProfissional(pedido),
      fotoAntes: fotos['antes'],
      fotoDepois: fotos['depois'],
      fotosCarregadas: true,
      legendaFotoAntes: 'Antes',
      legendaFotoDepois: 'Depois',
      orcamentoCentavos: saldo.clientePagouCentavos - aditivosPagos,
      aditivoCentavos: aditivosPagos,
      codigo: pedido.codigoConclusao ?? '',
      avisoLiberacao: ConfigPublica.atual.textoLiberacao,
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
      titulo: pedido.rotulo,
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
    final fotos = await enviarFotosLocais(
      upload,
      relato.fotos,
      FinalidadeArquivo.evidenciaDisputa,
      pedidoId: pedidoId,
    );
    await _api.post(
      '/v1/pedidos/$pedidoId/disputa',
      corpo: {
        'motivo': _motivosDisputa[indice < 0 ? 0 : indice],
        'descricao': '${relato.descricao}\n\nSolução que o cliente prefere: ${relato.solucao}',
        'fotos': fotos,
      },
    );
  }

  /// `POST /v1/contratos/{id}/avaliacao`. A nota geral é a média das notas dadas por critério
  /// (arredondada, de 1 a 5). Gorjeta não tem rota: em vez de sumir em silêncio, recusa.
  @override
  Future<int> avaliar(String pedidoId, EnvioAvaliacao avaliacao) async {
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
    final resposta = await _api.post(
      '/v1/contratos/$pedidoId/avaliacao',
      corpo: {'nota_geral': media, if (comentario.isNotEmpty) 'comentario': comentario},
    );
    if (resposta is Map && resposta['moedas_ganhas'] is int) {
      return resposta['moedas_ganhas'] as int;
    }
    return 0;
  }

  @override
  Future<DadosAvaliacao> dadosAvaliacao(String pedidoId) async {
    final (saldo, pedido) = await emParalelo2(_saldo(pedidoId), _pedido(pedidoId));
    return DadosAvaliacao(
      nomeProfissional: await _nomeDoProfissional(pedido),
      valorLiberadoCentavos: saldo.clientePagouCentavos,
      criterios: textos.criterios,
      gorjetasCentavos: textos.gorjetas,
      // Sem rota de gorjeta no servidor: a tela não oferece o que não dá para pagar.
      gorjetaDisponivel: false,
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
    final fotos = await _fotosDoServico(pedidoId);
    return DadosGarantia(
      fotoAntes: fotos['antes'],
      fotoDepois: fotos['depois'],
      titulo: 'Garantia do pedido ${PedidoApi.numeroDe(pedidoId)}',
      diasTotal: (j['dias'] as int?) ?? 0,
      diasRestantes: falta < 0 ? 0 : falta,
      fimEm: fim.toLocal(),
      cobre: textos.garantiaCobre,
      naoCobre: textos.garantiaNaoCobre,
      prazoAtendimentoDias: textos.prazoAtendimentoRetrabalhoDias,
    );
  }

  /// O contrato: pedido (`/v1/pedidos/{id}`), o que foi descrito (`/dados`), o saldo do ledger,
  /// os aditivos e o nome de quem contratou (`/v1/me`). Falha numa parte só esconde a parte.
  @override
  Future<DadosContrato> contrato(String pedidoId) async {
    final pedido = await _pedido(pedidoId);
    Map<String, dynamic> dados = const {};
    try {
      dados = _mapa(await _api.get('/v1/pedidos/$pedidoId/dados'));
    } on ErroTrato {
      dados = const {};
    }
    int? pago;
    try {
      final s = await _saldo(pedidoId);
      pago = pedido.pagamentoConfirmado ? s.clientePagouCentavos : null;
    } on ErroTrato {
      pago = null;
    }
    var aditivos = <Map<String, dynamic>>[];
    try {
      aditivos = _lista(await _api.get('/v1/contratos/$pedidoId/aditivos'));
    } on ErroTrato {
      aditivos = [];
    }
    String? cliente;
    try {
      final eu = _mapa(await _api.get('/v1/me'));
      final nome = ((eu['nome'] as String?) ?? '').trim();
      cliente = nome.isEmpty ? null : nome;
    } on ErroTrato {
      cliente = null;
    }
    final remoto = dados['modalidade'] == 'remoto' || pedido.remoto;
    final endereco = dados.isEmpty ? null : RepositorioPedidosApi.dadosDeJson(dados).enderecoCompleto;
    String situacao(String? e) => switch (e) {
          'proposto' => 'aguardando sua aprovação',
          'aprovado' => 'aprovado, aguardando pagamento',
          'pago' => 'pago',
          'recusado' => 'recusado',
          _ => e ?? '',
        };
    final aceite = pedido.contratadoEm?.toLocal();
    return DadosContrato(
      numeroPedido: pedido.numero,
      titulo: pedido.rotulo,
      descricao: ((dados['descricao'] as String?) ?? '').trim(),
      local: remoto
          ? 'Atendimento remoto'
          : (endereco == null || endereco.isEmpty ? 'Endereço não informado' : endereco),
      cliente: cliente,
      contratadoEm: aceite == null
          ? null
          : '${_doisDigitos(aceite.day)}/${_doisDigitos(aceite.month)}/${aceite.year}',
      visita: pedido.janelaRotulo,
      respostas: [
        for (final r in _lista(dados['respostas'] ?? const []))
          LinhaContrato('${r['pergunta']}', textoDaResposta(r['resposta'])),
      ],
      pagoCentavos: pago,
      aditivos: [
        for (final a in aditivos)
          LinhaContrato(
            '${a['descricao'] ?? 'Aditivo'} · ${situacao(a['estado'] as String?)}',
            formatarReais((a['valor_centavos'] as num?)?.toInt() ?? 0),
          ),
      ],
      prazoRetrabalhoDias: ConfigPublica.atual.prazoRetrabalhoDias,
    );
  }

  /// `POST /v1/pedidos/{id}/acoes/cancelar` `{prova: {motivo}}`.
  @override
  Future<void> cancelar(String pedidoId, String motivo) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/acoes/cancelar',
      corpo: {
        'prova': {'motivo': motivo},
      },
    );
  }

  @override
  Future<void> remarcarAgenda(String pedidoId, DateTime inicio, DateTime fim) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/acoes/remarcar',
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

  @override
  Future<void> pedirRetrabalho(
    String pedidoId,
    String descricao, {
    List<String> fotos = const [],
  }) async {
    final enviadas = await enviarFotosLocais(
      upload,
      fotos,
      FinalidadeArquivo.retrabalho,
      pedidoId: pedidoId,
    );
    await _api.post(
      '/v1/pedidos/$pedidoId/retrabalho',
      corpo: {'descricao': descricao, 'fotos': enviadas},
    );
  }
}

class RepositorioOrcamentosApi implements RepositorioOrcamentos {
  RepositorioOrcamentosApi(this._api);

  final ClienteApi _api;

  /// `POST /v1/pedidos/{id}/orcamentos/{orc}/contraproposta` `{valor_centavos, prazo_execucao_dias?, mensagem?}`.
  @override
  Future<void> contraproporValor(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
    String? mensagem,
  }) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/orcamentos/$orcamentoId/contraproposta',
      corpo: {
        'valor_centavos': valorCentavos,
        if (prazoExecucaoDias != null) 'prazo_execucao_dias': prazoExecucaoDias,
        if (mensagem != null && mensagem.trim().isNotEmpty) 'mensagem': mensagem.trim(),
      },
    );
  }

  /// `POST .../contraproposta/aceitar` `{valor_centavos, prazo_execucao_dias?}`: nova versão do orçamento.
  @override
  Future<void> aceitarContraproposta(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
  }) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/orcamentos/$orcamentoId/contraproposta/aceitar',
      corpo: {
        'valor_centavos': valorCentavos,
        if (prazoExecucaoDias != null) 'prazo_execucao_dias': prazoExecucaoDias,
      },
    );
  }

  /// `POST /v1/pedidos/{id}/orcamentos/{orc}/propor` `{valor_centavos, prazo_execucao_dias?, mensagem?}`.
  @override
  Future<void> proporNovaCondicao(
    String pedidoId,
    String orcamentoId,
    int valorCentavos, {
    int? prazoExecucaoDias,
    String? mensagem,
  }) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/orcamentos/$orcamentoId/propor',
      corpo: {
        'valor_centavos': valorCentavos,
        if (prazoExecucaoDias != null) 'prazo_execucao_dias': prazoExecucaoDias,
        if (mensagem != null && mensagem.trim().isNotEmpty) 'mensagem': mensagem.trim(),
      },
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
        titulo: pedido.rotulo,
        recebidos: brutos.length,
        // O limite e a janela vêm da configuração (`limite_orcamentos_por_pedido` e
        // `validade_pedido_horas`); o tempo restante só enquanto o pedido está aberto.
        limite: brutos.length > ConfigPublica.atual.limiteOrcamentos
            ? brutos.length
            : ConfigPublica.atual.limiteOrcamentos,
        tempoRestante: pedido.estado == 'aberto'
            ? _tempoRestante(
                pedido.abertoEm.add(Duration(hours: ConfigPublica.atual.validadePedidoHoras)),
              )
            : '',
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
              // O backend manda a quantidade como texto decimal ("45.00").
              quantidade: double.tryParse('${i['quantidade']}'),
              unitarioCentavos: (i['valor_unitario_centavos'] as num?)?.toInt(),
              porHora: const {'horas', 'deslocamento'}.contains(i['tipo']),
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
    final nota = (j['profissional_nota'] as num?)?.toDouble();
    final servicos = (j['profissional_servicos_concluidos'] as num?)?.toInt();
    return Orcamento(
      id: j['id'] as String,
      profissional: nome,
      iniciais: _iniciais(nome),
      verificacao: seloDeVerificacao(j['profissional_nivel_verificacao'] as String?),
      totalCentavos: j['valor_centavos'] as int,
      nota: nota ?? 0,
      notaResumo: nota == null ? semAvaliacoes : nota.toStringAsFixed(1).replaceAll('.', ','),
      servicosResumo: '${servicos ?? 0}',
      servicosConcluidos: servicos ?? 0,
      quando: _quandoRelativo(enviadoEm),
      inicio: enviadoEm,
      garantia: garantia == null ? '' : '$garantia dias',
      observacao: (j['observacoes'] as String?) ?? '',
      detalhe: detalhe,
      aceito: j['aceito'] == true,
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

  DadosPagamento _dadosDeMapa(String pedidoId, Map<String, dynamic> j) {
    final valor = j['valor_centavos'] as int?;
    if (valor == null) {
      throw const ErroTrato(TipoErro.recusado, 'Este pedido ainda não tem um valor a pagar.');
    }
    final meios = [for (final m in (j['meios_disponiveis'] as List? ?? const [])) m as String];
    return DadosPagamento(
      subtitulo: 'Pedido ${PedidoApi.numeroDe(pedidoId)}',
      valorAgoraCentavos: (j['total_a_pagar_centavos'] as int?) ?? valor,
      descontoCentavos: (j['desconto_centavos'] as num?)?.toInt() ?? 0,
      cupomCodigo: j['cupom_codigo'] as String?,
      moedasSaldo: (j['moedas_saldo'] as num?)?.toInt() ?? 0,
      moedasUsadas: (j['moedas_usadas'] as num?)?.toInt() ?? 0,
      moedasDescontoCentavos: (j['moedas_desconto_centavos'] as num?)?.toInt() ?? 0,
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
            descricao: 'Pagamento seguro processado no app.',
          ),
      ],
    );
  }

  /// `GET /v1/pedidos/{id}/pagamento`: valor do contrato e meios disponíveis (`pix`, `cartao`).
  @override
  Future<DadosPagamento> dados(String pedidoId) async =>
      _dadosDeMapa(pedidoId, _mapa(await _api.get('/v1/pedidos/$pedidoId/pagamento')));

  @override
  Future<DadosPagamento> recalcular(
    String pedidoId, {
    String? cupom,
    bool usarMoedas = false,
  }) async {
    final limpo = (cupom ?? '').trim();
    return _dadosDeMapa(
      pedidoId,
      _mapa(await _api.get(
        '/v1/pedidos/$pedidoId/pagamento',
        consulta: {
          if (limpo.isNotEmpty) 'cupom': limpo,
          if (usarMoedas) 'usar_moedas': 'true',
        },
      )),
    );
  }

  /// `POST /v1/contratos/{id}/cupom` `{codigo}`: valida e calcula desconto no servidor.
  @override
  Future<DadosPagamento> aplicarCupom(String pedidoId, String codigo) async {
    final limpo = codigo.trim();
    if (limpo.isEmpty) {
      return dados(pedidoId);
    }
    final j = _mapa(
      await _api.post('/v1/contratos/$pedidoId/cupom', corpo: {'codigo': limpo}),
    );
    return _dadosDeMapa(pedidoId, j);
  }

  /// `POST /v1/contratos/{id}/cobranca` `{meio, parcelas, cupom}`. Repetir devolve a mesma cobrança pendente.
  /// O segredo do cartão (`instrucao`) nunca vai para a tela.
  @override
  Future<Cobranca> criarCobranca(
    String pedidoId,
    MetodoPagamento metodo, {
    int parcelas = 1,
    String? cupom,
    bool usarMoedas = false,
  }) async {
    final meio = metodo == MetodoPagamento.pix ? 'pix' : 'cartao';
    final cupomLimpo = (cupom ?? '').trim();
    final sufixoParcela = metodo == MetodoPagamento.cartao && parcelas > 1 ? '-${parcelas}x' : '';
    final sufixoCupom = (cupomLimpo.isEmpty ? '' : '-${cupomLimpo.toUpperCase()}') +
        (usarMoedas ? '-moedas' : '');
    final j = _mapa(
      await _api.post(
        '/v1/contratos/$pedidoId/cobranca',
        corpo: {
          'meio': meio,
          if (metodo == MetodoPagamento.cartao && parcelas > 1) 'parcelas': parcelas,
          if (cupomLimpo.isNotEmpty) 'cupom': cupomLimpo,
          if (usarMoedas) 'usar_moedas': true,
        },
        chaveIdempotencia: 'cobranca-$pedidoId-$meio$sufixoParcela$sufixoCupom',
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
    final (contra, semContra) = ContrapropostaChat.ler(bruto);
    final (agenda, texto) =
        contra == null ? PropostaAgendaChat.ler(semContra) : (null, semContra);
    return MensagemChat(
      id: (m['id'] as num?)?.toInt(),
      tipo: contra == null && agenda == null && ehMensagemFoto(bruto)
          ? TipoMensagem.foto
          : TipoMensagem.texto,
      hora: _hora(DateTime.parse(m['enviada_em'] as String).toLocal()),
      texto: texto,
      minha: m['minha'] == true,
      lida: m['lida_em'] != null,
      recebida: m['entregue_em'] != null || m['lida_em'] != null,
      contraproposta: contra,
      propostaAgenda: agenda,
    );
  }

  @override
  Future<void> proporAgenda(
    String pedidoId,
    DateTime inicio,
    DateTime fim, {
    String justificativa = '',
  }) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/agenda/propor',
      corpo: {
        'janela': {
          'inicio': inicio.toUtc().toIso8601String(),
          'fim': fim.toUtc().toIso8601String(),
        },
        if (justificativa.trim().isNotEmpty) 'justificativa': justificativa.trim(),
      },
    );
  }

  @override
  Future<void> aceitarAgenda(
    String pedidoId, {
    int? mensagemId,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/agenda/aceitar',
      corpo: {
        if (mensagemId != null) 'mensagem_id': mensagemId,
        if (inicio != null && fim != null)
          'janela': {
            'inicio': inicio.toUtc().toIso8601String(),
            'fim': fim.toUtc().toIso8601String(),
          },
      },
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
    final numero = PedidoApi.numeroDe(pedidoId);
    final ((mensagens, orcamentos), (pedidoObj, interlocutor)) = await emParalelo2(
      emParalelo2(
        _api.get('/v1/pedidos/$pedidoId/mensagens', consulta: _consulta(profissionalId))
            .then(_lista),
        _api
            .get('/v1/pedidos/$pedidoId/orcamentos')
            .then(_lista)
            .catchError((Object _) => const <Map<String, dynamic>>[]),
      ),
      emParalelo2(
        _api.get('/v1/pedidos/$pedidoId').then<PedidoApi?>((b) => PedidoApi.deJson(_mapa(b))).catchError((Object e) {
          if (e is ErroTrato && e.tipo != TipoErro.naoEncontrado) throw e;
          return null;
        }),
        _api
            .get('/v1/pedidos/$pedidoId/interlocutor', consulta: _consulta(profissionalId))
            .then<Map<String, dynamic>?>((b) => _mapa(b))
            .catchError((Object _) => null),
      ),
    );
    final situacao = pedidoObj?.estadoNome ?? 'Pedido aberto';
    final pedidoAberto = pedidoObj == null || pedidoObj.estado == 'aberto';
    final orcamentosAtivos = {
      for (final o in orcamentos)
        if (o['id'] is String && o['aceito'] != true && pedidoAberto) o['id'] as String,
    };
    var nome = 'Pedido $numero';
    var iniciais = '#';
    String? outroId;
    if (interlocutor != null) {
      final n = ((interlocutor['nome'] as String?) ?? '').trim();
      if (n.isNotEmpty) {
        nome = n;
        iniciais = _iniciaisDe(n);
        outroId = interlocutor['id'] as String?;
      }
    }
    final meuId = ServicoAuthPadrao.atual.sessaoAtual?.id;
    final souCliente = interlocutor?['papel'] == 'cliente'
        ? false
        : (interlocutor?['papel'] == 'profissional'
            ? true
            : (pedidoObj != null && meuId != null
                ? pedidoObj.clienteId == meuId
                : ServicoAuthPadrao.atual.sessaoAtual?.ehProfissional != true));
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
      orcamentosAtivos: orcamentosAtivos,
      pedidoAberto: pedidoAberto,
      souCliente: souCliente,
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
          // Foto enviada por versão antiga do app: o texto é o CAMINHO do arquivo no celular de
          // quem mandou. Em outro aparelho não abre (e mostrar o caminho confunde).
          if (achou == null && m['minha'] != true && _ehCaminhoLocal(texto)) {
            return {...m, 'texto': '[Foto indisponível]'};
          }
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

  static bool _ehCaminhoLocal(String texto) =>
      RegExp(r'^(/|file://)[^\s]+\.(jpe?g|png|webp|heic)$', caseSensitive: false).hasMatch(texto);

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

  /// `POST /v1/notificacoes/{id}/lida`. Repetir é seguro.
  @override
  Future<void> marcarLida(String id) async {
    await _api.post('/v1/notificacoes/$id/lida');
  }

  String? _destino(Object? dados) {
    if (dados is! Map) return null;
    final id = dados['disputa_id'] ?? dados['pedido_id'];
    return id is String ? id : null;
  }

  @override
  Future<List<PreferenciaNotificacao>> carregarPreferencias() async {
    final j = _mapa(await _api.get('/v1/notificacoes/preferencias'));
    final cats = _mapa(j['categorias']);
    return [
      for (final e in cats.entries)
        () {
          final canais = _mapa(e.value);
          return PreferenciaNotificacao(
            categoria: e.key,
            app: canais['app'] != false,
            push: canais['push'] != false,
            email: canais['email'] != false,
          );
        }(),
    ];
  }

  @override
  Future<List<PreferenciaNotificacao>> salvarPreferencias(
    List<PreferenciaNotificacao> itens,
  ) async {
    final payload = {
      'categorias': {
        for (final item in itens)
          item.categoria: {
            'app': item.app,
            'push': item.push,
            'email': item.email,
          },
      },
    };
    final j = _mapa(await _api.put('/v1/notificacoes/preferencias', corpo: payload));
    final cats = _mapa(j['categorias']);
    return [
      for (final e in cats.entries)
        () {
          final canais = _mapa(e.value);
          return PreferenciaNotificacao(
            categoria: e.key,
            app: canais['app'] != false,
            push: canais['push'] != false,
            email: canais['email'] != false,
          );
        }(),
    ];
  }

  @override
  Future<void> registrarDispositivo(String token, String plataforma) async {
    final limpo = token.trim();
    if (limpo.length < 8) return;
    await _api.post(
      '/v1/dispositivos',
      corpo: {'token': limpo, 'plataforma': plataforma},
    );
  }

  @override
  Future<void> removerDispositivo(String token) async {
    final limpo = token.trim();
    if (limpo.length < 8) return;
    await _api.delete('/v1/dispositivos', corpo: {'token': limpo});
  }
}

/// `GET` e `PATCH /v1/me`. O primeiro `GET /v1/me` depois do login cria o usuário no backend.
class RepositorioPerfilApi implements RepositorioPerfil {
  RepositorioPerfilApi(this._api, {this.upload});

  final ClienteApi _api;
  final ServicoUpload? upload;
  String? _ultimoNome;
  String? _meuId;
  Future<PerfilCliente>? _carregarEmVoo;

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
  Future<PerfilCliente> carregar() {
    final ativo = _carregarEmVoo;
    if (ativo != null) return ativo;
    final busca = _carregarDoServidor();
    _carregarEmVoo = busca;
    return busca.whenComplete(() {
      if (identical(_carregarEmVoo, busca)) _carregarEmVoo = null;
    });
  }

  Future<PerfilCliente> _carregarDoServidor() async {
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
    int? moedas;
    try {
      final m = _mapa(await _api.get('/v1/me/moedas'));
      moedas = m['saldo'] as int?;
    } on Object {
      moedas = null; // moedas são extra: falha aqui não derruba o perfil
    }
    return PerfilCliente(
      moedas: moedas,
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
  Future<InicioProfissional>? _inicioEmVoo;

  /// `GET /v1/profissional/pedidos-abertos`. O backend já filtra por categoria, cidade, bairro,
  /// faixa de preço e recusas; não vêm distância, nem quantos já orçaram.
  @override
  Future<List<PedidoAberto>> pedidosAbertos(FiltroPedidosAbertos filtro) async {
    final onde = await _posicaoRapida();
    final consulta = {
      ...filtro.consulta,
      if (onde != null) 'lat': '${onde.latitude}',
      if (onde != null) 'lng': '${onde.longitude}',
    };
    final itens = _lista(await _api.get('/v1/profissional/pedidos-abertos', consulta: consulta));
    final meuId = ServicoAuthPadrao.atual.sessaoAtual?.id;
    return [
      for (final j in itens)
        if (meuId == null || j['cliente_id'] != meuId) _pedidoAberto(j),
    ];
  }

  /// A localização só serve para mostrar a distância dos pedidos (limite curto de 1,5 s para não
  /// travar a tela inicial do profissional).
  Future<PosicaoAtual?> _posicaoRapida() async {
    final buscar = posicao;
    if (buscar == null) return null;
    try {
      return await buscar().timeout(const Duration(milliseconds: 1500));
    } on Object {
      return null;
    }
  }

  PedidoAberto _pedidoAberto(Map<String, dynamic> j) {
    final prazo = j['prazo_desejado'] as String?;
    final urgente = j['urgente'] == true;
    final textoData = prazo == null ? 'Sem data fixa' : 'Até ${_dia(DateTime.parse(prazo))}';
    return PedidoAberto(
      id: j['id'] as String,
      titulo: j['titulo'] as String,
      bairro: (j['bairro'] as String?) ?? '',
      prazo: urgente ? (prazo == null ? 'Urgente' : 'Urgente · até ${_dia(DateTime.parse(prazo))}') : textoData,
      faixaMinCentavos: j['faixa_preco_min_centavos'] as int?,
      faixaMaxCentavos: j['faixa_preco_max_centavos'] as int?,
      urgente: urgente,
      distanciaKm: (j['distancia_km'] as num?)?.toDouble(),
      latitude: (j['local_aprox_lat'] as num?)?.toDouble(),
      longitude: (j['local_aprox_lng'] as num?)?.toDouble(),
      clienteId: j['cliente_id'] as String?,
      clienteNome: j['cliente_nome'] as String?,
      modalidade: (j['modalidade'] as String?) ?? 'presencial',
      convidado: j['convidado'] == true,
    );
  }

  /// Início = nome (`/v1/me`) + pedidos abertos + próximo atendimento (`/v1/pedidos`) + carteira
  /// (`/v1/profissionais/me/saldo`), tudo em paralelo.
  @override
  Future<InicioProfissional> inicio() {
    final emVoo = _inicioEmVoo;
    if (emVoo != null) return emVoo;
    final novo = _carregarInicio();
    _inicioEmVoo = novo;
    novo.whenComplete(() {
      if (identical(_inicioEmVoo, novo)) _inicioEmVoo = null;
    }).ignore();
    return novo;
  }

  Future<InicioProfissional> _carregarInicio() async {
    unawaited(_reenviarFila());
    unawaited(ConfigPublica.garantirAtualizada(_api));
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
    var emAnalise = false;
    ProximoAtendimento? proximo;
    var contratados = <PedidoContratado>[];
    var enviados = <OrcamentoEnviado>[];
    var meusPedidos = <PedidoApi>[];
    Map<String, DadosDoPedido> enderecosMeus = const {};
    var carteira = const ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0);
    var deuCerto = false;

    final futMe = _api.get('/v1/me').then((b) {
      me = _mapa(b);
      deuCerto = true;
    }).catchError((Object e) {
      primeiroErro ??= e;
    });
    final futAbertos = pedidosAbertos(const FiltroPedidosAbertos(limite: 20)).then((lista) {
      abertos = lista;
      deuCerto = true;
    }).catchError((Object e) {
      if (e is ErroTrato && e.codigoHttp == 403) {
        emAnalise = true;
        abertos = const [];
        deuCerto = true;
        return;
      }
      primeiroErro ??= e;
    });
    final futSaldo = _api.get('/v1/profissionais/me/saldo').then((b) {
      final saldo = _mapa(b);
      carteira = ResumoCarteira(
        retidoCentavos: (saldo['a_liberar_centavos'] as num?)?.toInt() ?? 0,
        paraSacarCentavos: (saldo['liberado_centavos'] as num?)?.toInt() ?? 0,
      );
      deuCerto = true;
    }).catchError((Object e) {
      primeiroErro ??= e;
    });
    final meuIdInicial = ServicoAuthPadrao.atual.sessaoAtual?.id;
    final futPedidos =
        _api.get('/v1/pedidos', consulta: const {'como': 'profissional'}).then((b) async {
      final itensBrutos = _lista(b);
      final meus = <PedidoApi>[];
      for (final j in itensBrutos) {
        final p = tentar(() => PedidoApi.deJson(j));
        if (p != null && (meuIdInicial == null || p.clienteId != meuIdInicial)) {
          meus.add(p);
        }
      }
      meusPedidos = meus;
      enderecosMeus = await _enderecosDosContratados([
        for (final p in meus)
          if (_estadosDoProfissional.contains(p.estado) && !p.remoto) p.id,
      ]);
      deuCerto = true;
    }).catchError((Object e) {
      primeiroErro ??= e;
    });
    final futOrcamentos = _api.get('/v1/profissional/orcamentos').then((b) {
      enviados = [
        for (final j in _lista(b))
          if (tentar(() => _orcamentoEnviado(j)) case final o?) o,
      ];
    }).catchError((Object _) {});

    await Future.wait([futMe, futAbertos, futSaldo, futPedidos, futOrcamentos]);
    if (!deuCerto && primeiroErro != null) throw primeiroErro!;
    final meuId = ServicoAuthPadrao.atual.sessaoAtual?.id ?? (me['id'] as String?);
    if (meuId != null) {
      abertos = abertos.where((p) => p.clienteId != meuId).toList();
      meusPedidos = meusPedidos.where((p) => p.clienteId != meuId).toList();
    }
    contratados = [
      for (final p in meusPedidos)
        if (_estadosDoProfissional.contains(p.estado)) _contratado(p, enderecosMeus[p.id]),
    ];
    for (final p in meusPedidos) {
      if (const {'pago_e_retido', 'agendado', 'em_andamento'}.contains(p.estado)) {
        proximo = ProximoAtendimento(
          pedidoId: p.id,
          quando: p.janelaRotulo ?? 'Data da visita ainda não marcada',
          titulo: p.clienteNome == null ? p.rotulo : '${p.rotulo} · ${p.clienteNome}',
          endereco: p.remoto ? 'Atendimento remoto' : (enderecosMeus[p.id]?.enderecoCompleto ?? ''),
          janelaInicio: p.janelaInicio?.toLocal(),
          emAndamento: p.estado == 'em_andamento',
          remoto: p.remoto,
          estadoApi: p.estado,
        );
        break;
      }
    }
    final nomeMe = ((me['nome'] as String?) ?? '').trim();
    final primeiroNome = nomeMe.isNotEmpty ? nomeMe.split(' ').first : 'Profissional';
    return InicioProfissional(
      nome: primeiroNome.isEmpty ? 'Profissional' : primeiroNome,
      disponivelAgora: me['disponivel_agora'] == true,
      carteira: carteira,
      pedidos: abertos,
      proximo: proximo,
      contratados: contratados,
      orcamentosEnviados: enviados,
      emAnalise: emAnalise,
    );
  }

  OrcamentoEnviado _orcamentoEnviado(Map<String, dynamic> j) {
    final pedidoId = j['pedido_id'] as String;
    final orcamentoId = (j['orcamento_id'] as String?) ?? (j['id'] as String?) ?? '';
    final titulo = ((j['titulo_pedido'] as String?) ?? '').trim();
    final enviado = j['enviado_em'] as String?;
    return OrcamentoEnviado(
      orcamentoId: orcamentoId,
      pedidoId: pedidoId,
      titulo: titulo.isEmpty ? 'Pedido ${PedidoApi.numeroDe(pedidoId)}' : titulo,
      valorCentavos: j['valor_centavos'] as int,
      versao: (j['versao'] as int?) ?? 1,
      situacao: (j['situacao'] as String?) ?? 'aguardando',
      enviadoEm: enviado == null ? null : DateTime.parse(enviado).toLocal(),
      prazoExecucaoDias: j['prazo_execucao_dias'] as int?,
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

  /// `GET /v1/pedidos/{id}/dados` de cada pedido, em paralelo. Falha em um não derruba o Início:
  /// aquele pedido só fica sem o endereço na tela.
  Future<Map<String, DadosDoPedido>> _enderecosDosContratados(List<String> ids) async {
    final achados = await Future.wait([
      for (final id in ids)
        () async {
          try {
            return MapEntry(
              id,
              RepositorioPedidosApi.dadosDeJson(_mapa(await _api.get('/v1/pedidos/$id/dados'))),
            );
          } on Object {
            return null;
          }
        }(),
    ]);
    return {for (final e in achados) if (e != null) e.key: e.value};
  }

  PedidoContratado _contratado(PedidoApi p, [DadosDoPedido? dados]) {
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
      titulo: p.rotulo,
      cliente: p.clienteNome,
      situacao: situacao,
      estadoApi: p.estado,
      quando: p.janelaRotulo,
      janelaInicio: p.janelaInicio?.toLocal(),
      remoto: p.remoto,
      endereco: dados?.enderecoCompleto,
      consultaMapa: dados?.consultaDoMapa,
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

  @override
  Future<void> remarcarAgenda(String pedidoId, DateTime inicio, DateTime fim) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/acoes/remarcar',
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
    var fotos = [
      for (final u in (j['fotos_urls'] as List? ?? const []))
        if (u is String && u.isNotEmpty) u,
    ];
    if (fotos.isEmpty) {
      try {
        final itens = _lista(
          await _api.get('/v1/pedidos/$pedidoId/fotos', consulta: const {'finalidade': 'pedido'}),
        );
        fotos = [
          for (final f in itens)
            if (f['url'] is String && (f['url'] as String).isNotEmpty) f['url'] as String,
        ];
      } on Object {
        fotos = const [];
      }
    }
    final aberto = _pedidoAberto(j);
    // Resumo do que o cliente pediu de prazo (o nome já aparece em cima, com o avatar).
    final prazo = DateTime.tryParse('${j['prazo_desejado']}');
    final resumo = [
      if (j['urgente'] == true) 'Urgente',
      if (prazo != null) 'Para até ${_dia(prazo)}',
    ].join(' · ');
    return DetalhePedido(
      pedido: aberto,
      fechaEm: 'Publicado ${_quandoRelativo(DateTime.parse(j['aberto_em'] as String))}',
      clienteResumo: resumo,
      legendasFotos: fotos,
      descricao: (j['descricao'] as String?) ?? '',
      linhas: [
        LinhaDetalhe('Modalidade', aberto.remoto ? 'Remoto' : 'Presencial'),
        if (!aberto.remoto && aberto.bairro.isNotEmpty) LinhaDetalhe('Bairro', aberto.bairro),
        // O que o cliente respondeu às perguntas da categoria (evita repetir o prazo já resumido acima).
        for (final r in _lista(j['respostas'] ?? const []))
          if ('${r['pergunta']}'.toLowerCase() != 'prazo')
            LinhaDetalhe('${r['pergunta']}', textoDaResposta(r['resposta'])),
      ],
    );
  }

  /// `POST /v1/pedidos/{id}/recusar` `{motivo}`. Não avisa o cliente; repetir é seguro.
  @override
  Future<void> recusar(String pedidoId, MotivoRecusa motivo) async {
    await _api.post('/v1/pedidos/$pedidoId/recusar', corpo: {'motivo': motivo.texto});
  }

  /// Extrato do ledger (D15). Cada lançamento vira uma linha; propaga erro real da API.
  @override
  Future<List<ItemExtrato>> extrato({int limite = 50, int deslocamento = 0}) async {
    final json = _mapa(
      await _api.get(
        '/v1/extrato',
        consulta: {'limite': '$limite', 'deslocamento': '$deslocamento'},
      ),
    );
    return [
      for (final l in ExtratoApi.deJson(json).itens)
        ItemExtrato(
          titulo: 'Pedido ${_curto(l.pedidoId)} · ${switch (l.tipo) {
            'retencao' => 'valor retido',
            'repasse' => 'valor liberado',
            'cobranca' => 'pagamento',
            'taxa' => 'custo do parcelamento',
            'estorno' => 'estorno',
            _ => l.tipo.replaceAll('_', ' '),
          }}',
          detalheData: _dia(l.data.toLocal()),
          brutoCentavos: l.valorCentavos,
          pedidoId: l.pedidoId,
          textoTaxa: l.estornoDe != null ? 'Estorno' : 'Toque para ver os valores',
          liquidoCentavos: l.valorCentavos,
          status: StatusExtrato.liberado,
        ),
    ];
  }

  /// `GET /v1/pedidos/{id}/saldo` (ledger), `GET /v1/contratos/{id}/aditivos` e `.../notas-material`.
  @override
  Future<DetalheValoresPedido> valoresDoPedido(String pedidoId) async {
    final saldo = _mapa(await _api.get('/v1/pedidos/$pedidoId/saldo'));
    var concluidoSemAvaliar = false;
    try {
      final pedido = _mapa(await _api.get('/v1/pedidos/$pedidoId'));
      concluidoSemAvaliar = pedido['estado'] == 'concluido' && pedido['ja_avaliou'] != true;
    } on ErroTrato {
      concluidoSemAvaliar = false;
    }
    var aditivos = <Map<String, dynamic>>[];
    var notas = <Map<String, dynamic>>[];
    try {
      aditivos = _lista(await _api.get('/v1/contratos/$pedidoId/aditivos'));
    } on ErroTrato {
      aditivos = [];
    }
    try {
      notas = _lista(await _api.get('/v1/contratos/$pedidoId/notas-material'));
    } on ErroTrato {
      notas = [];
    }
    int cent(Object? v) => v is num ? v.toInt() : 0;
    final retido = cent(saldo['retido_centavos']);
    final aLiberar = cent(saldo['a_liberar_centavos']);
    final liberado = cent(saldo['liberado_centavos']);
    final situacao = liberado > 0
        ? 'Valor já liberado para você.'
        : aLiberar > 0
            ? 'Serviço concluído: o valor está a liberar.'
            : 'Retido até o cliente confirmar o serviço.';
    String estadoAditivo(String? e) => switch (e) {
          'proposto' => 'Aguardando o cliente aprovar',
          'aprovado' => 'Aprovado: aguardando o pagamento do cliente',
          'pago' => 'Pago pelo cliente',
          'recusado' => 'Recusado pelo cliente',
          _ => e ?? '',
        };
    notas.sort((a, b) => '${a['enviada_em']}'.compareTo('${b['enviada_em']}'));
    return DetalheValoresPedido(
      pedidoNumero: _curto(pedidoId),
      pagoPeloClienteCentavos: cent(saldo['cliente_pagou_centavos']),
      voceRecebeCentavos: retido + aLiberar + liberado,
      situacao: situacao,
      podeAvaliarCliente: concluidoSemAvaliar,
      aditivos: [
        for (final a in aditivos)
          LinhaDeValor(
            '${a['descricao'] ?? 'Aditivo'}',
            cent(a['valor_centavos']),
            nota: estadoAditivo(a['estado'] as String?),
          ),
      ],
      notas: [
        for (var i = 0; i < notas.length; i++)
          LinhaDeValor('Nota ${i + 1}', cent(notas[i]['total_centavos'])),
      ],
    );
  }

  String _curto(String id) => '#${id.substring(0, id.length < 4 ? id.length : 4).toUpperCase()}';

  /// Manda o que ficou guardado sem internet (check-in e check-out). Roda sempre que o início do
  /// profissional carrega, que é atualizado sozinho; falha em silêncio e tenta de novo depois.
  Future<void> _reenviarFila() async {
    final f = fila;
    if (f == null || f.pendentes.isEmpty) return;
    for (final id in {for (final a in f.pendentes) a.pedidoId}) {
      try {
        await (servicoCheckIn(id) as ServicoCheckInApi).reenviarPendentes();
      } on Object {
        // sem internet de novo: fica na fila
      }
    }
  }

  /// `POST /v1/pedidos/{id}/avaliacao` `{nota_geral}`: o servidor vê que quem avalia é o
  /// profissional e grava como avaliação do cliente.
  @override
  Future<void> avaliarCliente(String pedidoId, int nota, String comentario) async {
    await _api.post(
      '/v1/pedidos/$pedidoId/avaliacao',
      corpo: {
        'nota_geral': nota,
        if (comentario.isNotEmpty) 'comentario': comentario,
      },
    );
  }

  @override
  ServicoOrcamento servicoOrcamento(String pedidoId) =>
      ServicoOrcamentoApi(_api, pedidoId: pedidoId);

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId, {bool remoto = false}) =>
      ServicoCheckInApi(
        _api,
        pedidoId: pedidoId,
        captura: capturaDoPedido?.call(pedidoId) ?? captura,
        upload: upload,
        fila: fila,
        remoto: remoto,
      );

  @override
  ServicoCheckOut servicoCheckOut(String pedidoId, {bool remoto = false}) {
    final captura = capturaFinalDoPedido?.call(pedidoId) ?? this.captura;
    final checkIn = ServicoCheckInApi(
      _api,
      pedidoId: pedidoId,
      captura: captura,
      upload: upload,
      fila: fila,
      remoto: remoto,
    );
    return ServicoCheckOutApi(checkIn, captura);
  }

  ContaRecebimento _contaRecebimentoDeJson(Map<String, dynamic> j) => ContaRecebimento(
        cadastrada: j['cadastrada'] == true,
        tipoPix: j['tipo_pix'] as String?,
        chavePix: j['chave_pix'] as String?,
        chavePixMascarada: j['chave_pix_mascarada'] as String?,
        bancoCodigo: j['banco_codigo'] as String?,
        bancoNome: j['banco_nome'] as String?,
        agencia: j['agencia'] as String?,
        conta: j['conta'] as String?,
        tipoConta: j['tipo_conta'] as String?,
        resumoExibicao: j['resumo_exibicao'] as String?,
      );

  @override
  Future<ContaRecebimento> obterContaRecebimento() async {
    final j = _mapa(await _api.get('/v1/profissional/conta-recebimento'));
    return _contaRecebimentoDeJson(j);
  }

  @override
  Future<ContaRecebimento> salvarContaRecebimento({
    required String tipoPix,
    required String chavePix,
    String? bancoCodigo,
    String? bancoNome,
    String? agencia,
    String? conta,
    String? tipoConta,
  }) async {
    final corpo = <String, Object?>{
      'tipo_pix': tipoPix,
      'chave_pix': chavePix.trim(),
      if (bancoCodigo != null && bancoCodigo.trim().isNotEmpty)
        'banco_codigo': bancoCodigo.trim(),
      if (bancoNome != null && bancoNome.trim().isNotEmpty) 'banco_nome': bancoNome.trim(),
      if (agencia != null && agencia.trim().isNotEmpty) 'agencia': agencia.trim(),
      if (conta != null && conta.trim().isNotEmpty) 'conta': conta.trim(),
      if (tipoConta != null && tipoConta.trim().isNotEmpty) 'tipo_conta': tipoConta.trim(),
    };
    final j = _mapa(await _api.put('/v1/profissional/conta-recebimento', corpo: corpo));
    return _contaRecebimentoDeJson(j);
  }

  @override
  Future<List<int>> baixarExtratoPdf({String? mes}) => _api.getBytes(
        '/v1/profissionais/me/extrato.pdf',
        consulta: mes != null && mes.trim().isNotEmpty ? {'mes': mes.trim()} : null,
      );

  @override
  Future<bool> alterarDisponivelAgora(bool disponivel) async {
    final j = _mapa(
      await _api.patch('/v1/profissional/perfil', corpo: {'disponivel_agora': disponivel}),
    );
    return j['disponivel_agora'] == true;
  }

  @override
  Future<DetalheOrcamentoEnviado> meuOrcamento(
    String orcamentoId, {
    String? tituloPedido,
    String? situacao,
  }) async {
    final j = _mapa(await _api.get('/v1/orcamentos/$orcamentoId'));
    final valido = j['validade_ate'] as String?;
    final itens = [
      for (final raw in _lista(j['itens'] ?? const []))
        ItemOrcamentoEnviado(
          tipo: (raw['tipo'] as String?) ?? 'outro',
          descricao: (raw['descricao'] as String?) ?? '',
          quantidade: '${raw['quantidade'] ?? '1'}',
          valorUnitarioCentavos: (raw['valor_unitario_centavos'] as num?)?.toInt() ?? 0,
          totalCentavos: (raw['total_centavos'] as num?)?.toInt() ?? 0,
        ),
    ];
    final statusApi = (j['status'] as String?) ?? 'enviado';
    final sit = situacao ?? (j['aceito'] == true ? 'aceito' : (statusApi == 'enviado' ? 'aguardando' : 'encerrado'));
    return DetalheOrcamentoEnviado(
      orcamentoId: (j['id'] as String?) ?? orcamentoId,
      pedidoId: (j['pedido_id'] as String?) ?? '',
      tituloPedido: (tituloPedido != null && tituloPedido.isNotEmpty)
          ? tituloPedido
          : 'Pedido ${PedidoApi.numeroDe((j['pedido_id'] as String?) ?? orcamentoId)}',
      versao: (j['versao'] as num?)?.toInt() ?? 1,
      situacao: sit,
      valorCentavos: (j['valor_centavos'] as num?)?.toInt() ?? 0,
      prazoExecucaoDias: (j['prazo_execucao_dias'] as num?)?.toInt(),
      garantiaDias: (j['garantia_dias'] as num?)?.toInt(),
      foraDoEscopo: j['fora_do_escopo'] as String?,
      observacoes: j['observacoes'] as String?,
      validoAte: valido == null ? null : DateTime.tryParse(valido)?.toLocal(),
      horasDeslocamento: j['horas_deslocamento'] as String?,
      horasTrabalhadas: j['horas_trabalhadas'] as String?,
      itens: itens,
    );
  }
}

/// `POST /v1/orcamentos/resumo` `{valor_centavos}` e `POST /v1/pedidos/{pedido_id}/orcamentos`.
/// O Trato não cobra taxa: o profissional recebe o valor inteiro do orçamento.
class ServicoOrcamentoApi implements ServicoOrcamento {
  ServicoOrcamentoApi(this._api, {this.pedidoId});

  final ClienteApi _api;
  final String? pedidoId;

  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async {
    final j = _mapa(
      await _api.post('/v1/orcamentos/resumo', corpo: {'valor_centavos': totalCentavos}),
    );
    return ResumoOrcamento(totalCentavos: j['valor_centavos'] as int);
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
        'prazo_execucao_dias': pronto.prazoExecucaoDias,
        'validade_ate': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
        'sinal_material_centavos': sinal,
        'garantia_dias': pronto.garantiaDias,
        if (pronto.foraDoEscopo != null && pronto.foraDoEscopo!.trim().isNotEmpty)
          'fora_do_escopo': pronto.foraDoEscopo!.trim(),
        if (pronto.observacoes != null && pronto.observacoes!.trim().isNotEmpty)
          'observacoes': pronto.observacoes!.trim(),
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
    this.remoto = false,
  });

  /// Serviço remoto: início e fim só com o código do cliente (sem foto, localização nem fila
  /// offline).
  final bool remoto;

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

  /// Mensagem rápida e aviso de cliente ausente saem como mensagem normal no chat do pedido: o
  /// cliente vê na conversa (e na notificação de mensagem nova), e fica guardada como prova.
  @override
  Future<void> enviarMensagemRapida(String mensagem) async {
    await _api.post('/v1/pedidos/$pedidoId/mensagens', corpo: {'texto': mensagem});
  }

  @override
  Future<void> avisarClienteAusente() async {
    if (remoto) {
      await _api.post(
        '/v1/pedidos/$pedidoId/acoes/registrar_cliente_ausente',
        corpo: {'prova': <String, Object?>{}},
      );
      return;
    }
    final foto = _foto;
    final posicao = _posicao;
    if (foto == null || posicao == null) {
      throw const ErroTrato(
        TipoErro.recusado,
        'Tire a foto do local e registre a localização antes de informar cliente ausente.',
      );
    }
    final enviada = await _enviada(foto, FinalidadeArquivo.checkIn);
    await _api.post(
      '/v1/pedidos/$pedidoId/acoes/registrar_cliente_ausente',
      corpo: {
        'prova': {
          'foto': _fotoJson(enviada),
          'localizacao': {'latitude': posicao.latitude, 'longitude': posicao.longitude},
        },
      },
    );
  }

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

  /// Serviço remoto: a prova é só o código. Código errado = recusado pelo backend.
  Future<bool> _postarSoComCodigo(String acao, String chave, String codigo) async {
    await _api.post('/v1/pedidos/$pedidoId/acoes/$acao', corpo: {
      'prova': {chave: codigo},
    });
    return true;
  }

  @override
  Future<ResultadoInicio> iniciarServico(String codigo) async {
    if (remoto) {
      try {
        await _postarSoComCodigo('fazer_check_in', 'codigo_inicio', codigo);
        return ResultadoInicio.iniciado;
      } on ErroTrato catch (erro) {
        if (erro.tipo == TipoErro.recusado) return ResultadoInicio.codigoIncorreto;
        rethrow;
      }
    }
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
  /// Check-out remoto: só o código de conclusão. Devolve sempre `true` (sem fila offline).
  Future<bool> fazerCheckOutRemoto(String codigo) =>
      _postarSoComCodigo('fazer_check_out', 'codigo_conclusao', codigo);

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
    if (_checkIn.remoto) {
      try {
        await _checkIn.fazerCheckOutRemoto(codigo);
        return ResultadoFim.concluido;
      } on ErroTrato catch (erro) {
        if (erro.tipo == TipoErro.recusado) return ResultadoFim.codigoIncorreto;
        rethrow;
      }
    }
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
