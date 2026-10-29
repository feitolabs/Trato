import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';

/// Tela 22 — Perfil do cliente. Cada item avisa [aoTocarItem]; "Usar como profissional"
/// é o item [AcaoPerfil.usarComoProfissional]. A barra inferior é da casca do app.
class PerfilClienteTela extends StatelessWidget {
  const PerfilClienteTela({
    super.key,
    this.perfil = DadosExemplo.perfil,
    this.aoTocarItem,
    this.aoSair,
  });

  final PerfilCliente perfil;
  final ValueChanged<AcaoPerfil>? aoTocarItem;
  final VoidCallback? aoSair;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x6),
            children: [
              Row(
                children: [
                  AvatarIniciais(iniciais: perfil.iniciais, tamanho: 72),
                  const SizedBox(width: EspacosTrato.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(perfil.nome, style: TipografiaTrato.tituloGrande),
                        const SizedBox(height: EspacosTrato.x1),
                        Text(
                          perfil.resumo,
                          style: TipografiaTrato.corpoPequeno.copyWith(
                            color: CoresTrato.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final grupo in perfil.grupos) ...[
                const SizedBox(height: EspacosTrato.x5),
                Text(grupo.titulo, style: TipografiaTrato.sobretitulo),
                const SizedBox(height: EspacosTrato.x3),
                _CartaoGrupo(grupo: grupo, aoTocar: aoTocarItem),
              ],
              const SizedBox(height: EspacosTrato.x6),
              Row(
                children: [
                  BotaoLink(texto: 'Sair', aoTocar: aoSair),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const LogoFeitoLabs(tamanho: 28),
                          const SizedBox(width: EspacosTrato.x2),
                          Flexible(
                            child: Text(
                              'um app Feito Labs',
                              style: TipografiaTrato.corpoPequeno.copyWith(
                                color: CoresTrato.textoSecundario,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartaoGrupo extends StatelessWidget {
  const _CartaoGrupo({required this.grupo, required this.aoTocar});

  final GrupoPerfil grupo;
  final ValueChanged<AcaoPerfil>? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < grupo.itens.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: EspacosTrato.x5,
                endIndent: EspacosTrato.x5,
                color: CoresTrato.borda,
              ),
            _LinhaItem(item: grupo.itens[i], aoTocar: () => aoTocar?.call(grupo.itens[i].acao)),
          ],
        ],
      ),
    );
  }
}

class _LinhaItem extends StatelessWidget {
  const _LinhaItem({required this.item, required this.aoTocar});

  final ItemPerfil item;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x5, vertical: EspacosTrato.x4),
        child: Row(
          children: [
            Expanded(child: Text(item.titulo, style: TipografiaTrato.corpo)),
            if (item.valor != null) ...[
              const SizedBox(width: EspacosTrato.x2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  item.valor!,
                  textAlign: TextAlign.end,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ),
            ],
            const SizedBox(width: EspacosTrato.x2),
            const Icon(Icons.chevron_right, color: CoresTrato.petroleo),
          ],
        ),
      ),
    );
  }
}
