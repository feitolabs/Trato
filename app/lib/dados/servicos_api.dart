import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../componentes/imagem_trato.dart';
import '../dispositivo/servico_camera.dart';
import '../telas/aditivo/aditivo.dart';
import '../telas/comuns/foco_rolagem.dart';
import 'repositorios.dart' show Cobranca, StatusPagamento;
import '../telas/disputa_profissional/disputa.dart';
import '../telas/lgpd/modelos.dart';
import '../telas/nota_material/nota_material.dart';
import '../telas/perfil_publico/perfil_publico.dart';
import '../telas/profissional_inicio/primeiros_passos.dart';
import '../telas/profissional_cadastro/cadastro.dart';
import '../telas/verificacao/verificacao.dart';
import 'cliente_api.dart';
import 'config_publica.dart';
import 'envio_fotos.dart';
import 'erros.dart';
import 'servico_upload.dart';
import 'paralelo.dart';

// Serviços das telas de aditivo, nota de materiais, disputa e verificação, falando com a API.
// Só pedem e mostram: o total da nota, o estado do aditivo e a cobrança são do backend.

Map<String, dynamic> _mapa(Object? json) => json! as Map<String, dynamic>;
List<Map<String, dynamic>> _lista(Object? json) =>
    [for (final item in json! as List) item as Map<String, dynamic>];

/// Motivo da disputa como o cliente escolheu (o servidor guarda um código).
String _motivoDisputa(String? codigo) => switch (codigo) {
      // Os mesmos textos que o cliente vê ao abrir (TextosPadraoTelas.motivos).
      'mal_feito' => 'O problema voltou ou não foi resolvido',
      'diferente_do_combinado' => 'Qualidade abaixo do combinado',
      'cobranca_extra' => 'Cobrança extra não combinada',
      'dano' => 'Dano no local',
      'abandono' => 'O profissional abandonou o serviço',
      'nao_compareceu' => 'O profissional não compareceu',
      null || '' => 'Disputa',
      _ => codigo.replaceAll('_', ' '),
    };

/// "Eletricista · 14/11/2026": a categoria e o dia da avaliação (o que o servidor mandar).
String servicoDaAvaliacao(Map<dynamic, dynamic> a) {
  final categoria = (a['categoria'] as String?)?.trim() ?? '';
  final quando = DateTime.tryParse('${a['criada_em']}')?.toLocal();
  final dia = quando == null
      ? ''
      : '${quando.day.toString().padLeft(2, '0')}/${quando.month.toString().padLeft(2, '0')}/${quando.year}';
  final partes = [if (categoria.isNotEmpty) categoria, if (dia.isNotEmpty) dia];
  return partes.isEmpty ? 'Serviço concluído' : partes.join(' · ');
}

/// `[Foto:<id>]` vira a URL assinada da foto de trabalho; qualquer outra coisa (caminho antigo,
/// sem rede) fica como veio.
Future<String> _urlDaFotoDoPortfolio(ClienteApi api, String usuarioId, String ref) async {
  final achou = RegExp(r'^\[Foto:([^\]]+)\]$').firstMatch(ref);
  if (achou == null || usuarioId.isEmpty) return ref;
  try {
    final r = _mapa(await api.get('/v1/usuarios/$usuarioId/portfolio/${achou.group(1)}/foto'));
    return (r['url'] as String?) ?? ref;
  } on ErroTrato {
    return ref;
  }
}

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

  /// `GET /v1/contratos/{id}/aditivos`: o aditivo proposto, ou o último decidido (`aprovado`,
  /// `pago` ou `recusado`). `null` se não houver nenhum.
  @override
  Future<DetalheAditivo?> carregar(String aditivoId) async {
    final todos = _lista(await _api.get('/v1/contratos/$aditivoId/aditivos'));
    if (todos.isEmpty) return null;
    Map<String, dynamic>? escolhido;
    for (final a in todos) {
      if (a['estado'] == 'proposto') {
        escolhido = a;
        break;
      }
    }
    escolhido ??= todos.reversed.firstWhere(
      (a) => const {'aprovado', 'pago', 'recusado'}.contains(a['estado']),
      orElse: () => todos.last,
    );
    final a = escolhido;
    final estado = switch (a['estado']) {
      'aprovado' || 'pago' => EstadoAditivo.aprovado,
      'recusado' => EstadoAditivo.recusado,
      _ => EstadoAditivo.aguardando,
    };
    // Quem pediu e qual pedido: sem rede para isso, o texto cai no genérico.
    var nome = nomeProfissional;
    if (nome.isEmpty) {
      try {
        final o = await _api.get('/v1/pedidos/$aditivoId/interlocutor');
        final n = (o is Map ? o['nome'] as String? : null)?.trim();
        if (n != null && n.isNotEmpty) nome = n;
      } on Object {
        nome = '';
      }
    }
    final curto = aditivoId.length >= 4 ? aditivoId.substring(0, 4).toUpperCase() : aditivoId;
    return DetalheAditivo(
      id: a['id'] as String,
      pedidoTitulo: tituloPedido == 'Pedido' ? 'Pedido #$curto' : tituloPedido,
      profissional: nome,
      motivo: a['descricao'] as String,
      valorCentavos: a['valor_centavos'] as int,
      estado: estado,
    );
  }

  /// `POST .../aditivos/{aditivo_id}/aprovar` (a cobrança nasce `aguardando_confirmacao`) ou
  /// `.../recusar`. Só o cliente decide; o profissional recebe 403.
  @override
  Future<Cobranca?> responder(String aditivoId, {required bool aprovar}) async {
    final a = await _aberto(aditivoId);
    if (a == null) {
      throw const ErroTrato(TipoErro.naoEncontrado, 'Este aditivo já foi respondido.');
    }
    final acao = aprovar ? 'aprovar' : 'recusar';
    final r = await _api.post(
      '/v1/contratos/$aditivoId/aditivos/${a['id']}/$acao',
      // Cartão: é o meio que o Stripe da conta já aceita (o Pix ainda não está liberado).
      corpo: aprovar ? {'meio': 'cartao'} : null,
    );
    final c = (aprovar && r is Map) ? r['cobranca'] : null;
    if (c is! Map) return null;
    return Cobranca(
      id: c['cobranca_id'] as String,
      pixCopiaECola: c['tipo_instrucao'] == 'pix_copia_e_cola' ? c['instrucao'] as String? : null,
      segredoCartao:
          c['tipo_instrucao'] == 'cartao_segredo_do_cliente' ? c['instrucao'] as String? : null,
      clienteCartaoId: c['cliente_externo_id'] as String?,
      chaveEfemera: c['chave_efemera'] as String?,
    );
  }

  /// O aditivo aprovado do contrato virou `pago` (webhook)? Se não, segue aguardando.
  @override
  Future<StatusPagamento> statusDoPagamento(String contratoId) async {
    final todos = _lista(await _api.get('/v1/contratos/$contratoId/aditivos'));
    for (final a in todos) {
      if (a['estado'] == 'pago') return StatusPagamento.pago;
    }
    return StatusPagamento.aguardando;
  }
}

/// Nota de materiais. O total sai do backend (quantidade × unitário); o app não soma.
class ServicoNotaMaterialApi implements ServicoNotaMaterial {
  ServicoNotaMaterialApi(
    this._api, {
    this.tituloPedido = 'Pedido',
    this.nomeProfissional = '',
    this.upload,
  });

  final ClienteApi _api;
  final String tituloPedido;
  final String nomeProfissional;
  final ServicoUpload? upload;

  /// `GET /v1/contratos/{id}/notas-material`: a nota mais recente, ou `null`.
  @override
  Future<NotaMaterial?> carregar(String pedidoId) async {
    final todas = await carregarTodas(pedidoId);
    return todas.isEmpty ? null : todas.last;
  }

  /// `GET /v1/contratos/{id}/notas-material`: todas, da mais antiga para a mais nova.
  @override
  Future<List<NotaMaterial>> carregarTodas(String pedidoId) async {
    final notas = _lista(await _api.get('/v1/contratos/$pedidoId/notas-material'));
    if (notas.isEmpty) return const [];
    notas.sort((a, b) => (a['enviada_em'] as String).compareTo(b['enviada_em'] as String));
    // Quem enviou e qual pedido: sem rede para isso, o texto cai no genérico.
    var nome = nomeProfissional;
    if (nome.isEmpty) {
      try {
        final o = await _api.get('/v1/pedidos/$pedidoId/interlocutor');
        final n = (o is Map ? o['nome'] as String? : null)?.trim();
        if (n != null && n.isNotEmpty) nome = n;
      } on Object {
        nome = '';
      }
    }
    final curto = pedidoId.length >= 4 ? pedidoId.substring(0, 4).toUpperCase() : pedidoId;
    return [
      for (final n in notas)
        NotaMaterial(
          pedidoTitulo: tituloPedido == 'Pedido' ? 'Pedido #$curto' : tituloPedido,
          profissional: nome.isEmpty ? 'Profissional' : nome,
          enviadaEm: DateTime.parse(n['enviada_em'] as String).toLocal(),
          fotoNota: (n['foto_url'] as String?)?.isNotEmpty == true ? n['foto_url'] as String : null,
          itens: [
            for (final i in (n['itens'] as List).cast<Map<String, dynamic>>())
              ItemNota(
                descricao: i['descricao'] as String,
                // O backend manda a quantidade como texto decimal ("2.00").
                quantidade: num.tryParse('${i['quantidade']}')?.toInt() ?? 1,
                valorUnitarioCentavos: (i['valor_unitario_centavos'] is num)
                    ? (i['valor_unitario_centavos'] as num).toInt()
                    : (i['total_centavos'] as int? ?? 0),
              ),
          ],
        ),
    ];
  }

  /// `POST /v1/contratos/{id}/notas-material`. A tela informa descrição e valor de cada item;
  /// a quantidade vai como 1 e o valor como unitário.
  @override
  Future<void> enviar(EnvioNota envio) async {
    String? midiaId;
    final fotoPath = envio.fotoNota;
    final up = upload;
    if (up != null && fotoPath.isNotEmpty) {
      try {
        final bytes = obterBytesImagem(fotoPath);
        if (bytes != null && bytes.isNotEmpty) {
          final cap = ArquivoCapturado(
            bytes: bytes,
            sha256: crypto.sha256.convert(bytes).toString(),
            capturadaEm: DateTime.now().toUtc(),
          );
          final res =
              await up.enviar(cap, FinalidadeArquivo.notaMaterial, pedidoId: envio.pedidoId);
          midiaId = res.arquivoId;
        } else if (temArquivoImagem(fotoPath)) {
          final caminho = obterCaminhoImagem(fotoPath) ?? fotoPath;
          final f = File(caminho);
          if (f.existsSync()) {
            final b = await f.readAsBytes();
            final cap = ArquivoCapturado(
              bytes: b,
              sha256: crypto.sha256.convert(b).toString(),
              capturadaEm: DateTime.now().toUtc(),
            );
            final res =
                await up.enviar(cap, FinalidadeArquivo.notaMaterial, pedidoId: envio.pedidoId);
            midiaId = res.arquivoId;
          }
        }
      } on ErroTrato {
        rethrow; // sem foto enviada a nota não vale; o caminho do aparelho não serve ao backend
      } catch (_) {}
      if (midiaId == null) {
        throw const ErroTrato(TipoErro.recusado, 'Não conseguimos ler a foto da nota. Tire outra.');
      }
    }

    final corpo = <String, dynamic>{
      if (midiaId != null)
        'midia_id': midiaId
      else
        'foto_storage_path': fotoPath.replaceAll(RegExp(r'^/+'), ''),
      'itens': [
        for (final i in envio.itens)
          {
            'descricao': i.descricao,
            'quantidade': i.quantidade,
            'valor_unitario_centavos': i.valorUnitarioCentavos,
          },
      ],
    };

    await _api.post(
      '/v1/contratos/${envio.pedidoId}/notas-material',
      corpo: corpo,
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
    if (todas.isEmpty) return textoLgpdPadrao;
    final v = todas.last;
    return TextoLgpd(
      finalidade: v['finalidade'] as String,
      retencao: 'Guardamos enquanto você mantiver sua conta ativa. '
          'Se a análise for recusada ou substituída, apagamos em até ${v['retencao_dias'] ?? 90} dias.',
      quemVe: textoLgpdPadrao.quemVe,
    );
  }

  /// `POST /v1/profissional/verificacao`. [EnvioVerificacao.documento] e `.selfie` são os
  /// `upload_id` devolvidos por [CapturaVerificacao]. O envio só acontece depois de a tela
  /// mostrar o aviso de privacidade (LGPD) e a pessoa tocar em enviar.
  @override
  Future<void> enviar(EnvioVerificacao envio) async {
    try {
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
      _cache = null;
    } on ErroTrato catch (e) {
      // Se já está em análise ou já foi enviada, considera concluído com sucesso.
      if (e.codigoHttp == 409 || e.mensagem.contains('já tem uma verificação')) {
        _cache = null;
        return;
      }
      rethrow;
    }
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
  ServicoCadastroProfissionalApi(this._api, {this.upload});

  final ClienteApi _api;

  /// Sobe as fotos de trabalhos escolhidas no celular. Sem ele, o caminho local vai como estava.
  final ServicoUpload? upload;
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

  /// Categorias e cidades vêm do banco. Se qualquer chamada falhar, o erro vai para a tela
  /// ("Tentar de novo"): nunca lista de exemplo. Raio, dias e períodos são opções fixas.
  /// Carga das opções em curso: [carregarAtual] reaproveita em vez de buscar de novo
  /// (a tela pede as duas coisas ao mesmo tempo).
  Future<OpcoesCadastro>? _opcoesEmCurso;

  @override
  Future<OpcoesCadastro> carregarOpcoes() => _opcoesEmCurso = _buscarOpcoes();

  /// `GET /v1/profissional/perfil` em linguagem da tela: ids viram nomes e janelas viram
  /// dias e períodos. Sem cadastro (404), `null`. O raio não é guardado no backend: vem 0.
  @override
  Future<DadosCadastroProfissional?> carregarAtual() async {
    final Object? bruto;
    try {
      bruto = (await emParalelo2(
        _api.get('/v1/profissional/perfil'),
        _opcoesEmCurso ?? carregarOpcoes(),
      ))
          .$1;
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404) return null;
      rethrow;
    }
    final p = _mapa(bruto);
    final nomePorIdCategoria = {for (final e in _idPorNomeCategoria.entries) e.value: e.key};
    final nomePorIdCidade = {for (final e in _idPorNomeCidade.entries) e.value: e.key};
    final diaPorIndice = {for (final e in _diaParaIndice.entries) e.value: e.key};
    final dias = <String>{};
    final periodos = <String>{};
    for (final j in _lista(p['disponibilidade'] ?? const [])) {
      final dia = diaPorIndice[j['dia_semana']];
      final periodo = _periodoDaJanela(j['inicio'] as String?, j['fim'] as String?);
      if (dia != null) dias.add(dia);
      if (periodo != null) periodos.add(periodo);
    }
    final regioes = _lista(p['regioes'] ?? const []);
    final donoId = (p['usuario_id'] as String?) ?? '';
    final portfolio = [
      for (final item in _lista(p['portfolio'] ?? const []))
        if (item['descricao'] case final String ref when ref.isNotEmpty) ref,
    ];
    final urlsDasFotos = <String, String>{};
    final urlsResolvidas = await Future.wait([
      for (final ref in portfolio) _urlDaFotoDoPortfolio(_api, donoId, ref),
    ]);
    for (var i = 0; i < portfolio.length; i++) {
      if (urlsResolvidas[i] != portfolio[i]) {
        urlsDasFotos[portfolio[i]] = urlsResolvidas[i];
      }
    }
    return DadosCadastroProfissional(
      urlsDasFotos: urlsDasFotos,
      nome: '',
      sobre: (p['bio'] as String?) ?? '',
      categorias: {
        for (final id in (p['categorias'] as List? ?? const []))
          if (nomePorIdCategoria[id] case final String nome) nome,
      },
      cidade: regioes.isEmpty ? '' : (nomePorIdCidade[regioes.first['cidade_id']] ?? ''),
      raioKm: 0,
      dias: dias,
      periodos: periodos,
      portfolio: portfolio,
      atendePresencial: p['atende_presencial'] as bool? ?? true,
      atendeRemoto: p['atende_remoto'] as bool? ?? false,
      categoriasTravadas: (p['status'] as String?) == 'aprovado' ||
          (p['nivel_verificacao'] as String?) == 'verificado' ||
          const {'enviada', 'em_analise', 'aprovada'}.contains(p['status_verificacao']),
    );
  }

  /// Foto escolhida no celular (caminho de arquivo) sobe como foto de portfólio e vira
  /// `[Foto:<id>]`, que qualquer aparelho consegue abrir. O que já é `[Foto:...]` fica como está.
  Future<List<String>> _enviarFotosDoPortfolio(List<String> refs) async {
    final envio = upload;
    final saida = <String>[];
    for (final ref in refs) {
      final arquivo = File(ref);
      if (envio == null || ref.startsWith('[') || !arquivo.existsSync()) {
        saida.add(ref);
        continue;
      }
      final bytes = await arquivo.readAsBytes();
      final enviado = await envio.enviar(
        ArquivoCapturado(
          bytes: bytes,
          sha256: crypto.sha256.convert(bytes).toString(),
          capturadaEm: DateTime.now().toUtc(),
        ),
        FinalidadeArquivo.portfolio,
      );
      saida.add('[Foto:${enviado.arquivoId}]');
    }
    return saida;
  }

  /// Manhã/Tarde/Noite da janela salva: a exata de [_periodoParaJanela] ou, se o horário foi
  /// gravado de outro jeito, pela hora de início.
  static String? _periodoDaJanela(String? inicio, String? fim) {
    if (inicio == null) return null;
    for (final e in _periodoParaJanela.entries) {
      if (e.value.$1 == inicio && e.value.$2 == fim) return e.key;
    }
    final hora = int.tryParse(inicio.split(':').first);
    if (hora == null) return null;
    return hora < 12 ? 'Manhã' : (hora < 18 ? 'Tarde' : 'Noite');
  }

  Future<OpcoesCadastro> _buscarOpcoes() async {
    final (catsBrutas, cidsBrutas) = await emParalelo2(
      _api.get('/v1/catalogo/categorias'),
      _api.get('/v1/catalogo/cidades'),
    );
    final cats = _lista(catsBrutas);
    final cids = _lista(cidsBrutas);
    _idPorNomeCategoria = {
      for (final c in cats)
        if (c['nome'] is String && c['id'] is String) (c['nome'] as String): (c['id'] as String),
    };
    _idPorNomeCidade = {
      for (final c in cids)
        if (c['nome'] is String && c['id'] is String) (c['nome'] as String): (c['id'] as String),
    };
    final categoriasOrdenadas = _idPorNomeCategoria.keys.toList()..sort(compararAlfabeticoPtBr);
    final cidadesOrdenadas = _idPorNomeCidade.keys.toList()..sort(compararAlfabeticoPtBr);
    return OpcoesCadastro(
      categorias: categoriasOrdenadas,
      cidades: cidadesOrdenadas,
      raiosKm: const [],
      dias: opcoesCadastroPadrao.dias,
      periodos: opcoesCadastroPadrao.periodos,
    );
  }

  String _resolverCategoriaId(String nome) {
    final id = _idPorNomeCategoria[nome];
    if (id == null) {
      throw ErroTrato(TipoErro.recusado, 'A categoria "$nome" não está mais disponível.');
    }
    return id;
  }

  /// Compara sem acento: "Divinópolis" digitado tem de achar "Divinopolis" do catálogo.
  static String _semAcento(String texto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const para = 'aaaaaeeeeiiiiooooouuuuc';
    final minusculo = texto.trim().toLowerCase();
    return [
      for (final letra in minusculo.split('')) de.contains(letra) ? para[de.indexOf(letra)] : letra,
    ].join();
  }

  /// O id da cidade digitada. Sem cidade conhecida, recusa: gravar outra cidade esconderia
  /// do profissional todos os pedidos da região dele, sem nenhum aviso.
  String _resolverCidadeId(String cidade) {
    final limpo = _semAcento(cidade);
    for (final entry in _idPorNomeCidade.entries) {
      if (_semAcento(entry.key) == limpo) return entry.value;
    }
    if (limpo.isNotEmpty) {
      for (final entry in _idPorNomeCidade.entries) {
        final nome = _semAcento(entry.key);
        if (limpo.contains(nome) || nome.contains(limpo)) return entry.value;
      }
    }
    throw ErroTrato(
      TipoErro.recusado,
      _idPorNomeCidade.isEmpty
          ? 'Não conseguimos carregar as cidades. Tente de novo.'
          : 'Ainda não atendemos essa cidade. Atendemos: ${_idPorNomeCidade.keys.join(', ')}.',
    );
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
    // A tela pede só a cidade: sem `bairro`, o profissional atende a cidade inteira. O nome da
    // cidade não pode ir como bairro, porque o filtro de pedidos abertos compara bairro exato.
    final regioes = [
      {'cidade_id': cidadeId},
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
    final referencias = await _enviarFotosDoPortfolio(dados.portfolio);
    final portfolio = [
      for (var i = 0; i < referencias.length; i++)
        {
          'titulo': 'Trabalho ${i + 1}',
          'descricao': referencias[i],
        },
    ];
    final corpo = <String, Object?>{
      'categorias': categoriasIds,
      'regioes': regioes,
      'disponibilidade': disponibilidade,
      'bio': dados.sobre.trim(),
      'portfolio': portfolio,
      'atende_presencial': dados.atendePresencial,
      'atende_remoto': dados.atendeRemoto,
    };
    try {
      await _api.post('/v1/profissional/cadastro', corpo: corpo);
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 409 || e.mensagem.contains('já tem cadastro')) {
        await _api.patch('/v1/profissional/perfil', corpo: corpo);
      } else {
        rethrow;
      }
    }
  }
}

/// Dados da trilha dos primeiros passos: `GET /v1/profissional/perfil` e `GET /v1/me`
/// (rotas que o app já usa). Falha em uma das duas = o passo fica pendente.
class ServicoPrimeirosPassosApi {
  ServicoPrimeirosPassosApi(this._api);

  final ClienteApi _api;

  Future<DadosPrimeirosPassos> carregar() async {
    Map<String, dynamic>? perfil;
    try {
      perfil = _mapa(await _api.get('/v1/profissional/perfil'));
    } on Object {
      perfil = null;
    }
    Object? concluidos;
    Object? usuarioId;
    try {
      final me = _mapa(await _api.get('/v1/me'));
      concluidos = me['servicos_concluidos'];
      usuarioId = me['id'];
    } on Object {
      concluidos = null;
      usuarioId = null;
    }
    return DadosPrimeirosPassos.deApi(
      perfil: perfil,
      servicosConcluidos: concluidos,
      usuarioId: usuarioId,
    );
  }
}

/// Perfil público do próprio profissional (`GET /v1/me` + `GET /v1/profissional/perfil`
/// + `GET /v1/profissionais/{id}`).
class ServicoPerfilPublicoApi implements ServicoPerfilPublico, RespostaAvaliacao {
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
    var etiquetasTop = <EtiquetaTop>[];
    String? respondeEmFaixa;
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
        etiquetasTop = EtiquetaTop.listaDeJson(pub['etiquetas_top']);
        respondeEmFaixa = DetalhePerfil.lerFaixaResposta(pub['responde_em_faixa']);
      } on ErroTrato {
        // Perfil ainda em análise (não aprovado publicamente): usa dados privados de /v1/profissional/perfil.
      }
    }

    final mapaNomesCategorias = <String, String>{};
    try {
      final cats = _lista(await _api.get('/v1/catalogo/categorias'));
      for (final c in cats) {
        if (c['id'] is String && c['nome'] is String) {
          mapaNomesCategorias[c['id'] as String] = c['nome'] as String;
        }
      }
    } catch (_) {}

    final categoriasRaw = [for (final c in (prof?['categorias'] as List? ?? const [])) '$c'];
    final categoriasNomes = [
      for (final c in categoriasRaw)
        if (mapaNomesCategorias.containsKey(c))
          mapaNomesCategorias[c]!
        else if (!c.contains('-'))
          c,
    ];
    final portfolioBruto = (prof?['portfolio'] as List? ?? const []).cast<Map<String, dynamic>>();
    final fotosPortfolio = await Future.wait([
      for (final item in portfolioBruto)
        _urlDaFotoDoPortfolio(
          _api,
          usuarioId,
          ((item['descricao'] as String?)?.isNotEmpty == true
              ? item['descricao'] as String
              : (item['titulo'] as String? ?? 'Foto')),
        ),
    ]);
    final status = (prof?['status'] as String?) ?? '';
    final nivel = (prof?['nivel_verificacao'] as String?) ?? '';
    final estaAprovado = status == 'aprovado';
    final String? verificacao;
    if (!estaAprovado || nivel == 'basico' || nivel.isEmpty) {
      verificacao = null;
    } else if (nivel.contains('plus')) {
      verificacao = 'Identidade e antecedentes conferidos';
    } else if (nivel == 'verificado') {
      verificacao = 'Identidade conferida';
    } else {
      verificacao = null;
    }

    // Foto de perfil (se o profissional já enviou). Sem foto ou sem rede, ficam as iniciais.
    String? fotoUrl;
    if (usuarioId.isNotEmpty) {
      try {
        fotoUrl = (_mapa(await _api.get('/v1/usuarios/$usuarioId/foto')))['url'] as String?;
      } on ErroTrato {
        fotoUrl = null;
      }
    }

    return PerfilPublico(
      fotoReferencia: fotoUrl,
      nome: nomeExibicao,
      iniciais: _iniciaisNome(nomeExibicao),
      categoria: categoriasNomes.isEmpty ? 'Profissional' : categoriasNomes.join(' · '),
      verificacao: verificacao,
      noTratoDesde: noTratoDesde,
      nota: nota,
      totalAvaliacoes: avaliacoes.length,
      servicosConcluidos: concluidos,
      sobre: (prof?['bio'] as String?) ?? 'Perfil profissional cadastrado no Trato.',
      cidade: cidades.isNotEmpty ? cidades.first : '',
      fotosPortfolio: fotosPortfolio.length,
      ultimasAvaliacoes: avaliacoes,
      etiquetasTop: etiquetasTop,
      respondeEmFaixa: respondeEmFaixa,
      listaFotosPortfolio: fotosPortfolio,
    );
  }

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async {
    final perfil = await carregarPerfil();
    return perfil.ultimasAvaliacoes;
  }

  @override
  Future<bool> temPerfilProfissional() async {
    try {
      final p = await _api.get('/v1/profissional/perfil');
      return p is Map;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> responderAvaliacao(String avaliacaoId, String resposta) async {
    final texto = resposta.trim();
    final j = _mapa(
      await _api.post('/v1/avaliacoes/$avaliacaoId/responder', corpo: {'resposta': texto}),
    );
    return (j['resposta'] as String?) ?? texto;
  }

  List<Avaliacao> _converterAvaliacoes(List<dynamic> brutas) => [
        for (final a in brutas)
          if (a is Map)
            () {
              final criterios = Avaliacao.lerCriterios(a['criterios']);
              return Avaliacao(
                id: a['id'] as String?,
                cliente: (a['cliente_nome'] as String?) ?? 'Cliente',
                servico: servicoDaAvaliacao(a),
                nota: (a['nota_decimal'] is num ? a['nota_decimal'] as num : a['nota_geral'] as num)
                    .toDouble(),
                comentario: (a['comentario'] as String?) ?? '',
                detalhes: Avaliacao.formatarCriterios(criterios),
                criterios: criterios,
                etiquetas: [for (final e in (a['etiquetas'] as List? ?? const [])) '$e'],
                resposta: a['resposta'] as String?,
              );
            }(),
      ];
}

/// Disputa e retrabalho do lado do profissional falando com a API.
class ServicoDisputaProfissionalApi implements ServicoDisputaProfissional {
  ServicoDisputaProfissionalApi(this._api, {this.upload});

  final ClienteApi _api;

  /// Sobe as fotos de prova da resposta. Sem ele, a resposta vai sem fotos.
  final ServicoUpload? upload;

  @override
  Future<DetalheDisputa?> carregarDisputa(String disputaId) async {
    try {
      final j = _mapa(await _api.get('/v1/pedidos/$disputaId/disputa'));
      // O relato do cliente leva a solução preferida no fim (é como o app do cliente envia).
      const marca = 'Solução que o cliente prefere:';
      final relato = ((j['descricao'] as String?) ?? '').trim();
      final corte = relato.lastIndexOf(marca);
      final descricao = corte < 0 ? relato : relato.substring(0, corte).trim();
      final solucao = corte < 0 ? '' : relato.substring(corte + marca.length).trim();
      // Prazo real desta disputa (resposta_ate - aberta_em); sem as datas, o da configuração.
      final aberta = DateTime.tryParse('${j['aberta_em']}');
      final ate = DateTime.tryParse('${j['resposta_ate']}');
      final prazo = aberta != null && ate != null && ate.isAfter(aberta)
          ? ate.difference(aberta).inHours
          : ConfigPublica.atual.prazoRespostaDisputaHoras;
      var cliente = 'Cliente';
      try {
        final o = await _api.get('/v1/pedidos/$disputaId/interlocutor');
        final n = (o is Map ? o['nome'] as String? : null)?.trim();
        if (n != null && n.isNotEmpty) cliente = n;
      } on Object {
        cliente = 'Cliente';
      }
      return DetalheDisputa(
        id: disputaId,
        titulo:
            'Disputa do pedido #${disputaId.substring(0, disputaId.length < 4 ? disputaId.length : 4).toUpperCase()}',
        cliente: cliente,
        motivo: _motivoDisputa(j['motivo'] as String?),
        descricao: descricao,
        solucaoPedida: solucao.isEmpty ? 'Não informada' : solucao,
        prazoRespostaHoras: prazo,
        valorCongeladoCentavos: (j['valor_congelado_centavos'] as int?) ?? 0,
      );
    } on ErroTrato catch (e) {
      if (e.tipo == TipoErro.naoEncontrado) return null;
      rethrow;
    }
  }

  @override
  Future<void> responder(RespostaDisputa resposta) async {
    final fotos = await enviarFotosLocais(
      upload,
      resposta.evidencias,
      FinalidadeArquivo.evidenciaDisputa,
      pedidoId: resposta.disputaId,
    );
    await _api.post(
      '/v1/pedidos/${resposta.disputaId}/disputa/resposta',
      corpo: {
        'mensagem': resposta.mensagem,
        'solucao': switch (resposta.tipo) {
          TipoRespostaDisputa.atenderRetrabalho => 'retrabalho',
          TipoRespostaDisputa.proporReembolsoParcial => 'reembolso_parcial',
          TipoRespostaDisputa.discordar => 'discordar',
        },
        if (resposta.reembolsoParcialCentavos != null)
          'reembolso_parcial_centavos': resposta.reembolsoParcialCentavos,
        'fotos': fotos,
      },
    );
  }

  @override
  Future<DadosRetrabalho?> carregarRetrabalho(String disputaId) async {
    try {
      final lista = _lista(await _api.get('/v1/pedidos/$disputaId/retrabalho'));
      // Só o que ainda pede ação do profissional; retrabalho resolvido ou vencido não abre tela.
      const emCurso = {'aberto', 'aceito', 'em_execucao'};
      final abertos = [
        for (final r in lista)
          if (emCurso.contains(r['estado'])) r
      ];
      if (abertos.isEmpty) return null;
      final ultimo = abertos.last;
      return DadosRetrabalho(
        estado: ultimo['estado'] as String,
        disputaId: disputaId,
        titulo:
            'Retrabalho do pedido #${disputaId.substring(0, disputaId.length < 4 ? disputaId.length : 4).toUpperCase()}',
        descricaoProblema: (ultimo['descricao'] as String?) ?? 'Retrabalho solicitado',
        prazoAtendimentoDias: ConfigPublica.atual.prazoRetrabalhoDias,
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
    // O horário e o recado do profissional vão para o cliente pelo chat do pedido (fica guardado).
    final recado = agendamento.mensagem.isEmpty ? '' : ' ${agendamento.mensagem}';
    try {
      await _api.post(
        '/v1/pedidos/${agendamento.disputaId}/mensagens',
        corpo: {'texto': 'Retrabalho aceito. Posso voltar: ${agendamento.horario}.$recado'},
      );
    } on ErroTrato {
      // O retrabalho já foi aceito; o recado é cortesia e não deve desfazer isso.
    }
  }

  @override
  Future<void> avancarRetrabalho(String disputaId, String etapa) async {
    await _api.post('/v1/pedidos/$disputaId/retrabalho/atender', corpo: {'etapa': etapa});
  }
}

/// Central de privacidade e exclusão da conta (LGPD) falando com a API real:
/// `GET /v1/me/consentimentos`, `POST /v1/me/consentimentos`, `GET /v1/me/dados`, `POST /v1/me/exclusao`.
class ServicoPrivacidadeApi implements ServicoPrivacidade, CancelamentoExclusao {
  ServicoPrivacidadeApi(this._api);

  final ClienteApi _api;

  static const _mapaUiParaBackend = {
    'dados_pedido': 'termos_de_uso',
    'localizacao': 'localizacao_no_servico',
    'avisos': 'comunicacoes_marketing',
  };

  static const _mapaBackendParaUi = {
    'termos_de_uso': 'dados_pedido',
    'politica_privacidade': 'dados_pedido',
    'localizacao_no_servico': 'localizacao',
    'comunicacoes_marketing': 'avisos',
  };

  @override
  Future<List<Consentimento>> consentimentos() async {
    final res = await _api.get('/v1/me/consentimentos');
    {
      final mapa = (res is Map<String, dynamic>) ? res : <String, dynamic>{};
      final ativosPorFinalidade = <String, bool>{};
      final vigentes = mapa['vigentes'];
      if (vigentes is Map) {
        for (final entry in vigentes.entries) {
          final chave = entry.key.toString();
          final val = entry.value;
          final aceito = val is Map ? (val['aceito'] as bool? ?? false) : false;
          final chaveUi = _mapaBackendParaUi[chave] ?? chave;
          ativosPorFinalidade[chaveUi] = aceito;
        }
      } else if (vigentes is List) {
        for (final v in vigentes) {
          if (v is Map && v['finalidade'] is String && v['aceito'] is bool) {
            final f = v['finalidade'] as String;
            final chaveUi = _mapaBackendParaUi[f] ?? f;
            ativosPorFinalidade[chaveUi] = v['aceito'] as bool;
          }
        }
      }
      return [
        for (final item in consentimentosPadrao)
          Consentimento(
            id: item.id,
            titulo: item.titulo,
            descricao: item.descricao,
            ativo: ativosPorFinalidade[item.id] ?? item.ativo,
            obrigatorio: item.obrigatorio,
          ),
      ];
    }
  }

  @override
  Future<void> alterarConsentimento(String id, {required bool ativo}) async {
    final finalidadeBackend = _mapaUiParaBackend[id] ?? id;
    await _api.post(
      '/v1/me/consentimentos',
      corpo: {
        'finalidade': finalidadeBackend,
        'aceito': ativo,
        'versao_texto': '1.0',
      },
    );
  }

  @override
  Future<String?> solicitarExportacao() async {
    final dados = await _api.get('/v1/me/dados');
    final jsonFormatado = const JsonEncoder.withIndent('  ').convert(dados);
    if (!kIsWeb) {
      try {
        final dir = await getTemporaryDirectory();
        final arquivo = File('${dir.path}${Platform.pathSeparator}trato_meus_dados.json');
        await arquivo.writeAsString(jsonFormatado);
      } on Object {
        // Sem acesso ao diretório temporário (ex.: testes): devolve o JSON mesmo assim.
      }
    }
    return jsonFormatado;
  }

  @override
  Future<void> cancelarExclusao() async {
    await _api.delete('/v1/me/exclusao');
  }

  @override
  Future<void> solicitarExclusao() async {
    // 1º passo: pede a exclusão para obter o token de confirmação
    final r1 = await _api.post('/v1/me/exclusao');
    final mapa1 = (r1 is Map<String, dynamic>) ? r1 : <String, dynamic>{};
    final token = mapa1['token_confirmacao'] as String?;
    if (token != null && token.isNotEmpty) {
      // 2º passo: confirma com o token emitido
      await _api.post('/v1/me/exclusao', corpo: {'token_confirmacao': token});
    }
  }
}
