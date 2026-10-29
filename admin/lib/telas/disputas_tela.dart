import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.2 — fila de disputas (suporte e análise de problemas).
class DisputasTela extends StatelessWidget {
  const DisputasTela({super.key});

  static (String, Tom) _chip(StatusDisputa s) => switch (s) {
        StatusDisputa.aberta => ('Aberta', Tom.info),
        StatusDisputa.aguardandoProfissional => ('Aguardando profissional', Tom.alerta),
        StatusDisputa.emAnalise => ('Em análise', Tom.info),
        StatusDisputa.aguardandoSegundaPessoa => ('Aguardando segunda pessoa', Tom.alerta),
        StatusDisputa.decidida => ('Decidida', Tom.ok),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CabecalhoPagina('Disputas', subtitulo: 'Problemas relatados em serviços'),
        Expanded(
          child: CarregaDados<List<Disputa>>(
            carregar: context.api.listarDisputas,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhuma disputa aberta.',
            construir: (context, lista, recarregar) => MestreDetalhe<Disputa>(
              itens: lista,
              tituloDetalhe: (d) => d.pedido,
              itemBuilder: (context, d, sel) {
                final (texto, tom) = _chip(d.status);
                return CartaoItem(
                  titulo: '${d.pedido} · ${d.motivo}',
                  linhas: ['${d.cliente} × ${d.profissional}', 'Em análise: ${formatarReais(d.valorEmAnaliseCentavos)}'],
                  chip: ChipEstado(texto, tom: tom),
                  selecionado: sel,
                );
              },
              detalheBuilder: (context, d) => DetalheDisputa(key: ValueKey(d.id), disputa: d, aoMudar: recarregar),
            ),
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
  final _segunda = TextEditingController();
  bool _tentou = false;
  bool _enviando = false;

  @override
  void dispose() {
    _valor.dispose();
    _justificativa.dispose();
    _segunda.dispose();
    super.dispose();
  }

  /// Valor que a decisão movimenta, só para decidir se mostra o campo da segunda pessoa.
  /// Quem confere a alçada de verdade é o backend.
  int? get _valorDaDecisao => switch (_decisao) {
        DecisaoDisputa.reembolsoTotal => widget.disputa.valorEmAnaliseCentavos,
        DecisaoDisputa.reembolsoParcial => lerReaisEmCentavos(_valor.text),
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

  Future<void> _registrar() async {
    setState(() => _tentou = true);
    final semJustificativa = _justificativa.text.trim().length < kMotivoMinimo;
    final semSegunda = _acimaDaAlcada && !_segunda.text.contains('@');
    if (_decisao == null || _erroValor != null || semJustificativa || semSegunda) return;
    setState(() => _enviando = true);
    final api = context.api;
    try {
      final r = await api.decidirDisputa(
        widget.disputa.id,
        decisao: _decisao!,
        valorReembolsoCentavos: _decisao == DecisaoDisputa.reembolsoParcial ? lerReaisEmCentavos(_valor.text) : null,
        justificativa: _justificativa.text.trim(),
        segundaPessoaEmail: _acimaDaAlcada ? _segunda.text.trim() : null,
      );
      if (mounted && r.mensagem != null) mostrarAviso(context, r.mensagem!);
      await widget.aoMudar();
    } catch (e) {
      if (mounted) mostrarAviso(context, e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.disputa;
    final podeDecidir = context.pode(Permissao.disputasDecidir) &&
        d.status != StatusDisputa.decidida &&
        d.status != StatusDisputa.aguardandoSegundaPessoa;
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text('${d.pedido} · ${d.motivo}', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Cliente', d.cliente),
        Linha('Profissional', d.profissional),
        Linha('Em análise', formatarReais(d.valorEmAnaliseCentavos)),
        Linha('Decisão até', formatarData(d.decisaoAte)),
        Linha('Relato', d.descricao),
        if (d.decisao != null) Linha('Decisão', d.decisao!.rotulo),
        const SizedBox(height: EspacosTrato.x4),
        Text('Evidências', style: TipografiaTrato.tituloCartao),
        const SizedBox(height: EspacosTrato.x2),
        for (final e in d.evidencias)
          Card(
            margin: const EdgeInsets.only(bottom: EspacosTrato.x2),
            child: ListTile(
              leading: Icon(e.nota ? Icons.lock_outline : Icons.attach_file),
              title: Text(e.texto),
              subtitle: Text('${e.autor} · ${e.nota ? 'nota interna (só equipe)' : e.tipo}'),
            ),
          ),
        const SizedBox(height: EspacosTrato.x4),
        Text('Linha do tempo', style: TipografiaTrato.tituloCartao),
        const SizedBox(height: EspacosTrato.x2),
        for (final e in d.linhaDoTempo)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: EspacosTrato.x2),
                  child: Icon(Icons.circle, size: 8, color: CoresTrato.azulTexto),
                ),
                Expanded(
                  child: Text('${formatarData(e.quando)} · ${e.autor}: ${e.texto}', style: TipografiaTrato.corpoPequeno),
                ),
              ],
            ),
          ),
        if (podeDecidir) ..._formulario(d) else if (d.status == StatusDisputa.aguardandoSegundaPessoa)
          const Padding(
            padding: EdgeInsets.only(top: EspacosTrato.x4),
            child: BannerInfo('Decisão acima da alçada: falta a aprovação da segunda pessoa.', tom: Tom.alerta),
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
      const Divider(height: EspacosTrato.x8),
      Text('Decidir', style: TipografiaTrato.tituloCartao),
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
            ),
        ],
      ),
      if (_tentou && _decisao == null)
        Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x1),
          child: Text('Escolha uma decisão.', style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto)),
        ),
      if (_decisao == DecisaoDisputa.reembolsoParcial) ...[
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _valor,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Valor do reembolso (R\$)',
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
          labelText: 'Justificativa (obrigatória)',
          helperText: 'Pelo menos $kMotivoMinimo caracteres. As partes recebem a decisão.',
          errorText: _tentou && _justificativa.text.trim().length < kMotivoMinimo ? 'Explique a decisão.' : null,
        ),
      ),
      if (_acimaDaAlcada) ...[
        const SizedBox(height: EspacosTrato.x3),
        BannerInfo(
          'Este valor passa da sua alçada (${formatarReais(alcada)}). Outra pessoa precisa aprovar '
          '(líder de suporte ou administrador).',
          tom: Tom.alerta,
          icone: Icons.supervisor_account_outlined,
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _segunda,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'E-mail da segunda pessoa',
            errorText: _tentou && !_segunda.text.contains('@') ? 'Informe quem vai aprovar.' : null,
          ),
        ),
      ],
      const SizedBox(height: EspacosTrato.x4),
      const AvisoAuditoria(),
      const SizedBox(height: EspacosTrato.x3),
      FilledButton(
        onPressed: _enviando ? null : _registrar,
        child: Text(_acimaDaAlcada ? 'Enviar para aprovação' : 'Registrar decisão'),
      ),
    ];
  }
}
