import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Tamanho mínimo do motivo (só orientação de tela; o backend também exige motivo).
const kMotivoMinimo = 10;

/// Largura a partir da qual o painel usa menu lateral e lista + detalhe lado a lado.
const kLarguraDesktop = 960.0;

const kTextoAuditoria = 'Será registrado na auditoria.';

enum Tom { neutro, ok, alerta, erro, info }

class ChipEstado extends StatelessWidget {
  const ChipEstado(this.texto, {super.key, this.tom = Tom.neutro});

  final String texto;
  final Tom tom;

  @override
  Widget build(BuildContext context) {
    final (fundo, letra) = switch (tom) {
      Tom.ok => (CoresTrato.verdeSuave, CoresTrato.verdeTexto),
      Tom.alerta => (CoresTrato.ambarSuave, CoresTrato.ambarTexto),
      Tom.erro => (CoresTrato.vermelhoSuave, CoresTrato.vermelhoTexto),
      Tom.info => (CoresTrato.azulSuave, CoresTrato.azulTexto),
      Tom.neutro => (CoresTrato.creme, CoresTrato.textoSecundario),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3, vertical: EspacosTrato.x1),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(EspacosTrato.raioPilula)),
      child: Text(texto, style: TipografiaTrato.legenda.copyWith(color: letra, fontWeight: FontWeight.w700)),
    );
  }
}

/// Aviso fixo de que a ação vira linha na trilha de auditoria.
class AvisoAuditoria extends StatelessWidget {
  const AvisoAuditoria({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.history_edu_outlined, size: 16, color: CoresTrato.textoSecundario),
        const SizedBox(width: EspacosTrato.x2),
        Flexible(child: Text(kTextoAuditoria, style: TipografiaTrato.legenda)),
      ],
    );
  }
}

class EstadoVazio extends StatelessWidget {
  const EstadoVazio(this.mensagem, {super.key});
  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 40, color: CoresTrato.textoDica),
            const SizedBox(height: EspacosTrato.x3),
            Text(mensagem, textAlign: TextAlign.center, style: TipografiaTrato.corpo),
          ],
        ),
      ),
    );
  }
}

class EstadoErro extends StatelessWidget {
  const EstadoErro(this.mensagem, {super.key, required this.aoTentar});
  final String mensagem;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: CoresTrato.vermelhoTexto),
            const SizedBox(height: EspacosTrato.x3),
            Text(mensagem, textAlign: TextAlign.center, style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x4),
            SizedBox(
              width: 220,
              child: OutlinedButton(onPressed: aoTentar, child: const Text('Tentar de novo')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carrega dados e mostra carregando, erro (com "tentar de novo"), vazio ou o conteúdo.
class CarregaDados<T> extends StatefulWidget {
  const CarregaDados({
    super.key,
    required this.carregar,
    required this.construir,
    this.estaVazio,
    this.mensagemVazia = 'Nada por aqui.',
  });

  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dados, Future<void> Function() recarregar) construir;
  final bool Function(T dados)? estaVazio;
  final String mensagemVazia;

  @override
  State<CarregaDados<T>> createState() => _CarregaDadosState<T>();
}

class _CarregaDadosState<T> extends State<CarregaDados<T>> {
  late Future<T> _futuro = widget.carregar();

  Future<void> _recarregar() async {
    final novo = widget.carregar();
    setState(() {
      _futuro = novo;
    });
    try {
      await novo;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EstadoErro(snap.error.toString(), aoTentar: _recarregar);
        }
        final dados = snap.data as T;
        if (widget.estaVazio?.call(dados) ?? false) return EstadoVazio(widget.mensagemVazia);
        return widget.construir(context, dados, _recarregar);
      },
    );
  }
}

/// Cabeçalho padrão de cada tela do painel.
class CabecalhoPagina extends StatelessWidget {
  const CabecalhoPagina(this.titulo, {super.key, this.subtitulo, this.acoes = const []});
  final String titulo;
  final String? subtitulo;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EspacosTrato.x6, EspacosTrato.x6, EspacosTrato.x6, EspacosTrato.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(titulo, style: TipografiaTrato.titulo)),
                if (subtitulo != null) ...[
                  const SizedBox(height: EspacosTrato.x1),
                  Text(subtitulo!, style: TipografiaTrato.legenda),
                ],
              ],
            ),
          ),
          ...acoes,
        ],
      ),
    );
  }
}

class BannerInfo extends StatelessWidget {
  const BannerInfo(this.texto, {super.key, this.tom = Tom.info, this.icone = Icons.info_outline});
  final String texto;
  final Tom tom;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final (fundo, letra) = switch (tom) {
      Tom.ok => (CoresTrato.verdeSuave, CoresTrato.verdeTexto),
      Tom.alerta => (CoresTrato.ambarSuave, CoresTrato.ambarTexto),
      Tom.erro => (CoresTrato.vermelhoSuave, CoresTrato.vermelhoTexto),
      _ => (CoresTrato.azulSuave, CoresTrato.azulTexto),
    };
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(EspacosTrato.raio)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: letra),
          const SizedBox(width: EspacosTrato.x2),
          Expanded(child: Text(texto, style: TipografiaTrato.corpoPequeno.copyWith(color: letra))),
        ],
      ),
    );
  }
}

/// Lista à esquerda e detalhe à direita no desktop; no tablet estreito o detalhe abre em outra tela.
class MestreDetalhe<T> extends StatefulWidget {
  const MestreDetalhe({
    super.key,
    required this.itens,
    required this.itemBuilder,
    required this.detalheBuilder,
    required this.tituloDetalhe,
  });

  final List<T> itens;
  final Widget Function(BuildContext context, T item, bool selecionado) itemBuilder;
  final Widget Function(BuildContext context, T item) detalheBuilder;
  final String Function(T item) tituloDetalhe;

  @override
  State<MestreDetalhe<T>> createState() => _MestreDetalheState<T>();
}

class _MestreDetalheState<T> extends State<MestreDetalhe<T>> {
  int _selecionado = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final largo = c.maxWidth >= 760;
        final atual = _selecionado < widget.itens.length ? _selecionado : 0;
        final lista = ListView.separated(
          padding: const EdgeInsets.all(EspacosTrato.x4),
          itemCount: widget.itens.length,
          separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
          itemBuilder: (context, i) {
            final item = widget.itens[i];
            return InkWell(
              borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
              onTap: () {
                if (largo) {
                  setState(() => _selecionado = i);
                } else {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (ctx) => Scaffold(
                      appBar: AppBar(title: Text(widget.tituloDetalhe(item))),
                      body: SafeArea(child: widget.detalheBuilder(ctx, item)),
                    ),
                  ));
                }
              },
              child: widget.itemBuilder(context, item, largo && i == atual),
            );
          },
        );
        if (!largo) return lista;
        return Row(
          children: [
            SizedBox(width: 340, child: lista),
            const VerticalDivider(width: 1),
            Expanded(child: widget.detalheBuilder(context, widget.itens[atual])),
          ],
        );
      },
    );
  }
}

/// Cartão de item de lista (usado dentro do [MestreDetalhe]).
class CartaoItem extends StatelessWidget {
  const CartaoItem({super.key, required this.titulo, required this.linhas, this.chip, this.selecionado = false});
  final String titulo;
  final List<String> linhas;
  final Widget? chip;
  final bool selecionado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: selecionado ? CoresTrato.azulSuave : CoresTrato.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: selecionado ? CoresTrato.azulTexto : CoresTrato.borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TipografiaTrato.tituloCartao),
          for (final l in linhas) Text(l, style: TipografiaTrato.legenda),
          if (chip != null) ...[const SizedBox(height: EspacosTrato.x2), chip!],
        ],
      ),
    );
  }
}

/// Pequeno bloco "rótulo: valor" dos detalhes.
class Linha extends StatelessWidget {
  const Linha(this.rotulo, this.valor, {super.key});
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(rotulo, style: TipografiaTrato.legenda)),
          Expanded(child: Text(valor, style: TipografiaTrato.corpoPequeno)),
        ],
      ),
    );
  }
}

void mostrarAviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Pede o motivo antes de uma ação sensível. Devolve o motivo, ou null se a pessoa cancelar.
Future<String?> pedirMotivo(
  BuildContext context, {
  required String titulo,
  String? descricao,
  String rotuloConfirmar = 'Confirmar',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogMotivo(titulo: titulo, descricao: descricao, rotuloConfirmar: rotuloConfirmar),
  );
}

class _DialogMotivo extends StatefulWidget {
  const _DialogMotivo({required this.titulo, required this.descricao, required this.rotuloConfirmar});
  final String titulo;
  final String? descricao;
  final String rotuloConfirmar;

  @override
  State<_DialogMotivo> createState() => _DialogMotivoState();
}

class _DialogMotivoState extends State<_DialogMotivo> {
  final _controle = TextEditingController();
  bool _tentou = false;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curto = _controle.text.trim().length < kMotivoMinimo;
    return AlertDialog(
      title: Text(widget.titulo, style: TipografiaTrato.tituloCartao),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.descricao != null) ...[
              Text(widget.descricao!, style: TipografiaTrato.corpoPequeno),
              const SizedBox(height: EspacosTrato.x3),
            ],
            TextField(
              controller: _controle,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Motivo (obrigatório)',
                helperText: 'Pelo menos $kMotivoMinimo caracteres.',
                errorText: _tentou && curto ? 'Explique o motivo.' : null,
              ),
            ),
            const SizedBox(height: EspacosTrato.x3),
            const AvisoAuditoria(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
          onPressed: () {
            if (curto) {
              setState(() => _tentou = true);
              return;
            }
            Navigator.of(context).pop(_controle.text.trim());
          },
          child: Text(widget.rotuloConfirmar),
        ),
      ],
    );
  }
}

/// Executa uma chamada e mostra o erro (ou o aviso de sucesso) numa faixa. Devolve true se deu certo.
Future<bool> executar(BuildContext context, Future<void> Function() acao, {String? sucesso}) async {
  try {
    await acao();
    if (context.mounted && sucesso != null) mostrarAviso(context, sucesso);
    return true;
  } catch (e) {
    if (context.mounted) mostrarAviso(context, e.toString());
    return false;
  }
}
