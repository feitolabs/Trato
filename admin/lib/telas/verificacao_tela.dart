import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.1 — fila de verificação de profissionais (RF-VER-01 a RF-VER-04).
class VerificacaoTela extends StatelessWidget {
  const VerificacaoTela({super.key});

  static (String, Tom) chip(StatusVerificacao s) => switch (s) {
        StatusVerificacao.enviada => ('Enviada', Tom.info),
        StatusVerificacao.emAnalise => ('Em análise', Tom.alerta),
        StatusVerificacao.aprovada => ('Aprovada', Tom.ok),
        StatusVerificacao.recusada => ('Recusada', Tom.erro),
      };

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<Verificacao>>(
      esqueleto: const EsqueletoPagina(),
      carregar: context.api.listarVerificacoes,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum cadastro esperando análise.',
      detalheVazio: 'Quando um profissional enviar os documentos, o cadastro aparece aqui.',
      construir: (context, lista, recarregar) => _FilaVerificacao(lista: lista, aoMudar: recarregar),
    );
  }
}

class _FilaVerificacao extends StatefulWidget {
  const _FilaVerificacao({required this.lista, required this.aoMudar});

  final List<Verificacao> lista;
  final Future<void> Function() aoMudar;

  @override
  State<_FilaVerificacao> createState() => _FilaVerificacaoState();
}

class _FilaVerificacaoState extends State<_FilaVerificacao> {
  /// `pendentes` (enviada + em análise) ou o nome de um status.
  String _filtro = 'pendentes';
  String _busca = '';

  int _contar(StatusVerificacao s) => widget.lista.where((v) => v.status == s).length;

  bool _casa(Verificacao v) {
    final ok = switch (_filtro) {
      'pendentes' => v.status == StatusVerificacao.enviada || v.status == StatusVerificacao.emAnalise,
      final nome => v.status.name == nome,
    };
    if (!ok) return false;
    final t = _busca.trim().toLowerCase();
    return t.isEmpty || v.profissional.toLowerCase().contains(t) || v.idPublico.toLowerCase().contains(t);
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _contar(StatusVerificacao.enviada) + _contar(StatusVerificacao.emAnalise);
    // Fila ordenada pelo envio mais antigo.
    final itens = widget.lista.where(_casa).toList()..sort((a, b) => a.enviadaEm.compareTo(b.enviadaEm));
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Verificação de profissionais',
          subtitulo: pendentes == 0
              ? 'Nenhum cadastro aguardando análise'
              : '$pendentes ${pendentes == 1 ? 'cadastro aguardando' : 'cadastros aguardando'} análise. '
                  'Fila pelo envio mais antigo. Aprovar libera pedidos só das categorias aprovadas.',
        ),
        Expanded(
          child: MestreDetalhe<Verificacao>(
            itens: itens,
            mensagemSemItens: 'Nenhum cadastro com esse filtro.',
            tituloDetalhe: (v) => v.profissional,
            topo: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FiltroStatus(
                  opcoes: [
                    ('pendentes', 'Pendentes', pendentes),
                    ('enviada', 'Enviada', _contar(StatusVerificacao.enviada)),
                    ('emAnalise', 'Em análise', _contar(StatusVerificacao.emAnalise)),
                    ('aprovada', 'Aprovada', _contar(StatusVerificacao.aprovada)),
                    ('recusada', 'Recusada', _contar(StatusVerificacao.recusada)),
                  ],
                  selecionado: _filtro,
                  aoMudar: (v) => setState(() => _filtro = v),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(margem, 0, EspacosTrato.x3, EspacosTrato.x2),
                  child: TextField(
                    onChanged: (v) => setState(() => _busca = v),
                    decoration: const InputDecoration(
                      labelText: 'Buscar cadastro',
                      prefixIcon: Icon(IconesTrato.buscar, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            itemBuilder: (context, v, sel) {
              final (texto, tom) = VerificacaoTela.chip(v.status);
              return CartaoLista(
                titulo: v.profissional,
                linhas: [
                  if (v.categorias.isNotEmpty) v.categorias.join(', '),
                  'Enviado em ${formatarData(v.enviadaEm)}',
                ],
                chips: [ChipEstado(texto, tom: tom)],
                selecionado: sel,
              );
            },
            detalheBuilder: (context, v) =>
                DetalheVerificacao(key: ValueKey(v.id), verificacao: v, aoMudar: widget.aoMudar),
          ),
        ),
      ],
    );
  }
}

/// Motivos padronizados de recusa (RF-VER-04): a pessoa escolhe um e pode somar texto livre.
const motivosRecusaPadrao = [
  'Documento ilegível ou cortado',
  'Selfie não confere com o documento',
  'Documento vencido ou inválido',
  'CPF não confere com o documento',
  'Categoria sem comprovação de experiência',
];

class DetalheVerificacao extends StatefulWidget {
  const DetalheVerificacao({super.key, required this.verificacao, required this.aoMudar});

  final Verificacao verificacao;
  final Future<void> Function() aoMudar;

  @override
  State<DetalheVerificacao> createState() => _DetalheVerificacaoState();
}

/// Quanto tempo um documento revelado fica liberado para reabrir sem novo motivo.
const kDocumentoLiberadoPor = Duration(minutes: 10);

/// Imagem de um link assinado. Trocável nos testes (lá não há rede).
ImageProvider Function(String url) imagemDoLink =
    (url) => NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.fallback);

/// Documento já revelado: a imagem fica presa na memória (não o link, que expira em segundos)
/// até [ate]. Reabrir nesse prazo não pede motivo nem chama o backend.
class _DocumentoLiberado {
  _DocumentoLiberado(this.imagem, this.ate, this.manter, this.fim);

  final ImageProvider imagem;
  final DateTime ate;
  final ImageStreamCompleterHandle? manter;
  final Timer fim;

  void descartar() {
    fim.cancel();
    manter?.dispose();
    imagem.evict();
  }
}

class _DetalheVerificacaoState extends State<DetalheVerificacao> {
  final _reveladas = <String>{};
  final _liberados = <String, _DocumentoLiberado>{};
  String? _cpfRevelado;
  Timer? _escondeCpf;
  bool _decidindo = false;

  @override
  void dispose() {
    _escondeCpf?.cancel();
    // Trocou de cadastro ou saiu da tela: a imagem some da memória.
    for (final d in _liberados.values) {
      d.descartar();
    }
    _liberados.clear();
    super.dispose();
  }

  void _soltar(String documento) {
    final d = _liberados.remove(documento);
    if (d == null) return;
    d.descartar();
    if (mounted) setState(() {});
  }

  /// Carrega e prende a imagem por [kDocumentoLiberadoPor]. Se não carregar, não guarda nada:
  /// o próximo "Ver de novo" pede motivo e um link novo.
  ImageProvider _liberar(String documento, String url) {
    _soltar(documento);
    final imagem = imagemDoLink(url);
    final fluxo = imagem.resolve(ImageConfiguration.empty);
    fluxo.addListener(ImageStreamListener((_, _) {}, onError: (_, _) => _soltar(documento)));
    _liberados[documento] = _DocumentoLiberado(
      imagem,
      DateTime.now().add(kDocumentoLiberadoPor),
      fluxo.completer?.keepAlive(),
      Timer(kDocumentoLiberadoPor, () => _soltar(documento)),
    );
    return imagem;
  }

  Future<void> _mostrar(String documento, ImageProvider imagem, {String? url}) => mostrarModal<void>(
        context,
        largura: 860,
        construir: (_) => VisualizadorDocumento(
          titulo: documento,
          imagem: imagem,
          url: url,
          profissional: widget.verificacao.profissional,
        ),
      );

  Future<void> _verDeNovo(String documento) async {
    final liberado = _liberados[documento];
    if (liberado == null) return _revelar(documento);
    await _mostrar(documento, liberado.imagem);
  }

  Future<void> _revelarCpf() async {
    final api = context.api;
    final v = widget.verificacao;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Revelar dados pessoais de ${v.profissional}?',
      descricao: 'O CPF aparece por 30 segundos e depois volta a ficar mascarado. O acesso é gravado.',
      rotuloConfirmar: 'Revelar dados pessoais',
    );
    if (motivo == null || !mounted) return;
    DadosPessoais? dados;
    final ok = await executar(context, () async {
      dados = await api.revelarDadosPessoais(v.profissionalId, motivo);
    }, sucesso: 'Dados pessoais revelados por 30 segundos.');
    if (!ok || !mounted) return;
    setState(() => _cpfRevelado = dados?.cpf);
    _escondeCpf?.cancel();
    _escondeCpf = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _cpfRevelado = null);
    });
  }

  Future<void> _revelar(String documento) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Ver $documento',
      descricao: 'O arquivo fica escondido por padrão. Ao abrir, a visualização é gravada. '
          'Depois, fica liberado por ${kDocumentoLiberadoPor.inMinutes} minutos enquanto este cadastro estiver aberto.',
      rotuloConfirmar: 'Revelar',
    );
    if (motivo == null || !mounted) return;
    String? url;
    final ok = await executar(context, () async {
      url = await api.revelarDocumento(widget.verificacao.id, documento, motivo);
    });
    if (!ok || !mounted) return;
    // A URL assinada vale poucos segundos: abre num modal aqui mesmo, nunca é mostrada nem guardada.
    // (Nova aba depois de um await cai no bloqueador de pop-up do navegador.)
    final aberta = url;
    if (aberta == null) {
      setState(() => _reveladas.add(documento));
      return;
    }
    final imagem = _liberar(documento, aberta);
    setState(() => _reveladas.add(documento));
    await _mostrar(documento, imagem, url: aberta);
  }

  Future<void> _decidir(bool aprovar) async {
    final api = context.api;
    final v = widget.verificacao;
    final motivo = await pedirMotivo(
      context,
      titulo: aprovar ? 'Aprovar ${v.profissional}?' : 'Recusar o cadastro de ${v.profissional}?',
      descricao: aprovar
          ? 'O profissional passa a receber pedidos só das categorias aprovadas'
              '${v.categorias.isEmpty ? '' : ': ${v.categorias.join(', ')}'}.'
          : 'O profissional é avisado do motivo e pode enviar de novo.',
      rotuloConfirmar: aprovar ? 'Aprovar profissional' : 'Recusar cadastro',
      destrutivo: !aprovar,
      motivosPadrao: aprovar ? null : motivosRecusaPadrao,
    );
    if (motivo == null || !mounted) return;
    setState(() => _decidindo = true);
    final ok = await executar(
      context,
      () => api.decidirVerificacao(v.id, aprovar: aprovar, motivo: motivo),
      sucesso: aprovar ? 'Profissional aprovado.' : 'Profissional recusado.',
    );
    if (mounted) setState(() => _decidindo = false);
    if (ok) await widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verificacao;
    final (textoStatus, tomStatus) = VerificacaoTela.chip(v.status);
    final decidida = v.status == StatusVerificacao.aprovada || v.status == StatusVerificacao.recusada;
    final podeRevelar = context.pode(Permissao.documentosRevelar);
    final podeRevelarPessoais = context.pode(Permissao.dadosPessoaisRevelar);
    final podeDecidir = context.pode(Permissao.verificacoesDecidir) && !decidida;
    final semCpf = v.cpfMascarado == null || v.cpfMascarado!.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.profissional, style: TipografiaTrato.titulo),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    [
                      if (v.idPublico.isNotEmpty) 'ID ${v.idPublico}',
                      if (v.cidade.isNotEmpty) v.cidade,
                      'enviado em ${formatarData(v.enviadaEm)}',
                    ].join(' · '),
                    style: TipografiaTrato.subtitulo,
                  ),
                ],
              ),
            ),
            ChipEstado(textoStatus, tom: tomStatus),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        Wrap(
          spacing: EspacosTrato.x8,
          runSpacing: EspacosTrato.x4,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            // Nível de verificação e categorias de serviço são coisas diferentes (seção 9).
            CampoLeitura('Nível de verificação', v.nivel.isEmpty ? 'Não informado' : v.nivel),
            CampoLeitura(
              'CPF',
              _cpfRevelado ?? (semCpf ? 'Não informado' : v.cpfMascarado!),
              alerta: semCpf ? 'Cadastro sem CPF. Confira antes de aprovar.' : null,
            ),
            if (!semCpf && _cpfRevelado == null && podeRevelarPessoais)
              Padding(
                padding: const EdgeInsets.only(top: EspacosTrato.x3),
                child: BotaoTrato.link('Revelar dados pessoais', aoPressionar: _revelarCpf, icone: IconesTrato.revelar),
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x5),
        Text('Categorias de serviço solicitadas', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        if (v.categorias.isEmpty)
          Text('Nenhuma categoria informada.', style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo))
        else
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [for (final c in v.categorias) ChipPapel(c)],
          ),
        const SizedBox(height: EspacosTrato.x5),
        Text('Documentos e selfie', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        if (v.documentos.isEmpty)
          const BannerInfo('O profissional ainda não enviou documentos.', tom: Tom.alerta)
        else
          Wrap(
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            children: [
              for (final doc in v.documentos)
                _ArquivoMascarado(
                  rotulo: doc,
                  revelado: _reveladas.contains(doc),
                  liberadoAte: _liberados[doc]?.ate,
                  aoRevelar: podeRevelar ? () => _verDeNovo(doc) : null,
                ),
            ],
          ),
        if (!podeRevelar) ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo('Seu papel não abre documentos. Quem analisa é o time de cadastro.'),
        ],
        if (v.enviosAnteriores.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x5),
          Text('Envios anteriores', style: TipografiaTrato.secao),
          const SizedBox(height: EspacosTrato.x2),
          for (final e in v.enviosAnteriores)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      e.aprovado
                          ? 'Aprovado'
                          : 'Recusado${e.motivo == null || e.motivo!.isEmpty ? '' : ': ${e.motivo}'}',
                      style: TipografiaTrato.corpo,
                    ),
                  ),
                  Text(formatarData(e.enviadoEm), style: TipografiaTrato.legenda),
                ],
              ),
            ),
        ],
        if (v.motivoDecisao != null && v.motivoDecisao!.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x4),
          Linha('Motivo da decisão', v.motivoDecisao!),
        ],
        if (podeDecidir) ...[
          const SizedBox(height: EspacosTrato.x6),
          const Divider(),
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            children: [
              BotaoTrato.secundario('Recusar cadastro', aoPressionar: _decidindo ? null : () => _decidir(false)),
              BotaoTrato.primario(
                'Aprovar profissional',
                aoPressionar: _decidindo ? null : () => _decidir(true),
                carregando: _decidindo,
                rotuloCarregando: 'Enviando',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ArquivoMascarado extends StatelessWidget {
  const _ArquivoMascarado({
    required this.rotulo,
    required this.revelado,
    required this.liberadoAte,
    required this.aoRevelar,
  });

  final String rotulo;
  final bool revelado;
  final DateTime? liberadoAte;
  final VoidCallback? aoRevelar;

  String get _legenda {
    final ate = liberadoAte;
    if (ate != null) {
      String dois(int n) => n.toString().padLeft(2, '0');
      return 'Liberado até ${dois(ate.hour)}:${dois(ate.minute)}';
    }
    return revelado ? 'Aberto nesta sessão' : 'Escondido';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(
        color: CoresTrato.fundoSuperficie,
        border: Border.all(color: CoresTrato.bordaSuave),
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Column(
        children: [
          Container(
            height: 110,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: revelado ? CoresTrato.sucessoFundo : CoresTrato.fundoSelecionado,
              borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
            ),
            child: Icon(
              revelado ? Icons.image_outlined : IconesTrato.travar,
              size: 36,
              color: revelado ? CoresTrato.sucessoTexto : CoresTrato.textoLink,
            ),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(rotulo, style: TipografiaTrato.corpoForte),
          Text(_legenda, style: TipografiaTrato.legenda),
          // Dentro do prazo reabre direto; depois dele, pede motivo e gera outro registro.
          if (aoRevelar != null) BotaoTrato.link(revelado ? 'Ver de novo' : 'Revelar', aoPressionar: aoRevelar),
        ],
      ),
    );
  }
}

/// Modal que mostra o documento revelado sem sair do painel. Dá zoom (pinça/roda) e arrasto.
/// Se a imagem não carregar (PDF, link expirado), oferece abrir em nova aba — com clique da
/// pessoa, para o navegador não bloquear.
class VisualizadorDocumento extends StatelessWidget {
  const VisualizadorDocumento({
    super.key,
    required this.titulo,
    required this.imagem,
    required this.profissional,
    this.url,
  });

  final String titulo;
  final ImageProvider imagem;
  final String profissional;

  /// Link assinado recém-gerado, para o "Abrir em nova aba". Nulo ao reabrir (já expirou).
  final String? url;

  @override
  Widget build(BuildContext context) {
    final altura = MediaQuery.sizeOf(context).height * 0.62;
    return CorpoModal(
      titulo: '$titulo · $profissional',
      consequencia: 'Use a roda do mouse ou a pinça para dar zoom. A visualização foi gravada na auditoria.',
      filhos: [
        ClipRRect(
          borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
          child: Container(
            height: altura,
            color: CoresTrato.fundoSelecionado,
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image(
                  image: imagem,
                  fit: BoxFit.contain,
                  semanticLabel: titulo,
                  loadingBuilder: (context, filho, progresso) => progresso == null
                      ? filho
                      : Semantics(
                          label: 'Carregando documento',
                          child: const BlocoEsqueleto(largura: double.infinity, altura: double.infinity),
                        ),
                  errorBuilder: (context, _, _) => Padding(
                    padding: const EdgeInsets.all(EspacosTrato.x6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined, size: 36, color: CoresTrato.textoMudo),
                        const SizedBox(height: EspacosTrato.x2),
                        Text(
                          'Não deu para mostrar o arquivo aqui.',
                          style: TipografiaTrato.corpo,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: EspacosTrato.x2),
                        if (url case final link?)
                          BotaoTrato.link(
                            'Abrir em nova aba',
                            aoPressionar: () => launchUrl(Uri.parse(link), webOnlyWindowName: '_blank'),
                          )
                        else
                          Text('Feche e use "Ver de novo" para gerar outro link.', style: TipografiaTrato.legenda),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      acoes: [BotaoTrato.secundario('Fechar', aoPressionar: () => Navigator.of(context).pop())],
    );
  }
}
