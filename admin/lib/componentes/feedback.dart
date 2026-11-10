import 'package:flutter/material.dart';

import '../nucleo/escopo.dart';
import '../tema/tema.dart';
import 'atualizacao.dart';
import 'botoes.dart';
import 'icones.dart';

/// Os cinco status do DS: success, warning, danger, info, neutral.
enum Tom { neutro, ok, alerta, erro, info }

extension TomVisual on Tom {
  Color get texto => switch (this) {
    Tom.ok => CoresTrato.sucessoTexto,
    Tom.alerta => CoresTrato.avisoTexto,
    Tom.erro => CoresTrato.perigoTexto,
    Tom.info => CoresTrato.infoTexto,
    Tom.neutro => CoresTrato.neutroTexto,
  };

  Color get fundo => switch (this) {
    Tom.ok => CoresTrato.sucessoFundo,
    Tom.alerta => CoresTrato.avisoFundo,
    Tom.erro => CoresTrato.perigoFundo,
    Tom.info => CoresTrato.infoFundo,
    Tom.neutro => CoresTrato.neutroFundo,
  };

  /// Status é sempre cor, ícone e palavra: o ícone repete o que a cor diz.
  IconData get icone => switch (this) {
    Tom.ok => Icons.check_circle_outline,
    Tom.alerta => Icons.schedule,
    Tom.erro => Icons.block,
    Tom.info => Icons.info_outline,
    Tom.neutro => Icons.remove_circle_outline,
  };
}

/// Etiqueta de status: cor + ícone + palavra, totalmente arredondada.
class ChipEstado extends StatelessWidget {
  const ChipEstado(this.texto, {super.key, this.tom = Tom.neutro, this.icone});

  final String texto;
  final Tom tom;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3, vertical: EspacosTrato.x1),
      decoration: BoxDecoration(color: tom.fundo, borderRadius: BorderRadius.circular(EspacosTrato.raioPilula)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone ?? tom.icone, size: 14, color: tom.texto),
          const SizedBox(width: EspacosTrato.x1),
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TipografiaTrato.etiqueta.copyWith(color: tom.texto),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de papel ou tipo (contorno): fica separada da etiqueta de status.
class ChipPapel extends StatelessWidget {
  const ChipPapel(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3, vertical: EspacosTrato.x1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
        border: Border.all(color: CoresTrato.bordaForte),
      ),
      child: Text(texto, style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoPadrao)),
    );
  }
}

/// Banner informativo: ícone à esquerda, mesmo visual do campo. Info, aviso, erro (e ok).
class BannerInfo extends StatelessWidget {
  const BannerInfo(this.texto, {super.key, this.tom = Tom.info, this.icone, this.titulo});

  final String texto;
  final String? titulo;
  final Tom tom;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final cor = tom.texto;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(EspacosTrato.x3),
        decoration: BoxDecoration(color: tom.fundo, borderRadius: BorderRadius.circular(EspacosTrato.raio)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone ?? (tom == Tom.neutro ? Icons.info_outline : tom.icone), size: 18, color: cor),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(
              child: titulo == null
                  ? Text(texto, style: TipografiaTrato.corpo.copyWith(color: cor))
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$titulo ',
                            style: TipografiaTrato.corpoForte.copyWith(color: cor),
                          ),
                          TextSpan(text: texto),
                        ],
                      ),
                      style: TipografiaTrato.corpo.copyWith(color: cor),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Código curto que a pessoa informa ao suporte quando algo falha (RNF-09).
String codigoDeErro(Object erro) {
  var h = 0x811c9dc5;
  for (final c in erro.toString().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'ERR-${(h & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

/// Aviso temporário (toast). Sucesso mostra o número do registro de auditoria; falha explica o
/// que fazer e vem com o código do erro.
void mostrarAviso(BuildContext context, String texto, {String? detalhe, bool erro = false}) {
  final cor = erro ? Tom.erro : Tom.ok;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CoresTrato.fundoSuperficie,
        elevation: 0,
        width: FaixaPainel.de(context).ehCelular ? null : 420,
        margin: FaixaPainel.de(context).ehCelular ? const EdgeInsets.all(EspacosTrato.x4) : null,
        duration: Duration(seconds: erro ? 8 : 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
          side: BorderSide(color: cor.texto),
        ),
        content: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(erro ? Icons.error_outline : Icons.check_circle_outline, color: cor.texto, size: 20),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(texto, style: TipografiaTrato.corpoForte),
                    if (detalhe != null) Text(detalhe, style: TipografiaTrato.legenda),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
}

/// Mostra uma falha com o motivo mantido no formulário e o código do erro.
void mostrarErro(BuildContext context, Object erro) {
  mostrarAviso(
    context,
    erro.toString(),
    erro: true,
    detalhe: 'Seu texto foi mantido. Tente de novo. Código ${codigoDeErro(erro)}',
  );
}

/// Executa uma chamada e mostra o aviso de sucesso (com o registro de auditoria) ou o erro.
/// Devolve true se deu certo.
Future<bool> executar(BuildContext context, Future<void> Function() acao, {String? sucesso}) async {
  final api = context.api;
  try {
    await acao();
    if (context.mounted && sucesso != null) {
      final n = api.ultimoRegistroAuditoria;
      mostrarAviso(context, sucesso, detalhe: n == null ? null : 'Registro de auditoria nº ${_milhar(n)}');
    }
    return true;
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
    return false;
  }
}

String _milhar(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

/// Estado vazio: ícone, frase de contexto e botão quando houver ação possível.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio(
    this.mensagem, {
    super.key,
    this.detalhe,
    this.icone = Icons.inbox_outlined,
    this.rotuloAcao,
    this.aoAcionar,
  });

  final String mensagem;
  final String? detalhe;
  final IconData icone;
  final String? rotuloAcao;
  final VoidCallback? aoAcionar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 40, color: CoresTrato.textoMudo),
              const SizedBox(height: EspacosTrato.x3),
              Text(mensagem, textAlign: TextAlign.center, style: TipografiaTrato.secao),
              if (detalhe != null) ...[
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  detalhe!,
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo),
                ),
              ],
              if (rotuloAcao != null && aoAcionar != null) ...[
                const SizedBox(height: EspacosTrato.x4),
                BotaoTrato.secundario(rotuloAcao!, aoPressionar: aoAcionar),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tela de erro: o que aconteceu, o código e "Tentar de novo".
class EstadoErro extends StatelessWidget {
  const EstadoErro(this.mensagem, {super.key, required this.aoTentar, this.titulo});

  final String mensagem;
  final String? titulo;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: CoresTrato.perigoTexto),
              const SizedBox(height: EspacosTrato.x3),
              Text(titulo ?? 'Não carregamos esta tela', textAlign: TextAlign.center, style: TipografiaTrato.secao),
              const SizedBox(height: EspacosTrato.x1),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo),
              ),
              Text('Código ${codigoDeErro(mensagem)}', textAlign: TextAlign.center, style: TipografiaTrato.legenda),
              const SizedBox(height: EspacosTrato.x4),
              BotaoTrato.secundario('Tentar de novo', aoPressionar: aoTentar),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa de brilho que passa sobre os blocos do esqueleto (1,4 s por volta).
/// Um só por árvore: esqueletos aninhados reaproveitam o de cima. Sem animação quando o
/// sistema pede menos movimento.
class BrilhoEsqueleto extends StatefulWidget {
  const BrilhoEsqueleto({super.key, required this.child});

  final Widget child;

  @override
  State<BrilhoEsqueleto> createState() => _BrilhoEsqueletoState();
}

/// Entrega o relógio do brilho aos blocos de baixo; todos andam juntos.
class _BrilhoAtivo extends InheritedNotifier<Animation<double>> {
  const _BrilhoAtivo({required Animation<double> super.notifier, required super.child});

  static Animation<double>? de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BrilhoAtivo>()?.notifier;
}

class _BrilhoEsqueletoState extends State<BrilhoEsqueleto> with SingleTickerProviderStateMixin {
  late final _controle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parado = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (parado) {
      _controle.stop();
    } else if (!_controle.isAnimating) {
      _controle.repeat();
    }
  }

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Já existe um brilho acima: usa o relógio dele, para os blocos não ficarem fora de passo.
    if (_BrilhoAtivo.de(context) != null) return widget.child;
    return _BrilhoAtivo(notifier: _controle, child: widget.child);
  }
}

/// Bloco do esqueleto de carregamento. Dentro de um esqueleto usa o brilho dele; sozinho,
/// traz o próprio.
class BlocoEsqueleto extends StatelessWidget {
  const BlocoEsqueleto({super.key, this.largura, required this.altura});
  final double? largura;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final relogio = _BrilhoAtivo.de(context);
    if (relogio == null) return BrilhoEsqueleto(child: this);
    // A faixa clara atravessa o bloco da esquerda para a direita.
    final x = relogio.value * 4 - 2;
    return Container(
      width: largura,
      height: altura,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
        gradient: LinearGradient(
          begin: Alignment(x - 1, 0),
          end: Alignment(x + 1, 0),
          colors: const [CoresTrato.neutroFundo, CoresTrato.fundoSuperficie, CoresTrato.neutroFundo],
        ),
      ),
    );
  }
}

typedef _Bloco = BlocoEsqueleto;

/// Esqueleto de lista e de card enquanto os dados carregam.
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({super.key, this.linhas = 5, this.padding = EdgeInsets.zero});

  final int linhas;

  /// Zero por padrão: quem usa já está dentro da margem da página.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando',
      child: BrilhoEsqueleto(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          itemCount: linhas,
          separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.intervaloCartoes),
          itemBuilder: (_, _) => Container(
            padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
            decoration: BoxDecoration(
              color: CoresTrato.fundoSuperficie,
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
              border: Border.all(color: CoresTrato.bordaSuave),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bloco(largura: 180, altura: 16),
                SizedBox(height: EspacosTrato.x2),
                _Bloco(largura: 280, altura: 12),
                SizedBox(height: EspacosTrato.x2),
                _Bloco(largura: 96, altura: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Esqueleto de uma fileira de cards de métrica.
/// Esqueleto de uma página inteira: mantém a margem e o lugar do título, para a tela não "pular"
/// quando os dados chegam (a API real demora mais que um dado de exemplo).
class EsqueletoPagina extends StatelessWidget {
  const EsqueletoPagina({super.key, this.linhas = 5});

  final int linhas;

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return BrilhoEsqueleto(
      child: Padding(
        padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x6, margem, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Bloco(largura: 220, altura: 24),
            const SizedBox(height: EspacosTrato.x2),
            const _Bloco(largura: 340, altura: 12),
            const SizedBox(height: EspacosTrato.x5),
            Expanded(child: EsqueletoLista(linhas: linhas)),
          ],
        ),
      ),
    );
  }
}

class EsqueletoCartoes extends StatelessWidget {
  const EsqueletoCartoes({super.key, this.quantidade = 4});

  final int quantidade;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando',
      child: BrilhoEsqueleto(
        child: Wrap(
          spacing: EspacosTrato.intervaloCartoes,
          runSpacing: EspacosTrato.intervaloCartoes,
          children: [
            for (var i = 0; i < quantidade; i++)
              Container(
                width: 240,
                padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
                decoration: BoxDecoration(
                  color: CoresTrato.fundoSuperficie,
                  borderRadius: BorderRadius.circular(EspacosTrato.raio),
                  border: Border.all(color: CoresTrato.bordaSuave),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bloco(largura: 100, altura: 12),
                    SizedBox(height: EspacosTrato.x3),
                    _Bloco(largura: 140, altura: 28),
                    SizedBox(height: EspacosTrato.x2),
                    _Bloco(largura: 180, altura: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Carrega dados e mostra esqueleto, erro (com "tentar de novo"), vazio ou o conteúdo.
class CarregaDados<T> extends StatefulWidget {
  const CarregaDados({
    super.key,
    required this.carregar,
    required this.construir,
    this.estaVazio,
    this.mensagemVazia = 'Nada por aqui.',
    this.detalheVazio,
    this.esqueleto,
    this.atualizarSozinho = false,
  });

  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dados, Future<void> Function() recarregar) construir;
  final bool Function(T dados)? estaVazio;
  final String mensagemVazia;
  final String? detalheVazio;
  final Widget? esqueleto;

  /// Liga a atualização automática (intervalo configurado e volta para a aba). Ver [AtualizaSozinho].
  final bool atualizarSozinho;

  @override
  State<CarregaDados<T>> createState() => _CarregaDadosState<T>();
}

/// Recarregar não troca a tela pelo esqueleto: os dados antigos ficam até os novos chegarem.
/// Assim filtro, seleção e o que a pessoa digitou no detalhe sobrevivem à atualização.
class _CarregaDadosState<T> extends State<CarregaDados<T>> with AtualizaSozinho {
  late T _dados;
  bool _temDados = false;
  Object? _erro;
  int _geracao = 0;

  @override
  bool get atualizacaoLigada => widget.atualizarSozinho;

  bool _iniciou = false;

  /// A primeira carga sai daqui, não do initState: quem carrega lê `context.api`.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    _buscar();
  }

  /// Só a resposta do pedido mais recente vale (uma resposta lenta não pisa numa nova).
  Future<void> _buscar() async {
    final geracao = ++_geracao;
    try {
      final dados = await widget.carregar();
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _dados = dados;
        _temDados = true;
        _erro = null;
      });
    } catch (e) {
      if (!mounted || geracao != _geracao) return;
      // Já tinha dados: mantém o que estava na tela (o erro de uma ação aparece na própria ação).
      if (!_temDados) setState(() => _erro = e);
    }
  }

  Future<void> _tentarDeNovo() async {
    setState(() => _erro = null);
    await _buscar();
  }

  @override
  Future<void> atualizarEmSilencio() => _buscar();

  @override
  Widget build(BuildContext context) {
    if (_erro case final erro?) return EstadoErro(erro.toString(), aoTentar: _tentarDeNovo);
    if (!_temDados) return widget.esqueleto ?? const EsqueletoLista();
    final dados = _dados;
    if (widget.estaVazio?.call(dados) ?? false) {
      return EstadoVazio(widget.mensagemVazia, detalhe: widget.detalheVazio);
    }
    return widget.construir(context, dados, _buscar);
  }
}

/// Cabeçalho padrão de cada tela: título de 20 px, subtítulo de uma linha e ações à direita.
class CabecalhoPagina extends StatelessWidget {
  const CabecalhoPagina(this.titulo, {super.key, this.subtitulo, this.acoes = const []});

  final String titulo;
  final String? subtitulo;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final celular = FaixaPainel.de(context).ehCelular;
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(titulo, style: TipografiaTrato.titulo)),
        if (subtitulo != null) ...[
          const SizedBox(height: EspacosTrato.x1),
          Text(subtitulo!, style: TipografiaTrato.subtitulo),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsivo.margemLateral(FaixaPainel.de(context)),
        EspacosTrato.x6,
        Responsivo.margemLateral(FaixaPainel.de(context)),
        EspacosTrato.x4,
      ),
      child: celular || acoes.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                textos,
                if (acoes.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  Wrap(spacing: EspacosTrato.x3, runSpacing: EspacosTrato.x2, children: acoes),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: textos),
                const SizedBox(width: EspacosTrato.x4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: EspacosTrato.x3,
                  runSpacing: EspacosTrato.x2,
                  children: acoes,
                ),
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
          Expanded(child: Text(valor, style: TipografiaTrato.corpo)),
        ],
      ),
    );
  }
}

/// Rótulo pequeno sobre um valor (usado nos detalhes lado a lado).
class CampoLeitura extends StatelessWidget {
  const CampoLeitura(this.rotulo, this.valor, {super.key, this.alerta});

  final String rotulo;
  final String valor;

  /// Mensagem de alerta mostrada sob o valor (ex.: CPF não informado).
  final String? alerta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: TipografiaTrato.legenda),
        const SizedBox(height: EspacosTrato.x1),
        Text(valor, style: TipografiaTrato.corpoForte),
        if (alerta != null) ...[
          const SizedBox(height: EspacosTrato.x1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 14, color: CoresTrato.avisoTexto),
              const SizedBox(width: EspacosTrato.x1),
              Flexible(
                child: Text(alerta!, style: TipografiaTrato.legenda.copyWith(color: CoresTrato.avisoTexto)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Texto de ajuda de indicador: ícone `?` com a definição do cálculo (RF-DAS-02).
class IconeAjuda extends StatelessWidget {
  const IconeAjuda(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: texto,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      child: const Padding(
        padding: EdgeInsets.all(EspacosTrato.x1),
        child: Icon(IconesTrato.ajuda, size: 16, color: CoresTrato.textoMudo),
      ),
    );
  }
}
