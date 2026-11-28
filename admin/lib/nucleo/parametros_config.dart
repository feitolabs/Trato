import '../dados/modelos.dart';
import 'formato.dart';

/// Temas de Configurações (RF-CFG-01), na ordem em que aparecem.
const gruposConfig = [
  'Pagamento',
  'Garantia',
  'Disputas',
  'Pedidos e propostas',
  'Risco',
  'Atendimento e dados',
  'Avisos',
];

/// Texto do parâmetro que a versão vigente não traz: o painel não inventa um número.
const kSemValorPublicado = 'sem valor publicado (vale o padrão do servidor)';

/// O que a tela sabe de cada parâmetro além do que o banco guarda: o tema e uma frase de ajuda.
/// Nome, unidade e faixa vêm do banco (`config_definicoes`); aqui não há nenhum valor de regra.
class InfoParametro {
  const InfoParametro(this.grupo, this.ajuda);
  final String grupo;
  final String ajuda;
}

const _info = <String, InfoParametro>{
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
  'arrependimento_dias': InfoParametro('Pedidos e propostas', 'Prazo legal de arrependimento (CDC art. 49)'),
  'ausencia_espera_minutos':
      InfoParametro('Pedidos e propostas', 'Espera mínima depois do check-in antes de registrar ausência'),
  'ausencia_justificativa_horas':
      InfoParametro('Pedidos e propostas', 'Tempo para o cliente justificar a ausência depois do aviso'),
  'ausencia_retencao_max_bps':
      InfoParametro('Pedidos e propostas', 'Teto de retenção por custos comprovados na ausência'),
  'disputa_contestacao_prazo_dias_uteis':
      InfoParametro('Disputas', 'Prazo para contestar a decisão da disputa (Termos 8.7)'),
  'disputa_contestacao_resposta_dias_uteis':
      InfoParametro('Disputas', 'Prazo para responder a contestação da disputa (Termos 8.7)'),
  'incidente_seguranca_cautela_horas':
      InfoParametro('Risco', 'Prazo das medidas de cautela depois do relato de segurança (Termos 9.6)'),
  'sac_resposta_dias_uteis': InfoParametro('Atendimento e dados', 'Prazo geral de resposta do SAC (Termos 25.4)'),
  'sac_dados_pessoais_dias':
      InfoParametro('Atendimento e dados', 'Resposta do SAC a pedido sobre dados pessoais (Termos 14.9)'),
  'lgpd_pedido_resposta_dias':
      InfoParametro('Atendimento e dados', 'Prazo de resposta a pedido sobre dados pessoais (Termos 14.9)'),
  'avaliacao_revisao_resposta_dias_uteis':
      InfoParametro('Atendimento e dados', 'Prazo de resposta ao pedido de revisão de avaliação (Termos 12.7)'),
  'aviso_previo_encerramento_dias':
      InfoParametro('Avisos', 'Antecedência do aviso de encerramento de conta sem falta (Termos 20.8)'),
  'aviso_previo_termos_dias':
      InfoParametro('Avisos', 'Antecedência do aviso de mudança relevante dos Termos (Termos 23.2)'),
  'aviso_previo_tratinhos_dias':
      InfoParametro('Avisos', 'Antecedência do aviso de mudança ou fim dos Tratinhos (Termos 13.11 e I.12)'),
  'aviso_previo_inatividade_dias':
      InfoParametro('Avisos', 'Antecedência do aviso antes de inativar conta sem uso (Termos 4.9)'),
  'tratinhos_aviso_vencimento_dias':
      InfoParametro('Avisos', 'Antecedência do aviso de vencimento dos Tratinhos (Termos I.5)'),
};

InfoParametro infoDe(String chave) => _info[chave] ?? const InfoParametro('Pedidos e propostas', '');

/// "0% a 20%", "R$ 0,00 a R$ 20,00", "1 a 30 dias".
String faixaLegivel(ConfigDefinicao d) {
  if (d.unidade == UnidadeConfig.quantidade && d.maximo == 1 && d.minimo == 0) return 'Desligada ou ligada';
  final a = d.unidade == UnidadeConfig.bps ? _pct(d.minimo) : valorLegivel(d.minimo, d);
  final b = d.unidade == UnidadeConfig.bps ? _pct(d.maximo) : valorLegivel(d.maximo, d);
  // "1 a 30 dias": a unidade aparece uma vez só.
  if (d.unidade == UnidadeConfig.horas ||
      d.unidade == UnidadeConfig.minutos ||
      d.unidade == UnidadeConfig.dias ||
      d.unidade == UnidadeConfig.diasUteis) {
    final unidade = switch (d.unidade) {
      UnidadeConfig.horas => 'horas',
      UnidadeConfig.minutos => 'minutos',
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
      UnidadeConfig.bps => centavosParaCampo(valor),
      UnidadeConfig.centavos => centavosParaCampo(valor),
      _ => '$valor',
    };

/// Inverso de [valorParaCampo]. Devolve null se o texto não é um número válido.
int? campoParaValor(String texto, ConfigDefinicao d) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  switch (d.unidade) {
    case UnidadeConfig.bps:
      return lerPercentualEmBps(t);
    case UnidadeConfig.centavos:
      return lerReaisEmCentavos(t);
    default:
      return int.tryParse(t);
  }
}

/// Diferenças entre duas versões, uma frase por parâmetro: "Prazo de resposta da disputa: 24 h → 36 h".
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
