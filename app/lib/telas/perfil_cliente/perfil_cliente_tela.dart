import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import 'modelos.dart';

/// Tela 22 — Perfil do cliente. Cada item avisa [aoTocarItem]; "Usar como profissional"
/// é o item [AcaoPerfil.usarComoProfissional]. A barra inferior é da casca do app.
class PerfilClienteTela extends StatefulWidget {
  const PerfilClienteTela({
    super.key,
    required this.perfil,
    this.aoTocarItem,
    this.aoSair,
    this.aoCapturarFotoPerfil,
  });

  final PerfilCliente perfil;
  final ValueChanged<AcaoPerfil>? aoTocarItem;
  final VoidCallback? aoSair;
  final Future<String?> Function()? aoCapturarFotoPerfil;

  @override
  State<PerfilClienteTela> createState() => _PerfilClienteTelaState();
}

class _PerfilClienteTelaState extends State<PerfilClienteTela> {
  static String? _fotoSalvaSessao;
  String? _fotoAtual;

  @override
  void initState() {
    super.initState();
    _fotoAtual = widget.perfil.fotoReferencia ?? _fotoSalvaSessao;
  }

  Future<void> _tocarAvatar() async {
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
          legenda: widget.perfil.nome,
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
    final perfil = widget.perfil;
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x6),
            children: [
              Row(
                children: [
                  AvatarIniciais(
                    iniciais: perfil.iniciais,
                    tamanho: 72,
                    fotoReferencia: _fotoAtual,
                    aoTocar: widget.aoCapturarFotoPerfil == null ? null : _tocarAvatar,
                  ),
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
                _CartaoGrupo(grupo: grupo, aoTocar: widget.aoTocarItem),
              ],
              const SizedBox(height: EspacosTrato.x6),
              Row(
                children: [
                  BotaoLink(texto: 'Sair', aoTocar: widget.aoSair),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const LogoFeitoLabs(tamanho: 28, sobreFundoClaro: true),
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
                indent: EspacosTrato.x4,
                endIndent: EspacosTrato.x4,
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
        padding: const EdgeInsets.symmetric(
          horizontal: EspacosTrato.x4,
          vertical: (EspacosTrato.alturaLinhaLista - 24) / 2,
        ),
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
