import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'retorno_conta_modais.dart';

const kStatusRetornoConta = {
  'aberto': 'Aberto',
  'em_analise': 'Em análise',
  'aprovado': 'Aprovado',
  'recusado': 'Recusado',
};

const kTiposIdentificadorImpedimento = {
  'cpf': 'CPF',
  'cnpj': 'CNPJ',
  'email': 'E-mail',
  'telefone': 'Telefone',
  'conta': 'Conta',
};

String rotuloRetorno(Map<String, String> mapa, String codigo) => mapa[codigo] ?? codigo;

(String, Tom) _chipRetorno(String status) => (
      rotuloRetorno(kStatusRetornoConta, status),
      switch (status) {
        'aberto' => Tom.alerta,
        'em_analise' => Tom.info,
        'aprovado' => Tom.ok,
        'recusado' => Tom.erro,
        _ => Tom.neutro,
      },
    );

/// Pedidos de retorno de conta e impedimentos de cadastro (Termos 20.9).
class RetornoContaTela extends StatelessWidget {
  const RetornoContaTela({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CabecalhoPagina(
            'Retorno de conta',
            subtitulo: 'Pedidos de retorno e impedimentos de cadastro (Termos 20.9)',
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Pedidos de retorno'),
              Tab(text: 'Impedimentos de cadastro'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _AbaRetornos(),
                _AbaImpedimentos(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AbaRetornos extends StatefulWidget {
  const _AbaRetornos();

  @override
  State<_AbaRetornos> createState() => _AbaRetornosState();
}

class _AbaRetornosState extends State<_AbaRetornos> {
  String? _status;
  String _usuarioId = '';

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('retorno-status'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in kStatusRetornoConta.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              key: const ValueKey('retorno-usuario-filtro'),
              decoration: const InputDecoration(labelText: 'Código do usuário', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _usuarioId = v.trim()),
            ),
          ),
        ],
      ),
    );
    return FilaRemota<PedidoRetornoConta>(
      filtro: (_status, _usuarioId),
      esqueleto: const EsqueletoPagina(),
      chave: (r) => r.id,
      carregar: (deslocamento, limite) => context.api.listarRetornosConta(
        status: _status,
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
              child: MestreDetalhe<PedidoRetornoConta>(
                itens: fila.itens,
                chave: (r) => r.id,
                mensagemSemItens: 'Nenhum pedido de retorno com esse filtro.',
                tituloDetalhe: (r) => r.protocolo,
                rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'pedidos'),
                itemBuilder: (context, r, sel) {
                  final (texto, tom) = _chipRetorno(r.status);
                  return CartaoLista(
                    titulo: '${r.protocolo} · Conta ${r.usuarioId}',
                    linhas: [
                      'Solicitado em ${formatarData(r.solicitadoEm)}',
                      'Prazo aplicado: ${r.prazoDiasAplicado} dia(s)',
                    ],
                    chips: [
                      ChipEstado(texto, tom: tom),
                      if (r.riscoIdentificado) const ChipEstado('Risco identificado', tom: Tom.erro),
                    ],
                    selecionado: sel,
                  );
                },
                detalheBuilder: (context, r) => _DetalheRetorno(
                  key: ValueKey('${r.id}-${r.status}'),
                  retorno: r,
                  aoMudar: () => fila.recarregar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetalheRetorno extends StatefulWidget {
  const _DetalheRetorno({super.key, required this.retorno, required this.aoMudar});
  final PedidoRetornoConta retorno;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheRetorno> createState() => _DetalheRetornoState();
}

class _DetalheRetornoState extends State<_DetalheRetorno> {
  bool _enviando = false;
  String? _erro;

  Future<void> _iniciarAnalise() async {
    if (_enviando) return;
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Iniciar análise?',
      texto: 'O pedido ${widget.retorno.protocolo} passa para "Em análise" sob sua responsabilidade.',
      verbo: 'Iniciar análise',
    );
    if (!ok || !mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.analisarRetornoConta(widget.retorno.id);
      if (mounted) mostrarAviso(context, 'Pedido colocado em análise.');
      await widget.aoMudar();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirE(Future<bool> Function() modal) async {
    if (await modal() && mounted) await widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.retorno;
    final (texto, tom) = _chipRetorno(r.status);
    final podeAnalisar = context.pode(Permissao.contaRetornoAnalisar);
    final podeAprovar = context.pode(Permissao.contaRetornoAprovar);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(r.protocolo, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          children: [
            ChipEstado(texto, tom: tom),
            if (r.riscoIdentificado) const ChipEstado('Risco identificado', tom: Tom.erro),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Usuário', r.usuarioId),
        Linha('Medida vinculada', r.medidaId),
        Linha('Canal', r.canal),
        Linha('Justificativa do usuário', r.justificativaUsuario),
        Linha('Solicitado em', formatarData(r.solicitadoEm)),
        Linha('Prazo aplicado', '${r.prazoDiasAplicado} dia(s)'),
        Linha('Elegível a partir de', formatarData(r.elegivelAPartirDe)),
        if (r.decisaoMotivo != null) Linha('Motivo da decisão', r.decisaoMotivo!),
        if (r.decididoEm != null) Linha('Decidido em', formatarData(r.decididoEm!)),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (r.decidido)
          const BannerInfo('Pedido decidido: não recebe novas alterações.')
        else if (podeAnalisar)
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (r.status == 'aberto')
                BotaoTrato.secundario('Iniciar análise', aoPressionar: _enviando ? null : _iniciarAnalise),
              BotaoTrato.destrutivo(
                'Recusar retorno',
                aoPressionar: _enviando ? null : () => _abrirE(() => abrirRecusarRetorno(context, r)),
              ),
              if (podeAprovar)
                BotaoTrato.primario(
                  'Aprovar retorno',
                  aoPressionar: _enviando ? null : () => _abrirE(() => abrirAprovarRetorno(context, r)),
                ),
            ],
          ),
      ],
    );
  }
}

class _AbaImpedimentos extends StatefulWidget {
  const _AbaImpedimentos();

  @override
  State<_AbaImpedimentos> createState() => _AbaImpedimentosState();
}

class _AbaImpedimentosState extends State<_AbaImpedimentos> {
  String _medidaId = '';
  bool _apenasAtivos = false;

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              key: const ValueKey('impedimento-medida-filtro'),
              decoration: const InputDecoration(labelText: 'Código da medida', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _medidaId = v.trim()),
            ),
          ),
          FilterChip(
            label: const Text('Só ativos'),
            selected: _apenasAtivos,
            onSelected: (v) => setState(() => _apenasAtivos = v),
          ),
        ],
      ),
    );
    return FilaRemota<ImpedimentoCadastro>(
      filtro: (_medidaId, _apenasAtivos),
      esqueleto: const EsqueletoPagina(),
      chave: (i) => i.id,
      carregar: (deslocamento, limite) => context.api.listarImpedimentosConta(
        medidaId: _medidaId.isEmpty ? null : _medidaId,
        apenasAtivos: _apenasAtivos,
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
              child: MestreDetalhe<ImpedimentoCadastro>(
                itens: fila.itens,
                chave: (i) => i.id,
                mensagemSemItens: 'Nenhum impedimento com esse filtro.',
                tituloDetalhe: (i) => rotuloRetorno(kTiposIdentificadorImpedimento, i.tipoIdentificador),
                rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'impedimentos'),
                itemBuilder: (context, i, sel) => CartaoLista(
                  titulo: '${rotuloRetorno(kTiposIdentificadorImpedimento, i.tipoIdentificador)} · Medida ${i.medidaId}',
                  linhas: ['Criado em ${formatarData(i.criadoEm)}'],
                  chips: [ChipEstado(i.ativo ? 'Ativo' : 'Revogado', tom: i.ativo ? Tom.erro : Tom.neutro)],
                  selecionado: sel,
                ),
                detalheBuilder: (context, i) => _DetalheImpedimento(
                  key: ValueKey('${i.id}-${i.ativo}'),
                  impedimento: i,
                  aoMudar: () => fila.recarregar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetalheImpedimento extends StatelessWidget {
  const _DetalheImpedimento({super.key, required this.impedimento, required this.aoMudar});
  final ImpedimentoCadastro impedimento;
  final Future<void> Function() aoMudar;

  @override
  Widget build(BuildContext context) {
    final i = impedimento;
    final podeAprovar = context.pode(Permissao.contaRetornoAprovar);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text('Impedimento · ${rotuloRetorno(kTiposIdentificadorImpedimento, i.tipoIdentificador)}',
            style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          children: [ChipEstado(i.ativo ? 'Ativo' : 'Revogado', tom: i.ativo ? Tom.erro : Tom.neutro)],
        ),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Identificador', rotuloRetorno(kTiposIdentificadorImpedimento, i.tipoIdentificador)),
        Linha('Medida', i.medidaId),
        Linha('Criado em', formatarData(i.criadoEm)),
        if (i.revogadoEm != null) Linha('Revogado em', formatarData(i.revogadoEm!)),
        if (i.motivoRevogacao != null) Linha('Motivo da revogação', i.motivoRevogacao!),
        const SizedBox(height: EspacosTrato.x4),
        if (!i.ativo)
          const BannerInfo('Impedimento já revogado.')
        else if (podeAprovar)
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.destrutivo(
              'Revogar impedimento',
              aoPressionar: () async {
                if (await abrirRevogarImpedimento(context, i) && context.mounted) {
                  await aoMudar();
                }
              },
            ),
          ),
      ],
    );
  }
}
