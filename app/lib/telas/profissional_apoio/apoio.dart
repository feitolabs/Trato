import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Peças comuns das telas do profissional (cadastro, verificação, nota, aditivo, disputa, perfil).
/// Só layout e estados de carga: nenhuma regra de negócio mora aqui.

/// Tipo de captura de foto: a tela pede, quem a liga abre câmera/galeria e devolve
/// uma referência (ou null se a pessoa cancelou).
typedef CapturarFoto = Future<String?> Function();

/// Barra + corpo que rola (limitado em tablet) + rodapé fixo opcional.
class PaginaTrato extends StatelessWidget {
  const PaginaTrato({super.key, required this.titulo, required this.children, this.rodape});

  final String titulo;
  final List<Widget> children;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: CorpoRolavel(rodape: rodape, children: children),
    );
  }
}

/// Conteúdo que rola com margem responsiva e rodapé fixo em superfície.
class CorpoRolavel extends StatelessWidget {
  const CorpoRolavel({super.key, required this.children, this.rodape});

  final List<Widget> children;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x6),
              child: ConteudoResponsivo(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
              ),
            ),
          ),
        ),
        if (rodape != null)
          Container(
            width: double.infinity,
            color: CoresTrato.superficie,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                child: ConteudoResponsivo(child: rodape!),
              ),
            ),
          ),
      ],
    );
  }
}

/// Carrega algo do serviço injetado e mostra carregando / erro com "Tentar de novo" / vazio.
/// [estaVazio] decide o estado vazio a partir do que voltou.
class PaginaCarregavel<T> extends StatefulWidget {
  const PaginaCarregavel({
    super.key,
    required this.titulo,
    required this.carregar,
    required this.construir,
    this.estaVazio,
    this.tituloVazio = 'Nada por aqui ainda',
    this.textoVazio = '',
    this.iconeVazio = Icons.inbox_outlined,
  });

  final String titulo;
  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dados) construir;
  final bool Function(T dados)? estaVazio;
  final String tituloVazio;
  final String textoVazio;
  final IconData iconeVazio;

  @override
  State<PaginaCarregavel<T>> createState() => _PaginaCarregavelState<T>();
}

class _PaginaCarregavelState<T> extends State<PaginaCarregavel<T>> {
  late Future<T> _futuro = widget.carregar()..ignore();

  void _tentarDeNovo() {
    setState(() {
      _futuro = widget.carregar()..ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: FutureBuilder<T>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                color: CoresTrato.azulTexto,
                semanticsLabel: 'Carregando',
              ),
            );
          }
          if (snap.hasError) {
            return MensagemCentral(
              icone: Icons.error_outline,
              titulo: 'Não foi possível carregar',
              texto: 'Confira a conexão e tente de novo.',
              acao: BotaoSecundario(texto: 'Tentar de novo', aoTocar: _tentarDeNovo),
            );
          }
          // T pode ser anulável (null = "não existe"): não usar requireData.
          final dados = snap.data as T;
          if (widget.estaVazio?.call(dados) ?? false) {
            return MensagemCentral(
              icone: widget.iconeVazio,
              titulo: widget.tituloVazio,
              texto: widget.textoVazio,
            );
          }
          return widget.construir(context, dados);
        },
      ),
    );
  }
}

/// Estado vazio ou de erro: ícone, título, frase curta e ação opcional.
class MensagemCentral extends StatelessWidget {
  const MensagemCentral({
    super.key,
    required this.icone,
    required this.titulo,
    this.texto = '',
    this.acao,
  });

  final IconData icone;
  final String titulo;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: ConteudoResponsivo(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x12),
            child: Column(
              children: [
                Icon(icone, size: 48, color: CoresTrato.textoSecundario),
                const SizedBox(height: EspacosTrato.x4),
                Text(titulo, style: TipografiaTrato.titulo, textAlign: TextAlign.center),
                if (texto.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    texto,
                    style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (acao != null) ...[const SizedBox(height: EspacosTrato.x5), acao!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faixa de aviso (erro ao enviar, nota de uso). Fundo suave + texto escuro.
class AvisoFaixa extends StatelessWidget {
  const AvisoFaixa({super.key, required this.texto, this.tipo = TipoStatus.alerta, this.icone});

  final String texto;
  final TipoStatus tipo;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(
        color: tipo.fundo,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 20, color: tipo.texto),
            const SizedBox(width: EspacosTrato.x2),
          ],
          Expanded(
            child: Text(texto, style: TipografiaTrato.corpoPequeno.copyWith(color: tipo.texto)),
          ),
        ],
      ),
    );
  }
}

/// Título de seção, com frase de ajuda opcional.
class TituloSecao extends StatelessWidget {
  const TituloSecao(this.texto, {super.key, this.ajuda});

  final String texto;
  final String? ajuda;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x5, bottom: EspacosTrato.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: TipografiaTrato.titulo),
          if (ajuda != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(ajuda!, style: TipografiaTrato.legenda),
          ],
        ],
      ),
    );
  }
}

/// Pílulas de escolha (várias ou uma) em Wrap, para não estourar em tela estreita.
class OpcoesPilula extends StatelessWidget {
  const OpcoesPilula({
    super.key,
    required this.opcoes,
    required this.selecionadas,
    required this.aoAlternar,
  });

  final List<String> opcoes;
  final Set<String> selecionadas;
  final ValueChanged<String> aoAlternar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: EspacosTrato.x2,
      runSpacing: EspacosTrato.x2,
      children: [
        for (final o in opcoes)
          _Pilula(
            texto: o,
            marcada: selecionadas.contains(o),
            aoTocar: () => aoAlternar(o),
          ),
      ],
    );
  }
}

class _Pilula extends StatelessWidget {
  const _Pilula({required this.texto, required this.marcada, required this.aoTocar});

  final String texto;
  final bool marcada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: marcada,
      label: texto,
      excludeSemantics: true,
      child: Material(
        color: marcada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: StadiumBorder(
          side: BorderSide(
            color: marcada ? CoresTrato.petroleo : CoresTrato.borda,
            width: marcada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EspacosTrato.x4,
                vertical: EspacosTrato.x2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (marcada) ...[
                    const Icon(Icons.check, size: 18, color: CoresTrato.petroleo),
                    const SizedBox(width: EspacosTrato.x1),
                  ],
                  Flexible(child: Text(texto, style: TipografiaTrato.corpoPequeno)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Espaço de foto com ação (tocar para tirar/trocar). A imagem real entra depois: por ora
/// mostra a legenda da referência devolvida por [CapturarFoto].
class CampoFoto extends StatelessWidget {
  const CampoFoto({
    super.key,
    required this.rotulo,
    required this.aoTocar,
    this.referencia,
    this.altura = 120,
  });

  final String rotulo;
  final String? referencia;
  final VoidCallback aoTocar;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final tem = referencia != null;
    return Semantics(
      button: true,
      label: tem ? '$rotulo, enviada. Toque para trocar' : '$rotulo. Toque para tirar a foto',
      excludeSemantics: true,
      child: Material(
        color: tem ? CoresTrato.azulClaro : CoresTrato.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        child: InkWell(
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
          onTap: aoTocar,
          child: Container(
            constraints: BoxConstraints(minHeight: altura),
            width: double.infinity,
            padding: const EdgeInsets.all(EspacosTrato.x3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
              border: Border.all(color: CoresTrato.borda),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tem ? Icons.check_circle_outline : Icons.photo_camera_outlined,
                  color: CoresTrato.petroleo,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  tem ? '$rotulo enviada' : rotulo,
                  style: TipografiaTrato.corpoForte,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  tem ? 'Toque para trocar' : 'Toque para tirar a foto',
                  style: TipografiaTrato.legenda.copyWith(color: CoresTrato.petroleo),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
