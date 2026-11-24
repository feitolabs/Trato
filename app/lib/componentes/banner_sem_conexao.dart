import 'package:flutter/material.dart';

import '../dados/estado_conexao.dart';
import '../tema/tema.dart';

/// Faixa discreta no topo, "Sem conexão com a internet", enquanto [EstadoConexao.online] for
/// falso. Some sozinha na próxima chamada que der certo ou ao tocar em "Tentar novamente".
class BannerSemConexao extends StatelessWidget {
  const BannerSemConexao({super.key, this.estado, this.aoTentarNovamente});

  /// Para teste; o padrão é o sinal global [EstadoConexao.online].
  final ValueNotifier<bool>? estado;

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
                        child: Text(
                          'Sem conexão com a internet',
                          style: TipografiaTrato.corpoPequeno.copyWith(color: c.sobrePetroleo),
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
