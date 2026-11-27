import 'package:flutter/material.dart';

import '../dados/perfil.dart';
import '../tema/tema.dart';
import 'barra_abas.dart';

/// Barra lateral fixa do profissional, no estilo do painel do PDF de referência
/// (`Trato Feito — versão web.pdf`, págs. 9–12): avatar + nome no topo, itens de navegação
/// abaixo, item ativo com pílula clara sobre o fundo petróleo.
class BarraLateralTrato extends StatelessWidget {
  const BarraLateralTrato({
    super.key,
    required this.abas,
    required this.indiceAtual,
    required this.aoSelecionar,
    required this.perfil,
  });

  final List<AbaTrato> abas;
  final int indiceAtual;
  final ValueChanged<int> aoSelecionar;
  final PerfilTrato perfil;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: CoresTrato.petroleo,
      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x6, horizontal: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trato',
            style: TipografiaTrato.marcaPequena.copyWith(color: CoresTrato.creme, fontSize: 20),
          ),
          Text(
            'PROFISSIONAL',
            style: TipografiaTrato.sobretitulo.copyWith(color: CoresTrato.azulClaro),
          ),
          const SizedBox(height: EspacosTrato.x6),
          Container(
            padding: const EdgeInsets.all(EspacosTrato.x3),
            decoration: BoxDecoration(
              color: CoresTrato.veuCartao,
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: CoresTrato.azulClaro,
                  child: Text(
                    (perfil.nome?.isNotEmpty ?? false) ? perfil.nome!.substring(0, 1) : '?',
                    style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo),
                  ),
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        perfil.nome?.isNotEmpty == true ? perfil.nome! : 'Sem nome',
                        style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.creme),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        perfil.notaPublica != null
                            ? '${perfil.status} · ${perfil.notaPublica!.toStringAsFixed(1)}'
                            : perfil.status,
                        style: TipografiaTrato.legenda.copyWith(color: CoresTrato.azulClaro),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x6),
          for (var i = 0; i < abas.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x1),
              child: _ItemLateral(
                aba: abas[i],
                selecionado: i == indiceAtual,
                aoTocar: () => aoSelecionar(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemLateral extends StatelessWidget {
  const _ItemLateral({required this.aba, required this.selecionado, required this.aoTocar});

  final AbaTrato aba;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selecionado ? CoresTrato.creme : Colors.transparent,
      borderRadius: BorderRadius.circular(EspacosTrato.raio),
      child: InkWell(
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3, vertical: EspacosTrato.x3),
          child: Row(
            children: [
              Icon(
                aba.icone,
                size: 20,
                color: selecionado ? CoresTrato.petroleo : CoresTrato.azulClaro,
              ),
              const SizedBox(width: EspacosTrato.x3),
              Text(
                aba.rotulo,
                style: TipografiaTrato.corpoForte.copyWith(
                  color: selecionado ? CoresTrato.petroleo : CoresTrato.creme,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
