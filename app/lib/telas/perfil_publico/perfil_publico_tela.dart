import 'dart:async';

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../cliente/cartao_avaliacao.dart';
import '../cliente/etiquetas_elogio.dart';
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
    this.aoUsarComoCliente,
    this.aoCapturarFotoPerfil,
    this.aoAbrirConfiguracoes,
    this.aoAbrirVerificacao,
    this.carregarTratinhosPendentes,
  });

  /// Texto dos Tratinhos a liberar ("Você tem 50 Tratinhos a liberar em 27/11"); nulo = não mostra.
  final Future<String?> Function()? carregarTratinhosPendentes;

  /// Abre as configurações (dados pessoais, notificações, privacidade, ajuda, termos, sair).
  /// A engrenagem só aparece se vier.
  final VoidCallback? aoAbrirConfiguracoes;
  final VoidCallback? aoAbrirVerificacao;

  final ServicoPerfilPublico servico;
  final VoidCallback? aoVerAvaliacoes;

  /// Abre a edição; quando ela termina, o perfil é carregado de novo.
  final FutureOr<void> Function()? aoEditarCadastro;
  final VoidCallback? aoUsarComoCliente;

  final Future<String?> Function()? aoCapturarFotoPerfil;

  /// Limpa a foto guardada em memória ao encerrar a sessão.
  static void limparFotoSessao() => _PerfilPublicoTelaState._fotoSalvaSessao = null;

  @override
  State<PerfilPublicoTela> createState() => _PerfilPublicoTelaState();
}

class _PerfilPublicoTelaState extends State<PerfilPublicoTela> {
  static String? _fotoSalvaSessao;
  String? _fotoAtual;

  /// Muda depois de editar o cadastro: a página carrega o perfil de novo.
  int _versao = 0;

  Future<void> _editarCadastro() async {
    await widget.aoEditarCadastro?.call();
    if (mounted) setState(() => _versao++);
  }

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
                leading: Icon(Icons.zoom_in, color: context.cores.petroleo),
                title: const Text('Ver foto de perfil'),
                onTap: () => Navigator.of(folha).pop('ver'),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: context.cores.petroleo),
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
    try {
      final nova = await capturar();
      if (nova != null && mounted) {
        setState(() {
          _fotoAtual = nova;
          _fotoSalvaSessao = nova;
        });
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar a foto agora. Tente de novo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<PerfilPublico>(
      key: ValueKey(_versao),
      titulo: 'Seu perfil público',
      acoes: [
        if (widget.aoAbrirConfiguracoes != null)
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings_outlined),
            onPressed: widget.aoAbrirConfiguracoes,
          ),
      ],
      carregar: widget.servico.carregarPerfil,
      construir: (context, p) {
        final fotoExibida = _fotoAtual ?? p.fotoReferencia ?? _fotoSalvaSessao;
        return CorpoRolavel(
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
                        [
                          if (p.categoria.trim().isNotEmpty) p.categoria.trim(),
                          if (p.cidade.trim().isNotEmpty) p.cidade.trim(),
                          'no Trato desde ${p.noTratoDesde}',
                        ].join(' · '),
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: context.cores.textoSecundario),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.carregarTratinhosPendentes != null)
              FutureBuilder<String?>(
                future: widget.carregarTratinhosPendentes!().catchError((Object _) => null),
                builder: (context, snap) => snap.data == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: EspacosTrato.x3),
                        child: Text(
                          snap.data!,
                          key: const Key('tratinhos-pendentes-perfil'),
                          style: TipografiaTrato.corpoPequeno
                              .copyWith(color: context.cores.textoSecundario),
                        ),
                      ),
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
                Expanded(
                    child: _Indicador(
                        rotulo: 'Serviços concluídos', valor: '${p.servicosConcluidos}')),
              ],
            ),
            SeloRespostaReal(faixa: p.respondeEmFaixa),
            EtiquetasMaisElogiadas(etiquetas: p.etiquetasTop),
            const TituloSecao('Sobre'),
            Text(
              p.sobre.isEmpty ? 'Você ainda não escreveu sobre você.' : p.sobre,
              style: TipografiaTrato.corpo,
            ),
            const TituloSecao('Trabalhos'),
            if (p.fotosPortfolio == 0 && p.listaFotosPortfolio.isEmpty)
              Text(
                'Sem fotos de trabalhos ainda.',
                style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
              )
            else
              Row(
                children: [
                  for (var i = 0;
                      i <
                          (p.listaFotosPortfolio.isNotEmpty
                              ? p.listaFotosPortfolio.length
                              : p.fotosPortfolio);
                      i++) ...[
                    if (i > 0) const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: EspacoFoto(
                        legenda: '[Foto]',
                        referencia:
                            i < p.listaFotosPortfolio.length ? p.listaFotosPortfolio[i] : null,
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
                style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
              )
            else ...[
              for (final a in p.ultimasAvaliacoes.take(2)) CartaoAvaliacao(avaliacao: a),
              if (widget.aoVerAvaliacoes != null) ...[
                const SizedBox(height: EspacosTrato.x2),
                BotaoLink(
                  texto: 'Ver todas as avaliações',
                  aoTocar: widget.aoVerAvaliacoes,
                ),
              ],
            ],
            if (widget.aoAbrirVerificacao != null) ...[
              const SizedBox(height: EspacosTrato.x5),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(Icons.verified_user_outlined, color: context.cores.petroleo),
                  title: Text('Verificação de identidade', style: TipografiaTrato.corpoForte),
                  subtitle: Text('Enviar ou acompanhar documentos', style: TipografiaTrato.legenda),
                  trailing: Icon(Icons.chevron_right, color: context.cores.textoSecundario),
                  onTap: widget.aoAbrirVerificacao,
                ),
              ),
            ],
            if (widget.aoUsarComoCliente != null) ...[
              const SizedBox(height: EspacosTrato.x3),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(Icons.swap_horiz, color: context.cores.petroleo),
                  title: Text('Usar como cliente', style: TipografiaTrato.corpoForte),
                  subtitle: Text('Trocar para contratar serviços', style: TipografiaTrato.legenda),
                  trailing: Icon(Icons.chevron_right, color: context.cores.textoSecundario),
                  onTap: widget.aoUsarComoCliente,
                ),
              ),
            ],
            if (widget.aoEditarCadastro != null) ...[
              const SizedBox(height: EspacosTrato.x4),
              BotaoSecundario(texto: 'Editar cadastro', aoTocar: _editarCadastro),
            ],
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
  const CartaoAvaliacao({super.key, required this.avaliacao, this.aoResponder});

  final Avaliacao avaliacao;
  final VoidCallback? aoResponder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
      child: CartaoAvaliacaoVisual(
        avaliacao: avaliacao,
        rotuloResposta: 'Sua resposta',
        aoResponder: aoResponder,
      ),
    );
  }
}
