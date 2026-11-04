import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/auditoria_texto.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Auditoria (RF-AUD-01 a RF-AUD-04): registro imutável, numerado, com nome do ator e descrição
/// legível. Ninguém edita nem apaga; cada entrada é encadeada por hash à anterior.
class AuditoriaTela extends StatefulWidget {
  const AuditoriaTela({super.key});

  @override
  State<AuditoriaTela> createState() => _AuditoriaTelaState();
}

class _AuditoriaTelaState extends State<AuditoriaTela> {
  static const _porPagina = 25;

  final _ator = TextEditingController();
  String? _acao;
  String _atorBusca = '';
  PeriodoSelecionado _periodo = const PeriodoSelecionado.dias(7);
  int _pagina = 0;
  int _recarga = 0;
  bool _verificando = false;
  bool _exportando = false;
  ResultadoCadeia? _cadeia;
  String? _erroCadeia;

  @override
  void dispose() {
    _ator.dispose();
    super.dispose();
  }

  DateTime _desde() {
    final p = _periodo;
    return p.dias != null ? DateTime.now().subtract(Duration(days: p.dias!)) : p.inicio!;
  }

  DateTime? _ate() => _periodo.personalizado
      ? DateTime(_periodo.fim!.year, _periodo.fim!.month, _periodo.fim!.day, 23, 59, 59)
      : null;

  Future<void> _verificar() async {
    setState(() {
      _verificando = true;
      _erroCadeia = null;
    });
    final api = context.api;
    try {
      final r = await api.verificarCadeia();
      if (mounted) setState(() => _cadeia = r);
    } catch (e) {
      if (mounted) setState(() => _erroCadeia = e.toString());
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _exportar() async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Exportar a auditoria?',
      descricao: 'O arquivo CSV sai com os filtros atuais. A exportação também é registrada.',
      rotuloConfirmar: 'Exportar CSV',
    );
    if (motivo == null || !mounted) return;
    setState(() => _exportando = true);
    RelatorioPronto? pronto;
    final ok = await executar(context, () async {
      pronto = await api.solicitarRelatorio(
        'auditoria',
        inicio: _desde(),
        fim: _ate() ?? DateTime.now(),
        motivo: motivo,
      );
    }, sucesso: 'Exportação pronta.');
    if (mounted) {
      setState(() {
        _exportando = false;
        if (ok) _recarga++; // a exportação também vira linha da trilha
      });
    }
    final r = pronto;
    if (ok && r != null) await launchUrl(Uri.parse(r.url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final cadeia = _cadeia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Auditoria',
          subtitulo: 'Registro imutável: ninguém edita nem apaga. Cada entrada é encadeada por hash à anterior.',
          acoes: [
            if (context.pode(Permissao.auditoriaVer))
              BotaoTrato.secundario(
                'Exportar CSV',
                icone: IconesTrato.exportar,
                aoPressionar: _exportando ? null : _exportar,
                carregando: _exportando,
                rotuloCarregando: 'Gerando',
              ),
            if (context.pode(Permissao.auditoriaVerificarCadeia))
              BotaoTrato.primario(
                'Verificar cadeia de hash',
                aoPressionar: _verificando ? null : _verificar,
                carregando: _verificando,
                rotuloCarregando: 'Verificando',
              ),
          ],
        ),
        if (cadeia != null)
          Padding(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
            child: cadeia.ok
                ? BannerInfo(
                    cadeia.verificadas == null
                        ? 'Nenhum registro foi alterado.'
                        : '${formatarMilhar(cadeia.verificadas!)} registros conferidos, nenhum alterado.',
                    titulo: 'Cadeia íntegra.',
                    tom: Tom.ok,
                    icone: Icons.verified_outlined,
                  )
                : BannerInfo(
                    'Cadeia de hash quebrada a partir do registro nº ${formatarMilhar(cadeia.primeiraQuebraId ?? 0)}. '
                    'Avise a equipe técnica.',
                    tom: Tom.erro,
                    icone: Icons.warning_amber_outlined,
                  ),
          ),
        if (_erroCadeia != null)
          Padding(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
            child: BannerInfo(_erroCadeia!, tom: Tom.erro),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BarraFiltros(
                filtros: [
                DropdownButtonFormField<String?>(
                  key: ValueKey('acao-$_acao'),
                  initialValue: _acao,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ação'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    for (final f in filtrosDeAcao) DropdownMenuItem(value: f.$1, child: Text(f.$2)),
                  ],
                  onChanged: (v) => setState(() {
                    _acao = v;
                    _pagina = 0;
                  }),
                ),
                TextField(
                  controller: _ator,
                  onSubmitted: (v) => setState(() {
                    _atorBusca = v;
                    _pagina = 0;
                  }),
                  decoration: InputDecoration(
                    labelText: 'Quem',
                    helperText: 'Nome da pessoa',
                    suffixIcon: BotaoIcone(
                      icone: IconesTrato.buscar,
                      rotulo: 'Filtrar por quem',
                      aoPressionar: () => setState(() {
                        _atorBusca = _ator.text;
                        _pagina = 0;
                      }),
                    ),
                  ),
                ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              FiltroPeriodo(
                selecionado: _periodo,
                aoMudar: (p) => setState(() {
                  _periodo = p;
                  _pagina = 0;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: CarregaDados<PaginaAuditoria>(
            key: ValueKey('$_acao|$_atorBusca|${_periodo.hashCode}|$_pagina|$_recarga'),
            carregar: () => context.api.listarAuditoria(
              acao: _acao,
              ator: _atorBusca,
              desde: _desde(),
              ate: _ate(),
              limite: _porPagina,
              deslocamento: _pagina * _porPagina,
            ),
            estaVazio: (p) => p.itens.isEmpty,
            mensagemVazia: 'Nenhum registro com esse filtro',
            detalheVazio: 'Mude o período ou limpe os filtros para ver mais registros.',
            construir: (context, p, _) {
              final ini = _pagina * _porPagina;
              final fim = ini + p.itens.length;
              final paginas = (p.total / _porPagina).ceil();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
                      itemCount: p.itens.length,
                      separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.intervaloCartoes),
                      itemBuilder: (context, i) => _EntradaCartao(p.itens[i]),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: EspacosTrato.x2,
                      children: [
                        Text(
                          'Mostrando ${formatarMilhar(p.total - ini)} a ${formatarMilhar(p.total - fim + 1)} '
                          'de ${formatarMilhar(p.total)}',
                          style: TipografiaTrato.legenda,
                        ),
                        if (paginas > 1)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BotaoTrato.secundario(
                                'Anterior',
                                aoPressionar: _pagina > 0 ? () => setState(() => _pagina--) : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
                                child: Text('$_porPagina por página', style: TipografiaTrato.legenda),
                              ),
                              BotaoTrato.secundario(
                                'Próxima',
                                aoPressionar: _pagina < paginas - 1 ? () => setState(() => _pagina++) : null,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntradaCartao extends StatefulWidget {
  const _EntradaCartao(this.e);
  final EntradaAuditoria e;

  @override
  State<_EntradaCartao> createState() => _EntradaCartaoState();
}

class _EntradaCartaoState extends State<_EntradaCartao> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    return CartaoSecao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('nº ${formatarMilhar(e.id)}', style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo)),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: descreverAtor(e), style: TipografiaTrato.corpoForte),
                    TextSpan(text: ' ${descreverAcao(e)}'),
                  ]),
                  style: TipografiaTrato.corpo,
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Text(formatarData(e.ocorridaEm), style: TipografiaTrato.legenda),
            ],
          ),
          if (e.motivo != null && e.motivo!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: EspacosTrato.x1),
              child: Text('Motivo: “${e.motivo}”', style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.link(
              _aberto ? 'Ocultar detalhe técnico' : 'Ver detalhe técnico',
              aoPressionar: () => setState(() => _aberto = !_aberto),
            ),
          ),
          if (_aberto) ...[
            Linha('ação', e.acao),
            Linha('entidade', e.entidade),
            if (e.hash != null) Linha('hash', e.hash!),
          ],
        ],
      ),
    );
  }
}
