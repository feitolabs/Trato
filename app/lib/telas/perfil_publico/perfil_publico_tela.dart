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
class PerfilPublicoTela extends StatefulWidget {
  const PerfilPublicoTela({
    super.key,
    required this.servico,
    this.aoVerAvaliacoes,
    this.aoEditarCadastro,
    this.aoSair,
    this.aoUsarComoCliente,
    this.aoCapturarFotoPerfil,
  });

  final ServicoPerfilPublico servico;
  final VoidCallback? aoVerAvaliacoes;
  final VoidCallback? aoEditarCadastro;
  final VoidCallback? aoUsarComoCliente;

  /// Sai da conta (limpa a sessão). Sem ele, o botão não aparece.
  final VoidCallback? aoSair;
  final Future<String?> Function()? aoCapturarFotoPerfil;

  @override
  State<PerfilPublicoTela> createState() => _PerfilPublicoTelaState();
}

class _PerfilPublicoTelaState extends State<PerfilPublicoTela> {
  static String? _fotoSalvaSessao;
  String? _fotoAtual;

  Future<void> _tocarAvatar(String nome) async {
    final capturar = widget.aoCapturarFotoPerfil;
    if (capturar == null) return;
    final temFoto = _fotoAtual != null && _fotoAtual!.isNotEmpty;
    if (temFoto) {
      final acao = await showModalBottomSheet<String>(
        context: context,
        builder: (folha) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.zoom_in, color: CoresTrato.petroleo),
                title: const Text('Ver foto de perfil'),
                onTap: () => Navigator.of(folha).pop('ver'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: CoresTrato.petroleo),
                title: const Text('Trocar foto de perfil'),
                onTap: () => Navigator.of(folha).pop('trocar'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || acao == null) return;
      if (acao == 'ver') {
        await abrirPreviewImagem(
          context,
          referencia: _fotoAtual!,
          legenda: nome,
        );
        return;
      }
    }
    final nova = await capturar();
    if (nova != null && mounted) {
      setState(() {
        _fotoAtual = nova;
        _fotoSalvaSessao = nova;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<PerfilPublico>(
      titulo: 'Seu perfil público',
      carregar: widget.servico.carregarPerfil,
      construir: (context, p) {
        final fotoExibida = _fotoAtual ?? p.fotoReferencia ?? _fotoSalvaSessao;
        return CorpoRolavel(
          rodape: widget.aoEditarCadastro == null
              ? null
              : BotaoSecundario(texto: 'Editar cadastro', aoTocar: widget.aoEditarCadastro),
          children: [
            Row(
              children: [
                AvatarIniciais(
                  iniciais: p.iniciais,
                  tamanho: 80,
                  fotoReferencia: fotoExibida,
                  aoTocar: widget.aoCapturarFotoPerfil == null ? null : () => _tocarAvatar(p.nome),
                ),
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
            if (p.fotosPortfolio == 0 && p.listaFotosPortfolio.isEmpty)
              Text(
                'Sem fotos de trabalhos ainda.',
                style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
              )
            else
              Row(
                children: [
                  for (var i = 0; i < (p.listaFotosPortfolio.isNotEmpty ? p.listaFotosPortfolio.length : p.fotosPortfolio); i++) ...[
                    if (i > 0) const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: EspacoFoto(
                        legenda: '[Foto]',
                        referencia: i < p.listaFotosPortfolio.length ? p.listaFotosPortfolio[i] : null,
                        altura: 88,
                      ),
                    ),
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
              aoTocar: widget.aoVerAvaliacoes,
            ),
            if (widget.aoUsarComoCliente != null)
              BotaoLink(texto: 'Usar como cliente', aoTocar: widget.aoUsarComoCliente),
            if (widget.aoSair != null) BotaoLink(texto: 'Sair', aoTocar: widget.aoSair),
          ],
        );
      },
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
