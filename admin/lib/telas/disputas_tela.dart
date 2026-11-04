import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/api_admin.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.2 — fila de disputas (RF-DIS-01 a RF-DIS-04).
class DisputasTela extends StatelessWidget {
  const DisputasTela({super.key});

  static (String, Tom) chip(Disputa d) {
    if (d.status == StatusDisputa.decidida) return ('Decidida', Tom.ok);
    if (d.status == StatusDisputa.aguardandoSegundaPessoa) return ('Aguardando segunda pessoa', Tom.alerta);
    if (d.atrasada) return ('Prazo vencendo', Tom.erro);
    final perto = d.decisaoAte.difference(DateTime.now()).inHours < 24;
    if (perto && d.status != StatusDisputa.aguardandoProfissional) return ('Prazo vencendo', Tom.alerta);
    return switch (d.status) {
      StatusDisputa.aberta => ('Aberta', Tom.info),
      StatusDisputa.aguardandoProfissional => ('Aguardando resposta', Tom.alerta),
      StatusDisputa.emAnalise => ('Em análise', Tom.info),
      _ => ('Em análise', Tom.info),
    };
  }

  /// "Resposta em 31 h" enquanto o profissional não respondeu; depois, "Decisão em 3 dias".
  static String prazo(Disputa d) {
    if (d.status == StatusDisputa.decidida) return 'Decidida';
    if (d.status == StatusDisputa.aguardandoProfissional && d.respostaAte != null) {
      return 'Resposta em ${formatarRestante(d.respostaAte!)}';
    }
    return 'Decisão em ${formatarRestante(d.decisaoAte)}';
  }

  static String tituloDe(Disputa d) => d.titulo.isNotEmpty ? d.titulo : d.motivo;

  /// "Prazos vigentes em Configurações: resposta em 48 horas, decisão em 5 dias úteis."
  static Future<String?> _prazosVigentes(ApiAdmin api) async {
    try {
      final c = await api.carregarConfig();
      final vigente = c.versoes.where((v) => v.status == StatusVersao.vigente).firstOrNull;
      if (vigente == null) return null;
      final resp = vigente.valores['prazo_resposta_disputa_horas'];
      final dec = vigente.valores['prazo_decisao_disputa_dias_uteis'];
      if (resp == null || dec == null) return null;
      return 'Prazos vigentes em Configurações: resposta em ${formatarConfig(resp, 'horas')}, '
          'decisão em ${formatarConfig(dec, 'dias_uteis')}.';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CarregaDados<(List<Disputa>, String?)>(
      esqueleto: const EsqueletoPagina(),
      carregar: () async {
        final api = context.api;
        final lista = await api.listarDisputas();
        final prazos = await _prazosVigentes(api);
        return (lista, prazos);
      },
      estaVazio: (d) => d.$1.isEmpty,
      mensagemVazia: 'Nenhuma disputa aberta.',
      detalheVazio: 'Quando um cliente relatar problema, ele aparece aqui com o prazo de resposta.',
      construir: (context, dados, recarregar) => _FilaDisputas(lista: dados.$1, prazos: dados.$2, aoMudar: recarregar),
    );
  }
}

class _FilaDisputas extends StatefulWidget {
  const _FilaDisputas({required this.lista, required this.prazos, required this.aoMudar});
  final List<Disputa> lista;
  final String? prazos;
  final Future<void> Function() aoMudar;

  @override
  State<_FilaDisputas> createState() => _FilaDisputasState();
}

class _FilaDisputasState extends State<_FilaDisputas> {
  String _filtro = 'abertas';

  @override
  Widget build(BuildContext context) {
    final abertas = widget.lista.where((d) => d.status != StatusDisputa.decidida).length;
    final itens = [
      for (final d in widget.lista)
        if (_filtro == 'todas' || (_filtro == 'abertas') == (d.status != StatusDisputa.decidida)) d,
    ]..sort((a, b) => a.decisaoAte.compareTo(b.decisaoAte)); // o prazo mais curto primeiro

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina('Disputas', subtitulo: widget.prazos ?? 'Problemas relatados em serviços'),
        Expanded(
          child: MestreDetalhe<Disputa>(
            itens: itens,
            mensagemSemItens: 'Nenhuma disputa com esse filtro.',
            tituloDetalhe: DisputasTela.tituloDe,
            topo: FiltroStatus(
              opcoes: [
                ('abertas', 'Abertas', abertas),
                ('decididas', 'Decididas', widget.lista.length - abertas),
                ('todas', 'Todas', widget.lista.length),
              ],
              selecionado: _filtro,
              aoMudar: (v) => setState(() => _filtro = v),
            ),
            itemBuilder: (context, d, sel) {
              final (texto, tom) = DisputasTela.chip(d);
              return CartaoLista(
                titulo: DisputasTela.tituloDe(d),
                linhas: [
                  '${d.pedido} · ${d.cliente} × ${d.profissional}',
                  DisputasTela.prazo(d),
                  'Retido ${formatarReais(d.valorEmAnaliseCentavos)}',
                ],
                chips: [ChipEstado(texto, tom: tom)],
                selecionado: sel,
              );
            },
            detalheBuilder: (context, d) => DetalheDisputa(key: ValueKey(d.id), disputa: d, aoMudar: widget.aoMudar),
          ),
        ),
      ],
    );
  }
}

class DetalheDisputa extends StatefulWidget {
  const DetalheDisputa({super.key, required this.disputa, required this.aoMudar});

  final Disputa disputa;
  final Future<void> Function() aoMudar;

  @override
  State<DetalheDisputa> createState() => _DetalheDisputaState();
}

class _DetalheDisputaState extends State<DetalheDisputa> {
  DecisaoDisputa? _decisao;
  final _valor = TextEditingController();
  final _justificativa = TextEditingController();
  bool _tentou = false;
  bool _enviando = false;

  @override
  void dispose() {
    _valor.dispose();
    _justificativa.dispose();
    super.dispose();
  }

  /// Valor que a decisão movimenta, só para decidir se mostra o aviso da segunda pessoa.
  /// Quem confere a alçada de verdade é o backend.
  int? get _valorDaDecisao => switch (_decisao) {
        DecisaoDisputa.reembolsoTotal => widget.disputa.valorEmAnaliseCentavos,
        DecisaoDisputa.reembolsoParcial => lerReaisEmCentavos(_valor.text),
        DecisaoDisputa.liberarTudo => widget.disputa.valorEmAnaliseCentavos,
        _ => null,
      };

  bool get _acimaDaAlcada => (_valorDaDecisao ?? 0) > (context.eu?.alcadaCentavos ?? 0);

  String? get _erroValor {
    if (_decisao != DecisaoDisputa.reembolsoParcial) return null;
    final v = lerReaisEmCentavos(_valor.text);
    if (v == null || v <= 0) return 'Informe o valor do reembolso.';
    if (v > widget.disputa.valorEmAnaliseCentavos) return 'O valor passa do que está em análise.';
    return null;
  }

  String get _verbo {
    if (_acimaDaAlcada) return 'Enviar para aprovação';
    return switch (_decisao) {
      DecisaoDisputa.reembolsoTotal => 'Reembolsar cliente',
      DecisaoDisputa.reembolsoParcial => 'Reembolsar em parte',
      DecisaoDisputa.liberarTudo => 'Liberar ao profissional',
      DecisaoDisputa.novaVisita => 'Pedir nova visita',
      null => 'Registrar decisão',
    };
  }

  Future<void> _registrar() async {
    setState(() => _tentou = true);
    final semJustificativa = _justificativa.text.trim().length < kMotivoMinimo;
    if (_decisao == null || _erroValor != null || semJustificativa) return;
    setState(() => _enviando = true);
    final api = context.api;
    try {
      final r = await api.decidirDisputa(
        widget.disputa.id,
        decisao: _decisao!,
        valorReembolsoCentavos: _decisao == DecisaoDisputa.reembolsoParcial ? lerReaisEmCentavos(_valor.text) : null,
        justificativa: _justificativa.text.trim(),
      );
      if (mounted) {
        final n = api.ultimoRegistroAuditoria;
        mostrarAviso(
          context,
          r.mensagem ?? 'Decisão registrada.',
          detalhe: n == null ? null : 'Registro de auditoria nº ${formatarMilhar(n)}',
        );
      }
      await widget.aoMudar();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.disputa;
    final (textoChip, tomChip) = DisputasTela.chip(d);
    final podeDecidir = context.pode(Permissao.disputasDecidir) &&
        d.status != StatusDisputa.decidida &&
        d.status != StatusDisputa.aguardandoSegundaPessoa;
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(DisputasTela.tituloDe(d), style: TipografiaTrato.titulo)),
            ChipEstado(textoChip, tom: tomChip),
          ],
        ),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          'Pedido ${d.pedido} · cliente ${d.cliente} · profissional ${d.profissional}',
          style: TipografiaTrato.subtitulo,
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (d.status != StatusDisputa.decidida)
          BannerInfo(
            'O repasse de ${formatarReais(d.valorEmAnaliseCentavos)} ao profissional só sai depois que a '
            'disputa for resolvida.',
            titulo: 'Valor congelado até a decisão.',
            tom: Tom.alerta,
            icone: IconesTrato.travar,
          ),
        const SizedBox(height: EspacosTrato.x4),
        Linha('Motivo', d.motivo),
        Linha('Retido', formatarReais(d.valorEmAnaliseCentavos)),
        Linha('Decisão até', formatarData(d.decisaoAte)),
        if (d.respostaAte != null) Linha('Resposta até', formatarData(d.respostaAte!)),
        if (d.descricao.isNotEmpty && d.descricao != d.motivo) Linha('Relato', d.descricao),
        if (d.decisao != null) Linha('Decisão', d.decisao!.rotulo),
        const SizedBox(height: EspacosTrato.x5),
        Text('Linha do tempo', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        if (d.linhaDoTempo.isEmpty)
          Text('Ainda sem eventos.', style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo))
        else
          for (final e in d.linhaDoTempo)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: EspacosTrato.x2),
                    child: Icon(Icons.circle, size: 8, color: CoresTrato.bordaSelecionada),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.texto, style: TipografiaTrato.corpo),
                        Text('${formatarData(e.quando)} · ${e.autor}', style: TipografiaTrato.legenda),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: EspacosTrato.x5),
        Text('Evidências', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        if (d.evidencias.isEmpty)
          Text('Nenhuma evidência anexada.', style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo))
        else
          Wrap(
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            children: [for (final e in d.evidencias) _CartaoEvidencia(e)],
          ),
        if (podeDecidir)
          ..._formulario(d)
        else if (d.status == StatusDisputa.aguardandoSegundaPessoa)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x4),
            child: _AprovacaoSegundaPessoa(disputa: d, aoMudar: widget.aoMudar),
          )
        else if (!context.pode(Permissao.disputasDecidir))
          const Padding(
            padding: EdgeInsets.only(top: EspacosTrato.x4),
            child: BannerInfo('Seu papel acompanha a disputa, mas não decide.'),
          ),
      ],
    );
  }

  List<Widget> _formulario(Disputa d) {
    final alcada = context.eu?.alcadaCentavos ?? 0;
    return [
      const SizedBox(height: EspacosTrato.x6),
      const Divider(),
      const SizedBox(height: EspacosTrato.x4),
      Text('Decisão', style: TipografiaTrato.secao),
      const SizedBox(height: EspacosTrato.x3),
      Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          for (final op in DecisaoDisputa.values)
            ChoiceChip(
              label: Text(op.rotulo),
              selected: _decisao == op,
              onSelected: (_) => setState(() => _decisao = op),
              labelStyle: TipografiaTrato.etiqueta,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      if (_tentou && _decisao == null)
        Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x1),
          child: Text('Escolha uma decisão.', style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto)),
        ),
      if (_decisao == DecisaoDisputa.reembolsoParcial) ...[
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _valor,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Valor do reembolso (R\$)',
            prefixText: 'R\$ ',
            helperText: 'Até ${formatarReais(d.valorEmAnaliseCentavos)}.',
            errorText: _tentou ? _erroValor : null,
          ),
        ),
      ],
      const SizedBox(height: EspacosTrato.x3),
      TextField(
        controller: _justificativa,
        minLines: 3,
        maxLines: 5,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Motivo',
          helperText: _justificativa.text.trim().isEmpty
              ? 'Pelo menos $kMotivoMinimo caracteres · fica registrado na auditoria'
              : '${_justificativa.text.trim().length} de $kMotivoMinimo caracteres mínimos · as partes recebem a decisão',
          errorText: _tentou && _justificativa.text.trim().length < kMotivoMinimo
              ? 'Escreva ao menos $kMotivoMinimo caracteres'
              : null,
        ),
      ),
      if (_acimaDaAlcada) ...[
        const SizedBox(height: EspacosTrato.x3),
        BannerInfo(
          'Este valor passa da sua alçada (${alcada > 0 ? formatarReais(alcada) : 'Sem alçada financeira'}). '
          'A decisão fica aguardando outra pessoa (líder de suporte ou administrador), que aprova com a própria conta.',
          tom: Tom.alerta,
          icone: Icons.supervisor_account_outlined,
        ),
      ],
      const SizedBox(height: EspacosTrato.x4),
      const AvisoAuditoria(),
      const SizedBox(height: EspacosTrato.x3),
      Align(
        alignment: Alignment.centerRight,
        child: BotaoTrato.primario(
          _verbo,
          aoPressionar: _enviando ? null : _registrar,
          carregando: _enviando,
          rotuloCarregando: 'Registrando',
        ),
      ),
    ];
  }
}

class _CartaoEvidencia extends StatelessWidget {
  const _CartaoEvidencia(this.e);
  final EvidenciaDisputa e;

  @override
  Widget build(BuildContext context) {
    final icone = e.nota
        ? IconesTrato.travar
        : switch (e.tipo) {
            'foto' => Icons.image_outlined,
            'documento' => Icons.description_outlined,
            _ => Icons.chat_bubble_outline,
          };
    return Container(
      width: 240,
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(
        color: e.nota ? CoresTrato.avisoFundo : CoresTrato.fundoPagina,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        border: Border.all(color: CoresTrato.bordaSuave),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: CoresTrato.textoMudo),
          const SizedBox(width: EspacosTrato.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.texto, style: TipografiaTrato.corpo),
                Text(
                  '${e.autor} · ${e.nota ? 'nota interna (só equipe)' : e.tipo}',
                  style: TipografiaTrato.legenda,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Decisão acima da alçada: outra pessoa (líder ou administrador) aprova com a própria conta.
class _AprovacaoSegundaPessoa extends StatelessWidget {
  const _AprovacaoSegundaPessoa({required this.disputa, required this.aoMudar});

  final Disputa disputa;
  final Future<void> Function() aoMudar;

  Future<void> _aprovar(BuildContext context) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Aprovar a decisão?',
      descricao: 'Você confirma a decisão de outra pessoa. Quem decidiu não pode aprovar a própria decisão.',
      rotuloConfirmar: 'Aprovar decisão',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(context, () async {
      await api.aprovarDisputa(disputa.id, justificativa: motivo);
    }, sucesso: 'Decisão aprovada.');
    if (ok) await aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final pode = context.pode(Permissao.disputasSegundaPessoa);
    final propria = disputa.decididoPor != null && disputa.decididoPor == context.eu?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerInfo('Decisão acima da alçada: falta a aprovação de uma segunda pessoa.', tom: Tom.alerta),
        if (pode && !propria) ...[
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
          const SizedBox(height: EspacosTrato.x3),
          Align(
            alignment: Alignment.centerRight,
            child: BotaoTrato.primario('Aprovar decisão', aoPressionar: () => _aprovar(context)),
          ),
        ],
      ],
    );
  }
}
