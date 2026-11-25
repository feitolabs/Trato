import 'dart:async';

import 'package:flutter/material.dart';

import '../../dispositivo/toque_push.dart';
import '../../tema/tema.dart';
import '../fluxo/deep_link.dart';
import '../fluxo/deep_link_modelo.dart';
import '../fluxo/rotas.dart';

/// Aviso dentro do app quando chega um push com o app ABERTO (o Android não mostra bandeja nessa
/// hora). Mostra só o título e o corpo que vieram; tocar (ou "Abrir") abre a tela pelo mesmo
/// caminho do toque na bandeja; some sozinho em 5 s.
///
/// Vive num OVERLAY do navegador raiz, não num SnackBar: o SnackBar pertence ao Scaffold da tela
/// de baixo, e a casca do profissional se refaz sozinha (recarrega o início), o que derrubava o
/// aviso em 1 a 3 s. O overlay não depende de nenhum Scaffold.
abstract final class AvisoPush {
  static const duracao = Duration(seconds: 5);

  static OverlayEntry? _atual;
  static Timer? _relogio;

  static void mostrar(
    MensagemPush mensagem, {
    NavigatorState? Function()? navegador,
    Duration tempo = duracao,
  }) {
    final nav = (navegador ?? DeepLinks.navegador)();
    final overlay = nav?.overlay;
    if (overlay == null || !RotasTrato.temSessao) return;
    final titulo = mensagem.titulo?.trim() ?? '';
    final corpo = mensagem.corpo?.trim() ?? '';
    if (titulo.isEmpty && corpo.isEmpty) return; // mensagem só de dados: nada a mostrar
    final abre = resultadoDoPush(mensagem.dados).situacao != SituacaoLink.ignorado;
    esconder();
    late final OverlayEntry entrada;
    void abrir() {
      esconder();
      DeepLinks.receberPush(mensagem.dados);
    }

    entrada = OverlayEntry(
      builder: (context) => _Banner(
        titulo: titulo,
        corpo: corpo,
        aoAbrir: abre ? abrir : null,
        aoFechar: esconder,
      ),
    );
    _atual = entrada;
    overlay.insert(entrada);
    _relogio = Timer(tempo, () {
      if (identical(_atual, entrada)) esconder();
    });
  }

  static void esconder() {
    _relogio?.cancel();
    _relogio = null;
    final e = _atual;
    _atual = null;
    if (e != null && e.mounted) e.remove();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.titulo,
    required this.corpo,
    required this.aoAbrir,
    required this.aoFechar,
  });

  final String titulo;
  final String corpo;
  final VoidCallback? aoAbrir;
  final VoidCallback aoFechar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Positioned(
      left: EspacosTrato.x3,
      right: EspacosTrato.x3,
      top: MediaQuery.paddingOf(context).top + EspacosTrato.x2,
      child: Material(
        key: const Key('aviso-push'),
        color: c.petroleo,
        elevation: 6,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        child: InkWell(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          onTap: aoAbrir,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x3),
            child: Semantics(
              label: [titulo, corpo].where((t) => t.isNotEmpty).join('. '),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (titulo.isNotEmpty)
                          Text(titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TipografiaTrato.corpoForte.copyWith(color: c.sobrePetroleo)),
                        if (corpo.isNotEmpty)
                          Text(corpo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TipografiaTrato.corpoPequeno.copyWith(color: c.sobrePetroleo)),
                      ],
                    ),
                  ),
                  if (aoAbrir != null)
                    TextButton(
                      key: const Key('aviso-push-abrir'),
                      onPressed: aoAbrir,
                      child: Text('Abrir',
                          style: TipografiaTrato.corpoForte.copyWith(color: c.sobrePetroleo)),
                    ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: aoFechar,
                    icon: Icon(Icons.close, color: c.sobrePetroleo, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
