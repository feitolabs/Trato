import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'lgpd_pedidos_modais.dart';

const kTipoRevisaoAutomatizada = 'revisao_decisao_automatizada';

const kStatusPedidoLgpd = {
  'aberto': 'Aberto',
  'em_analise': 'Em análise',
  'aguardando_titular': 'Aguardando titular',
  'atendido': 'Atendido',
  'atendido_parcial': 'Atendido parcialmente',
  'negado': 'Negado',
};

const kTiposPedidoLgpd = {
  'confirmacao': 'Confirmação de tratamento',
  'acesso': 'Acesso aos dados',
  'correcao': 'Correção de dados',
  'anonimizacao_bloqueio_eliminacao': 'Anonimização, bloqueio ou eliminação',
  'portabilidade': 'Portabilidade',
  'eliminacao_consentimento': 'Eliminação por consentimento',
  'compartilhamento': 'Informação de compartilhamento',
  'nao_consentir': 'Informação sobre não consentir',
  'revogacao_consentimento': 'Revogação de consentimento',
  'revisao_decisao_automatizada': 'Revisão de decisão automatizada',
};

const kDecisoesAutomatizadas = {
  'ocultacao_contato': 'Ocultação de contato',
  'documentos_rosto': 'Validação de documentos e rosto',
  'alerta_fraude': 'Alerta de fraude',
  'ordem_resultados': 'Ordem de resultados',
  'outra': 'Outra decisão automatizada',
};

String rotuloLgpd(Map<String, String> mapa, String codigo) => mapa[codigo] ?? codigo;

(String, Tom) _chip(String status) => (
      rotuloLgpd(kStatusPedidoLgpd, status),
      switch (status) {
        'aberto' => Tom.alerta,
        'em_analise' || 'aguardando_titular' => Tom.info,
        'atendido' => Tom.ok,
        'atendido_parcial' => Tom.alerta,
        'negado' => Tom.neutro,
        _ => Tom.neutro,
      },
    );

/// Pedidos de titular LGPD e revisão de decisão automatizada (Termos 14.9 e 14.10).
class LgpdPedidosTela extends StatefulWidget {
  const LgpdPedidosTela({super.key});

  @override
  State<LgpdPedidosTela> createState() => _LgpdPedidosTelaState();
}

class _LgpdPedidosTelaState extends State<LgpdPedidosTela> {
  String? _status;
  String? _tipo;
  String _usuarioId = '';

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final gerenciaTodos = context.pode(Permissao.lgpdPedidosGerenciar);
    final tipoEfetivo = gerenciaTodos ? _tipo : kTipoRevisaoAutomatizada;
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!gerenciaTodos) ...[
            const BannerInfo(
              'Seu papel consulta e trata apenas pedidos de revisão de decisão automatizada (Termos 14.10).',
              tom: Tom.info,
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  key: const ValueKey('lgpd-status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Situação'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    for (final e in kStatusPedidoLgpd.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
              if (gerenciaTodos)
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('lgpd-tipo'),
                    initialValue: _tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (final e in kTiposPedidoLgpd.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _tipo = v),
                  ),
                ),
              SizedBox(
                width: 220,
                child: TextField(
                  key: const ValueKey('lgpd-usuario-filtro'),
                  decoration: const InputDecoration(
                    labelText: 'Código do usuário',
                    helperText: 'Enter para buscar',
                  ),
                  onSubmitted: (v) => setState(() => _usuarioId = v.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Pedidos LGPD',
          subtitulo: gerenciaTodos
              ? 'Direitos do titular e revisão automatizada (Termos 14.9 e 14.10)'
              : 'Revisão de decisão automatizada (Termos 14.10)',
        ),
        Expanded(
          child: FilaRemota<PedidoTitularLgpd>(
            filtro: (_status, tipoEfetivo, _usuarioId),
            esqueleto: const EsqueletoPagina(),
            chave: (p) => p.id,
            carregar: (deslocamento, limite) => context.api.listarPedidosLgpd(
              status: _status,
              tipo: tipoEfetivo,
              usuarioId: _usuarioId.isEmpty ? null : _usuarioId,
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
                    child: MestreDetalhe<PedidoTitularLgpd>(
                      itens: fila.itens,
                      chave: (p) => p.id,
                      mensagemSemItens: 'Nenhum pedido LGPD com esse filtro.',
                      tituloDetalhe: (p) => p.protocolo,
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'pedidos'),
                      itemBuilder: (context, p, sel) {
                        final (texto, tom) = _chip(p.status);
                        return CartaoLista(
                          titulo: '${p.protocolo} · ${rotuloLgpd(kTiposPedidoLgpd, p.tipo)}',
                          linhas: [
                            'Aberto em ${formatarData(p.abertoEm)}',
                            if (!p.respondido) 'Prazo legal até ${formatarData(p.responderAte)}',
                          ],
                          chips: [
                            if (p.atrasado(DateTime.now())) const ChipEstado('Prazo vencido', tom: Tom.erro),
                            ChipEstado(texto, tom: tom),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, p) => _DetalhePedidoLgpd(
                        key: ValueKey('${p.id}-${p.status}'),
                        pedido: p,
                        aoMudar: () => fila.recarregar(),
                      ),
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

class _DetalhePedidoLgpd extends StatefulWidget {
  const _DetalhePedidoLgpd({super.key, required this.pedido, required this.aoMudar});
  final PedidoTitularLgpd pedido;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalhePedidoLgpd> createState() => _DetalhePedidoLgpdState();
}

class _DetalhePedidoLgpdState extends State<_DetalhePedidoLgpd> {
  bool _enviando = false;
  String? _erro;

  Future<void> _iniciarAnalise() async {
    if (_enviando) return;
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Iniciar análise?',
      texto: 'O pedido ${widget.pedido.protocolo} passa para "Em análise" sob sua responsabilidade.',
      verbo: 'Iniciar análise',
    );
    if (!ok || !mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.analisarPedidoLgpd(widget.pedido.id);
      if (mounted) mostrarAviso(context, 'Pedido colocado em análise.');
      await widget.aoMudar();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirResponder() async {
    if (await abrirResponderPedidoLgpd(context, widget.pedido) && mounted) {
      await widget.aoMudar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final (texto, tom) = _chip(p.status);
    final atrasado = p.atrasado(DateTime.now());
    final podeTratar = context.pode(Permissao.lgpdPedidosGerenciar) ||
        (context.pode(Permissao.lgpdRevisaoAutomatizada) && p.tipo == kTipoRevisaoAutomatizada);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(p.protocolo, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          children: [
            if (atrasado) const ChipEstado('Prazo vencido', tom: Tom.erro),
            ChipEstado(texto, tom: tom),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (atrasado) ...[
          BannerInfo(
            'O prazo legal de resposta venceu em ${formatarData(p.responderAte)}.',
            titulo: 'Prazo legal vencido.',
            tom: Tom.erro,
            icone: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        Linha('Tipo', rotuloLgpd(kTiposPedidoLgpd, p.tipo)),
        if (p.decisaoAutomatizada != null)
          Linha('Decisão automatizada', rotuloLgpd(kDecisoesAutomatizadas, p.decisaoAutomatizada!)),
        if (p.usuarioId != null) Linha('Usuário', p.usuarioId!),
        if (p.contato != null) Linha('Contato', p.contato!),
        if (p.referenciaTipo != null || p.referenciaId != null)
          Linha('Referência', '${p.referenciaTipo ?? ''} ${p.referenciaId ?? ''}'.trim()),
        if (p.exclusaoId != null) Linha('Pedido de exclusão', p.exclusaoId!),
        Linha('Canal', p.canal),
        Linha('Descrição', p.descricao.isEmpty ? 'Sem descrição' : p.descricao),
        Linha('Aberto em', formatarData(p.abertoEm)),
        Linha('Prazo legal até', formatarData(p.responderAte)),
        if (p.resposta != null) Linha('Resposta', p.resposta!),
        if (p.motivoNaoAtendido != null) Linha('Motivo de não atendimento', p.motivoNaoAtendido!),
        if (p.criteriosInformados != null) Linha('Critérios informados', p.criteriosInformados!),
        if (p.respondidoEm != null) Linha('Respondido em', formatarData(p.respondidoEm!)),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (p.respondido)
          const BannerInfo('Pedido respondido: não recebe novas alterações.')
        else if (podeTratar)
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (p.status == 'aberto' || p.status == 'aguardando_titular')
                BotaoTrato.secundario(
                  'Iniciar análise',
                  aoPressionar: _enviando ? null : _iniciarAnalise,
                ),
              BotaoTrato.primario(
                'Responder pedido',
                aoPressionar: _enviando ? null : _abrirResponder,
              ),
            ],
          ),
      ],
    );
  }
}
