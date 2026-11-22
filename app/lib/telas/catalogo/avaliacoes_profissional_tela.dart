import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../cliente/modelos.dart';
import '../cliente/perfil_profissional_tela.dart' show CartaoAvaliacao;
import '../comuns/estados.dart';

/// Todas as avaliações que um profissional recebeu (a partir do perfil público),
/// com filtro rápido por estrelas (Todas, ★ 5 .. ★ 1).
class AvaliacoesProfissionalTela extends StatefulWidget {
  const AvaliacoesProfissionalTela({super.key, required this.profissional});

  final Profissional profissional;

  @override
  State<AvaliacoesProfissionalTela> createState() => _AvaliacoesProfissionalTelaState();
}

class _AvaliacoesProfissionalTelaState extends State<AvaliacoesProfissionalTela> {
  int? _estrelaFiltro;

  static int _faixaEstrela(double nota) => nota.floor().clamp(1, 5);

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final lista = widget.profissional.detalhe?.avaliacoes ?? const <Avaliacao>[];
    final filtradas = _estrelaFiltro == null
        ? lista
        : [
            for (final a in lista)
              if (_faixaEstrela(a.nota) == _estrelaFiltro) a,
          ];

    return MolduraTelaComum(
      titulo: 'Avaliações de ${widget.profissional.primeiroNome}',
      child: lista.isEmpty
          ? const EstadoVazio(
              icone: Icons.star_border,
              titulo: 'Ainda sem avaliações',
              texto: 'As avaliações aparecem aqui depois dos primeiros serviços.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ChipEstrela(
                        chave: const ValueKey('filtro-estrela-todas'),
                        rotulo: 'Todas (${lista.length})',
                        selecionado: _estrelaFiltro == null,
                        cores: c,
                        aoTocar: () => setState(() => _estrelaFiltro = null),
                      ),
                      for (final estrela in const [5, 4, 3, 2, 1]) ...[
                        const SizedBox(width: EspacosTrato.x2),
                        Builder(
                          builder: (_) {
                            final qtd = lista.where((a) => _faixaEstrela(a.nota) == estrela).length;
                            return _ChipEstrela(
                              chave: ValueKey('filtro-estrela-$estrela'),
                              rotulo: qtd > 0 ? '★ $estrela ($qtd)' : '★ $estrela',
                              selecionado: _estrelaFiltro == estrela,
                              cores: c,
                              aoTocar: () => setState(() => _estrelaFiltro = estrela),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x4),
                Expanded(
                  child: filtradas.isEmpty
                      ? EstadoVazio(
                          icone: Icons.star_border,
                          titulo:
                              'Nenhuma avaliação com $_estrelaFiltro ${_estrelaFiltro == 1 ? 'estrela' : 'estrelas'}',
                          texto: 'Escolha outra faixa de estrelas ou veja todas as avaliações.',
                          textoAcao: 'Ver todas',
                          aoAcao: () => setState(() => _estrelaFiltro = null),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                          itemCount: filtradas.length,
                          separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                          itemBuilder: (_, i) => CartaoAvaliacao(avaliacao: filtradas[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

class _ChipEstrela extends StatelessWidget {
  const _ChipEstrela({
    required this.chave,
    required this.rotulo,
    required this.selecionado,
    required this.cores,
    required this.aoTocar,
  });

  final Key chave;
  final String rotulo;
  final bool selecionado;
  final CoresTemaTrato cores;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: chave,
      color: selecionado ? cores.petroleo : cores.superficie,
      shape: StadiumBorder(
        side: BorderSide(
          color: selecionado ? cores.petroleo : cores.bordaControle,
          width: EspacosTrato.bordaFina,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x3 + 2,
            vertical: EspacosTrato.x2,
          ),
          child: Text(
            rotulo,
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: selecionado ? cores.sobrePetroleo : cores.texto,
              fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
