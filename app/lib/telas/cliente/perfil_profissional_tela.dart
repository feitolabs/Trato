import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import 'avatar_iniciais.dart';
import 'modelos.dart';

/// Tela 10 do protótipo: perfil do profissional. Só abre para quem tem [Profissional.detalhe].
/// As fotos de trabalhos e o texto da avaliação são os marcadores do protótipo ("[Foto]").
class PerfilProfissionalTela extends StatelessWidget {
  PerfilProfissionalTela({super.key, required this.profissional})
      : assert(profissional.detalhe != null);

  final Profissional profissional;

  void _emBreve(BuildContext context, String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    final d = p.detalhe!;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Favoritar',
            icon: const Icon(Icons.favorite_border),
            onPressed: () => _emBreve(context, 'Favoritos'),
          ),
          const SizedBox(width: EspacosTrato.x2),
        ],
      ),
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
                            'Eletricista · no Trato desde ${d.noTratoDesde}',
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
                const SizedBox(height: EspacosTrato.x3),
                Text('Trabalhos', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                Row(
                  children: [
                    for (var i = 0; i < d.fotosTrabalhos; i++) ...[
                      if (i > 0) const SizedBox(width: EspacosTrato.x3),
                      const Expanded(child: _FotoReservada()),
                    ],
                  ],
                ),
                const SizedBox(height: EspacosTrato.x6),
                Row(
                  children: [
                    Expanded(child: Text('Avaliações', style: TipografiaTrato.titulo)),
                    BotaoLink(
                      texto: 'Ver as ${d.totalAvaliacoes}',
                      aoTocar: () => _emBreve(context, 'Avaliações de ${p.nome}'),
                    ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x2),
                for (final a in d.avaliacoes) ...[
                  _CartaoAvaliacao(avaliacao: a),
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
                  aoTocar: () => _emBreve(context, 'Novo pedido'),
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

/// Marcador de foto do protótipo (quadrado azul-claro com "[Foto]").
class _FotoReservada extends StatelessWidget {
  const _FotoReservada();

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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '[Foto]',
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

class _CartaoAvaliacao extends StatelessWidget {
  const _CartaoAvaliacao({required this.avaliacao});

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
