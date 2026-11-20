import '../comuns/desconto_moedas.dart';

/// Ações dos itens do perfil do cliente. A tela só avisa qual foi tocado.
enum AcaoPerfil {
  dadosPessoais,
  enderecos,
  formasPagamento,
  favoritos,
  contatosConfianca,
  notificacoes,
  usarComoProfissional,
  meusDados,
  centralAjuda,
  termos,
}

class ItemPerfil {
  const ItemPerfil({required this.acao, required this.titulo, this.valor});

  final AcaoPerfil acao;
  final String titulo;

  /// Texto à direita, ex.: "2" ou "Pix, Visa".
  final String? valor;
}

class GrupoPerfil {
  const GrupoPerfil({required this.titulo, required this.itens});

  final String titulo;
  final List<ItemPerfil> itens;
}

class PerfilCliente {
  const PerfilCliente({
    required this.nome,
    required this.iniciais,
    required this.resumo,
    required this.grupos,
    this.fotoReferencia,
    this.moedas,
    this.moedasDescontoDisponivel = true,
    this.moedasDescontoMotivo,
    this.moedasDescontoVoltaEm,
    this.moedasPendentes = 0,
    this.moedasProximaLiberacao,
    this.moedasValorCentavos,
    this.moedasVenceEm,
    this.tetoDescontoMesCentavos,
    this.descontoUsadoMesCentavos,
  });

  /// Tratinhos de avaliação ainda em espera (valem 7 dias depois, sem disputa) e a data em que
  /// liberam. Ausente = 0. O valor em reais de cada um vem do backend; sem ele, só a quantidade.
  final int moedasPendentes;
  final DateTime? moedasProximaLiberacao;
  final int? moedasValorCentavos;

  /// Opcionais (API nova): quando o saldo vence e quanto do teto mensal de desconto já foi usado.
  final DateTime? moedasVenceEm;
  final int? tetoDescontoMesCentavos;
  final int? descontoUsadoMesCentavos;

  /// O backend diz se o desconto das moedas está disponível. Ausente = true.
  final bool moedasDescontoDisponivel;
  final MotivoDescontoIndisponivel? moedasDescontoMotivo;
  final DateTime? moedasDescontoVoltaEm;

  /// Saldo de moedas do Trato (calculado pelo backend). Nulo ou 0: não mostra o cartão.
  final int? moedas;

  final String nome;
  final String iniciais;

  /// "Nota 4,8 como cliente · 6 serviços" (a nota é calculada pelo backend).
  final String resumo;
  final List<GrupoPerfil> grupos;
  final String? fotoReferencia;
}
