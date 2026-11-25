import 'package:flutter/material.dart';

import '../../dispositivo/toque_push.dart';
import '../fluxo/deep_link.dart';
import '../fluxo/deep_link_modelo.dart';
import '../fluxo/rotas.dart';

/// O mensageiro raiz do app: onde o aviso de push em primeiro plano aparece, por cima de
/// qualquer tela. O `main.dart` liga ao MaterialApp.
final mensageiroTrato = GlobalKey<ScaffoldMessengerState>();

/// Aviso dentro do app quando chega um push com o app ABERTO (o Android não mostra bandeja nessa
/// hora). Mostra só o título e o corpo que vieram; tocar abre a tela pelo mesmo caminho do toque
/// na bandeja; some sozinho em ~5 s.
abstract final class AvisoPush {
  static const duracao = Duration(seconds: 5);

  static void mostrar(
    MensagemPush mensagem, {
    GlobalKey<ScaffoldMessengerState>? mensageiro,
  }) {
    final estado = (mensageiro ?? mensageiroTrato).currentState;
    if (estado == null || !RotasTrato.temSessao) return;
    final titulo = mensagem.titulo?.trim() ?? '';
    final corpo = mensagem.corpo?.trim() ?? '';
    if (titulo.isEmpty && corpo.isEmpty) return; // mensagem só de dados: nada a mostrar
    final abre = resultadoDoPush(mensagem.dados).situacao != SituacaoLink.ignorado;
    void abrir() {
      estado.hideCurrentSnackBar();
      DeepLinks.receberPush(mensagem.dados);
    }

    estado
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('aviso-push'),
          duration: duracao,
          persist: false, // com ação, o SnackBar não sumiria sozinho por padrão
          behavior: SnackBarBehavior.floating,
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: abre ? abrir : null,
            child: Semantics(
              label: [titulo, corpo].where((t) => t.isNotEmpty).join('. '),
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (titulo.isNotEmpty)
                    Text(titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (corpo.isNotEmpty) Text(corpo, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          action: abre ? SnackBarAction(label: 'Abrir', onPressed: abrir) : null,
        ),
      );
  }
}
