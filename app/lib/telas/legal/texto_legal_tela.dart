import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../tema/tema.dart';
import '../comuns/estados.dart';

/// Textos legais do app. Os arquivos em `assets/legal/` são cópias de `docs/juridico/` (um teste
/// confere que continuam iguais). São RASCUNHOS: a tela avisa que o texto será revisado.
enum TextoLegal {
  termos('Termos de uso', 'assets/legal/termos-de-uso.md'),
  privacidade('Política de privacidade', 'assets/legal/politica-de-privacidade.md');

  const TextoLegal(this.titulo, this.arquivo);

  final String titulo;
  final String arquivo;

  Future<String> carregar() => rootBundle.loadString(arquivo);
}

/// Aviso fixo no alto de cada texto legal.
const avisoRascunhoLegal =
    'Documento oficial vigente no piloto em Belo Horizonte/MG. '
    'Dúvidas ou exercício de direitos LGPD: privacidade@trato.app.br.';

/// Índice com os dois textos (Termos de uso e Política de privacidade).
class TermosEPoliticaTela extends StatelessWidget {
  const TermosEPoliticaTela({super.key, required this.aoAbrir});

  final ValueChanged<TextoLegal> aoAbrir;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Termos e política',
      child: ListView(
        children: [
          for (final t in TextoLegal.values)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
              child: Material(
                color: CoresTrato.superficie,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
                  side: const BorderSide(color: CoresTrato.borda),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minVerticalPadding: EspacosTrato.x4,
                  title: Text(t.titulo, style: TipografiaTrato.tituloCartao),
                  trailing: const Icon(Icons.chevron_right, color: CoresTrato.petroleo),
                  onTap: () => aoAbrir(t),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mostra um texto legal (Markdown simples) com o aviso de rascunho.
class TextoLegalTela extends StatelessWidget {
  const TextoLegalTela({super.key, required this.titulo, required this.carregar});

  TextoLegalTela.de(TextoLegal texto, {Key? key})
      : this(key: key, titulo: texto.titulo, carregar: texto.carregar);

  final String titulo;
  final Future<String> Function() carregar;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: titulo,
      child: CarregadorTela<String>(
        carregar: carregar,
        construir: (context, texto, _) {
          final blocos = interpretarTextoLegal(texto);
          return ListView(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x8),
            children: [
              Container(
                padding: const EdgeInsets.all(EspacosTrato.x3),
                decoration: BoxDecoration(
                  color: CoresTrato.azulSuave,
                  borderRadius: BorderRadius.circular(EspacosTrato.raio),
                ),
                child: Text(
                  avisoRascunhoLegal,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
                ),
              ),
              const SizedBox(height: EspacosTrato.x4),
              for (final b in blocos) _Linha(bloco: b),
            ],
          );
        },
      ),
    );
  }
}

enum TipoBlocoLegal { secao, paragrafo, item }

class BlocoLegal {
  const BlocoLegal(this.tipo, this.texto);

  final TipoBlocoLegal tipo;
  final String texto;
}

/// Lê o Markdown dos textos legais: ignora o título (a tela já mostra), as notas internas
/// (linhas com `>`), separadores e tabelas viram linhas de texto.
List<BlocoLegal> interpretarTextoLegal(String markdown) {
  final saida = <BlocoLegal>[];
  for (final bruta in markdown.split('\n')) {
    final linha = bruta.trimRight();
    final t = linha.trim();
    if (t.isEmpty || t.startsWith('>') || t == '---' || t.startsWith('# ')) continue;
    if (t.startsWith('## ') || t.startsWith('### ')) {
      saida.add(BlocoLegal(TipoBlocoLegal.secao, t.replaceFirst(RegExp(r'^#+\s*'), '')));
    } else if (t.startsWith('|')) {
      if (RegExp(r'^\|[\s\-:|]+\|?$').hasMatch(t)) continue;
      final celulas = [
        for (final c in t.split('|'))
          if (c.trim().isNotEmpty) c.trim(),
      ];
      saida.add(BlocoLegal(TipoBlocoLegal.item, celulas.join(' · ')));
    } else if (t.startsWith('- ') || t.startsWith('* ')) {
      saida.add(BlocoLegal(TipoBlocoLegal.item, t.substring(2)));
    } else {
      saida.add(BlocoLegal(TipoBlocoLegal.paragrafo, t));
    }
  }
  return saida;
}

class _Linha extends StatelessWidget {
  const _Linha({required this.bloco});

  final BlocoLegal bloco;

  /// Troca `**negrito**` por trechos em negrito e tira as crases.
  static List<InlineSpan> _trechos(String texto, TextStyle base) {
    final limpo = texto.replaceAll('`', '');
    final partes = limpo.split('**');
    return [
      for (final (i, p) in partes.indexed)
        if (p.isNotEmpty)
          TextSpan(
            text: p,
            style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700) : base,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    switch (bloco.tipo) {
      case TipoBlocoLegal.secao:
        return Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x4, bottom: EspacosTrato.x2),
          child: Semantics(
            header: true,
            child: Text(bloco.texto, style: TipografiaTrato.titulo),
          ),
        );
      case TipoBlocoLegal.item:
        return Padding(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x2, left: EspacosTrato.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TipografiaTrato.corpo),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _trechos(bloco.texto, TipografiaTrato.corpo)),
                ),
              ),
            ],
          ),
        );
      case TipoBlocoLegal.paragrafo:
        return Padding(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
          child: Text.rich(TextSpan(children: _trechos(bloco.texto, TipografiaTrato.corpo))),
        );
    }
  }
}
