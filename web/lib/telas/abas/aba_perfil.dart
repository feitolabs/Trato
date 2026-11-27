import 'package:flutter/material.dart';

import '../../auth/sessao_auth.dart';
import '../../dados/perfil.dart';
import '../../tema/tema.dart';

/// Perfil: dados reais de `GET /v1/me` e botão para sair (Supabase signOut de verdade).
class AbaPerfil extends StatelessWidget {
  const AbaPerfil({super.key, required this.perfil, required this.servicoAuth});

  final PerfilTrato perfil;
  final ServicoAuthWeb servicoAuth;

  @override
  Widget build(BuildContext context) {
    return ConteudoResponsivo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: EspacosTrato.x4),
          Text('Perfil', style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo)),
          const SizedBox(height: EspacosTrato.x4),
          CircleAvatar(
            radius: 32,
            backgroundColor: CoresTrato.azulSuave,
            child: Text(
              (perfil.nome?.isNotEmpty ?? false) ? perfil.nome!.substring(0, 1) : '?',
              style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.azulTexto),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            perfil.nome?.isNotEmpty == true ? perfil.nome! : 'Sem nome cadastrado',
            style: TipografiaTrato.titulo.copyWith(color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            perfil.ehProfissional ? 'Profissional' : 'Cliente',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x5),
          Card(
            child: Column(
              children: [
                _LinhaPerfil(rotulo: 'Status da conta', valor: perfil.status),
                const Divider(height: 1),
                _LinhaPerfil(
                  rotulo: 'Nota pública',
                  valor: perfil.notaPublica?.toStringAsFixed(1) ?? '—',
                ),
                const Divider(height: 1),
                _LinhaPerfil(
                  rotulo: 'Serviços concluídos',
                  valor: '${perfil.servicosConcluidos ?? 0}',
                ),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x5),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: servicoAuth.sair,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sair'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaPerfil extends StatelessWidget {
  const _LinhaPerfil({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario)),
          Text(valor, style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo)),
        ],
      ),
    );
  }
}
