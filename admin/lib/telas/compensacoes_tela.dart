import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'compensacoes_modal.dart';

const _status = {'aberta': 'Aberta', 'quitada': 'Quitada', 'cancelada': 'Cancelada'};

const _origens = {
  'disputa': 'Decisão de disputa',
  'disputa_contestacao': 'Decisão mudada por contestação',
  'regresso': 'Regresso',
};

(String, Tom) _chip(String s) => (
      _status[s] ?? s,
      switch (s) { 'aberta' => Tom.alerta, 'quitada' => Tom.ok, _ => Tom.neutro },
    );

/// Compensações (Termos 8.6): reembolso descontado de repasses futuros do profissional. O painel
/// não calcula nada: valor, descontado, restante e devolvido vêm do backend.
class CompensacoesTela extends StatefulWidget {
  const CompensacoesTela({super.key});

  @override
  State<CompensacoesTela> createState() => _CompensacoesTelaState();
}

class _CompensacoesTelaState extends State<CompensacoesTela> {
  String _profissional = '';
  String _pedido = '';
  String? _situacao;
  int _versao = 0;

  Future<void> _registrar() async {
    await abrirRegistroDeCompensacao(context);
    // Mesmo em erro ou desistência a lista é relida: o servidor é quem sabe o que ficou.
    if (mounted) setState(() => _versao++);
  }

  Widget _campo(String rotulo, ValueChanged<String> aoBuscar) => SizedBox(
        width: 230,
        child: TextField(
          decoration: InputDecoration(labelText: rotulo, helperText: 'Enter para buscar'),
          onSubmitted: (v) => setState(() => aoBuscar(v.trim())),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          _campo('Código do profissional', (v) => _profissional = v),
          _campo('Código do pedido', (v) => _pedido = v),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              initialValue: _situacao,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in _status.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _situacao = v),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Compensações',
          subtitulo: 'Reembolso descontado de repasses futuros (Termos 8.6)',
          acoes: [BotaoTrato.primario('Registrar compensação', aoPressionar: _registrar)],
        ),
        Expanded(
          child: FilaRemota<Compensacao>(
            key: ValueKey('fila-compensacoes-$_versao'),
            filtro: (_profissional, _pedido, _situacao),
            esqueleto: const EsqueletoPagina(),
            chave: (c) => c.id,
            carregar: (deslocamento, limite) => context.api.listarCompensacoes(
              profissionalId: _profissional.isEmpty ? null : _profissional,
              pedidoId: _pedido.isEmpty ? null : _pedido,
              status: _situacao,
              deslocamento: deslocamento,
              limite: limite,
            ),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<Compensacao>(
                      itens: fila.itens,
                      chave: (c) => c.id,
                      mensagemSemItens: 'Nenhuma compensação com esse filtro.',
                      tituloDetalhe: (c) => formatarReais(c.valorCentavos),
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'compensações'),
                      itemBuilder: (context, c, sel) {
                        final (texto, tom) = _chip(c.status);
                        return CartaoLista(
                          titulo: '${formatarReais(c.valorCentavos)} · falta ${formatarReais(c.restanteCentavos)}',
                          linhas: ['Pedido ${c.pedidoId}', 'Criada em ${formatarData(c.criadaEm)}'],
                          chips: [
                            ChipEstado(texto, tom: tom),
                            if (c.avisadoEm == null && c.status == 'aberta')
                              const ChipEstado('Sem aviso', tom: Tom.erro),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, c) =>
                          _DetalheCompensacao(key: ValueKey(c.id), inicial: c, aoMudar: fila.recarregar),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetalheCompensacao extends StatefulWidget {
  const _DetalheCompensacao({super.key, required this.inicial, required this.aoMudar});
  final Compensacao inicial;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheCompensacao> createState() => _DetalheCompensacaoState();
}

class _DetalheCompensacaoState extends State<_DetalheCompensacao> {
  /// O que o servidor devolveu na última ação (não há rota de detalhe).
  Compensacao? _atual;
  bool _enviando = false;
  String? _erro;

  @override
  void didUpdateWidget(covariant _DetalheCompensacao antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.inicial != widget.inicial) _atual = null;
  }

  Future<void> _enviar(Future<(Compensacao, String, bool)> Function() chamada) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final (nova, mensagem, atencao) = await chamada();
      if (mounted) {
        setState(() => _atual = nova);
        mostrarAviso(context, mensagem, erro: atencao);
      }
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      try {
        await widget.aoMudar();
      } catch (_) {
        // A releitura da lista falhou: o resultado da ação já está na tela.
      }
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _avisar(Compensacao c) async {
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Avisar o profissional?',
      texto: 'Ele recebe o aviso da compensação de ${formatarReais(c.valorCentavos)} com o motivo. '
          'Depois do aviso, os próximos repasses podem ser descontados.',
      verbo: 'Enviar aviso',
    );
    if (!ok || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final r = await api.avisarCompensacao(c.id);
      return (
        r.compensacao,
        r.avisado ? 'Profissional avisado.' : 'O aviso não saiu. Sem aviso, nada é descontado.',
        !r.avisado,
      );
    });
  }

  Future<void> _cancelar(Compensacao c) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Cancelar a compensação?',
      descricao: 'Use quando a contestação do profissional foi aceita. O que já foi descontado '
          '(${formatarReais(c.compensadoCentavos)} até agora) volta a ele, que é avisado. Não dá para desfazer.',
      rotuloConfirmar: 'Cancelar compensação',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final r = await api.cancelarCompensacao(c.id, motivo: motivo);
      return (
        r.compensacao,
        r.resultado == 'ja_cancelada'
            ? 'Esta compensação já estava cancelada. Devolvido: ${formatarReais(r.devolvidoCentavos)}.'
            : 'Compensação cancelada. Devolvido ao profissional: ${formatarReais(r.devolvidoCentavos)}.',
        false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _atual ?? widget.inicial;
    final (texto, tom) = _chip(c.status);
    final semAviso = c.avisadoEm == null && c.status == 'aberta';
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(formatarReais(c.valorCentavos), style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(spacing: EspacosTrato.x2, children: [ChipEstado(texto, tom: tom)]),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Já descontado', formatarReais(c.compensadoCentavos)),
        Linha('Falta descontar', formatarReais(c.restanteCentavos)),
        Linha('Pedido', c.pedidoId),
        Linha('Origem', _origens[c.origem] ?? c.origem),
        Linha('Motivo (o profissional lê)', c.motivo),
        Linha('Criada em', formatarData(c.criadaEm)),
        Linha('Aviso', c.avisadoEm == null ? 'Não enviado' : 'Enviado em ${formatarData(c.avisadoEm!)}'),
        if (c.canceladaEm != null) Linha('Cancelada em', formatarData(c.canceladaEm!)),
        if (c.motivoCancelamento != null) Linha('Motivo do cancelamento', c.motivoCancelamento!),
        if (semAviso) ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo('Sem aviso, nada é descontado.', tom: Tom.alerta),
        ],
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            if (semAviso && context.pode(Permissao.regressoPropor))
              BotaoTrato.primario('Avisar profissional', aoPressionar: _enviando ? null : () => _avisar(c)),
            if (c.status != 'cancelada' && context.pode(Permissao.compensacoesCancelar))
              BotaoTrato.destrutivo('Cancelar compensação', aoPressionar: _enviando ? null : () => _cancelar(c)),
          ],
        ),
        if (c.status != 'cancelada' && !context.pode(Permissao.compensacoesCancelar))
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Text('Cancelar é só para líder de suporte e administrador.', style: TipografiaTrato.legenda),
          ),
      ],
    );
  }
}
