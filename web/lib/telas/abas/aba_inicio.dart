import 'package:flutter/material.dart';

import '../../dados/perfil.dart';
import '../../tema/tema.dart';

/// Início: saudação com o nome real da conta logada (vindo de `GET /v1/me`).
class AbaInicio extends StatelessWidget {
  const AbaInicio({super.key, required this.perfil});

  final PerfilTrato perfil;

  @override
  Widget build(BuildContext context) {
    final partes = (perfil.nome ?? '').trim().split(' ');
    final primeiroNome = partes.isEmpty ? '' : partes.first;
    return ConteudoResponsivo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: EspacosTrato.x4),
          Text(
            primeiroNome.isEmpty ? 'Olá!' : 'Olá, $primeiroNome!',
            style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            perfil.ehProfissional ? 'Conta de profissional' : 'Conta de cliente',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x5),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined, color: CoresTrato.azulTexto),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(
                    child: Text(
                      'Status da conta: ${perfil.status}',
                      style: TipografiaTrato.corpo.copyWith(color: CoresTrato.petroleo),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
