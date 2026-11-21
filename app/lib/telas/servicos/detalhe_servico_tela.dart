import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_de_usuario.dart';
import '../cliente/avatar_iniciais.dart' show SeloVerificacao;
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import 'modelos.dart';

/// Detalhe do serviço (pedido) do cliente: situação, linha do tempo, profissional, valores e as
/// ações possíveis em cada estado. Tudo vem do backend; a tela só mostra e avisa o que foi tocado.
class DetalheServicoTela extends StatelessWidget {
  const DetalheServicoTela({
    super.key,
    required this.dados,
    required this.aoAcao,
    this.aoVerProfissional,
    this.aoEditarPedido,
    this.aoVerContrato,
    this.aoVerNota,
    this.aoVerAditivo,
    this.aoVerConclusao,
  });

  final DetalheServico dados;
  final ValueChanged<AcaoServico> aoAcao;
  final ValueChanged<ProfissionalDoServico>? aoVerProfissional;
  final VoidCallback? aoEditarPedido;
  final VoidCallback? aoVerContrato;
  final VoidCallback? aoVerNota;
  final VoidCallback? aoVerAditivo;
  final VoidCallback? aoVerConclusao;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    final acoes = dados.acoes;
    final pro = dados.profissional;
    final recarregar = AtualizadorTela.de(context);
    final conteudo = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dados.titulo, style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x2),
                Text('Pedido ${dados.numero} · ${dados.abertoEm}', style: secundario),
                const SizedBox(height: EspacosTrato.x3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ChipStatus(texto: dados.statusTexto, tipo: dados.statusTipo),
                ),
                if (dados.descricao != null) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  Text(dados.descricao!, style: TipografiaTrato.corpo),
                ],
                const SizedBox(height: EspacosTrato.x5),
                Text('Local do serviço', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                CartaoTrato(
                  key: const ValueKey('local-do-servico'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        dados.remoto ? Icons.videocam_outlined : Icons.location_on_outlined,
                        color: CoresTrato.petroleo,
                      ),
                      const SizedBox(width: EspacosTrato.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dados.remoto ? 'Atendimento remoto' : 'Atendimento presencial',
                              style: TipografiaTrato.corpoForte,
                            ),
                            Text(
                              dados.remoto
                                  ? 'Sem endereço: você combina tudo com o profissional pelo chat.'
                                  : dados.local ?? 'Endereço não informado neste pedido.',
                              style: secundario,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if ((dados.codigoInicio ?? '').isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x5),
                  Text('Código de início', style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x3),
                  CartaoTrato(
                    key: const ValueKey('codigo-de-inicio'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dados.codigoInicio!, style: TipografiaTrato.tituloGrande),
                        const SizedBox(height: EspacosTrato.x1),
                        Text(
                          dados.remoto
                              ? 'Passe este código ao profissional quando o atendimento começar. '
                                  'Não envie o código por mensagem.'
                              : 'Passe este código ao profissional quando ele chegar. '
                                  'Não envie o código por mensagem.',
                          style: secundario,
                        ),
                      ],
                    ),
                  ),
                ],
                if ((dados.codigoConclusao ?? '').isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x5),
                  Text('Código de conclusão', style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x3),
                  CartaoTrato(
                    key: const ValueKey('codigo-de-conclusao'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dados.codigoConclusao!, style: TipografiaTrato.tituloGrande),
                        const SizedBox(height: EspacosTrato.x1),
                        Text(
                          'Quando o serviço estiver pronto, passe este código ao profissional '
                          'para ele concluir. Não envie o código por mensagem.',
                          style: secundario,
                        ),
                      ],
                    ),
                  ),
                ],
                if (pro != null) ...[
                  const SizedBox(height: EspacosTrato.x5),
                  Text('Profissional', style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x3),
                  CartaoTrato(
                    aoTocar: pro.id == null || aoVerProfissional == null
                        ? null
                        : () => aoVerProfissional!(pro),
                    child: Row(
                      children: [
                        AvatarDeUsuario(iniciais: pro.iniciais, usuarioId: pro.id),
                        const SizedBox(width: EspacosTrato.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pro.nome, style: TipografiaTrato.tituloCartao),
                              if (pro.verificacao != null) SeloVerificacao(pro.verificacao!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: EspacosTrato.x5),
                Text('Andamento', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                LinhaDoTempo(etapas: dados.etapas),
                if (dados.valores.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x5),
                  Text('Valores', style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x3),
                  CartaoTrato(
                    child: Column(
                      children: [
                        for (final v in dados.valores)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    v.rotulo,
                                    style: v.destaque
                                        ? TipografiaTrato.corpoForte
                                        : TipografiaTrato.corpo,
                                  ),
                                ),
                                Text(
                                  formatarReais(v.centavos),
                                  style: v.destaque
                                      ? TipografiaTrato.corpoForte
                                      : TipografiaTrato.corpo,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (dados.avisoValores != null) ...[
                    const SizedBox(height: EspacosTrato.x2),
                    Text(dados.avisoValores!, style: secundario),
                  ],
                ],
                if (acoes.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x6),
                  for (final (i, a) in acoes.indexed) ...[
                    if (i > 0) const SizedBox(height: EspacosTrato.x3),
                    i == 0
                        ? BotaoPrimario(texto: a.rotulo, aoTocar: () => aoAcao(a))
                        : BotaoSecundario(texto: a.rotulo, aoTocar: () => aoAcao(a)),
                  ],
                ],
                if (aoEditarPedido != null ||
                    aoVerContrato != null ||
                    aoVerNota != null ||
                    aoVerAditivo != null ||
                    aoVerConclusao != null) ...[
                  const SizedBox(height: EspacosTrato.x4),
                  if (aoEditarPedido != null)
                    BotaoSecundario(
                      texto: 'Editar pedido',
                      aoTocar: aoEditarPedido,
                    ),
                  if (aoVerContrato != null)
                    BotaoLink(texto: 'Ver contrato', aoTocar: aoVerContrato),
                  if (aoVerNota != null && !dados.remoto)
                    BotaoLink(texto: 'Ver nota de materiais', aoTocar: aoVerNota),
                  if (aoVerAditivo != null)
                    BotaoLink(texto: 'Ver aditivo do serviço', aoTocar: aoVerAditivo),
                  if (aoVerConclusao != null)
                    BotaoLink(texto: 'Ver conclusão do serviço', aoTocar: aoVerConclusao),
                ],
              ],
            ),
          );
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: recarregar == null
              ? conteudo
              : RefreshIndicator(onRefresh: recarregar, child: conteudo),
        ),
      ),
    );
  }
}
