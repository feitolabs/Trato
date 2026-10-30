import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../cliente/modelos.dart' show formatarNota;
import '../conclusao/apoio_conclusao.dart' show EspacoFoto;
import '../profissional_apoio/apoio.dart';
import 'perfil_publico.dart';

/// Como os clientes veem o profissional. Não é a tela 10 do cliente: aqui é a pré-visualização
/// do próprio perfil, com atalho para as avaliações recebidas.
class PerfilPublicoTela extends StatelessWidget {
  const PerfilPublicoTela({
    super.key,
    required this.servico,
    this.aoVerAvaliacoes,
    this.aoEditarCadastro,
  });

  final ServicoPerfilPublico servico;
  final VoidCallback? aoVerAvaliacoes;
  final VoidCallback? aoEditarCadastro;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<PerfilPublico>(
      titulo: 'Seu perfil público',
      carregar: servico.carregarPerfil,
      construir: (context, p) => CorpoRolavel(
        rodape: aoEditarCadastro == null
            ? null
            : BotaoSecundario(texto: 'Editar cadastro', aoTocar: aoEditarCadastro),
        children: [
          Row(
            children: [
              AvatarIniciais(iniciais: p.iniciais, tamanho: 80),
              const SizedBox(width: EspacosTrato.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nome, style: TipografiaTrato.tituloGrande),
                    const SizedBox(height: EspacosTrato.x1),
                    if (p.verificacao != null) SeloVerificacao(p.verificacao!),
                    const SizedBox(height: EspacosTrato.x1),
                    Text(
                      '${p.categoria} · ${p.cidade} · no Trato desde ${p.noTratoDesde}',
                      style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
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
                  valor: p.totalAvaliacoes == 0 ? '—' : formatarNota(p.nota),
                  extra: '(${p.totalAvaliacoes})',
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: _Indicador(rotulo: 'Serviços concluídos', valor: '${p.servicosConcluidos}')),
            ],
          ),
          const TituloSecao('Sobre'),
          Text(
            p.sobre.isEmpty ? 'Você ainda não escreveu sobre você.' : p.sobre,
            style: TipografiaTrato.corpo,
          ),
          const TituloSecao('Trabalhos'),
          if (p.fotosPortfolio == 0)
            Text(
              'Sem fotos de trabalhos ainda.',
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            )
          else
            Row(
              children: [
                for (var i = 0; i < p.fotosPortfolio; i++) ...[
                  if (i > 0) const SizedBox(width: EspacosTrato.x3),
                  const Expanded(child: EspacoFoto(legenda: '[Foto]', altura: 88)),
                ],
              ],
            ),
          const TituloSecao('Avaliações recentes'),
          if (p.ultimasAvaliacoes.isEmpty)
            Text(
              'Você ainda não recebeu avaliações.',
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            )
          else
            for (final a in p.ultimasAvaliacoes.take(2)) CartaoAvaliacao(avaliacao: a),
          const SizedBox(height: EspacosTrato.x2),
          BotaoLink(
            texto: 'Ver todas as avaliações',
            aoTocar: aoVerAvaliacoes,
          ),
        ],
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
          Text(rotulo, style: TipografiaTrato.legenda),
          const SizedBox(height: EspacosTrato.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              extra == null ? valor : '$valor $extra',
              style: TipografiaTrato.titulo,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma avaliação recebida: cliente, serviço, nota, comentário e critérios.
class CartaoAvaliacao extends StatelessWidget {
  const CartaoAvaliacao({super.key, required this.avaliacao});

  final Avaliacao avaliacao;

  @override
  Widget build(BuildContext context) {
    final a = avaliacao;
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
      child: CartaoTrato(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, size: 18, color: CoresTrato.petroleo),
                const SizedBox(width: EspacosTrato.x1),
                Text(formatarNota(a.nota), style: TipografiaTrato.corpoForte),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Text(
                    '${a.cliente} · ${a.servico}',
                    style: TipografiaTrato.corpoPequeno,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EspacosTrato.x2),
            Text(a.comentario, style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x1),
            Text(a.detalhes, style: TipografiaTrato.legenda),
          ],
        ),
      ),
    );
  }
}
