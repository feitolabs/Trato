import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import 'modelos.dart';
import 'pecas.dart';
import 'recursos_mvp.dart';

/// Tela 16 — Serviço em execução. Centraliza acompanhamento, código, chat, contrato e aditivos.
class PedidoExecucaoTela extends StatefulWidget {
  const PedidoExecucaoTela({
    super.key,
    required this.pedido,
    this.aoAprovarAditivo,
    this.aoRecusarAditivo,
    this.aoTocarSos,
    this.aoConversar,
    this.aoVerConclusao,
    this.aoVerNota,
    this.aoVerAditivo,
    this.aoVerContrato,
    this.aoAbrirProblema,
    this.aoCancelarPedido,
    this.aoRemarcarVisita,
    this.aoPagar,
    this.aoAvaliar,
    this.aoVerGarantia,
    this.aoBaixarComprovante,
    this.aoRepetirServico,
    this.secaoReagendamento,
    this.aoCompartilharAtendimento,
    this.aoSosEmergencia,
    this.atualizarAditivoLocalmente = true,
  });

  /// Ação principal por estado: `Pagar` (orçamento aceito), `Avaliar` e `Ver garantia`
  /// (finalizado). `Confirmar serviço` usa [aoVerConclusao]. Sem o callback, a ação não aparece.
  final VoidCallback? aoPagar;
  final VoidCallback? aoAvaliar;
  final VoidCallback? aoVerGarantia;

  /// Baixa o comprovante (PDF) do pedido concluído. Só aparece com o pedido `concluido`.
  final VoidCallback? aoBaixarComprovante;

  /// "Repetir este serviço" (serviço recorrente): só no pedido `concluido`.
  final VoidCallback? aoRepetirServico;

  /// Reagendamento dentro do pedido (botão "Reagendar" ou proposta pendente). Quem monta a tela
  /// só passa nos estados pago/agendado.
  final Widget? secaoReagendamento;
  final VoidCallback? aoCompartilharAtendimento;
  final VoidCallback? aoSosEmergencia;

  final PedidoEmExecucao pedido;
  final VoidCallback? aoAprovarAditivo;
  final VoidCallback? aoRecusarAditivo;
  final VoidCallback? aoTocarSos;
  final VoidCallback? aoConversar;
  final VoidCallback? aoVerConclusao;

  /// Abrem a nota de materiais e o aditivo do pedido (quem liga as telas é o `rotas.dart`).
  final VoidCallback? aoVerNota;
  final VoidCallback? aoVerAditivo;
  final VoidCallback? aoVerContrato;
  final VoidCallback? aoAbrirProblema;
  final VoidCallback? aoCancelarPedido;
  final VoidCallback? aoRemarcarVisita;
  final bool atualizarAditivoLocalmente;

  @override
  State<PedidoExecucaoTela> createState() => _PedidoExecucaoTelaState();
}

class _PedidoExecucaoTelaState extends State<PedidoExecucaoTela> {
  late Aditivo? _aditivo = widget.pedido.aditivo;

  @override
  void didUpdateWidget(covariant PedidoExecucaoTela oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pedido.aditivo != oldWidget.pedido.aditivo) {
      _aditivo = widget.pedido.aditivo;
    }
  }

  String _textoResumoAtendimento(PedidoEmExecucao pedido) {
    final partes = <String>[
      'Atendimento Trato (${pedido.numero})',
      if ((pedido.profissionalNome ?? '').isNotEmpty) 'Profissional: ${pedido.profissionalNome}',
      if ((pedido.visita ?? '').isNotEmpty) 'Horário: ${pedido.visita}',
      if ((pedido.enderecoResumo ?? '').isNotEmpty) 'Endereço: ${pedido.enderecoResumo}',
    ];
    return partes.join('\n');
  }

  Future<void> _abrirResumoCompartilhamento(PedidoEmExecucao pedido) async {
    final resumo = _textoResumoAtendimento(pedido);
    await showModalBottomSheet<void>(
      context: context,
      builder: (folha) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EspacosTrato.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Compartilhar atendimento', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x3),
              Text(resumo, style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x4),
              BotaoPrimario(
                texto: 'Copiar resumo',
                aoTocar: () async {
                  await Clipboard.setData(ClipboardData(text: resumo));
                  if (folha.mounted) Navigator.of(folha).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirConfirmacaoSos(PedidoEmExecucao pedido) async {
    final resumo = _textoResumoAtendimento(pedido);
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('SOS / Emergência'),
        content: Text(
          'Se você estiver em risco, ligue para a polícia (190) ou copie os dados do atendimento para enviar a um contato de confiança.\n\n$resumo',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Fechar'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: resumo));
              if (dialogo.mounted) Navigator.of(dialogo).pop();
            },
            child: const Text('Copiar dados'),
          ),
        ],
      ),
    );
  }

  void _decidir(EstadoAditivo estado, VoidCallback? aviso) {
    if (widget.atualizarAditivoLocalmente) {
      setState(() => _aditivo = _aditivo?.comEstado(estado));
    }
    aviso?.call();
  }

  /// UMA ação principal por estado (o que o cliente faz agora). Sem callback, sem botão.
  Widget? _acaoPrincipal(PedidoEmExecucao pedido) {
    switch (pedido.estadoApi) {
      case 'orcamento_aceito':
        final pagar = widget.aoPagar;
        return pagar == null
            ? null
            : BotaoPrimario(key: const ValueKey('acao-principal'), texto: 'Pagar', aoTocar: pagar);
      case 'em_confirmacao':
        final ver = widget.aoVerConclusao;
        return ver == null
            ? null
            : BotaoPrimario(
                key: const ValueKey('acao-principal'),
                texto: 'Confirmar serviço',
                aoTocar: ver,
              );
      case 'concluido':
        final avaliar = widget.aoAvaliar;
        if (!pedido.jaAvaliou && avaliar != null) {
          return BotaoPrimario(
            key: const ValueKey('acao-principal'),
            texto: 'Avaliar',
            aoTocar: avaliar,
          );
        }
        final garantia = widget.aoVerGarantia;
        return garantia == null
            ? null
            : BotaoPrimario(
                key: const ValueKey('acao-principal'),
                texto: 'Ver garantia',
                aoTocar: garantia,
              );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final recarregar = AtualizadorTela.de(context);
    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
      children: [
        _Topo(numero: pedido.numero, aoTocarSos: widget.aoTocarSos),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          (pedido.categoriaNome ?? '').isNotEmpty ? pedido.categoriaNome! : pedido.titulo,
          key: const ValueKey('titulo-pedido'),
          style: TipografiaTrato.tituloGrande,
        ),
        if ((pedido.categoriaNome ?? '').isNotEmpty) ...[
          if ((pedido.descricao ?? '').isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              pedido.descricao!,
              key: const ValueKey('descricao-pedido'),
              style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
            ),
          ],
          const SizedBox(height: EspacosTrato.x2),
          Text(pedido.titulo,
              key: const ValueKey('situacao-pedido'), style: TipografiaTrato.corpoForte),
        ],
        const SizedBox(height: EspacosTrato.x3),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            if (pedido.estadoApi != 'concluido' && pedido.estadoApi != 'cancelado')
              if (pedido.pagamentoConfirmado)
                const ChipStatus(
                  texto: 'Pagamento protegido: fica guardado até o serviço ser confirmado.',
                  tipo: TipoStatus.info,
                  icone: Icons.lock_outline,
                )
              else
                const ChipStatus(
                  texto: 'Aguardando o pagamento',
                  tipo: TipoStatus.alerta,
                  icone: Icons.schedule,
                ),
            if (pedido.remoto)
              const ChipStatus(
                key: ValueKey('selo-remoto'),
                texto: 'Remoto',
                tipo: TipoStatus.info,
                icone: Icons.videocam_outlined,
              ),
            if (pedido.urgente)
              const ChipStatus(
                key: ValueKey('selo-urgente'),
                texto: 'Urgente',
                tipo: TipoStatus.destaque,
              ),
          ],
        ),
        if (pedido.etapas.isNotEmpty &&
            !const {'aberto', 'reservado'}.contains(pedido.estadoApi)) ...[
          const SizedBox(height: EspacosTrato.x5),
          Text('Linha do tempo', style: TipografiaTrato.titulo),
          const SizedBox(height: EspacosTrato.x4),
          LinhaDoTempo(etapas: pedido.etapas),
        ],
        if (pedido.visita != null || pedido.prazoConfirmacao != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          if (pedido.visita != null)
            Text(
              pedido.remoto ? 'Início combinado: ${pedido.visita}' : 'Visita: ${pedido.visita}',
              key: const ValueKey('visita-marcada'),
              style: TipografiaTrato.corpoForte,
            ),
          if (pedido.prazoConfirmacao != null)
            Text(
              pedido.prazoConfirmacao!,
              key: const ValueKey('prazo-confirmacao'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
        ],
        if (pedido.codigoInicio != null) ...[
          const SizedBox(height: EspacosTrato.x4),
          CartaoTrato(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Código de início', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x2),
                Semantics(
                  label: 'Código de início ${pedido.codigoInicio!.split('').join(' ')}',
                  child: ExcludeSemantics(
                    child: Text(pedido.codigoInicio!, style: TipografiaTrato.tituloGrande),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  pedido.remoto
                      ? 'Passe este código ao profissional quando o atendimento começar. '
                          'Não envie o código por mensagem.'
                      : 'Passe este código ao profissional quando ele chegar. '
                          'Não envie o código por mensagem.',
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: context.cores.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (pedido.codigoConclusao != null) ...[
          const SizedBox(height: EspacosTrato.x4),
          CartaoTrato(
            key: const ValueKey('codigo-de-conclusao'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Código de conclusão', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x2),
                Semantics(
                  label: 'Código de conclusão ${pedido.codigoConclusao!.split('').join(' ')}',
                  child: ExcludeSemantics(
                    child: Text(pedido.codigoConclusao!, style: TipografiaTrato.tituloGrande),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  'Quando o serviço estiver pronto, passe este código ao profissional '
                  'para ele concluir. Não envie o código por mensagem.',
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: context.cores.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_acaoPrincipal(pedido) case final principal?) ...[
          const SizedBox(height: EspacosTrato.x4),
          principal,
        ],
        if (!pedido.remoto && pedido.estadoApi == 'em_andamento') ...[
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x2,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('botao-compartilhar-atendimento'),
                onPressed:
                    widget.aoCompartilharAtendimento ?? () => _abrirResumoCompartilhamento(pedido),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Compartilhar atendimento'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('botao-sos-emergencia'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.cores.vermelhoTexto,
                  side: BorderSide(color: context.cores.vermelhoTexto),
                ),
                onPressed: widget.aoSosEmergencia ?? () => _abrirConfirmacaoSos(pedido),
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('SOS / Emergência'),
              ),
            ],
          ),
        ],
        if (_aditivo != null) ...[
          const SizedBox(height: EspacosTrato.x4),
          CartaoAditivo(
            aditivo: _aditivo!,
            aoRecusar: () => _decidir(EstadoAditivo.recusado, widget.aoRecusarAditivo),
            aoAprovar: () => _decidir(EstadoAditivo.aprovado, widget.aoAprovarAditivo),
          ),
        ],
        if (widget.secaoReagendamento != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          widget.secaoReagendamento!,
        ],
        if (widget.aoRemarcarVisita != null ||
            (widget.aoVerGarantia != null && pedido.estadoApi == 'concluido') ||
            (widget.aoBaixarComprovante != null && pedido.estadoApi == 'concluido') ||
            (widget.aoRepetirServico != null && pedido.estadoApi == 'concluido') ||
            widget.aoVerContrato != null ||
            widget.aoVerNota != null ||
            widget.aoVerAditivo != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x1,
            children: [
              if (widget.aoRemarcarVisita != null &&
                  !(pedido.remoto && pedido.estadoApi == 'agendado'))
                BotaoLink(
                  texto: pedido.remoto
                      ? 'Combinar início'
                      : (pedido.estadoApi == 'agendado'
                          ? 'Remarcar visita'
                          : 'Sugerir horário da visita'),
                  aoTocar: widget.aoRemarcarVisita!,
                ),
              if (widget.aoVerGarantia != null && pedido.estadoApi == 'concluido')
                BotaoLink(
                  key: const ValueKey('ver-garantia'),
                  texto: 'Ver garantia ou pedir retrabalho',
                  aoTocar: widget.aoVerGarantia!,
                ),
              if (widget.aoRepetirServico != null && pedido.estadoApi == 'concluido')
                BotaoLink(
                  key: const ValueKey('repetir-servico'),
                  texto: 'Repetir este serviço',
                  aoTocar: widget.aoRepetirServico!,
                ),
              if (widget.aoBaixarComprovante != null && pedido.estadoApi == 'concluido')
                BotaoLink(
                  key: const ValueKey('baixar-comprovante'),
                  texto: 'Baixar comprovante (PDF)',
                  aoTocar: widget.aoBaixarComprovante!,
                ),
              if (widget.aoVerContrato != null)
                BotaoLink(
                  texto: 'Ver contrato do serviço',
                  aoTocar: widget.aoVerContrato!,
                ),
              if (widget.aoVerNota != null && !pedido.remoto)
                BotaoLink(
                  texto: 'Ver nota de materiais',
                  aoTocar: widget.aoVerNota!,
                ),
              if (widget.aoVerAditivo != null)
                BotaoLink(
                  texto: 'Ver aditivo do serviço',
                  aoTocar: widget.aoVerAditivo!,
                ),
            ],
          ),
        ],
        if (pedido.aditivos.isNotEmpty ||
            pedido.notas.isNotEmpty ||
            pedido.orcamentoCentavos != null) ...[
          const SizedBox(height: EspacosTrato.x5),
          _CartaoValoresAditivosNotas(
            pedido: pedido,
            aoAbrirNotas: widget.aoVerNota,
          ),
        ],
        if (pedido.fotos.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x6),
          Row(
            children: [
              for (var i = 0; i < pedido.fotos.length; i++) ...[
                if (i > 0) const SizedBox(width: EspacosTrato.x3),
                Expanded(child: EspacoFoto(rotulo: pedido.fotos[i], altura: 100)),
              ],
            ],
          ),
        ],
        if (widget.aoAbrirProblema != null || widget.aoCancelarPedido != null) ...[
          const SizedBox(height: EspacosTrato.x5),
          const Divider(),
          Wrap(
            spacing: EspacosTrato.x4,
            runSpacing: EspacosTrato.x1,
            children: [
              if (widget.aoAbrirProblema != null)
                BotaoLink(
                  texto: 'Relatar problema',
                  destrutivo: true,
                  aoTocar: widget.aoAbrirProblema!,
                ),
              if (widget.aoCancelarPedido != null)
                BotaoLink(
                  texto: 'Cancelar pedido',
                  destrutivo: true,
                  aoTocar: widget.aoCancelarPedido!,
                ),
            ],
          ),
        ],
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ConteudoResponsivo(
                child: recarregar == null
                    ? lista
                    : RefreshIndicator(onRefresh: recarregar, child: lista),
              ),
            ),
            _Rodape(
              aoConversar: widget.aoConversar,
              aoVerConclusao: widget.pedido.podeVerConclusao ? widget.aoVerConclusao : null,
              mostrarConclusao:
                  widget.pedido.podeVerConclusao && widget.pedido.estadoApi != 'em_confirmacao',
            ),
          ],
        ),
      ),
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo({required this.numero, required this.aoTocarSos});

  final String numero;
  final VoidCallback? aoTocarSos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Voltar',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          ),
          Expanded(
            child: Text(
              'Pedido $numero',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
            ),
          ),
          if (kSosHabilitado) BotaoSos(aoTocar: aoTocarSos),
        ],
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({
    required this.aoConversar,
    required this.aoVerConclusao,
    required this.mostrarConclusao,
  });

  final VoidCallback? aoConversar;
  final VoidCallback? aoVerConclusao;

  /// Sem serviço terminado, só "Conversar" (em largura cheia).
  final bool mostrarConclusao;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.cores.superficie,
        border: Border(top: BorderSide(color: context.cores.borda)),
      ),
      child: ConteudoResponsivo(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
          child: Row(
            children: [
              Expanded(
                child: BotaoSecundario(
                  texto: 'Conversar',
                  icone: Icons.chat_bubble_outline,
                  aoTocar: aoConversar ?? () {},
                ),
              ),
              if (mostrarConclusao) ...[
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: BotaoSecundario(texto: 'Ver conclusão', aoTocar: aoVerConclusao ?? () {}),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CartaoValoresAditivosNotas extends StatelessWidget {
  const _CartaoValoresAditivosNotas({
    required this.pedido,
    this.aoAbrirNotas,
  });

  final PedidoEmExecucao pedido;
  final VoidCallback? aoAbrirNotas;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    final aditivosAprovados = pedido.aditivos
        .where((a) => a.estado == 'aprovado' || a.estado == 'pago')
        .fold<int>(0, (soma, a) => soma + a.valorCentavos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Valores, aditivos e notas', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pedido.orcamentoCentavos != null) ...[
                _LinhaValorResumo(
                  rotulo: 'Orçamento contratado',
                  valor: formatarReais(pedido.orcamentoCentavos!),
                ),
                if (aditivosAprovados > 0) ...[
                  const SizedBox(height: EspacosTrato.x1),
                  _LinhaValorResumo(
                    rotulo: 'Aditivos aprovados',
                    valor: '+ ${formatarReais(aditivosAprovados)}',
                  ),
                ],
                if (pedido.totalAtualizadoCentavos != null) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  _LinhaValorResumo(
                    rotulo: 'Total atualizado do pedido',
                    valor: formatarReais(pedido.totalAtualizadoCentavos!),
                    destaque: true,
                  ),
                ],
              ],
              if (pedido.aditivos.isNotEmpty) ...[
                if (pedido.orcamentoCentavos != null) const Divider(height: EspacosTrato.x5),
                Text('Aditivos vinculados', style: TipografiaTrato.corpoForte),
                const SizedBox(height: EspacosTrato.x2),
                for (final a in pedido.aditivos) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.descricao, style: TipografiaTrato.corpo),
                              const SizedBox(height: EspacosTrato.x1),
                              ChipStatus(
                                texto: a.estadoTexto,
                                tipo: switch (a.estado) {
                                  'aprovado' || 'pago' => TipoStatus.sucesso,
                                  'recusado' => TipoStatus.perigo,
                                  _ => TipoStatus.alerta,
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: EspacosTrato.x3),
                        Text(formatarReais(a.valorCentavos), style: TipografiaTrato.corpoForte),
                      ],
                    ),
                  ),
                ],
              ],
              if (pedido.notas.isNotEmpty) ...[
                if (pedido.orcamentoCentavos != null || pedido.aditivos.isNotEmpty)
                  const Divider(height: EspacosTrato.x5),
                Text('Notas de materiais', style: TipografiaTrato.corpoForte),
                const SizedBox(height: EspacosTrato.x2),
                for (final n in pedido.notas) ...[
                  InkWell(
                    onTap: aoAbrirNotas,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Nota ${n.numero}', style: TipografiaTrato.corpoForte),
                                if (n.itensResumo.isNotEmpty)
                                  Text(n.itensResumo, style: secundario),
                              ],
                            ),
                          ),
                          const SizedBox(width: EspacosTrato.x3),
                          Text(formatarReais(n.totalCentavos), style: TipografiaTrato.corpoForte),
                        ],
                      ),
                    ),
                  ),
                ],
                if (pedido.totalNotasCentavos != null) ...[
                  const SizedBox(height: EspacosTrato.x1),
                  _LinhaValorResumo(
                    rotulo: 'Total em materiais',
                    valor: formatarReais(pedido.totalNotasCentavos!),
                    destaque: true,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LinhaValorResumo extends StatelessWidget {
  const _LinhaValorResumo({
    required this.rotulo,
    required this.valor,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final estilo = destaque ? TipografiaTrato.corpoForte : TipografiaTrato.corpo;
    return Row(
      children: [
        Expanded(child: Text(rotulo, style: estilo)),
        Text(valor, style: estilo),
      ],
    );
  }
}
