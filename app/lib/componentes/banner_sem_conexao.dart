import 'package:flutter/material.dart';

import '../dados/estado_conexao.dart';
import '../tema/tema.dart';

/// Faixa discreta no topo, "Sem conexão com a internet", enquanto [EstadoConexao.online] for
/// falso. Some sozinha na próxima chamada que der certo ou ao tocar em "Tentar novamente".
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
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, size: 18, color: c.sobrePetroleo),
                      const SizedBox(width: EspacosTrato.x2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sem conexão com a internet',
                              style: TipografiaTrato.corpoPequeno.copyWith(color: c.sobrePetroleo),
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: dadosSalvos ?? EstadoConexao.dadosSalvos,
                              builder: (context, salvos, _) => salvos
                                  ? Text(
                                      'Mostrando dados salvos — sem internet',
                                      key: const ValueKey('aviso-dados-salvos'),
                                      style: TipografiaTrato.legenda
                                          .copyWith(color: c.sobrePetroleo),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          sinal.value = true;
                          aoTentarNovamente?.call();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: c.sobrePetroleo,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x2),
                        ),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
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
      builder: (context, online, _) => Column(
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
  }
}
