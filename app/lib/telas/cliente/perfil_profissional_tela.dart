import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'avatar_iniciais.dart';
import 'modelos.dart';

/// Tela 10 do protótipo: perfil público do profissional. Só abre para quem tem
/// [Profissional.detalhe]. Abre da busca, da categoria e do orçamento.
///
/// O selo de verificação mostra só o que foi conferido no cadastro; a tela não promete
/// segurança. [aoPedirOrcamento] abre o Novo pedido; [aoVerAvaliacoes] abre a lista completa.
class PerfilProfissionalTela extends StatelessWidget {
  PerfilProfissionalTela({
    super.key,
    required this.profissional,
    this.aoPedirOrcamento,
    this.aoVerAvaliacoes,
  }) : assert(profissional.detalhe != null);

  final Profissional profissional;
  final ValueChanged<Profissional>? aoPedirOrcamento;
  final ValueChanged<Profissional>? aoVerAvaliacoes;

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    final d = p.detalhe!;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AvatarIniciais(iniciais: p.iniciais, tamanho: 80),
                    const SizedBox(width: EspacosTrato.x4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.nome, style: TipografiaTrato.tituloGrande),
                          const SizedBox(height: EspacosTrato.x1),
                          SeloVerificacao(p.verificacao),
                          const SizedBox(height: EspacosTrato.x1),
                          Text(
                            '${p.especialidade} · no Trato desde ${d.noTratoDesde}',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: CoresTrato.textoSecundario),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x5),
                Row(
                  children: [
                    Expanded(
                      child: _Indicador(
                        rotulo: 'Nota',
                        valor: formatarNota(p.nota),
                        extra: '(${d.totalAvaliacoes})',
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: _Indicador(
                        rotulo: 'Serviços concluídos',
                        valor: '${p.servicosConcluidos}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x3),
                Row(
                  children: [
                    Expanded(
                      child: _Indicador(rotulo: 'Taxa de conclusão', valor: '${d.taxaConclusao}%'),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(child: _Indicador(rotulo: 'Responde em', valor: d.respondeEm)),
                  ],
                ),
                if (d.bio != null && d.bio!.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x6),
                  Text('Sobre', style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x2),
                  Text(d.bio!, style: TipografiaTrato.corpo),
                ],
                if (d.servicos.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x6),
                  Text('Serviços', style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x3),
                  Wrap(
                    spacing: EspacosTrato.x2,
                    runSpacing: EspacosTrato.x2,
                    children: [
                      for (final servico in d.servicos)
                        Chip(
                          label: Text(servico, style: TipografiaTrato.corpoPequeno),
                          backgroundColor: CoresTrato.superficie,
                          side: const BorderSide(color: CoresTrato.borda),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: EspacosTrato.x6),
                Text('Verificações', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                for (final v in d.verificacoes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 22, color: CoresTrato.verdeTexto),
                        const SizedBox(width: EspacosTrato.x3),
                        Expanded(child: Text(v, style: TipografiaTrato.corpo)),
                      ],
                    ),
                  ),
                Text(
                  'O selo mostra o que foi conferido no cadastro. Compare os orçamentos e '
                  'converse antes de decidir.',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
                const SizedBox(height: EspacosTrato.x6),
                Text('Trabalhos', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                Row(
                  children: [
                    for (var i = 0; i < d.fotosTrabalhos; i++) ...[
                      if (i > 0) const SizedBox(width: EspacosTrato.x3),
                      Expanded(
                        child: _FotoReservada(
                          legenda: i < d.trabalhos.length ? d.trabalhos[i] : 'Trabalho ${i + 1}',
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: EspacosTrato.x6),
                Row(
                  children: [
                    Expanded(child: Text('Avaliações', style: TipografiaTrato.titulo)),
                    if (aoVerAvaliacoes != null)
                      BotaoLink(
                        texto: 'Ver as ${d.totalAvaliacoes}',
                        aoTocar: () => aoVerAvaliacoes!(p),
                      ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x2),
                for (final a in d.avaliacoes) ...[
                  CartaoAvaliacao(avaliacao: a),
                  const SizedBox(height: EspacosTrato.x3),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: CoresTrato.creme,
          border: Border(top: BorderSide(color: CoresTrato.borda)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Responsivo.margemLateral(TamanhoTela.de(context)),
              EspacosTrato.x4,
              Responsivo.margemLateral(TamanhoTela.de(context)),
              EspacosTrato.x4,
            ),
            // heightFactor: a barra tem a altura do botão (ConteudoResponsivo ocuparia a tela toda).
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Responsivo.larguraMaximaConteudo),
                child: BotaoPrimario(
                  texto: 'Pedir orçamento ao ${p.primeiroNome}',
                  aoTocar: aoPedirOrcamento == null ? null : () => aoPedirOrcamento!(p),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.rotulo, required this.valor, this.extra});

  final String rotulo;
  final String valor;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              rotulo,
              maxLines: 1,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
          ),
          const SizedBox(height: EspacosTrato.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              maxLines: 1,
              TextSpan(
                text: valor,
                style: TipografiaTrato.titulo,
                children: [
                  if (extra != null)
                    TextSpan(
                      text: ' $extra',
                      style:
                          TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
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

/// Espaço da foto de um trabalho do portfólio: quadrado azul-claro com a legenda. A foto em si
/// chega por URL assinada quando o portfólio tiver imagens.
class _FotoReservada extends StatelessWidget {
  const _FotoReservada({required this.legenda});

  final String legenda;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(EspacosTrato.x2),
        decoration: BoxDecoration(
          color: CoresTrato.azulClaro,
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
        ),
        child: Semantics(
          label: 'Trabalho: $legenda',
          child: Text(
            legenda,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: CoresTrato.petroleo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class CartaoAvaliacao extends StatelessWidget {
  const CartaoAvaliacao({super.key, required this.avaliacao});

  final Avaliacao avaliacao;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: secundario,
                    children: [
                      TextSpan(
                        text: avaliacao.cliente,
                        style: secundario.copyWith(
                          color: CoresTrato.petroleo,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: ' · ${avaliacao.servico}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Text(formatarNota(avaliacao.nota), style: secundario),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(avaliacao.comentario, style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x2),
          Text(avaliacao.detalhes, style: secundario),
        ],
      ),
    );
  }
}
