import 'package:flutter/material.dart';

// Modelos do Novo pedido. Provisórios: as perguntas guiadas de cada categoria virão do backend.

/// Faixa de preço em centavos inteiros ("R$ 200 a R$ 500"). Só exibe: não há regra no app.
class FaixaPreco {
  const FaixaPreco({required this.minimoCentavos, required this.maximoCentavos});

  final int minimoCentavos;
  final int maximoCentavos;
}

/// Cidade atendida, escolhida no Novo pedido (`GET /v1/catalogo/cidades`).
class CidadeOpcao {
  const CidadeOpcao({required this.id, required this.nome, this.uf = ''});

  final String id;
  final String nome;
  final String uf;

  String get rotulo => uf.isEmpty ? nome : '$nome · $uf';
}

/// Perguntas e opções do formulário da categoria escolhida.
class FormularioPedido {
  const FormularioPedido({
    required this.categoria,
    required this.servicos,
    required this.servicosIniciais,
    required this.perguntaQuantidade,
    required this.dicaQuantidade,
    required this.quantidadeInicial,
    required this.perguntaVoltagem,
    required this.voltagens,
    required this.voltagemInicial,
    required this.descricaoInicial,
    required this.fotos,
    required this.prazos,
    required this.faixas,
    required this.endereco,
    required this.avisoEndereco,
    required this.avisoPrazo,
    this.categoriaId,
    this.icone = Icons.bolt,
    this.cidades = const [],
  });

  /// Cidades para escolher. Vazio = formulário de exemplo, sem seleção de cidade.
  final List<CidadeOpcao> cidades;

  /// Ex.: "Elétrica · Tomadas e chuveiro".
  final String categoria;
  final List<String> servicos;
  final Set<String> servicosIniciais;
  final String perguntaQuantidade;
  final String dicaQuantidade;
  final int quantidadeInicial;
  final String perguntaVoltagem;
  final List<String> voltagens;
  final String voltagemInicial;
  final String descricaoInicial;

  /// Rótulos das fotos já anexadas ("[Foto 1]").
  final List<String> fotos;
  final List<String> prazos;
  final List<FaixaPreco> faixas;
  final String endereco;
  final String avisoEndereco;
  final String avisoPrazo;

  /// Id da categoria no catálogo; nulo no formulário de exemplo.
  final String? categoriaId;

  /// Ícone da categoria, mostrado ao lado do nome.
  final IconData icone;

  /// Cópia deste formulário com a lista de cidades para escolher.
  FormularioPedido comCidades(List<CidadeOpcao> novas) => FormularioPedido(
        categoria: categoria,
        servicos: servicos,
        servicosIniciais: servicosIniciais,
        perguntaQuantidade: perguntaQuantidade,
        dicaQuantidade: dicaQuantidade,
        quantidadeInicial: quantidadeInicial,
        perguntaVoltagem: perguntaVoltagem,
        voltagens: voltagens,
        voltagemInicial: voltagemInicial,
        descricaoInicial: descricaoInicial,
        fotos: fotos,
        prazos: prazos,
        faixas: faixas,
        endereco: endereco,
        avisoEndereco: avisoEndereco,
        avisoPrazo: avisoPrazo,
        categoriaId: categoriaId,
        icone: icone,
        cidades: novas,
      );
}

/// O que o cliente preencheu, devolvido em `aoEnviar`.
class RascunhoPedido {
  const RascunhoPedido({
    required this.servicos,
    required this.quantidade,
    required this.voltagem,
    required this.descricao,
    required this.prazo,
    required this.faixa,
    this.fotos = const [],
    this.categoriaId,
    this.cidadeId,
    this.bairro,
    this.prazoDesejado,
  });

  /// Data que o cliente informou em "Sem pressa" / "Com pressa".
  final DateTime? prazoDesejado;

  /// Cidade escolhida (id do catálogo); nula no formulário de exemplo.
  final String? cidadeId;
  final String? bairro;

  /// Categoria escolhida (id do catálogo); nula quando vem do formulário de exemplo.
  final String? categoriaId;

  final List<String> servicos;
  final int quantidade;
  final String voltagem;
  final String descricao;
  final String prazo;
  final FaixaPreco faixa;

  /// Referências (`arquivoId`) das fotos já enviadas.
  final List<String> fotos;
}
