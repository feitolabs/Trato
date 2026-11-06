import 'package:flutter/material.dart';

import '../fluxo/rotas.dart';
import 'avatar_iniciais.dart';

/// Avatar de OUTRA pessoa (ou da própria): busca a foto de perfil no backend pelo id e, se não
/// tiver, mostra as iniciais. A foto vem por URL curta; o repositório guarda em cache.
class AvatarDeUsuario extends StatelessWidget {
  const AvatarDeUsuario({super.key, required this.iniciais, this.usuarioId, this.tamanho = 56});

  final String iniciais;
  final String? usuarioId;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final id = usuarioId;
    if (id == null || id.isEmpty) return AvatarIniciais(iniciais: iniciais, tamanho: tamanho);
    return FutureBuilder<String?>(
      future: RotasTrato.repos.perfil.fotoDe(id),
      builder: (context, foto) => AvatarIniciais(
        iniciais: iniciais,
        tamanho: tamanho,
        fotoReferencia: foto.data,
      ),
    );
  }
}
