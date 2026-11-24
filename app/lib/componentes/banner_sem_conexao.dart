import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/estado_conexao.dart';
import '../tema/tema.dart';

/// Faixa discreta no topo, "Sem internet" (e "Mostrando dados salvos" quando for o caso), enquanto
/// [EstadoConexao.online] for falso. Some sozinha na próxima chamada que der certo ou ao tocar em "Tentar novamente".
class BannerSemConexao extends StatelessWidget {
  const BannerSemConexao({super.key, this.estado, this.dadosSalvos, this.aoTentarNovamente});

  /// Para teste; o padrão é o sinal global [EstadoConexao.online].
  final ValueNotifier<bool>? estado;

  /// Para teste; o padrão é [EstadoConexao.dadosSalvos] (tela mostrando a última leitura guardada).
  final ValueNotifier<bool>? dadosSalvos;

  /// Chamado ao tocar em "Tentar novamente" (ex.: recarregar a tela). O banner some na hora; se
  /// a rede continuar fora, a próxima chamada o traz de volta.
  final VoidCallback? aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    final sinal = estado ?? EstadoConexao.online;
    return ValueListenableBuilder<bool>(
      valueListenable: sinal,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();
        final c = context.cores;
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EspacosTrato.x4,
              EspacosTrato.x1,
              EspacosTrato.x4,
              0,
            ),
            child: Semantics(
              liveRegion: true,
              child: Material(
                key: const ValueKey('banner-sem-conexao'),
                color: c.petroleo,
                borderRadius: BorderRadius.circular(EspacosTrato.raio),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EspacosTrato.x3,
                    vertical: EspacosTrato.x1,
                  ),
                  child: _Conteudo(
                    dadosSalvos: dadosSalvos ?? EstadoConexao.dadosSalvos,
                    aoTentar: () {
                      sinal.value = true;
                      aoTentarNovamente?.call();
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ícone, "Sem internet" + "Mostrando dados salvos" e "Tentar novamente". O botão fica na mesma
/// linha quando os textos cabem inteiros; senão (fonte ampliada, tela estreita) desce para baixo,
/// alinhado à direita. Nenhum texto quebra no meio.
class _Conteudo extends StatelessWidget {
  const _Conteudo({required this.dadosSalvos, required this.aoTentar});

  final ValueNotifier<bool> dadosSalvos;
  final VoidCallback aoTentar;

  static const _principal = 'Sem internet';
  static const _secundario = 'Mostrando dados salvos';
  static const _botao = 'Tentar novamente';

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final forte = TipografiaTrato.corpoPequeno.copyWith(
      color: c.sobrePetroleo,
      fontWeight: FontWeight.w700,
    );
    final fraco = TipografiaTrato.legenda.copyWith(color: c.sobrePetroleo);
    final acao = TipografiaTrato.corpoPequeno.copyWith(
      color: c.sobrePetroleo,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: c.sobrePetroleo,
    );
    final escala = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    double largura(String texto, TextStyle estilo) {
      final p = TextPainter(
        text: TextSpan(text: texto, style: base.merge(estilo)),
        textDirection: TextDirection.ltr,
        textScaler: escala,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    return ValueListenableBuilder<bool>(
      valueListenable: dadosSalvos,
      builder: (context, salvos, _) => LayoutBuilder(
        builder: (context, limites) {
          final textos = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_principal, style: forte),
              if (salvos)
                Text(_secundario, key: const ValueKey('aviso-dados-salvos'), style: fraco),
            ],
          );
          final botao = TextButton(
            onPressed: aoTentar,
            style: TextButton.styleFrom(
              foregroundColor: c.sobrePetroleo,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x1),
            ),
            child: Text(_botao, style: acao),
          );
          final maiorTexto = [
            largura(_principal, forte),
            if (salvos) largura(_secundario, fraco),
          ].reduce((a, b) => a > b ? a : b);
          // ícone (18) + 2 espaços (8) + folga do botão (8)
          final cabe = 18 + EspacosTrato.x2 * 2 + 8 + maiorTexto + largura(_botao, acao) <=
              limites.maxWidth;
          final linha = Row(
            children: [
              Icon(Icons.wifi_off, size: 18, color: c.sobrePetroleo),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(child: textos),
              if (cabe) ...[const SizedBox(width: EspacosTrato.x2), botao],
            ],
          );
          if (cabe) return linha;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(padding: const EdgeInsets.only(top: EspacosTrato.x1), child: linha),
              botao,
            ],
          );
        },
      ),
    );
  }
}

/// Envolve o app: o banner de "sem conexão" ocupa uma faixa no topo (a AppBar e as ações descem,
/// nada fica coberto) e some quando a internet volta. A árvore do app não muda entre os estados,
/// então as telas não perdem o que já digitaram.
class MoldeConexao extends StatelessWidget {
  const MoldeConexao({
    super.key,
    required this.child,
    this.estado,
    this.dadosSalvos,
    this.aoTentarNovamente,
  });

  final Widget child;
  final ValueNotifier<bool>? estado;
  final ValueNotifier<bool>? dadosSalvos;
  final VoidCallback? aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: estado ?? EstadoConexao.online,
      // Fundo do app atrás de tudo: sem ele a área da barra de status fica preta com o banner.
      builder: (context, online, _) {
        final claro = Theme.of(context).brightness == Brightness.light;
        final arvore = ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              BannerSemConexao(
                estado: estado,
                dadosSalvos: dadosSalvos,
                aoTentarNovamente: aoTentarNovamente,
              ),
              // A faixa já cuida do recuo do topo; as telas de baixo não repetem.
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: !online,
                  child: child,
                ),
              ),
            ],
          ),
        );
        // Onde não há AppBar (a área do banner), os ícones da barra de status seguem o tema; as
        // barras das próprias telas continuam mandando nelas. Sempre presente: não recria as telas.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: claro ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
          child: arvore,
        );
      },
    );
  }
}
