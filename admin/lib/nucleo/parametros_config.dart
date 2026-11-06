import '../dados/modelos.dart';
import 'formato.dart';

/// Temas de Configurações (RF-CFG-01), na ordem em que aparecem.
const gruposConfig = ['Taxas', 'Pagamento', 'Garantia', 'Disputas', 'Pedidos e propostas', 'Risco'];

/// O que a tela sabe de cada parâmetro além do que o banco guarda: o tema e uma frase de ajuda.
/// Nome, unidade e faixa vêm do banco (`config_definicoes`); aqui não há nenhum valor de regra.
class InfoParametro {
  const InfoParametro(this.grupo, this.ajuda);
  final String grupo;
  final String ajuda;
}

const _info = <String, InfoParametro>{
  'taxa_bps': InfoParametro('Taxas', 'Percentual retido sobre o valor do serviço concluído'),
  'taxa_minima_centavos': InfoParametro('Taxas', 'Cobrada quando o percentual der menos que isso'),
  'taxa_progressiva_ativa': InfoParametro('Taxas', 'Liga a tabela progressiva de taxa'),
  'adiantamento_bps': InfoParametro('Pagamento', 'Parte do valor paga quando o serviço começa'),
  'prazo_liberacao_dias': InfoParametro('Pagamento', 'Tempo entre o encerramento e o repasse'),
  'janela_chargeback_dias': InfoParametro('Pagamento', 'Quanto tempo o cliente tem para reclamar'),
  'prazo_confirmacao_cliente_horas': InfoParametro('Pagamento', 'Tempo para o cliente confirmar que o serviço acabou'),
  'prazo_pagamento_pendente_horas': InfoParametro('Pagamento', 'Tempo até um pagamento pendente expirar'),
  'garantia_retrabalho_dias_padrao': InfoParametro('Garantia', 'Garantia usada quando a categoria não define a sua'),
  'prazo_retrabalho_atendimento_dias': InfoParametro('Garantia', 'Tempo para o profissional atender um retrabalho'),
  'prazo_resposta_disputa_horas': InfoParametro('Disputas', 'Tempo para o profissional responder a disputa'),
  'prazo_congelar_disputa_horas': InfoParametro('Disputas', 'Tempo até o repasse ficar congelado'),
  'prazo_decisao_disputa_dias_uteis': InfoParametro('Disputas', 'Tempo para a equipe decidir a disputa'),
  'limite_orcamentos_por_pedido': InfoParametro('Pedidos e propostas', 'Quantas propostas um pedido recebe'),
  'validade_pedido_horas': InfoParametro('Pedidos e propostas', 'Tempo que um pedido fica aberto para propostas'),
  'tolerancia_comparecimento_horas': InfoParametro('Pedidos e propostas', 'Atraso aceito antes de contar como falta'),
  'valor_minimo_servico_centavos': InfoParametro('Pedidos e propostas', 'Menor valor aceito na criação do pedido'),
  'valor_maximo_servico_centavos': InfoParametro('Pedidos e propostas', 'Valor acima disso é recusado na criação do pedido'),
  'limite_valor_atipico_centavos': InfoParametro('Risco', 'Acima disso o pedido gera alerta de risco'),
};

InfoParametro infoDe(String chave) => _info[chave] ?? const InfoParametro('Pedidos e propostas', '');

/// "0% a 20%", "R$ 0,00 a R$ 20,00", "1 a 30 dias".
String faixaLegivel(ConfigDefinicao d) {
  if (d.unidade == UnidadeConfig.quantidade && d.maximo == 1 && d.minimo == 0) return 'Desligada ou ligada';
  final a = d.unidade == UnidadeConfig.bps ? _pct(d.minimo) : valorLegivel(d.minimo, d);
  final b = d.unidade == UnidadeConfig.bps ? _pct(d.maximo) : valorLegivel(d.maximo, d);
  // "1 a 30 dias": a unidade aparece uma vez só.
  if (d.unidade == UnidadeConfig.horas || d.unidade == UnidadeConfig.dias || d.unidade == UnidadeConfig.diasUteis) {
    final unidade = switch (d.unidade) {
      UnidadeConfig.horas => 'horas',
      UnidadeConfig.dias => 'dias',
      _ => 'dias úteis',
    };
    return '${d.minimo} a ${d.maximo} $unidade';
  }
  return '$a a $b';
}

/// Faixa em %: "20%" quando é inteiro, "7,50%" quando não é.
String _pct(int bps) => bps % 100 == 0 ? '${bps ~/ 100}%' : formatarConfig(bps, 'bps');

/// Valor com unidade visível: bps vira %, centavos vira R$, prazos mostram horas/dias.
String valorLegivel(int valor, ConfigDefinicao d) {
  if (d.unidade == UnidadeConfig.quantidade && d.minimo == 0 && d.maximo == 1) {
    return valor == 1 ? 'Ligada' : 'Desligada';
  }
  return formatarConfig(valor, d.unidade.codigo);
}

/// Texto que a pessoa edita para o valor atual ("7,50" para 750 bps; "3,00" para 300 centavos).
String valorParaCampo(int valor, ConfigDefinicao d) => switch (d.unidade) {
      UnidadeConfig.bps => (valor / 100).toStringAsFixed(2).replaceAll('.', ','),
      UnidadeConfig.centavos => (valor / 100).toStringAsFixed(2).replaceAll('.', ','),
      _ => '$valor',
    };

/// Inverso de [valorParaCampo]. Devolve null se o texto não é um número válido.
int? campoParaValor(String texto, ConfigDefinicao d) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  switch (d.unidade) {
    case UnidadeConfig.bps:
      final v = double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
      return v == null ? null : (v * 100).round();
    case UnidadeConfig.centavos:
      return lerReaisEmCentavos(t);
    default:
      return int.tryParse(t);
  }
}

/// Diferenças entre duas versões, uma frase por parâmetro: "Taxa mínima por pedido: R$ 3,00 → R$ 4,00".
List<String> diferencas(ConfigVersao nova, ConfigVersao base, List<ConfigDefinicao> definicoes) {
  final linhas = <String>[];
  for (final d in definicoes) {
    final a = base.valores[d.chave];
    final b = nova.valores[d.chave];
    if (b != null && b != a) {
      linhas.add('${d.descricao}: ${a == null ? 'sem valor' : valorLegivel(a, d)} → ${valorLegivel(b, d)}');
    }
  }
  return linhas;
}
