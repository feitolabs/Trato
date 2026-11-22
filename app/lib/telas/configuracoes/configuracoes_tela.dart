import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional_apoio/apoio.dart';

/// Uma linha da lista de configurações (dados pessoais, notificações, ajuda...).
class ItemContaPerfil {
  const ItemContaPerfil({required this.icone, required this.titulo, required this.aoTocar});

  final IconData icone;
  final String titulo;
  final VoidCallback aoTocar;
}

/// Um bloco de linhas com título ("CONTA", "PRIVACIDADE E AJUDA").
class GrupoConfiguracao {
  const GrupoConfiguracao({required this.titulo, required this.itens});

  final String titulo;
  final List<ItemContaPerfil> itens;
}

/// Configurações da conta, para cliente e profissional. Fica atrás da engrenagem do Perfil
/// para o Perfil mostrar só o que a pessoa usa todo dia. Cada linha só avisa o toque: quem liga
/// cada tela é o `rotas.dart`. "Sair" fica no fim.
class ConfiguracoesTela extends StatelessWidget {
  const ConfiguracoesTela({super.key, required this.grupos, this.aoSair});

  final List<GrupoConfiguracao> grupos;

  /// Sai da conta (limpa a sessão). Sem ele, a linha "Sair" não aparece.
  final VoidCallback? aoSair;

  @override
  Widget build(BuildContext context) {
    return PaginaTrato(
      titulo: 'Configurações',
      children: [
        for (final grupo in grupos) ...[
          Text(grupo.titulo, style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          _Cartao(itens: [
            for (final i in grupo.itens)
              _Linha(icone: i.icone, titulo: i.titulo, aoTocar: i.aoTocar),
          ]),
          const SizedBox(height: EspacosTrato.x5),
        ],
        const SeletorAparencia(),
        const SizedBox(height: EspacosTrato.x5),
        if (aoSair != null)
          _Cartao(itens: [
            _Linha(
                icone: Icons.logout,
                titulo: 'Sair',
                aoTocar: () async {
                  final sair = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sair da conta?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Sair'),
                        ),
                      ],
                    ),
                  );
                  if (sair == true) aoSair!();
                })
          ]),
      ],
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.itens});

  final List<Widget> itens;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < itens.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: CoresTrato.borda,
                indent: EspacosTrato.x4,
                endIndent: EspacosTrato.x4,
              ),
            itens[i],
          ],
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.titulo, required this.aoTocar});

  final IconData icone;
  final String titulo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone, color: CoresTrato.petroleo),
      title: Text(titulo, style: TipografiaTrato.corpoForte),
      trailing: const Icon(Icons.chevron_right, color: CoresTrato.textoSecundario),
      onTap: aoTocar,
    );
  }
}
