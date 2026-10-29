import '../componentes/componentes.dart';
import '../dispositivo/servico_camera.dart';
import '../telas/carteira/modelos.dart';
import '../telas/conclusao/dados_exemplo.dart';
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

/// Estados em que o backend já reconhece o pagamento.
const _estadosPagos = {'pago_e_retido', 'agendado', 'em_andamento', 'em_confirmacao', 'concluido'};
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

  // Sem rota no backend: POST /v1/pedidos/{id}/avaliacao.
  @override
  Future<void> avaliar(String pedidoId, EnvioAvaliacao avaliacao) async =>
      throw ErroTrato.indisponivel;

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

  // Sem rota no backend: GET /v1/pedidos/{id}/garantia.
  @override
  Future<DadosGarantia> garantia(String pedidoId) async => throw ErroTrato.indisponivel;

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

  // Sem rota no backend: GET /v1/pedidos/{id}/orcamentos.
  @override
  Future<OrcamentosDoPedido> listar(String pedidoId) async => throw ErroTrato.indisponivel;

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

class RepositorioPagamentoApi implements RepositorioPagamento {
  RepositorioPagamentoApi(this._api);

  final ClienteApi _api;

  // Sem rota no backend: GET /v1/pedidos/{id}/pagamento (valor e opções).
  @override
  Future<DadosPagamento> dados(String pedidoId) async => throw ErroTrato.indisponivel;

  // Sem rota no backend: POST /v1/pedidos/{id}/cobranca (cria a cobrança no provedor, modo teste).
  @override
  Future<Cobranca> criarCobranca(String pedidoId, MetodoPagamento metodo) async =>
      throw ErroTrato.indisponivel;

  /// "Pago" só quando o backend (depois do webhook assinado do provedor) mudou o estado.
  @override
  Future<StatusPagamento> status(String pedidoId) async {
    final pedido = PedidoApi.deJson(_mapa(await _api.get('/v1/pedidos/$pedidoId')));
    if (_estadosPagos.contains(pedido.estado)) return StatusPagamento.pago;
    if (pedido.estado == 'cancelado') return StatusPagamento.falhou;
    return StatusPagamento.aguardando;
  }
}

// Sem rota no backend: GET/POST /v1/pedidos/{id}/mensagens.
class RepositorioChatApi implements RepositorioChat {
  RepositorioChatApi();

  @override
  Future<ConversaPedido> conversa(String pedidoId) async => throw ErroTrato.indisponivel;

  @override
  Future<void> enviar(String pedidoId, String texto) async => throw ErroTrato.indisponivel;
}

// Sem rota no backend: GET /v1/notificacoes.
class RepositorioNotificacoesApi implements RepositorioNotificacoes {
  RepositorioNotificacoesApi();

  @override
  Future<List<Notificacao>> listar() async => throw ErroTrato.indisponivel;
}

// Sem rota no backend: GET /v1/me (perfil do cliente).
class RepositorioPerfilApi implements RepositorioPerfil {
  RepositorioPerfilApi();

  @override
  Future<PerfilCliente> carregar() async => throw ErroTrato.indisponivel;
}

class RepositorioProfissionalApi implements RepositorioProfissional {
  RepositorioProfissionalApi(
    this._api, {
    this.captura = const CapturaIndisponivel(),
    this.upload,
    this.fila,
  });

  final ClienteApi _api;
  final CapturaCheckIn captura;
  final ServicoUpload? upload;
  final FilaOffline? fila;

  // Sem rota no backend: GET /v1/profissionais/me/inicio (pedidos abertos, próximo atendimento).
  @override
  Future<InicioProfissional> inicio() async => throw ErroTrato.indisponivel;

  // Sem rota no backend: GET /v1/pedidos-abertos/{id}.
  @override
  Future<DetalhePedido> detalhe(String pedidoId) async => throw ErroTrato.indisponivel;

  // Sem rota no backend: POST /v1/pedidos-abertos/{id}/recusa.
  @override
  Future<void> recusar(String pedidoId, MotivoRecusa motivo) async => throw ErroTrato.indisponivel;

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
  ServicoOrcamento servicoOrcamento(String pedidoId) => ServicoOrcamentoApi();

  @override
  ServicoCheckIn servicoCheckIn(String pedidoId) =>
      ServicoCheckInApi(_api, pedidoId: pedidoId, captura: captura, upload: upload, fila: fila);
}

// Sem rota no backend: POST /v1/orcamentos/resumo {total_centavos} → taxa e líquido.
class ServicoOrcamentoApi implements ServicoOrcamento {
  ServicoOrcamentoApi();

  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async => throw ErroTrato.indisponivel;
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
