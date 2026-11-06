import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Risco e antifraude (RF-RIS-01 a RF-RIS-04).
class RiscoTela extends StatefulWidget {
  const RiscoTela({super.key});

  @override
  State<RiscoTela> createState() => _RiscoTelaState();
}

class _RiscoTelaState extends State<RiscoTela> {
  int _versao = 0;

  static (String, Tom) severidade(String s) => switch (s) {
        'critica' => ('Crítica', Tom.erro),
        'alta' => ('Alta', Tom.erro),
        'media' => ('Média', Tom.alerta),
        _ => ('Baixa', Tom.neutro),
      };

  static (String, Tom) status(AlertaRisco a) => switch (a.status) {
        'resolvido' => (a.resultado == 'improcedente' ? 'Resolvido · improcedente' : 'Resolvido', Tom.ok),
        'em_analise' => ('Em análise', Tom.info),
        _ => ('Em aberto', Tom.alerta),
      };

  /// "valor_atipico" -> "Valor atípico". Códigos que a tela não conhece viram texto simples.
  static String nomeDoTipo(String tipo) => switch (tipo) {
        'valor_atipico' || 'valor_atípico' => 'Valor atípico',
        'varios_pedidos_em_pouco_tempo' => 'Vários pedidos em pouco tempo',
        'troca_de_chave_pix' => 'Troca de chave PIX',
        'cupom_reutilizado' => 'Cupom reutilizado',
        'mesmo_aparelho_em_2_contas' => 'Mesmo aparelho em 2 contas',
        'saque_travado' => 'Saques travados',
        final t => '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}',
      };

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<AlertaRisco>>(
      esqueleto: const EsqueletoPagina(),
      key: ValueKey('risco-$_versao'),
      carregar: context.api.listarAlertasRisco,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum alerta de risco',
      detalheVazio: 'Quando o sistema detectar algo fora do normal, o alerta aparece aqui.',
      construir: (context, lista, _) => _FilaRisco(lista: lista, aoMudar: () => setState(() => _versao++)),
    );
  }
}

class _FilaRisco extends StatefulWidget {
  const _FilaRisco({required this.lista, required this.aoMudar});
  final List<AlertaRisco> lista;
  final VoidCallback aoMudar;

  @override
  State<_FilaRisco> createState() => _FilaRiscoState();
}

class _FilaRiscoState extends State<_FilaRisco> {
  String _status = 'abertos';
  String? _severidade;

  @override
  Widget build(BuildContext context) {
    final itens = [
      for (final a in widget.lista)
        if ((_status == 'todos' || (_status == 'abertos') == !a.resolvido) &&
            (_severidade == null || a.severidade == _severidade))
          a,
    ];
    final abertos = widget.lista.where((a) => !a.resolvido).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Risco e antifraude',
          subtitulo: 'Limites de detecção vêm de Configurações e mudam só com aprovação.',
        ),
        Expanded(
          child: MestreDetalhe<AlertaRisco>(
            itens: itens,
            mensagemSemItens: 'Nenhum alerta com esse filtro.',
            tituloDetalhe: (a) => _RiscoTelaState.nomeDoTipo(a.tipo),
            topo: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FiltroStatus(
                  opcoes: [
                    ('abertos', 'Em aberto', abertos),
                    ('resolvidos', 'Resolvidos', widget.lista.length - abertos),
                    ('todos', 'Todos', widget.lista.length),
                  ],
                  selecionado: _status,
                  aoMudar: (v) => setState(() => _status = v),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsivo.margemLateral(FaixaPainel.de(context)),
                    0,
                    Responsivo.margemLateral(FaixaPainel.de(context)),
                    EspacosTrato.x2,
                  ),
                  child: DropdownButtonFormField<String?>(
                      key: ValueKey('sev-$_severidade'),
                      initialValue: _severidade,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Severidade'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Todas')),
                        DropdownMenuItem(value: 'critica', child: Text('Crítica')),
                        DropdownMenuItem(value: 'alta', child: Text('Alta')),
                        DropdownMenuItem(value: 'media', child: Text('Média')),
                        DropdownMenuItem(value: 'baixa', child: Text('Baixa')),
                      ],
                      onChanged: (v) => setState(() => _severidade = v),
                    ),
                ),
              ],
            ),
            itemBuilder: (context, a, sel) {
              final (txtSev, tomSev) = _RiscoTelaState.severidade(a.severidade);
              final (txtSt, tomSt) = _RiscoTelaState.status(a);
              return CartaoLista(
                titulo: _RiscoTelaState.nomeDoTipo(a.tipo),
                linhas: [
                  [
                    if (a.usuarioNome != null) '${a.usuarioNome}${a.usuarioTipo == null ? '' : ' (${a.usuarioTipo})'}',
                    a.pedido ?? 'Sem pedido',
                  ].join(' · '),
                  a.responsavel == null ? 'Sem responsável' : 'Responsável ${a.responsavel}',
                ],
                chips: [ChipEstado(txtSev, tom: tomSev), ChipEstado(txtSt, tom: tomSt)],
                selecionado: sel,
              );
            },
            detalheBuilder: (context, a) => _DetalheAlerta(key: ValueKey(a.id), alerta: a, aoMudar: widget.aoMudar),
          ),
        ),
      ],
    );
  }
}

class _DetalheAlerta extends StatefulWidget {
  const _DetalheAlerta({super.key, required this.alerta, required this.aoMudar});
  final AlertaRisco alerta;
  final VoidCallback aoMudar;

  @override
  State<_DetalheAlerta> createState() => _DetalheAlertaState();
}

class _DetalheAlertaState extends State<_DetalheAlerta> {
  String _resultado = 'procedente';
  final _motivo = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _resolver() async {
    final a = widget.alerta;
    setState(() => _enviando = true);
    final ok = await executar(
      context,
      () => context.api.resolverAlertaRisco(a.id, resultado: _resultado, motivo: _motivo.text.trim()),
      sucesso: 'Alerta resolvido.',
    );
    if (mounted) setState(() => _enviando = false);
    if (ok) widget.aoMudar();
  }

  Future<void> _assumir() async {
    final a = widget.alerta;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Assumir este alerta?',
      descricao: 'Ele vai para Em análise e você fica como responsável.',
      rotuloConfirmar: 'Assumir alerta',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.assumirAlertaRisco(a.id, motivo: motivo),
      sucesso: 'Alerta em análise.',
    );
    if (ok) widget.aoMudar();
  }

  /// Travar saques, bloquear a conta e as ações contrárias: sempre com consequência e motivo.
  Future<void> _acao({
    required String titulo,
    required String descricao,
    required String verbo,
    required Future<void> Function(String motivo) executarAcao,
    required String sucesso,
    bool destrutivo = false,
  }) async {
    final motivo = await pedirMotivo(
      context,
      titulo: titulo,
      descricao: descricao,
      rotuloConfirmar: verbo,
      destrutivo: destrutivo,
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(context, () => executarAcao(motivo), sucesso: sucesso);
    if (ok) widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alerta;
    final api = context.api;
    final (txtSev, tomSev) = _RiscoTelaState.severidade(a.severidade);
    final (txtSt, tomSt) = _RiscoTelaState.status(a);
    final podeDecidir = context.pode(Permissao.riscoDecidir);
    final nome = a.usuarioNome ?? 'o usuário';
    final motivoValido = _motivo.text.trim().length >= kMotivoMinimo;

    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(_RiscoTelaState.nomeDoTipo(a.tipo), style: TipografiaTrato.titulo)),
            Wrap(spacing: EspacosTrato.x2, children: [ChipEstado(txtSev, tom: tomSev), ChipEstado(txtSt, tom: tomSt)]),
          ],
        ),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          [
            if (a.usuarioNome != null) '${a.usuarioNome}${a.usuarioTipo == null ? '' : ' (${a.usuarioTipo})'}',
            if (a.pedido != null) a.pedido!,
            if (a.criadoEm.isNotEmpty) 'aberto em ${formatarData(DateTime.tryParse(a.criadoEm)?.toLocal() ?? DateTime.now())}',
          ].join(' · '),
          style: TipografiaTrato.subtitulo,
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text(a.detalhes, style: TipografiaTrato.corpo),
        if (a.saquesTravados || a.contaBloqueada) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(
            a.contaBloqueada
                ? 'A conta não cria nem recebe pedidos novos. Reversível com motivo.'
                : 'Novos repasses ficam retidos até alguém destravar. Pedidos em andamento continuam.',
            titulo: a.contaBloqueada ? 'Conta bloqueada.' : 'Saques travados.',
            tom: Tom.alerta,
            icone: IconesTrato.travar,
          ),
        ],
        if (!a.resolvido && podeDecidir) ...[
          const SizedBox(height: EspacosTrato.x5),
          Text('Resolver alerta', style: TipografiaTrato.secao),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            children: [
              ChoiceChip(
                label: const Text('Procedente'),
                selected: _resultado == 'procedente',
                onSelected: (_) => setState(() => _resultado = 'procedente'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              ChoiceChip(
                label: const Text('Improcedente'),
                selected: _resultado == 'improcedente',
                onSelected: (_) => setState(() => _resultado = 'improcedente'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoMotivo(controle: _motivo, aoMudar: () => setState(() {})),
          const SizedBox(height: EspacosTrato.x2),
          const AvisoAuditoria(),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            children: [
              if (a.status == 'em_aberto') BotaoTrato.secundario('Assumir alerta', aoPressionar: _assumir),
              BotaoTrato.primario(
                'Resolver alerta',
                aoPressionar: motivoValido && !_enviando ? _resolver : null,
                carregando: _enviando,
                rotuloCarregando: 'Resolvendo',
              ),
            ],
          ),
        ],
        if (a.usuarioId != null && podeDecidir && a.usuarioTipo != 'equipe') ...[
          const SizedBox(height: EspacosTrato.x5),
          Text('Ações preventivas', style: TipografiaTrato.secao),
          const SizedBox(height: EspacosTrato.x3),
          _AcaoPreventiva(
            titulo: a.saquesTravados ? 'Destravar saques' : 'Travar saques',
            descricao: a.saquesTravados
                ? 'Os repasses voltam a sair normalmente. Exige motivo.'
                : 'Novos repasses ficam retidos. Pedidos em andamento continuam. Reversível com motivo.',
            verbo: a.saquesTravados ? 'Destravar saques' : 'Travar saques',
            icone: a.saquesTravados ? IconesTrato.destravar : IconesTrato.travar,
            aoPressionar: () => _acao(
              titulo: a.saquesTravados ? 'Destravar saques de $nome?' : 'Travar saques de $nome?',
              descricao: a.saquesTravados
                  ? 'Os repasses de $nome voltam a sair normalmente.'
                  : 'Novos repasses ficam retidos até alguém destravar. Pedidos em andamento continuam normalmente.',
              verbo: a.saquesTravados ? 'Destravar saques' : 'Travar saques',
              executarAcao: (m) => a.saquesTravados
                  ? api.destravarSaque(a.usuarioId!, motivo: m)
                  : api.travarSaque(a.usuarioId!, motivo: m),
              sucesso: a.saquesTravados ? 'Saques destravados.' : 'Saques travados.',
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          _AcaoPreventiva(
            titulo: a.contaBloqueada ? 'Desbloquear conta' : 'Bloqueio preventivo',
            descricao: a.contaBloqueada
                ? 'A conta volta a criar e receber pedidos. Exige motivo.'
                : 'A conta não cria nem recebe pedidos novos. Reversível com motivo.',
            verbo: a.contaBloqueada ? 'Desbloquear conta' : 'Bloquear conta',
            destrutivo: !a.contaBloqueada,
            icone: Icons.shield_outlined,
            aoPressionar: () => _acao(
              titulo: a.contaBloqueada ? 'Desbloquear a conta de $nome?' : 'Bloquear a conta de $nome?',
              descricao: a.contaBloqueada
                  ? '$nome volta a criar e receber pedidos.'
                  : '$nome não cria nem recebe pedidos novos. Pedidos em andamento continuam.',
              verbo: a.contaBloqueada ? 'Desbloquear conta' : 'Bloquear conta',
              destrutivo: !a.contaBloqueada,
              executarAcao: (m) => a.contaBloqueada
                  ? api.desbloquearConta(a.usuarioId!, motivo: m)
                  : api.aplicarBloqueioPreventivo(a.usuarioId!, motivo: m),
              sucesso: a.contaBloqueada ? 'Conta desbloqueada.' : 'Conta bloqueada.',
            ),
          ),
        ],
        if (!podeDecidir)
          const Padding(
            padding: EdgeInsets.only(top: EspacosTrato.x4),
            child: BannerInfo('Seu papel acompanha os alertas, mas não age sobre eles.'),
          ),
      ],
    );
  }
}

class _AcaoPreventiva extends StatelessWidget {
  const _AcaoPreventiva({
    required this.titulo,
    required this.descricao,
    required this.verbo,
    required this.icone,
    required this.aoPressionar,
    this.destrutivo = false,
  });

  final String titulo;
  final String descricao;
  final String verbo;
  final IconData icone;
  final VoidCallback aoPressionar;
  final bool destrutivo;

  @override
  Widget build(BuildContext context) {
    return CartaoSecao(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: destrutivo ? CoresTrato.perigoTexto : CoresTrato.textoMudo),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TipografiaTrato.corpoForte),
                Text(descricao, style: TipografiaTrato.legenda),
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          destrutivo
              ? BotaoTrato.destrutivo(verbo, aoPressionar: aoPressionar)
              : BotaoTrato.secundario(verbo, aoPressionar: aoPressionar),
        ],
      ),
    );
  }
}
