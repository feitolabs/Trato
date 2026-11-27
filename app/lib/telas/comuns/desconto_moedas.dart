// Textos das moedas do Trato ("Tratinhos") e o motivo do desconto indisponível.
// Quem decide é o backend; o app só mostra.

import '../profissional/dinheiro.dart';

enum MotivoDescontoIndisponivel {
  orcamentoEsgotado,
  tetoCliente,
  limiteDiario;

  /// Lê `desconto_indisponivel_motivo`. Valor desconhecido: null (não quebra).
  static MotivoDescontoIndisponivel? deTexto(Object? valor) => switch (valor) {
        'orcamento_esgotado' => orcamentoEsgotado,
        'teto_cliente' => tetoCliente,
        'limite_diario' => limiteDiario,
        _ => null,
      };

  /// Frase completa. [voltaEm] vem do backend (`desconto_volta_em`); ausente = texto sem data.
  /// Limite diário sempre diz "amanhã". Termina sempre com a explicação do limite.
  String mensagem({DateTime? voltaEm}) {
    final quando = switch (this) {
      limiteDiario => 'Ele volta amanhã.',
      _ => voltaEm == null
          ? 'Ele volta no próximo mês.'
          : 'Ele volta no dia 1º (${formatarDiaMes(voltaEm)}).',
    };
    final abertura = switch (this) {
      orcamentoEsgotado => 'Desconto indisponível agora.',
      tetoCliente => 'Você já usou o desconto máximo deste mês.',
      limiteDiario => 'O desconto de hoje já acabou.',
    };
    return '$abertura $quando $_explicacaoLimite';
  }
}

const _explicacaoLimite =
    'O desconto é pago pelo Trato e tem limite por dia e por mês. Seus Tratinhos continuam guardados.';

/// Limite de uso mostrado antes de usar (Anexo I). Os valores são os do servidor; sem o
/// teto, a tela diz que não foi informado.
String textoLimiteDoDesconto(int? tetoMesCentavos, int? usadoMesCentavos) {
  if (tetoMesCentavos == null) {
    return 'O limite mensal do desconto com Tratinhos não foi informado agora.';
  }
  final usado = usadoMesCentavos == null
      ? ''
      : ' Você já usou ${Dinheiro.formatar(usadoMesCentavos)} neste mês.';
  return 'Limite de desconto com Tratinhos: ${Dinheiro.formatar(tetoMesCentavos)} por mês.'
      '$usado';
}

/// Frase fixa aprovada pelo João. Não prometer mais nada além disso.
const fraseSemTaxa = 'Sem taxa para você neste serviço.';

/// Cadastro (sem serviço ainda): sem a promessa nem o aviso de cobrança futura.
const fraseSemTaxaCadastro = 'Sem taxa para você.';

/// Esclarece que o desconto vale tanto no Pix quanto no cartão.
const fraseDescontoMetodos =
    'O desconto com Tratinhos vale no Pix e no cartão (à vista ou parcelado).';

/// 27/11 (dia e mês com 2 dígitos).
String formatarDiaMes(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Mensagem quando o backend diz `desconto_disponivel: false`. Sem motivo conhecido, usa a do orçamento.
String mensagemDescontoIndisponivel(MotivoDescontoIndisponivel? motivo, {DateTime? voltaEm}) =>
    (motivo ?? MotivoDescontoIndisponivel.orcamentoEsgotado).mensagem(voltaEm: voltaEm);

/// 1 -> "1 Tratinho"; 50 -> "50 Tratinhos".
String textoTratinhos(int quantidade) => quantidade == 1 ? '1 Tratinho' : '$quantidade Tratinhos';

/// "50 Tratinhos = R$ 0,50". Sem o valor da moeda (backend antigo), só a quantidade.
/// A conta é só para exibir: o valor da moeda vem do backend.
String textoTratinhosEmReais(int quantidade, int? valorMoedaCentavos) {
  if (valorMoedaCentavos == null) return textoTratinhos(quantidade);
  return '${textoTratinhos(quantidade)} = ${Dinheiro.formatar(quantidade * valorMoedaCentavos)}';
}

/// "2026-11-27" (ou data ISO completa) -> data sem hora. Ausente ou inválido -> null.
DateTime? lerDataIso(Object? valor) {
  if (valor is! String || valor.length < 10) return null;
  final d = DateTime.tryParse(valor.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// "Você tem 50 Tratinhos a liberar em 27/11 (R$ 0,50)". Null quando não há pendentes.
String? textoTratinhosPendentes(int pendentes, DateTime? liberacao, int? valorMoedaCentavos) {
  if (pendentes <= 0) return null;
  final quando = liberacao == null ? '' : ' em ${formatarDiaMes(liberacao)}';
  final reais =
      valorMoedaCentavos == null ? '' : ' (${Dinheiro.formatar(pendentes * valorMoedaCentavos)})';
  return 'Você tem ${textoTratinhos(pendentes)} a liberar$quando$reais';
}
