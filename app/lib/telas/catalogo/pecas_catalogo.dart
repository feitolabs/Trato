import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../cliente/modelos.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;

/// Barra fixa no rodapé com o botão principal da tela (mesmo padrão do perfil do profissional).
class BarraAcaoInferior extends StatelessWidget {
  const BarraAcaoInferior({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(TamanhoTela.de(context));
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CoresTrato.creme,
        border: Border(top: BorderSide(color: CoresTrato.borda)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x4, margem, EspacosTrato.x4),
          // heightFactor: a barra tem a altura do botão.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Responsivo.larguraMaximaConteudo),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão de profissional nas listas (categoria): nota, serviços concluídos, região e o botão
/// "Pedir orçamento". Tocar no cartão abre o perfil.
class CartaoProfissional extends StatelessWidget {
  const CartaoProfissional({
    super.key,
    required this.profissional,
    required this.aoAbrir,
    this.aoPedirOrcamento,
  });

  final Profissional profissional;
  final VoidCallback aoAbrir;
  final VoidCallback? aoPedirOrcamento;

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Perfil de ${p.nome}, nota ${formatarNota(p.nota)}, '
                '${p.servicosConcluidos} serviços concluídos',
            excludeSemantics: true,
            child: InkWell(
              onTap: aoAbrir,
              child: Padding(
                padding: const EdgeInsets.all(EspacosTrato.x4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AvatarIniciais(iniciais: p.iniciais),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.nome, style: TipografiaTrato.tituloCartao),
                          const SizedBox(height: EspacosTrato.x1),
                          SeloVerificacao(p.verificacao),
                          const SizedBox(height: EspacosTrato.x1),
                          Text(
                            '${p.servicosConcluidos} serviços concluídos'
                            '${p.regiao == null ? '' : ' · ${p.regiao}'}',
                            style: secundario,
                          ),
                          if (p.precoAPartirCentavos != null)
                            Text(
                              'A partir de ${formatarReais(p.precoAPartirCentavos!)}',
                              style: secundario,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 18, color: CoresTrato.petroleo),
                            const SizedBox(width: EspacosTrato.x1),
                            Text(formatarNota(p.nota), style: TipografiaTrato.tituloCartao),
                          ],
                        ),
                        if (p.distanciaKm > 0) ...[
                          const SizedBox(height: EspacosTrato.x1),
                          Text(formatarDistancia(p.distanciaKm), style: secundario),
                        ],
                        if (p.atendeHoje) ...[
                          const SizedBox(height: EspacosTrato.x1),
                          const ChipStatus(texto: 'Hoje', tipo: TipoStatus.sucesso),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (aoPedirOrcamento != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EspacosTrato.x4,
                0,
                EspacosTrato.x4,
                EspacosTrato.x4,
              ),
              child: BotaoSecundario(
                texto: 'Pedir orçamento a ${p.primeiroNome}',
                aoTocar: aoPedirOrcamento,
              ),
            ),
        ],
      ),
    );
  }
}
