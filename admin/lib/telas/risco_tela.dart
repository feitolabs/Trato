import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'campos_ao_usuario.dart';
import 'campos_trava.dart';
import 'conversa_modal.dart';

/// Risco e antifraude (RF-RIS-01 a RF-RIS-04).
class RiscoTela extends StatefulWidget {
  const RiscoTela({super.key});

  @override
  State<RiscoTela> createState() => _RiscoTelaState();
}

class _RiscoTelaState extends State<RiscoTela> {
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
        'saque_travado' => 'Trava de saques',
        'denuncia_perfil' => 'Denúncia de perfil',
        'denuncia_chat' => 'Denúncia no chat',
        final t => '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}',
      };

  @override
  Widget build(BuildContext context) {
    // Recarregar mantém filtro e alerta selecionado (antes a tela inteira era recriada).
    return CarregaDados<List<AlertaRisco>>(
      esqueleto: const EsqueletoPagina(),
      atualizarSozinho: true,
      carregar: context.api.listarAlertasRisco,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum alerta de risco',
      detalheVazio: 'Quando o sistema detectar algo fora do normal, o alerta aparece aqui.',
      construir: (context, lista, recarregar) => _FilaRisco(lista: lista, aoMudar: recarregar),
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
  bool _soDenuncias = false;

  /// Denúncias de perfil e de chat (tipos `denuncia_*`), para a moderação priorizar.
  static bool ehDenuncia(AlertaRisco a) => a.tipo.startsWith('denuncia_');

  @override
  Widget build(BuildContext context) {
    final itens = [
      for (final a in widget.lista)
        if ((_status == 'todos' || (_status == 'abertos') == !a.resolvido) &&
            (_severidade == null || a.severidade == _severidade) &&
            (!_soDenuncias || ehDenuncia(a)))
          a,
    ];
    final denuncias = widget.lista.where((a) => ehDenuncia(a) && !a.resolvido).length;
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
            chave: (a) => a.id,
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
                    EspacosTrato.x3,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      key: const ValueKey('risco-so-denuncias'),
                      label: Text('Só denúncias $denuncias'),
                      selected: _soDenuncias,
                      onSelected: (v) => setState(() => _soDenuncias = v),
                      labelStyle: TipografiaTrato.etiqueta.copyWith(
                        color: _soDenuncias ? CoresTrato.primaria : CoresTrato.textoMudo,
                      ),
                      side: BorderSide(color: _soDenuncias ? CoresTrato.bordaSelecionada : CoresTrato.bordaForte),
                    ),
                  ),
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
  bool _abrindoTrava = false;
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
    String? Function()? mensagemDoServidor,
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
    final ok = await executar(context, () => executarAcao(motivo),
        sucesso: sucesso, mensagemDoServidor: mensagemDoServidor);
    if (ok) widget.aoMudar();
  }

  /// A trava de saques e o bloqueio criam uma medida: pede também o texto ao usuário e as cláusulas.
  Future<void> _acaoComAviso({
    required String titulo,
    required String descricao,
    required String verbo,
    required Future<void> Function(String motivo, String aoUsuario, List<String> clausulas) executarAcao,
    required String sucesso,
    String? Function()? mensagemDoServidor,
    CamposTrava? trava,
    bool destrutivo = false,
  }) async {
    final aviso = CamposAoUsuario();
    final r = await pedirFormulario<(String, String, List<String>)>(
      context,
      titulo: titulo,
      consequencia: descricao,
      rotuloConfirmar: verbo,
      destrutivo: destrutivo,
      rotuloMotivo: 'Motivo interno (o usuário não vê)',
      campos: (ctx, rebuild) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trava != null) CamposTravaForm(trava, aoMudar: rebuild),
          CamposAoUsuarioForm(aviso, aoMudar: rebuild),
        ],
      ),
      camposValidos: () => aviso.valido && (trava?.valido ?? true),
      resultado: (m) => (m, aviso.motivo, aviso.clausulas),
    );
    if (r == null || !mounted) return;
    final ok = await executar(context, () => executarAcao(r.$1, r.$2, r.$3),
        sucesso: sucesso, mensagemDoServidor: mensagemDoServidor);
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
    // Resposta do backend à trava ou à remoção dela, mostrada no aviso de sucesso.
    String? mensagem;

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
        // O backend confere o vínculo entre a base escolhida e o pedido.
        if (a.pedidoId != null && context.pode(Permissao.conversasLer)) ...[
          const SizedBox(height: EspacosTrato.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.secundario(
              'Ver conversa',
              aoPressionar: () => abrirConversa(context, a.pedidoId!, a.pedido ?? 'pedido',
                  baseInicial: a.tipo.startsWith('denuncia_') ? 'denuncia' : 'incidente'),
            ),
          ),
        ],
        if (a.contaRestrita || a.contaBloqueada || a.travaFraudeVigente == true) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(
            a.contaBloqueada
                ? 'A conta não cria nem recebe pedidos novos. Reversível com motivo.'
                    '${a.travaFraudeVigente == true ? ' Há trava por fraude em vigor. $kTravaComFraude' : ''}'
                : switch (a.travaFraudeVigente) {
                    true => 'Há trava por fraude em vigor. $kTravaComFraude',
                    false => 'Não há trava por fraude em vigor. $kTravaSemFraude',
                    null => 'Só a trava por fraude adia a liberação no livro, e não foi informado se há uma: confira '
                        'em Medidas. Pagamento manual ou no Stripe: confira à mão.',
                  },
            titulo: a.contaBloqueada
                ? 'Conta bloqueada.'
                : (a.contaRestrita ? 'Conta restrita.' : 'Trava por fraude.'),
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
          const BannerInfo(kAcoesImediatas, tom: Tom.alerta),
          const SizedBox(height: EspacosTrato.x3),
          if (a.contaBloqueada)
            const BannerInfo('Conta bloqueada: para registrar uma trava de saques, use a seção Medidas.')
          else
            _AcaoPreventiva(
              titulo: 'Registrar trava de saques',
              descricao: 'Restringe a conta. Só a trava por fraude, com limite, adia a liberação no livro; pagamento '
                  'manual ou no Stripe continua sem trava. Reversível com motivo.',
              verbo: 'Registrar trava',
              icone: IconesTrato.travar,
              aoPressionar: () async {
                if (_abrindoTrava) return;
                _abrindoTrava = true;
                // Só quem tem a permissão da rota pergunta o prazo máximo.
                final prazo = context.pode(Permissao.medidasAplicar) ? await lerPrazoMaximoDaTrava(api) : null;
                _abrindoTrava = false;
                if (!context.mounted) return;
                final trava = CamposTrava()..prazoMaximo = prazo;
                await _acaoComAviso(
                  titulo: 'Registrar trava de saques de $nome?',
                  descricao: 'A trava é registrada e a conta fica restrita.',
                  verbo: 'Registrar trava',
                  trava: trava,
                  executarAcao: (m, u, c) async => mensagem = await api.travarSaque(a.usuarioId!,
                      motivo: m,
                      motivoUsuario: u,
                      clausulas: c,
                      motivoFraude: trava.fraude,
                      limiteRetencaoCentavos: trava.limiteCentavos,
                      dias: trava.dias),
                  sucesso: 'Trava de saques enviada. Confira a medida em Medidas.',
                  mensagemDoServidor: () => mensagem,
                );
              },
            ),
          if (a.contaRestrita) ...[
            const SizedBox(height: EspacosTrato.x3),
            _AcaoPreventiva(
              titulo: 'Remover trava de saques',
              descricao: '${avisoAoDestravar(a.travaFraudeVigente)} A conta continua restrita se houver outra medida '
                  'em vigor. Exige motivo.',
              verbo: 'Remover trava',
              icone: IconesTrato.destravar,
              aoPressionar: () => _acao(
                titulo: 'Remover a trava de saques de $nome?',
                descricao: '${avisoAoDestravar(a.travaFraudeVigente)} A conta continua restrita se houver outra '
                    'medida em vigor.',
                verbo: 'Remover trava',
                executarAcao: (m) async => mensagem = await api.destravarSaque(a.usuarioId!, motivo: m),
                sucesso: 'Trava de saques removida. Confira a liberação e os repasses à mão.',
                mensagemDoServidor: () => mensagem,
              ),
            ),
          ],
          const SizedBox(height: EspacosTrato.x3),
          _AcaoPreventiva(
            titulo: a.contaBloqueada ? 'Desbloquear conta' : 'Bloqueio preventivo',
            descricao: a.contaBloqueada
                ? 'A conta volta a criar e receber pedidos. Exige motivo.'
                : 'A conta não cria nem recebe pedidos novos. Reversível com motivo.',
            verbo: a.contaBloqueada ? 'Desbloquear conta' : 'Bloquear conta',
            destrutivo: !a.contaBloqueada,
            icone: Icons.shield_outlined,
            aoPressionar: () => a.contaBloqueada
                ? _acao(
                    titulo: 'Desbloquear a conta de $nome?',
                    descricao: '$nome volta a criar e receber pedidos.',
                    verbo: 'Desbloquear conta',
                    executarAcao: (m) => api.desbloquearConta(a.usuarioId!, motivo: m),
                    sucesso: 'Conta desbloqueada.',
                  )
                : _acaoComAviso(
                    titulo: 'Bloquear a conta de $nome?',
                    descricao: '$nome não cria nem recebe pedidos novos. Pedidos em andamento continuam.',
                    verbo: 'Bloquear conta',
                    destrutivo: true,
                    executarAcao: (m, u, c) =>
                        api.aplicarBloqueioPreventivo(a.usuarioId!, motivo: m, motivoUsuario: u, clausulas: c),
                    sucesso: 'Conta bloqueada.',
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
