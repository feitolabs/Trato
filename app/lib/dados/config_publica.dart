import 'cliente_api.dart';

/// Prazos e limites que as telas escrevem em texto ("até 5 orçamentos em 48 horas").
///
/// Vêm da tabela de configuração do servidor (`GET /v1/config/publica`). O app carrega uma vez ao
/// abrir; até chegar (ou sem rede), valem os padrões abaixo, que são os valores vigentes hoje.
/// Nenhuma regra é aplicada aqui: os números só aparecem em texto. Quem decide é o backend.
class ConfigPublica {
  const ConfigPublica({
    this.limiteOrcamentos = 5,
    this.validadePedidoHoras = 48,
    this.prazoConfirmacaoHoras = 48,
    this.prazoRetrabalhoDias = 7,
    this.prazoRespostaDisputaHoras = 48,
    this.prazoLiberacaoDias = 0,
    this.suporteEmail,
  });

  factory ConfigPublica.deJson(Map<String, dynamic> j) {
    const p = ConfigPublica();
    int valor(String chave, int padrao) {
      final v = j[chave];
      return v is num && v >= 0 ? v.toInt() : padrao;
    }

    return ConfigPublica(
      limiteOrcamentos: valor('limite_orcamentos_por_pedido', p.limiteOrcamentos),
      validadePedidoHoras: valor('validade_pedido_horas', p.validadePedidoHoras),
      prazoConfirmacaoHoras: valor('prazo_confirmacao_cliente_horas', p.prazoConfirmacaoHoras),
      prazoRetrabalhoDias: valor('prazo_retrabalho_atendimento_dias', p.prazoRetrabalhoDias),
      prazoRespostaDisputaHoras:
          valor('prazo_resposta_disputa_horas', p.prazoRespostaDisputaHoras),
      prazoLiberacaoDias: valor('prazo_liberacao_dias', p.prazoLiberacaoDias),
      suporteEmail: _email(j['suporte_email']),
    );
  }

  static String? _email(Object? v) {
    final t = v is String ? v.trim() : '';
    return t.contains('@') ? t : null;
  }

  /// E-mail do atendimento; nulo = o servidor não configurou (o botão "Falar com o suporte" some).
  final String? suporteEmail;

  /// Quantos orçamentos um pedido recebe.
  final int limiteOrcamentos;

  /// Por quantas horas o pedido recebe orçamentos.
  final int validadePedidoHoras;

  /// Quanto tempo o cliente tem para confirmar o serviço depois do check-out.
  final int prazoConfirmacaoHoras;

  /// Prazo do profissional para atender um retrabalho da garantia.
  final int prazoRetrabalhoDias;

  /// Prazo do profissional para responder uma disputa.
  final int prazoRespostaDisputaHoras;

  /// Dias até o valor ser liberado ao profissional depois da confirmação (0 = na hora).
  final int prazoLiberacaoDias;

  /// A configuração em uso pelas telas.
  static ConfigPublica atual = const ConfigPublica();

  /// Busca no servidor e troca [atual]. Sem rede ou sem a rota, fica como estava.
  static Future<void> carregar(ClienteApi api) async {
    try {
      final j = await api.get('/v1/config/publica');
      if (j is Map<String, dynamic>) atual = ConfigPublica.deJson(j);
    } on Object {
      // Segue com os valores que já estavam.
    }
  }

  /// "48 horas", "1 hora".
  static String horas(int h) => '$h ${h == 1 ? 'hora' : 'horas'}';

  /// "7 dias", "1 dia".
  static String dias(int d) => '$d ${d == 1 ? 'dia' : 'dias'}';

  /// Frase do aviso de liberação na conclusão.
  String get textoLiberacao => prazoLiberacaoDias <= 0
      ? 'Depois da sua confirmação, o valor é liberado ao profissional.'
      : 'Depois da sua confirmação, o valor é liberado ao profissional em até '
          '${dias(prazoLiberacaoDias)}.';
}
