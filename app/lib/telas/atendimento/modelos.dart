/// Atendimento do Trato (Termos 25.1 a 25.5). Protocolo, status e prazos vêm do servidor
/// (`/v1/sac/chamados`): o app só pede e mostra.
library;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _texto(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

/// Categorias aceitas pelo servidor, na ordem da tela.
const categoriasDeChamado = <String, String>{
  'duvida': 'Dúvida',
  'reclamacao': 'Reclamação',
  'contestacao': 'Contestação',
  'dados_pessoais': 'Meus dados pessoais',
  'seguranca': 'Segurança',
  'outro': 'Outro assunto',
};

/// Incidentes que devem ser relatados (Termos 9.4). O texto vira o assunto do chamado.
const casoPessoaDiferente = 'Chegou uma pessoa diferente da que aparece no app';
const casosDeSeguranca = <String>[
  'Furto, roubo ou sumiço de objetos',
  'Agressão, ameaça, assédio, discriminação ou constrangimento',
  'Acidente com pessoa ou dano grave ao imóvel',
  casoPessoaDiferente,
  'Comportamento suspeito ou perigoso',
  'Pedido de pagamento por fora, de códigos ou de dados sensíveis',
];

/// Termos 9.5.
const orientacaoPessoaDiferente = 'Quem chegou não é a pessoa do app? Não abra a porta e não '
    'informe o Código de Início.';

class MensagemChamado {
  const MensagemChamado({required this.autor, required this.texto, this.criadaEm});

  factory MensagemChamado.deJson(Map<String, dynamic> j) => MensagemChamado(
        autor: _texto(j['autor']) ?? '',
        texto: _texto(j['texto']) ?? '',
        criadaEm: _data(j['criada_em']),
      );

  /// `usuario`, `equipe` ou `sistema`.
  final String autor;
  final String texto;
  final DateTime? criadaEm;

  String get nomeDoAutor => switch (autor) {
        'usuario' => 'Você',
        'sistema' => 'Aviso automático',
        _ => 'Atendimento Trato',
      };
}

class Chamado {
  const Chamado({
    required this.id,
    required this.protocolo,
    required this.assunto,
    required this.status,
    this.categoria = '',
    this.pedidoId,
    this.criadoEm,
    this.responderAte,
    this.novoPrazoAte,
    this.motivoExtensao,
    this.mensagens = const [],
  });

  factory Chamado.deJson(Map<String, dynamic> j) => Chamado(
        id: '${j['id'] ?? ''}',
        protocolo: _texto(j['protocolo']) ?? '',
        assunto: _texto(j['assunto']) ?? 'Chamado',
        status: _texto(j['status']) ?? '',
        categoria: _texto(j['categoria']) ?? '',
        pedidoId: _texto(j['pedido_id']),
        criadoEm: _data(j['criado_em']),
        responderAte: _data(j['responder_ate']),
        novoPrazoAte: _data(j['novo_prazo_ate']),
        motivoExtensao: _texto(j['motivo_extensao']),
        mensagens: [
          for (final m in (j['mensagens'] as List? ?? const []))
            if (m is Map<String, dynamic>) MensagemChamado.deJson(m),
        ],
      );

  final String id;
  final String protocolo;
  final String assunto;
  final String status;
  final String categoria;
  final String? pedidoId;
  final DateTime? criadoEm;
  final DateTime? responderAte;

  /// Prazo estendido, com o motivo (25.4).
  final DateTime? novoPrazoAte;
  final String? motivoExtensao;
  final List<MensagemChamado> mensagens;

  bool get encerrado => status == 'encerrado';

  String get statusTexto => switch (status) {
        'aberto' => 'Aberto',
        'em_atendimento' => 'Em atendimento',
        'aguardando_usuario' => 'Aguardando você',
        'respondido' => 'Respondido',
        'encerrado' => 'Encerrado',
        _ => 'Em andamento',
      };

  String get categoriaTexto => categoriasDeChamado[categoria] ?? 'Atendimento';
}

class PaginaDeChamados {
  const PaginaDeChamados({required this.itens, required this.total});

  final List<Chamado> itens;
  final int total;
}

const textoAtendimentoIndisponivel =
    'O atendimento pelo app está indisponível. Escreva para o suporte por e-mail.';

abstract interface class ServicoSac {
  /// Nulo: o servidor não tem o atendimento (404/503).
  Future<PaginaDeChamados?> listar({int deslocamento = 0});

  Future<Chamado> abrir({
    required String categoria,
    required String assunto,
    required String texto,
    String? pedidoId,
  });

  Future<Chamado> ver(String id);

  Future<Chamado> responder(String id, String texto);
}

/// Resposta do relato de pessoa diferente (Termos 9.5). Quem decide se cancela é o servidor.
class RelatoPessoaDiferente {
  const RelatoPessoaDiferente({this.protocolo = '', this.cancelado = false, this.mensagem = ''});

  factory RelatoPessoaDiferente.deJson(Map<Object?, Object?> j) => RelatoPessoaDiferente(
        protocolo: _texto(j['protocolo']) ?? '',
        cancelado: j['cancelado'] == true,
        mensagem: _texto(j['mensagem']) ?? '',
      );

  final String protocolo;

  /// Só `true` quando o servidor diz que cancelou.
  final bool cancelado;
  final String mensagem;
}

abstract interface class ServicoPessoaDiferente {
  Future<RelatoPessoaDiferente> relatarPessoaDiferente(String pedidoId, {String? descricao});
}

class ServicoSacApi implements ServicoSac, ServicoPessoaDiferente {
  ServicoSacApi(this._api);

  final ClienteApi _api;

  static Chamado _um(Object? j) => Chamado.deJson(j! as Map<String, dynamic>);

  @override
  Future<RelatoPessoaDiferente> relatarPessoaDiferente(String pedidoId, {String? descricao}) async {
    final texto = (descricao ?? '').trim();
    final j = await _api.post(
      '/v1/pedidos/$pedidoId/seguranca/pessoa-diferente',
      corpo: {if (texto.isNotEmpty) 'descricao': texto},
    );
    if (j is! Map) throw ErroTrato.servidor;
    return RelatoPessoaDiferente.deJson(j);
  }

  @override
  Future<PaginaDeChamados?> listar({int deslocamento = 0}) async {
    try {
      final j = (await _api.get(
        '/v1/sac/chamados',
        consulta: {if (deslocamento > 0) 'deslocamento': '$deslocamento'},
      ))! as Map<String, dynamic>;
      final itens = [
        for (final c in (j['itens'] as List? ?? const []))
          if (c is Map<String, dynamic>) Chamado.deJson(c),
      ];
      return PaginaDeChamados(itens: itens, total: (j['total'] as num?)?.toInt() ?? itens.length);
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }

  @override
  Future<Chamado> abrir({
    required String categoria,
    required String assunto,
    required String texto,
    String? pedidoId,
  }) async {
    try {
      return _um(await _api.post('/v1/sac/chamados', corpo: {
        'categoria': categoria,
        'assunto': assunto.trim(),
        'texto': texto.trim(),
        if (pedidoId != null) 'pedido_id': pedidoId,
      }));
    } on ErroTrato catch (e) {
      // 404 com pedido é "pedido não encontrado": o texto do servidor segue.
      if (e.codigoHttp == 503 || (e.codigoHttp == 404 && pedidoId == null)) {
        throw const ErroTrato(TipoErro.recusado, textoAtendimentoIndisponivel);
      }
      rethrow;
    }
  }

  @override
  Future<Chamado> ver(String id) async => _um(await _api.get('/v1/sac/chamados/$id'));

  @override
  Future<Chamado> responder(String id, String texto) async => _um(
        await _api.post('/v1/sac/chamados/$id/mensagens', corpo: {'texto': texto.trim()}),
      );
}
