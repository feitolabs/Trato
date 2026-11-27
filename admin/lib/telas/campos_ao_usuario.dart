import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../tema/tema.dart';

/// "9.2, 20.3" ou uma por linha -> lista de cláusulas.
List<String> lerClausulas(String texto) =>
    [for (final c in texto.split(RegExp(r'[,;\n]'))) if (c.trim().isNotEmpty) c.trim()];

/// O que vai para o aviso escrito ao usuário (Termos 20.4): motivo e cláusulas.
class CamposAoUsuario {
  String textoMotivo = '';
  String textoClausulas = '';

  static const maximoMotivo = 2000;
  static const maximoClausulas = 20;

  String get motivo => textoMotivo.trim();
  List<String> get clausulas => lerClausulas(textoClausulas);

  bool get valido =>
      motivo.length >= kMotivoMinimo && clausulas.isNotEmpty && clausulas.length <= maximoClausulas;
}

class CamposAoUsuarioForm extends StatelessWidget {
  const CamposAoUsuarioForm(this.campos, {super.key, required this.aoMudar});

  final CamposAoUsuario campos;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BannerInfo('O usuário vai ler este motivo e as cláusulas. Não cite quem denunciou.', tom: Tom.alerta),
        const SizedBox(height: EspacosTrato.x3),
        TextFormField(
          initialValue: campos.textoMotivo,
          minLines: 2,
          maxLines: 5,
          maxLength: CamposAoUsuario.maximoMotivo,
          onChanged: (v) {
            campos.textoMotivo = v;
            aoMudar();
          },
          decoration: const InputDecoration(
            labelText: 'Motivo que o usuário vai ler',
            helperText: 'Pelo menos $kMotivoMinimo caracteres',
          ),
        ),
        const SizedBox(height: EspacosTrato.x2),
        TextFormField(
          initialValue: campos.textoClausulas,
          onChanged: (v) {
            campos.textoClausulas = v;
            aoMudar();
          },
          decoration: const InputDecoration(
            labelText: 'Cláusulas dos Termos',
            helperText: 'Separe por vírgula. Exemplo: 9.2, 20.3',
          ),
        ),
      ],
    );
  }
}
