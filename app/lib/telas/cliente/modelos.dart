import 'package:flutter/widgets.dart';

/// Modelos simples das telas do cliente. Provisórios: o formato real vem do backend.

String formatarNota(double nota) => nota.toStringAsFixed(1).replaceAll('.', ',');

String formatarDistancia(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

class Avaliacao {
  const Avaliacao({
    required this.cliente,
    required this.servico,
    required this.nota,
    required this.comentario,
    required this.detalhes,
    this.id,
    this.resposta,
    this.etiquetas = const [],
    this.criterios = const {},
  });

  /// Chaves de critérios na ordem exibida ao cliente e esperada pelo backend.
  static const chavesCriterios = <String>[
    'pontualidade',
    'qualidade',
    'limpeza',
    'comunicacao',
    'preco_justo',
  ];

  static const rotulosCriterios = <String, String>{
    'pontualidade': 'Pontualidade',
    'qualidade': 'Qualidade',
    'limpeza': 'Limpeza',
    'comunicacao': 'Comunicação',
    'preco_justo': 'Preço justo',
  };

  /// Lê `criterios` da API com fallback seguro quando ausente, nulo ou inválido.
  static Map<String, int> lerCriterios(Object? bruto) {
    if (bruto is! Map) return const {};
    final saida = <String, int>{};
    for (final chave in chavesCriterios) {
      final valor = bruto[chave];
      if (valor is num) {
        final nota = valor.round();
        if (nota >= 1 && nota <= 5) saida[chave] = nota;
      }
    }
    for (final entry in bruto.entries) {
      final k = '${entry.key}'.trim();
      if (k.isEmpty || saida.containsKey(k)) continue;
      final v = entry.value;
      if (v is num) {
        final nota = v.round();
        if (nota >= 1 && nota <= 5) saida[k] = nota;
      }
    }
    return Map.unmodifiable(saida);
  }

  /// Formata os critérios na ordem padrão: "Pontualidade 5 · Qualidade 5 · ...".
  static String formatarCriterios(Map<String, int> criterios) {
    if (criterios.isEmpty) return '';
    final partes = <String>[];
    for (final chave in chavesCriterios) {
      final nota = criterios[chave];
      if (nota != null) {
        partes.add('${rotulosCriterios[chave] ?? chave} $nota');
      }
    }
    for (final entry in criterios.entries) {
      if (rotulosCriterios.containsKey(entry.key)) continue;
      partes.add('${entry.key} ${entry.value}');
    }
    return partes.join(' · ');
  }

  /// Pares (rótulo, nota) prontos para exibição em badges ordenados.
  List<({String rotulo, int nota})> get itensCriterios {
    if (criterios.isEmpty) return const [];
    final itens = <({String rotulo, int nota})>[];
    for (final chave in chavesCriterios) {
      final n = criterios[chave];
      if (n != null) {
        itens.add((rotulo: rotulosCriterios[chave] ?? chave, nota: n));
      }
    }
    for (final entry in criterios.entries) {
      if (rotulosCriterios.containsKey(entry.key)) continue;
      itens.add((rotulo: entry.key, nota: entry.value));
    }
    return itens;
  }

  /// Elogios em tags dessa avaliação (`etiquetas`); vazio em servidor antigo.
  final List<String> etiquetas;

  /// Notas individuais por critério (`pontualidade`, `qualidade`, etc.).
  final Map<String, int> criterios;

  final String cliente;
  final String servico;
  final double nota;
  final String comentario;

  /// Ex.: "Pontualidade 5 · Qualidade 5 · Limpeza 5".
  final String detalhes;
  final String? id;
  final String? resposta;
}

/// Um elogio e quantas vezes foi recebido (`{"etiqueta": "Pontual", "total": 12}`).
class EtiquetaTop {
  const EtiquetaTop(this.etiqueta, this.total);

  final String etiqueta;
  final int total;

  /// Lê `etiquetas_top` sem quebrar: campo ausente, nulo ou fora do formato = lista vazia.
  static List<EtiquetaTop> listaDeJson(Object? bruto) {
    if (bruto is! List) return const [];
    final saida = <EtiquetaTop>[];
    for (final item in bruto) {
      if (item is! Map) continue;
      final nome = item['etiqueta'];
      final total = item['total'];
      if (nome is String && nome.trim().isNotEmpty && total is num && total > 0) {
        saida.add(EtiquetaTop(nome.trim(), total.toInt()));
      }
    }
    return saida;
  }
}

/// Dados que só aparecem na tela do perfil do profissional.
class DetalhePerfil {
  const DetalhePerfil({
    required this.noTratoDesde,
    required this.totalAvaliacoes,
    required this.taxaConclusao,
    required this.verificacoes,
    required this.avaliacoes,
    this.fotosTrabalhos = 3,
    this.bio,
    this.servicos = const [],
    this.trabalhos = const [],
    this.fotosUrls = const [],
    this.temHistorico = true,
    this.etiquetasTop = const [],
    this.respondeEmFaixa,
  });

  /// `responde_em_faixa` da API ("no mesmo dia"); só a presença importa: o texto da tela é fixo.
  /// Nulo/vazio = não mostra nada.
  final String? respondeEmFaixa;

  /// Lê `responde_em_faixa` sem quebrar: ausente, nulo, vazio ou de outro tipo = nulo.
  static String? lerFaixaResposta(Object? bruto) {
    if (bruto is! String) return null;
    final t = bruto.trim();
    return t.isEmpty ? null : t;
  }

  /// Elogios mais recebidos (`etiquetas_top`, já contados pelo backend); vazio = não mostra.
  final List<EtiquetaTop> etiquetasTop;

  /// Falso quando o profissional ainda não encerrou nenhum serviço (a taxa aparece como "—").
  final bool temHistorico;

  /// Texto de apresentação escrito pelo profissional (já filtrado pelo backend).
  final String? bio;

  /// Serviços que o profissional oferece.
  final List<String> servicos;

  /// Legendas dos trabalhos do portfólio (as fotos vêm da URL assinada quando houver).
  final List<String> trabalhos;

  /// URL assinada da foto de cada trabalho (mesma ordem de [trabalhos]); nulo = sem foto.
  final List<String?> fotosUrls;

  final int noTratoDesde;
  final int totalAvaliacoes;
  final int taxaConclusao;
  final List<String> verificacoes;
  final List<Avaliacao> avaliacoes;
  final int fotosTrabalhos;
}

class Profissional {
  const Profissional({
    required this.nome,
    required this.iniciais,
    required this.verificacao,
    required this.especialidade,
    required this.servicosConcluidos,
    required this.nota,
    required this.distanciaKm,
    this.respostaCurta,
    this.atendeHoje = false,
    this.detalhe,
    this.id,
    this.regiao,
    this.categoriaId,
    this.precoAPartirCentavos,
  });

  /// Id do profissional na API (nulo nos dados do protótipo).
  final String? id;

  /// Bairro ou região de atendimento, ex.: "Savassi e Funcionários".
  final String? regiao;
  final String? categoriaId;

  /// Referência de preço mostrada na lista; o valor do serviço é o do orçamento.
  final int? precoAPartirCentavos;

  final String nome;
  final String iniciais;

  /// "Verificado" ou "Verificado Plus".
  final String verificacao;
  final String especialidade;
  final int servicosConcluidos;
  final double nota;
  final double distanciaKm;

  /// Ex.: "resp. em 1 h". Ausente quando o protótipo não mostra.
  final String? respostaCurta;
  final bool atendeHoje;
  final DetalhePerfil? detalhe;

  String get primeiroNome => nome.split(' ').first;
}

class CategoriaServico {
  const CategoriaServico(
    this.nome,
    this.icone, {
    this.id = '',
    this.servicos = const [],
    this.descricao = '',
    this.aceitaRemoto = false,
  });

  /// O admin liberou o atendimento remoto nesta categoria (o cliente escolhe presencial ou
  /// remoto). Padrão: só presencial, com endereço obrigatório.
  final bool aceitaRemoto;

  /// Id da categoria no catálogo (vazio nos dados do protótipo).
  final String id;
  final String nome;
  final IconData icone;

  /// Serviços típicos da categoria, usados no Novo pedido.
  final List<String> servicos;
  final String descricao;
}

class PedidoEmAndamento {
  const PedidoEmAndamento({
    required this.titulo,
    required this.situacao,
    required this.aviso,
    this.pedidoId,
  });

  /// Id do pedido na API (nulo nos dados do protótipo).
  final String? pedidoId;

  final String titulo;
  final String situacao;
  final String aviso;
}

class ServicoRecente {
  const ServicoRecente({
    required this.titulo,
    required this.profissional,
    required this.data,
    this.garantia,
    this.pedidoId,
    this.statusTexto = 'Finalizado',
  });

  /// Situação do serviço mostrada no chip ("Finalizado", "Em execução"...).
  final String statusTexto;

  /// Id do pedido na API (nulo nos dados do protótipo).
  final String? pedidoId;

  final String titulo;
  final String profissional;
  final String data;

  /// Texto pronto da garantia; ausente quando o backend não informa.
  final String? garantia;
}

/// Tudo o que o Início do cliente mostra, já carregado do catálogo e dos pedidos.
class DadosInicio {
  const DadosInicio({
    required this.nome,
    required this.categorias,
    this.emAndamento,
    this.recentes = const [],
    this.notificacoesNaoLidas = 0,
  });

  /// Primeiro nome do cliente.
  final String nome;

  /// Categorias ativas (a tela mostra as primeiras e o atalho "Ver todas").
  final List<CategoriaServico> categorias;
  final PedidoEmAndamento? emAndamento;
  final List<ServicoRecente> recentes;
  final int notificacoesNaoLidas;
}
