/// Checklists pré-preenchidos por categoria no Novo pedido (F43).
/// Só exibição e apoio ao preenchimento; nenhuma regra de negócio ou rota nova.
library;

/// Normaliza nome/slug de categoria (minúsculas, sem acentos, espaços simples).
String normalizarCategoriaChecklist(String texto) {
  const mapa = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  final sb = StringBuffer();
  for (final code in texto.toLowerCase().runes) {
    final ch = String.fromCharCode(code);
    sb.write(mapa[ch] ?? ch);
  }
  return sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

class _EntradaChecklist {
  const _EntradaChecklist(this.chaves, this.itens);

  final List<String> chaves;
  final List<String> itens;
}

const _checklists = <_EntradaChecklist>[
  _EntradaChecklist(
    ['eletricista', 'eletrica'],
    [
      'Disjuntor desarmando',
      'Tomada ou interruptor com defeito',
      'Instalar ou trocar chuveiro',
      'Trocar luminária ou ventilador',
    ],
  ),
  _EntradaChecklist(
    ['encanador', 'hidraulica'],
    [
      'Vazamento em cano ou registro',
      'Torneira ou pia pingando',
      'Ralo ou vaso entupido',
      'Caixa acoplada ou descarga com defeito',
    ],
  ),
  _EntradaChecklist(
    ['diarista', 'limpeza', 'faxina'],
    [
      'Limpeza geral da casa',
      'Cozinha e banheiros',
      'Vidros e janelas',
      'Limpeza pós-obra',
    ],
  ),
  _EntradaChecklist(
    ['pintor', 'pintura'],
    [
      'Pintura interna de paredes',
      'Corrigir infiltrações ou rachaduras',
      'Pintar teto ou portas',
      'Retoque de pintura',
    ],
  ),
  _EntradaChecklist(
    ['ar condicionado', 'climatizacao'],
    [
      'Instalação de aparelho novo',
      'Limpeza e higienização',
      'Aparelho não está gelando',
      'Recarga de gás ou vazamento',
    ],
  ),
  _EntradaChecklist(
    ['montador de moveis', 'montador', 'moveis'],
    [
      'Montar móvel novo na caixa',
      'Desmontar para mudança',
      'Ajustar portas ou gavetas',
      'Fixar armário ou prateleira na parede',
    ],
  ),
  _EntradaChecklist(
    ['marido de aluguel', 'pequenos reparos', 'reparos'],
    [
      'Instalar suporte de TV ou cortina',
      'Fixar prateleiras ou quadros',
      'Trocar dobradiça ou fechadura simples',
      'Pequenos consertos em casa',
    ],
  ),
  _EntradaChecklist(
    ['chaveiro'],
    [
      'Abertura de porta trancada',
      'Troca de fechadura ou miolo',
      'Cópia de chave',
      'Chave quebrada na fechadura',
    ],
  ),
  _EntradaChecklist(
    ['dedetizacao', 'dedetizador', 'controle de pragas'],
    [
      'Baratas e formigas',
      'Cupins em móveis ou portas',
      'Escorpiões ou aranhas',
      'Imóvel residencial (casa ou apartamento)',
    ],
  ),
  _EntradaChecklist(
    ['jardinagem', 'jardineiro'],
    [
      'Corte de grama e limpeza',
      'Poda de árvores ou arbustos',
      'Retirada de mato e folhas',
      'Plantio ou manutenção de vasos',
    ],
  ),
];

/// Devolve os itens sugeridos para [categoria], removendo os que já existem em [excluir].
/// Se a categoria não estiver no mapa, devolve lista vazia.
List<String> itensChecklistCategoria(
  String categoria, {
  Iterable<String> excluir = const [],
}) {
  final norm = normalizarCategoriaChecklist(categoria);
  if (norm.isEmpty) return const [];
  final excluidos = {
    for (final e in excluir) normalizarCategoriaChecklist(e),
  };
  for (final entrada in _checklists) {
    final casou = entrada.chaves.any((c) => norm == c || norm.contains(c));
    if (casou) {
      return [
        for (final item in entrada.itens)
          if (!excluidos.contains(normalizarCategoriaChecklist(item))) item,
      ];
    }
  }
  return const [];
}

/// Combina o texto livre digitado pelo cliente com os itens marcados no checklist,
/// sem duplicar itens nem alterar o texto livre.
String montarDescricaoComChecklist({
  required String textoLivre,
  required Iterable<String> itensMarcados,
}) {
  final livre = textoLivre.trim();
  final unicos = <String>[];
  final vistos = <String>{};
  for (final item in itensMarcados) {
    final limpo = item.trim();
    if (limpo.isEmpty) continue;
    final chave = normalizarCategoriaChecklist(limpo);
    if (vistos.add(chave)) unicos.add(limpo);
  }
  if (unicos.isEmpty) return livre;
  final bloco = 'Itens selecionados: ${unicos.join(', ')}.';
  if (livre.isEmpty) return bloco;
  return '$livre\n\n$bloco';
}
