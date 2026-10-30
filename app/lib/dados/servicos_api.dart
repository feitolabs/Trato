import '../dispositivo/servico_camera.dart';
import '../telas/aditivo/aditivo.dart';
import '../telas/nota_material/nota_material.dart';
import '../telas/verificacao/verificacao.dart';
import 'cliente_api.dart';
import 'erros.dart';
import 'servico_upload.dart';

// Serviços das telas de aditivo, nota de materiais e verificação, falando com a API. Só pedem e
// mostram: o total da nota, o estado do aditivo e a cobrança são do backend.

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
    return (await _upload.enviar(foto, FinalidadeArquivo.documento)).arquivoId;
  }

  Future<String?> selfie() async {
    final foto = await _camera.tirarFoto(frontal: true);
    if (foto == null) return null;
    return (await _upload.enviar(foto, FinalidadeArquivo.selfie)).arquivoId;
  }
}
