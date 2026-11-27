import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/textos_dos_termos.dart';
import 'guardar_texto.dart';
import 'registro_do_aceite.dart';

/// Textos legais do app. Os arquivos em `assets/legal/` são cópias de `docs/juridico/` (um teste
/// confere que continuam iguais). São RASCUNHOS: a tela avisa que o texto será revisado.
enum TextoLegal {
  termos('Termos de uso', 'assets/legal/termos-de-uso.md', versaoDosTermos),
  privacidade(
    'Política de privacidade',
    'assets/legal/politica-de-privacidade.md',
    versaoDaPrivacidade,
  );

  const TextoLegal(this.titulo, this.arquivo, this.versao);

  final String titulo;
  final String arquivo;
  final String versao;

  /// Nome do arquivo da cópia que a pessoa guarda.
  String get nomeDaCopia => 'trato-${arquivo.split('/').last.replaceAll('.md', '')}-v$versao.txt';

  Future<String> carregar() => rootBundle.loadString(arquivo);
}

/// Aviso fixo no alto de cada texto legal.
const avisoRascunhoLegal = 'Documento oficial em vigor durante o piloto. '
    'Dúvidas ou exercício de direitos LGPD: privacidade@tratofeitolabs.com.br.';

/// Índice com os dois textos (Termos de uso e Política de privacidade).
class TermosEPoliticaTela extends StatelessWidget {
  const TermosEPoliticaTela({super.key, required this.aoAbrir, this.consultaDoAceite});

  final ValueChanged<TextoLegal> aoAbrir;

  /// Termos 1.4: nulo sem conta aberta (não há aceite para consultar).
  final ConsultaDoAceite? consultaDoAceite;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Termos e políticas',
      child: ListView(
        children: [
          for (final t in TextoLegal.values)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
              child: Material(
                color: context.cores.superficie,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
                  side: BorderSide(color: context.cores.borda),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minVerticalPadding: EspacosTrato.x4,
                  title: Text(t.titulo, style: TipografiaTrato.tituloCartao),
                  trailing: Icon(Icons.chevron_right, color: context.cores.petroleo),
                  onTap: () => aoAbrir(t),
                ),
              ),
            ),
          if (consultaDoAceite != null) CartaoRegistroDoAceite(consulta: consultaDoAceite!),
        ],
      ),
    );
  }
}

/// Mostra um texto legal (Markdown simples) com o aviso de rascunho.
class TextoLegalTela extends StatelessWidget {
  const TextoLegalTela({
    super.key,
    required this.titulo,
    required this.carregar,
    this.nomeDaCopia = 'trato-texto-legal.txt',
    this.guardar = guardarTextoNoAparelho,
  });

  TextoLegalTela.de(TextoLegal texto, {Key? key, GuardarTextoLegal guardar = guardarTextoNoAparelho})
      : this(
          key: key,
          titulo: texto.titulo,
          carregar: texto.carregar,
          nomeDaCopia: texto.nomeDaCopia,
          guardar: guardar,
        );

  final String titulo;
  final Future<String> Function() carregar;
  final String nomeDaCopia;
  final GuardarTextoLegal guardar;

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
                  color: context.cores.azulSuave,
                  borderRadius: BorderRadius.circular(EspacosTrato.raio),
                ),
                child: Text(
                  avisoRascunhoLegal,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.azulTexto),
                ),
              ),
              const SizedBox(height: EspacosTrato.x3),
              BotaoGuardarTexto(
                nomeArquivo: nomeDaCopia,
                conteudo: textoParaGuardar(titulo, blocos),
                guardar: guardar,
              ),
              const SizedBox(height: EspacosTrato.x4),
              for (final b in blocos) LinhaDoTextoLegal(bloco: b),
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

/// O mesmo texto da tela em texto puro, para guardar e imprimir.
String textoParaGuardar(String titulo, List<BlocoLegal> blocos) {
  final saida = StringBuffer('$titulo\n');
  for (final b in blocos) {
    final limpo = b.texto.replaceAll('**', '').replaceAll('`', '');
    saida.write(switch (b.tipo) {
      TipoBlocoLegal.secao => '\n$limpo\n',
      TipoBlocoLegal.item => '- $limpo\n',
      TipoBlocoLegal.paragrafo => '$limpo\n',
    });
  }
  return saida.toString();
}

/// Um bloco de texto legal na tela.
class LinhaDoTextoLegal extends StatelessWidget {
  const LinhaDoTextoLegal({super.key, required this.bloco});

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
