import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'campos_trava.dart';
import 'medidas_modais.dart';
import 'provas_modal.dart';

const kTiposMedida = {
  'aviso': 'Aviso',
  'restricao': 'Restrição de funções',
  'suspensao': 'Suspensão',
  'encerramento': 'Encerramento',
  'bloqueio_preventivo': 'Bloqueio preventivo',
  'trava_saque': 'Trava de saques',
  'remocao_conteudo': 'Remoção de conteúdo',
};

const kResultadosContestacao = {'mantida': 'Mantida', 'alterada': 'Alterada', 'revertida': 'Revertida'};

String nomeDaMedida(String tipo) => kTiposMedida[tipo] ?? tipo;

(String, Tom) chipDaMedida(Medida m) {
  if (m.revertidaEm != null) return ('Revertida', Tom.neutro);
  return m.vigente ? ('Em vigor', Tom.alerta) : ('Encerrada', Tom.neutro);
}

/// Medidas de conta (Termos 11.8 e 20). Tudo pede `medidas_aplicar`; quem decide é o backend.
class MedidasTela extends StatefulWidget {
  const MedidasTela({super.key});

  @override
  State<MedidasTela> createState() => _MedidasTelaState();
}

class _MedidasTelaState extends State<MedidasTela> {
  String _usuario = '';
  String? _tipo;
  bool _vigentes = false;
  bool _contestacoes = false;
  int _versao = 0;

  Future<void> _aplicar() async {
    if (await abrirAplicarMedida(context) && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final filtro = FiltroMedidas(
      usuarioId: _usuario.isEmpty ? null : _usuario,
      tipo: _tipo,
      vigentes: _vigentes,
      contestacaoAberta: _contestacoes,
    );
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(labelText: 'Código da conta', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _usuario = v.trim()),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: _tipo,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final e in kTiposMedida.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _tipo = v),
            ),
          ),
          FilterChip(label: const Text('Só em vigor'), selected: _vigentes, onSelected: (v) => setState(() => _vigentes = v)),
          FilterChip(
            label: const Text('Contestação aberta'),
            selected: _contestacoes,
            onSelected: (v) => setState(() => _contestacoes = v),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Medidas de conta',
          subtitulo: 'Aviso, restrição, suspensão e contestação (Termos 20)',
          acoes: [BotaoTrato.primario('Aplicar medida', aoPressionar: _aplicar)],
        ),
        Expanded(
          child: FilaRemota<Medida>(
            key: ValueKey('fila-medidas-$_versao'),
            filtro: filtro,
            esqueleto: const EsqueletoPagina(),
            chave: (m) => m.id,
            carregar: (deslocamento, limite) =>
                context.api.listarMedidas(filtro, deslocamento: deslocamento, limite: limite),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<Medida>(
                      itens: fila.itens,
                      chave: (m) => m.id,
                      mensagemSemItens: 'Nenhuma medida com esse filtro.',
                      tituloDetalhe: (m) => m.protocolo ?? nomeDaMedida(m.tipo),
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'medidas'),
                      itemBuilder: (context, m, sel) {
                        final (texto, tom) = chipDaMedida(m);
                        return CartaoLista(
                          titulo: '${nomeDaMedida(m.tipo)} · ${m.usuarioNome ?? 'Conta'}',
                          linhas: [
                            if (m.protocolo != null) m.protocolo!,
                            m.contestacaoAberta
                                ? 'Responder contestação até ${formatarData(m.contestacao!.responderAte)}'
                                : 'Desde ${formatarDia(m.inicioEm)}',
                          ],
                          chips: [
                            ChipEstado(texto, tom: tom),
                            if (m.contestacaoAberta) const ChipEstado('Contestação aberta', tom: Tom.erro),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, m) => CarregaDados<Medida>(
                        key: ValueKey('medida-${m.id}'),
                        esqueleto: const EsqueletoPagina(),
                        atualizarSozinho: true,
                        carregar: () => context.api.obterMedida(m.id),
                        construir: (context, completa, recarregar) => _DetalheMedida(
                          key: ValueKey(m.id),
                          medida: completa,
                          aoMudar: () async {
                            await recarregar();
                            await fila.recarregar();
                          },
                        ),
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

class _DetalheMedida extends StatefulWidget {
  const _DetalheMedida({super.key, required this.medida, required this.aoMudar});
  final Medida medida;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheMedida> createState() => _DetalheMedidaState();
}

class _DetalheMedidaState extends State<_DetalheMedida> {
  final _resposta = TextEditingController();
  final _dias = TextEditingController();
  final _justificativa = TextEditingController();
  String? _resultado;
  bool _pedirJustificativa = false;
  bool _tentou = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _resposta.dispose();
    _dias.dispose();
    _justificativa.dispose();
    super.dispose();
  }

  /// O backend recusa (422 mesmo_analista) sem justificativa; aqui o campo já aparece.
  bool get _fuiEu {
    String limpo(String? s) => (s ?? '').replaceAll('-', '');
    final eu = limpo(context.eu?.id);
    return eu.isNotEmpty && limpo(widget.medida.aplicadaPor) == eu;
  }

  int? get _novosDias {
    final n = int.tryParse(_dias.text.trim());
    return n == null || n < 1 || n > 3650 ? null : n;
  }

  Future<void> _enviar(Future<Medida> Function() chamada, String sucesso) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await chamada();
      if (mounted) mostrarAviso(context, sucesso);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          if (e is ErroApi && e.codigo == 'mesmo_analista') _pedirJustificativa = true;
        });
      }
    } finally {
      await widget.aoMudar();
      if (mounted) setState(() => _enviando = false);
    }
  }

  bool get _travaPorFraude => widget.medida.tipo == 'trava_saque' && widget.medida.motivoFraude;

  Future<void> _reverter() async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Reverter a medida?',
      descricao: '${_travaPorFraude ? '$kFimDaTravaAoReverter ' : ''}'
          'A conta volta ao que as outras medidas em vigor permitem. O usuário é avisado da reversão; '
          'o motivo abaixo é interno.',
      rotuloConfirmar: 'Reverter medida',
    );
    if (motivo == null || !mounted) return;
    final api = context.api;
    await _enviar(() => api.reverterMedida(widget.medida.id, motivo: motivo), 'Medida revertida.');
  }

  Future<void> _registrarContestacao() async {
    if (await abrirRegistroDeContestacao(context, widget.medida) && mounted) await widget.aoMudar();
  }

  Future<void> _decidir() async {
    if (_enviando) return;
    setState(() => _tentou = true);
    final resultado = _resultado;
    final resposta = _resposta.text.trim();
    final dias = resultado == 'alterada' ? _novosDias : null;
    final comJustificativa = _fuiEu || _pedirJustificativa;
    final justificativa = _justificativa.text.trim();
    if (resultado == null ||
        resposta.length < kMotivoMinimo ||
        (resultado == 'alterada' && dias == null) ||
        (comJustificativa && justificativa.length < kMotivoMinimo)) {
      return;
    }
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Decidir a contestação?',
      texto: 'Decisão: ${kResultadosContestacao[resultado]}'
          '${dias == null ? '' : ' (a medida passa a terminar em $dias dia(s) a partir de hoje)'}.\n\n'
          'O usuário vai ler:\n$resposta'
          '${comJustificativa ? '\n\nSó a equipe vê:\n$justificativa' : ''}'
          '${resultado == 'revertida' && _travaPorFraude ? '\n\n$kFimDaTravaAoReverter' : ''}'
          '${resultado == 'alterada' && _travaPorFraude ? '\n\n$kFimDaTravaAoEncurtar' : ''}',
      verbo: 'Enviar decisão',
    );
    if (!ok || !mounted) return;
    final api = context.api;
    await _enviar(
      () => api.decidirContestacaoMedida(
        widget.medida.id,
        resultado: resultado,
        resposta: resposta,
        diasAPartirDeHoje: dias,
        mesmoAnalistaJustificativa: comJustificativa ? justificativa : null,
      ),
      'Contestação decidida.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.medida;
    final (texto, tom) = chipDaMedida(m);
    final contestacao = m.contestacao;
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text('${nomeDaMedida(m.tipo)} · ${m.usuarioNome ?? 'Conta'}', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            ChipEstado(texto, tom: tom),
            if (m.infracaoGrave) const ChipEstado('Infração grave', tom: Tom.erro),
            if (m.impedirNovaConta) const ChipEstado('Impede nova conta', tom: Tom.erro),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (m.protocolo != null) Linha('Protocolo', m.protocolo!),
        Linha('Código da conta', m.usuarioId),
        const SizedBox(height: EspacosTrato.x4),
        Text('O que o usuário lê', style: TipografiaTrato.secao),
        Linha('Motivo', m.motivoAoUsuario),
        Linha('Cláusulas', m.clausulas.join(', ')),
        Linha('Início', formatarData(m.inicioEm)),
        Linha('Fim', m.fimEm == null ? 'Sem data final' : formatarData(m.fimEm!)),
        Linha('Pedidos e valores', m.efeito),
        Linha('Como contestar', m.comoContestar),
        if (m.contestavelAte != null) Linha('Pode contestar até', formatarData(m.contestavelAte!)),
        const SizedBox(height: EspacosTrato.x4),
        Text('Só a equipe vê', style: TipografiaTrato.secao),
        if (m.detalheAdiado) Linha('Motivo registrado (adiado)', m.motivoCompleto),
        if (m.justificativaAdiamento != null) Linha('Por que adiou', m.justificativaAdiamento!),
        if (m.tipo == 'encerramento')
          Linha(
            'Sem falta do usuário',
            switch (m.semFalta) {
              true => 'Sim: Tratinhos não usados guardados por 90 dias (Termos 13.10)',
              false => 'Não',
              null => 'Não informado',
            },
          ),
        if (m.infracaoGrave) const Linha('Infração grave', 'Sim (Termos 20.9)'),
        if (m.impedirNovaConta) const Linha('Impedimento de nova conta', 'Sim'),
        if (m.tipo == 'trava_saque') Linha('Trava por fraude', m.motivoFraude ? 'Sim' : 'Não'),
        if (m.limiteRetencaoCentavos case final limite?) Linha('Limite da retenção', formatarReais(limite)),
        if (m.tipo == 'trava_saque') Linha('Efeito no dinheiro', m.motivoFraude ? kTravaComFraude : kTravaSemFraude),
        Linha('Nota interna', m.notaInterna ?? 'Sem nota'),
        Linha(
          'Aplicada por',
          m.origem == 'automatica'
              ? 'Sistema (automática)'
              : (_fuiEu ? 'Você' : m.aplicadaPorNome ?? 'Outra pessoa da equipe'),
        ),
        if (m.revertidaEm != null) Linha('Revertida em', formatarData(m.revertidaEm!)),
        if (contestacao != null) ...[
          const SizedBox(height: EspacosTrato.x4),
          Text('Contestação', style: TipografiaTrato.secao),
          if (contestacao.protocolo != null) Linha('Protocolo', contestacao.protocolo!),
          Linha('Situação', kResultadosContestacao[contestacao.status] ?? contestacao.status),
          Linha('Canal', contestacao.canal == 'sac' ? 'Atendimento' : contestacao.canal),
          Linha('Aberta em', formatarData(contestacao.abertaEm)),
          Linha('Responder até', formatarData(contestacao.responderAte)),
          Linha('Versão do usuário', contestacao.versao),
          if (m.contestacaoAnalistaNome != null) Linha('Analista', m.contestacaoAnalistaNome!),
          if (contestacao.resposta != null) Linha('Resposta ao usuário', contestacao.resposta!),
          if (contestacao.decididaEm != null) Linha('Decidida em', formatarData(contestacao.decididaEm!)),
          if (contestacao.anexos.isEmpty)
            const Linha('Provas', 'Nenhuma prova anexada.')
          else ...[
            for (final (i, a) in contestacao.anexos.indexed)
              Linha('Prova ${i + 1}', '${formatoDoArquivo(a.tipoConteudo) ?? 'arquivo'} · ${tamanhoLegivel(a.tamanhoBytes)}'),
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoTrato.secundario(
                'Abrir provas',
                aoPressionar: () => abrirProvasDaContestacao(context, m.id, m.protocolo ?? 'medida'),
              ),
            ),
          ],
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
            if (contestacao == null)
              BotaoTrato.secundario('Registrar contestação', aoPressionar: _enviando ? null : _registrarContestacao),
            if (m.revertidaEm == null)
              BotaoTrato.destrutivo('Reverter medida', aoPressionar: _enviando ? null : _reverter),
          ],
        ),
        if (m.contestacaoAberta) ..._formularioDaDecisao(),
      ],
    );
  }

  List<Widget> _formularioDaDecisao() {
    final comJustificativa = _fuiEu || _pedirJustificativa;
    return [
      const SizedBox(height: EspacosTrato.x5),
      const Divider(),
      Text('Decidir a contestação', style: TipografiaTrato.secao),
      const SizedBox(height: EspacosTrato.x3),
      Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          for (final (valor, rotulo) in const [('mantida', 'Manter'), ('alterada', 'Encurtar'), ('revertida', 'Reverter')])
            ChoiceChip(
              label: Text(rotulo),
              selected: _resultado == valor,
              onSelected: _enviando ? null : (_) => setState(() => _resultado = valor),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      if (_tentou && _resultado == null)
        Text('Escolha uma decisão.', style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto)),
      if (_resultado == 'alterada') ...[
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _dias,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Novo prazo (dias a partir de hoje)',
            helperText: 'Tem de encurtar a medida. O servidor confere.',
            errorText: _tentou && _novosDias == null ? 'Informe de 1 a 3650 dias' : null,
          ),
        ),
      ],
      const SizedBox(height: EspacosTrato.x3),
      TextField(
        controller: _resposta,
        minLines: 3,
        maxLines: 6,
        maxLength: 4000,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Resposta que o usuário vai ler',
          errorText:
              _tentou && _resposta.text.trim().length < kMotivoMinimo ? 'Escreva ao menos $kMotivoMinimo caracteres' : null,
        ),
      ),
      if (comJustificativa) ...[
        const BannerInfo(
          'Você aplicou esta medida. Passe a outro analista; se não for possível, justifique.',
          tom: Tom.alerta,
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _justificativa,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Por que você mesmo decide (só a equipe vê)',
            errorText: _tentou && _justificativa.text.trim().length < kMotivoMinimo
                ? 'Escreva ao menos $kMotivoMinimo caracteres'
                : null,
          ),
        ),
      ],
      const AvisoAuditoria(),
      const SizedBox(height: EspacosTrato.x3),
      Align(
        alignment: Alignment.centerRight,
        child: BotaoTrato.primario(
          'Revisar decisão',
          aoPressionar: _enviando ? null : _decidir,
          carregando: _enviando,
          rotuloCarregando: 'Enviando',
        ),
      ),
    ];
  }
}
