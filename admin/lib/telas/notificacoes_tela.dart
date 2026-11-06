import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

const _tituloMax = 50;
const _mensagemMax = 140;

String rotuloSegmento(String s) => switch (s) {
      'todos' => 'Todos os ativos',
      'clientes' => 'Só clientes',
      'profissionais' => 'Só profissionais',
      'cidade' => 'Por cidade',
      'categoria' => 'Por categoria',
      final outro => outro,
    };

/// Notificações push (RF-COM-01 a RF-COM-04): prévia, estimativa de destinatários e histórico.
class NotificacoesTela extends StatefulWidget {
  const NotificacoesTela({super.key});

  @override
  State<NotificacoesTela> createState() => _NotificacoesTelaState();
}

class _NotificacoesTelaState extends State<NotificacoesTela> {
  int _versao = 0;

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Notificações push',
          subtitulo: 'Antes de enviar, confira a prévia e a quantidade de destinatários.',
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x6),
            children: [
              _NovaCampanha(aoEnviar: () => setState(() => _versao++)),
              const SizedBox(height: EspacosTrato.x5),
              Text('Histórico', style: TipografiaTrato.secao),
              const SizedBox(height: EspacosTrato.x3),
              SizedBox(
                height: 360,
                child: CarregaDados<List<CampanhaNotificacao>>(
                  key: ValueKey('campanhas-$_versao'),
                  carregar: context.api.listarCampanhasNotificacao,
                  estaVazio: (l) => l.isEmpty,
                  mensagemVazia: 'Nenhuma campanha enviada',
                  detalheVazio: 'As campanhas enviadas aparecem aqui com entregues e abertos.',
                  construir: (context, lista, _) => _Historico(lista),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NovaCampanha extends StatefulWidget {
  const _NovaCampanha({required this.aoEnviar});
  final VoidCallback aoEnviar;

  @override
  State<_NovaCampanha> createState() => _NovaCampanhaState();
}

class _NovaCampanhaState extends State<_NovaCampanha> {
  final _titulo = TextEditingController();
  final _mensagem = TextEditingController();
  final _motivo = TextEditingController();
  String _tipo = 'marketing';
  String _segmento = 'todos';
  String? _cidadeId;
  String? _categoriaId;
  List<CidadeAdmin> _cidades = const [];
  List<CategoriaAdmin> _categorias = const [];
  Future<EstimativaCampanha>? _estimativa;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final api = context.api;
      try {
        final c = await api.listarCidades();
        final k = await api.listarCategorias();
        if (mounted) {
          setState(() {
            _cidades = c;
            _categorias = k;
          });
        }
      } catch (_) {
        // sem cidades/categorias o segmento "por cidade/categoria" só não fica disponível
      }
      _atualizarEstimativa();
    });
  }

  @override
  void dispose() {
    _titulo.dispose();
    _mensagem.dispose();
    _motivo.dispose();
    super.dispose();
  }

  bool get _segmentoCompleto =>
      (_segmento != 'cidade' || _cidadeId != null) && (_segmento != 'categoria' || _categoriaId != null);

  void _atualizarEstimativa() {
    if (!mounted || !_segmentoCompleto) {
      setState(() => _estimativa = null);
      return;
    }
    setState(() {
      _estimativa = context.api.estimarCampanhaNotificacao(
        segmento: _segmento,
        tipo: _tipo,
        categoriaId: _categoriaId,
        cidadeId: _cidadeId,
      );
    });
  }

  bool get _valida =>
      _titulo.text.trim().length >= 3 &&
      _mensagem.text.trim().length >= 5 &&
      _motivo.text.trim().length >= kMotivoMinimo &&
      _segmentoCompleto;

  Future<void> _revisar() async {
    final api = context.api;
    final confirmou = await mostrarModal<bool>(
      context,
      construir: (ctx) => CorpoModal(
        titulo: 'Enviar esta campanha?',
        consequencia: 'O envio não pode ser desfeito: as pessoas recebem a notificação na hora.',
        filhos: [
          Linha('Tipo', _tipo == 'marketing' ? 'Marketing' : 'Operacional'),
          Linha('Segmento', rotuloSegmento(_segmento)),
          Linha('Título', _titulo.text.trim()),
          Linha('Mensagem', _mensagem.text.trim()),
          const SizedBox(height: EspacosTrato.x2),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(ctx).pop(false)),
          BotaoTrato.primario('Enviar campanha', aoPressionar: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    setState(() => _enviando = true);
    final ok = await executar(
      context,
      () => api.dispararCampanhaNotificacao(
        titulo: _titulo.text.trim(),
        mensagem: _mensagem.text.trim(),
        segmento: _segmento,
        tipo: _tipo,
        categoriaId: _categoriaId,
        cidadeId: _cidadeId,
        motivo: _motivo.text.trim(),
      ),
      sucesso: 'Campanha enviada.',
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (ok) {
      _titulo.clear();
      _mensagem.clear();
      _motivo.clear();
      widget.aoEnviar();
      _atualizarEstimativa();
    }
  }

  Widget _cartaoTipo(String valor, String titulo, String descricao) {
    final ativo = _tipo == valor;
    return Expanded(
      child: Semantics(
        selected: ativo,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
          onTap: () {
            setState(() => _tipo = valor);
            _atualizarEstimativa();
          },
          child: Container(
            padding: const EdgeInsets.all(EspacosTrato.x3),
            decoration: BoxDecoration(
              color: ativo ? CoresTrato.fundoSelecionado : CoresTrato.fundoSuperficie,
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
              border: Border.all(
                color: ativo ? CoresTrato.bordaSelecionada : CoresTrato.bordaSuave,
                width: ativo ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TipografiaTrato.corpoForte),
                Text(descricao, style: TipografiaTrato.legenda),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formulario = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cartaoTipo('operacional', 'Operacional', 'Andamento de serviço e avisos de conta'),
            const SizedBox(width: EspacosTrato.x3),
            _cartaoTipo('marketing', 'Marketing', 'Campanhas e novidades'),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        TextField(
          controller: _titulo,
          maxLength: _tituloMax,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Título',
            counterText: '${_titulo.text.length} de $_tituloMax caracteres',
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _mensagem,
          maxLength: _mensagemMax,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Mensagem',
            counterText: '${_mensagem.text.length} de $_mensagemMax caracteres',
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        SeletorTrato<String>(
          rotulo: 'Segmento',
          valor: _segmento,
          opcoes: [
            for (final s in ['todos', 'clientes', 'profissionais', 'cidade', 'categoria']) (s, rotuloSegmento(s)),
          ],
          aoMudar: (v) {
            setState(() {
              _segmento = v;
              _cidadeId = null;
              _categoriaId = null;
            });
            _atualizarEstimativa();
          },
        ),
        if (_segmento == 'cidade') ...[
          const SizedBox(height: EspacosTrato.x3),
          SeletorTrato<String>(
            rotulo: 'Cidade',
            valor: _cidadeId,
            opcoes: [for (final c in _cidades) (c.id, '${c.nome} - ${c.uf}')],
            aoMudar: (v) {
              setState(() => _cidadeId = v);
              _atualizarEstimativa();
            },
          ),
        ],
        if (_segmento == 'categoria') ...[
          const SizedBox(height: EspacosTrato.x3),
          SeletorTrato<String>(
            rotulo: 'Categoria',
            valor: _categoriaId,
            opcoes: [for (final c in _categorias) (c.id, c.nome)],
            aoMudar: (v) {
              setState(() => _categoriaId = v);
              _atualizarEstimativa();
            },
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Envio'),
          child: Text('Agora', style: TipografiaTrato.corpo),
        ),
        const SizedBox(height: EspacosTrato.x3),
        CampoMotivo(controle: _motivo, aoMudar: () => setState(() {}), rotulo: 'Motivo do disparo'),
        const SizedBox(height: EspacosTrato.x2),
        const AvisoAuditoria(),
      ],
    );

    final lateral = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PRÉVIA NO CELULAR', style: TipografiaTrato.sobretitulo),
        const SizedBox(height: EspacosTrato.x2),
        _Previa(titulo: _titulo.text.trim(), mensagem: _mensagem.text.trim()),
        const SizedBox(height: EspacosTrato.x4),
        Text('Destinatários estimados', style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo)),
        const SizedBox(height: EspacosTrato.x1),
        if (_estimativa == null)
          Text('Escolha o segmento', style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo))
        else
          FutureBuilder<EstimativaCampanha>(
            future: _estimativa,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              if (snap.hasError) return Text(snap.error.toString(), style: TipografiaTrato.legenda);
              final e = snap.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${formatarMilhar(e.destinatarios)} pessoas', style: TipografiaTrato.valor),
                  if (_tipo == 'marketing')
                    Text(
                      'Marketing respeita a preferência de cada usuário: ${formatarMilhar(e.desativaram)} '
                      'desativaram e não recebem.',
                      style: TipografiaTrato.legenda,
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: EspacosTrato.x4),
        BotaoTrato.primario(
          'Revisar e enviar',
          aoPressionar: _valida && !_enviando ? _revisar : null,
          carregando: _enviando,
          rotuloCarregando: 'Enviando',
        ),
      ],
    );

    return CartaoSecao(
      titulo: 'Nova campanha',
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 760) {
            return Column(children: [formulario, const SizedBox(height: EspacosTrato.x5), lateral]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: formulario),
              const SizedBox(width: EspacosTrato.x6),
              Expanded(flex: 2, child: lateral),
            ],
          );
        },
      ),
    );
  }
}

/// Como a notificação aparece no celular.
class _Previa extends StatelessWidget {
  const _Previa({required this.titulo, required this.mensagem});
  final String titulo;
  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(
        color: CoresTrato.fundoPagina,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        border: Border.all(color: CoresTrato.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: CoresTrato.primaria, borderRadius: BorderRadius.circular(5)),
                child: Text('T', style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoSobrePrimaria)),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Text('Trato', style: TipografiaTrato.legenda),
              const Spacer(),
              Text('agora', style: TipografiaTrato.legenda),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(titulo.isEmpty ? 'Título da notificação' : titulo, style: TipografiaTrato.corpoForte),
          Text(
            mensagem.isEmpty ? 'A mensagem aparece aqui.' : mensagem,
            style: TipografiaTrato.corpo.copyWith(color: titulo.isEmpty && mensagem.isEmpty ? CoresTrato.textoMudo : null),
          ),
        ],
      ),
    );
  }
}

class _Historico extends StatelessWidget {
  const _Historico(this.lista);
  final List<CampanhaNotificacao> lista;

  @override
  Widget build(BuildContext context) {
    final celular = FaixaPainel.de(context).ehCelular;
    String data(String iso) {
      final d = DateTime.tryParse(iso)?.toLocal();
      return d == null ? '—' : formatarDia(d);
    }

    if (celular) {
      return ListView.separated(
        itemCount: lista.length,
        separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.intervaloCartoes),
        itemBuilder: (context, i) {
          final c = lista[i];
          return CartaoLista(
            titulo: c.titulo,
            linhas: [
              '${data(c.criadoEm)} · ${c.autor ?? '—'} · ${rotuloSegmento(c.segmento)}',
              'Enviados ${formatarMilhar(c.enviados)} · entregues ${formatarMilhar(c.entregues)} · '
                  'abertos ${formatarMilhar(c.abertos)}',
            ],
            chips: [ChipPapel(c.tipo == 'marketing' ? 'Marketing' : 'Operacional')],
          );
        },
      );
    }
    Widget cel(String t, int flex, {bool direita = false, bool forte = false}) => Expanded(
          flex: flex,
          child: Text(
            t,
            textAlign: direita ? TextAlign.right : TextAlign.left,
            overflow: TextOverflow.ellipsis,
            style: forte ? TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo) : TipografiaTrato.numeroTabular,
          ),
        );
    return CartaoSecao(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
            child: Row(children: [
              cel('Campanha', 5, forte: true),
              cel('Data', 3, forte: true),
              cel('Autor', 3, forte: true),
              cel('Segmento', 3, forte: true),
              cel('Enviados', 2, direita: true, forte: true),
              cel('Entregues', 2, direita: true, forte: true),
              cel('Abertos', 2, direita: true, forte: true),
            ]),
          ),
          for (final c in lista)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Flexible(child: Text(c.titulo, style: TipografiaTrato.corpoForte, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: EspacosTrato.x2),
                        ChipPapel(c.tipo == 'marketing' ? 'Marketing' : 'Operacional'),
                      ],
                    ),
                  ),
                  cel(data(c.criadoEm), 3),
                  cel(c.autor ?? '—', 3),
                  cel(rotuloSegmento(c.segmento), 3),
                  cel(formatarMilhar(c.enviados), 2, direita: true),
                  cel(formatarMilhar(c.entregues), 2, direita: true),
                  cel(formatarMilhar(c.abertos), 2, direita: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
