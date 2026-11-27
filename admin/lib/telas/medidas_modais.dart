import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'campos_ao_usuario.dart';
import 'campos_trava.dart';
import 'medidas_tela.dart';
import 'modal_sigiloso.dart';
import 'provas_modal.dart' show tamanhoLegivel;
import 'seletor_arquivo.dart';

/// Aplicar uma medida (Termos 20.4): preencher, conferir o que o usuário lê e confirmar.
/// Devolve true se o backend aceitou. [usuarioId] preenchido vem da busca de usuários.
Future<bool> abrirAplicarMedida(BuildContext context, {String? usuarioId, String? usuarioNome}) async =>
    await mostrarModal<bool>(
      context,
      largura: 600,
      construir: (_) => _ModalAplicar(usuarioId: usuarioId, usuarioNome: usuarioNome),
    ) ??
    false;

/// Termos 20.6: o backend não trata pedidos nem valores; a única exceção é a trava de saques por
/// fraude, que adia a liberação no livro. Só informa: nenhuma ação sai daqui.
const _avisoConferenciaManual = BannerInfo(
  'Pedidos em andamento e valores não são tratados automaticamente por esta medida. '
  'Confira cada caso manualmente (Termos 20.6).',
  titulo: 'Conferência manual necessária.',
  tom: Tom.alerta,
);

const kEfeitoSemFalta = 'Sem falta do usuário: os Tratinhos não usados ficam guardados por 90 dias, para uso se a conta '
    'for restabelecida (Termos 13.10).';
const kEfeitoComFalta = 'Por falta do usuário: os Tratinhos não ficam guardados por essa regra (Termos 13.10).';
const kSemFaltaDefinitivo = 'Depois de aplicar, não há como trocar de "por falta" para "sem falta". Confira antes.';

const _avisoTravaPorFraude = BannerInfo(
  '$kTravaComFraude Pedidos em andamento também precisam de conferência manual (Termos 20.6).',
  titulo: 'Trava por fraude.',
  tom: Tom.alerta,
);

/// Contestação que chegou pelo atendimento (20.5).
Future<bool> abrirRegistroDeContestacao(BuildContext context, Medida medida) async =>
    await mostrarModal<bool>(context, construir: (_) => _ModalContestacao(medida)) ?? false;

class _ModalAplicar extends StatefulWidget {
  const _ModalAplicar({this.usuarioId, this.usuarioNome});
  final String? usuarioId;
  final String? usuarioNome;

  @override
  State<_ModalAplicar> createState() => _ModalAplicarState();
}

class _ModalAplicarState extends State<_ModalAplicar> {
  late final _usuario = TextEditingController(text: widget.usuarioId ?? '');
  final _motivo = TextEditingController();
  final _clausulas = TextEditingController();
  final _dias = TextEditingController();
  final _efeito = TextEditingController();
  final _contestar = TextEditingController();
  final _justificativa = TextEditingController();
  final _nota = TextEditingController();
  final _limite = TextEditingController();
  bool _fraude = false;
  int? _prazoMaximo;

  Future<void> _lerPrazoMaximo() async {
    final n = await lerPrazoMaximoDaTrava(context.api);
    if (mounted && n != null) setState(() => _prazoMaximo = n);
  }

  int get _maximoDeDias => _porFraude ? (_prazoMaximo ?? 3650) : 3650;
  String _tipo = 'aviso';
  bool _adiar = false;
  bool _infracaoGrave = false;

  /// Sem pré-escolha: em encerramento a pessoa precisa responder.
  bool? _semFalta;
  bool _impedirNovaConta = false;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_usuario, _motivo, _clausulas, _dias, _efeito, _contestar, _justificativa, _nota, _limite]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Encerramento não tem prazo (o backend recusa).
  bool get _temPrazo => _tipo != 'encerramento';

  int? get _numeroDeDias => !_temPrazo || _dias.text.trim().isEmpty ? null : int.tryParse(_dias.text.trim());

  bool get _porFraude => _tipo == 'trava_saque' && _fraude;

  bool get _diasValidos {
    if (!_temPrazo || _dias.text.trim().isEmpty) return true;
    final n = _numeroDeDias;
    return n != null && n >= 1 && n <= _maximoDeDias;
  }

  String? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Campo opcional com mínimo no backend: vazio ou pelo menos 10 caracteres.
  bool _opcionalValido(TextEditingController c) => c.text.trim().isEmpty || c.text.trim().length >= kMotivoMinimo;

  bool get _valido {
    final clausulas = lerClausulas(_clausulas.text);
    return _usuario.text.trim().isNotEmpty &&
        _motivo.text.trim().length >= kMotivoMinimo &&
        clausulas.isNotEmpty &&
        clausulas.length <= 20 &&
        _diasValidos &&
        (!_porFraude || lerLimiteDaTrava(_limite.text) != null) &&
        (_tipo != 'encerramento' || _semFalta != null) &&
        _opcionalValido(_efeito) &&
        _opcionalValido(_contestar) &&
        (!_adiar || _justificativa.text.trim().isNotEmpty);
  }

  NovaMedida get _nova => NovaMedida(
        usuarioId: _usuario.text.trim(),
        tipo: _tipo,
        motivo: _motivo.text.trim(),
        clausulas: lerClausulas(_clausulas.text),
        dias: _numeroDeDias,
        efeito: _opcional(_efeito),
        comoContestar: _opcional(_contestar),
        detalheAdiado: _adiar,
        justificativaAdiamento: _adiar ? _justificativa.text.trim() : null,
        notaInterna: _opcional(_nota),
        semFalta: _tipo == 'encerramento' ? _semFalta : null,
        infracaoGrave: _tipo == 'encerramento' && _infracaoGrave,
        impedirNovaConta: _tipo == 'encerramento' && _infracaoGrave && _impedirNovaConta,
        motivoFraude: _porFraude,
        limiteRetencaoCentavos: _porFraude ? lerLimiteDaTrava(_limite.text) : null,
      );

  Future<void> _aplicar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final nova = _nova;
      final r = await context.api.aplicarMedida(nova);
      if (!mounted) return;
      final protocolo = r.medida.protocolo ?? 'sem protocolo';
      // Pediu por fraude e o servidor não devolveu a marcação: não prometer retenção.
      final semConfirmacao = nova.motivoFraude && !r.medida.motivoFraude;
      // Escolha enviada e não devolvida igual (inclui repetição de uma medida anterior).
      final semFaltaDiferente = nova.semFalta != null && r.medida.semFalta != nova.semFalta;
      mostrarAviso(
        context,
        semFaltaDiferente
            ? 'O servidor não confirmou a resposta "sem falta" ($protocolo). Confira a medida.'
            : semConfirmacao
            ? 'O servidor não confirmou a trava por fraude ($protocolo). Não conte com a retenção: confira a medida.'
            : r.repetida
                ? 'Uma medida igual já tinha sido criada há menos de 5 minutos ($protocolo). Nada novo foi criado.'
                : 'Medida aplicada. Protocolo $protocolo.',
        erro: semConfirmacao || semFaltaDiferente,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  Widget _campo(String rotulo, TextEditingController c, {int maximo = 2000, int linhas = 1, String? ajuda, String? erro}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: ajuda,
            helperMaxLines: 2,
            errorText: erro,
            counterText: '',
          ),
        ),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x4),
        child: Text(t, style: TipografiaTrato.secao),
      );

  List<Widget> _formulario() => [
        if (widget.usuarioNome != null) Linha('Conta', widget.usuarioNome!),
        if (widget.usuarioId == null) _campo('Código da conta', _usuario, maximo: 64),
        Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x3),
          child: DropdownButtonFormField<String>(
            initialValue: _tipo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo da medida'),
            items: [for (final e in kTiposMedida.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() {
              _tipo = v ?? _tipo;
              if (_tipo != 'trava_saque') {
                _fraude = false;
                _limite.clear();
              }
              if (_tipo != 'encerramento') {
                _semFalta = null;
                _infracaoGrave = false;
                _impedirNovaConta = false;
              }
            }),
          ),
        ),
        if (_tipo == 'trava_saque') ...[
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Por fraude', style: TipografiaTrato.corpo),
              value: _fraude,
              onChanged: (v) {
                setState(() => _fraude = v ?? false);
                if (_fraude && _prazoMaximo == null) _lerPrazoMaximo();
              },
            ),
          ),
          if (_fraude) ...[
            Text(kTravaRenovar, style: TipografiaTrato.legenda),
            _campo('Limite da retenção em R\$ (prejuízo apurado)', _limite,
                maximo: 20,
                erro: _limite.text.trim().isNotEmpty && lerLimiteDaTrava(_limite.text) == null
                    ? kErroLimiteDaTrava
                    : null),
          ] else
            Text(kTravaSemFraude, style: TipografiaTrato.legenda),
        ],
        _titulo('O usuário vai ler'),
        _campo('Motivo (o usuário lê)', _motivo, linhas: 3, ajuda: 'Pelo menos $kMotivoMinimo caracteres. Não cite quem denunciou.'),
        _campo('Cláusulas dos Termos', _clausulas, maximo: 500, ajuda: 'Separe por vírgula. Exemplo: 9.2, 20.3'),
        if (_temPrazo)
          _campo('Duração em dias', _dias,
              maximo: 4,
              ajuda: !_porFraude
                  ? 'Vazio = sem data final.'
                  : _prazoMaximo == null
                      ? 'Vazio = prazo máximo configurado no servidor.'
                      : 'Vazio = prazo máximo configurado ($_prazoMaximo dias).',
              erro: _diasValidos ? null : 'Use de 1 a $_maximoDeDias dias'),
        const SizedBox(height: EspacosTrato.x3),
        _porFraude ? _avisoTravaPorFraude : _avisoConferenciaManual,
        _campo('Pedidos e valores em andamento (opcional)', _efeito,
            linhas: 2,
            ajuda: 'Vazio = texto padrão do servidor.',
            erro: _opcionalValido(_efeito) ? null : 'Escreva ao menos $kMotivoMinimo caracteres ou deixe vazio'),
        _campo('Como contestar (opcional)', _contestar,
            linhas: 2,
            ajuda: 'Vazio = texto padrão do servidor.',
            erro: _opcionalValido(_contestar) ? null : 'Escreva ao menos $kMotivoMinimo caracteres ou deixe vazio'),
        _titulo('Só a equipe vê'),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Adiar o detalhe do motivo para o usuário', style: TipografiaTrato.corpo),
            subtitle: Text('Ele recebe o aviso e as cláusulas, sem o texto do motivo.', style: TipografiaTrato.legenda),
            value: _adiar,
            onChanged: (v) => setState(() => _adiar = v ?? false),
          ),
        ),
        if (_adiar) _campo('Justificativa do adiamento (interna)', _justificativa, maximo: 1000, linhas: 2),
        if (_tipo == 'encerramento') ...[
          const SizedBox(height: EspacosTrato.x3),
          Text('Foi sem falta do usuário? (obrigatório)', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final (valor, rotulo) in const [(true, 'Sim, sem falta'), (false, 'Não, por falta')])
                ChoiceChip(
                  label: Text(rotulo),
                  selected: _semFalta == valor,
                  onSelected: (_) => setState(() => _semFalta = valor),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text('$kEfeitoSemFalta $kSemFaltaDefinitivo', style: TipografiaTrato.legenda),
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Infração grave (Termos 20.9)', style: TipografiaTrato.corpo),
              subtitle: Text('A conta encerrada por infração grave não pode pedir retorno.', style: TipografiaTrato.legenda),
              value: _infracaoGrave,
              onChanged: (v) => setState(() {
                _infracaoGrave = v ?? false;
                if (!_infracaoGrave) _impedirNovaConta = false;
              }),
            ),
          ),
          if (_infracaoGrave)
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Impedir criação de nova conta', style: TipografiaTrato.corpo),
                subtitle: Text('Registra impedimento de cadastro vinculado a esta medida.', style: TipografiaTrato.legenda),
                value: _impedirNovaConta,
                onChanged: (v) => setState(() => _impedirNovaConta = v ?? false),
              ),
            ),
        ],
        _campo('Nota interna (opcional)', _nota, linhas: 2),
      ];

  List<Widget> _revisao() {
    final n = _nova;
    return [
      Linha('Conta', widget.usuarioNome ?? n.usuarioId),
      Linha('Tipo', nomeDaMedida(n.tipo)),
      _titulo('O usuário vai ler'),
      Linha(
        'Motivo',
        n.detalheAdiado ? 'Aviso de que o detalhe do motivo foi adiado, com as cláusulas. O seu texto não vai.' : n.motivo,
      ),
      Linha('Cláusulas', n.clausulas.join(', ')),
      Linha(
        'Duração',
        n.dias != null
            ? '${n.dias} dia(s)'
            : (n.motivoFraude ? 'Prazo máximo configurado no servidor' : 'Sem data final'),
      ),
      if (n.tipo == 'trava_saque') Linha('Trava por fraude', n.motivoFraude ? 'Sim' : 'Não'),
      if (n.limiteRetencaoCentavos case final limite?) Linha('Limite da retenção', formatarReais(limite)),
      Linha('Pedidos e valores', n.efeito ?? 'Texto padrão do servidor'),
      Linha('Como contestar', n.comoContestar ?? 'Texto padrão do servidor'),
      const SizedBox(height: EspacosTrato.x3),
      n.motivoFraude ? _avisoTravaPorFraude : _avisoConferenciaManual,
      _titulo('Só a equipe vê'),
      if (n.detalheAdiado) Linha('Motivo registrado', n.motivo),
      if (n.justificativaAdiamento != null) Linha('Por que adiar', n.justificativaAdiamento!),
      if (n.semFalta case final semFalta?) ...[
        Linha('Sem falta do usuário', semFalta ? 'Sim' : 'Não'),
        BannerInfo(semFalta ? kEfeitoSemFalta : '$kEfeitoComFalta $kSemFaltaDefinitivo', tom: Tom.alerta),
      ],
      if (n.infracaoGrave) const Linha('Infração grave', 'Sim (Termos 20.9)'),
      if (n.impedirNovaConta) const Linha('Impedir nova conta', 'Sim'),
      Linha('Nota interna', n.notaInterna ?? 'Sem nota'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar a medida?' : 'Aplicar medida',
        consequencia: _revisando
            ? 'A conta muda na hora e o usuário é avisado por escrito. Confira o que ele vai ler.'
            : 'O usuário é avisado por escrito com motivo, cláusulas e como contestar.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi aplicada.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          // O formulário fica montado fora da revisão; os textos ficam nos controladores.
          ...(_revisando ? _revisao() : _formulario()),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(texto: 'A medida fica na auditoria com seu nome e o motivo.'),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          _revisando
              ? BotaoTrato.destrutivo(
                  'Confirmar e aplicar',
                  carregando: _enviando,
                  rotuloCarregando: 'Aplicando',
                  aoPressionar: _enviando ? null : _aplicar,
                )
              : BotaoTrato.primario(
                  'Revisar medida',
                  aoPressionar: _valido
                      ? () => setState(() {
                            _erro = null;
                            _revisando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}

class _ModalContestacao extends StatefulWidget {
  const _ModalContestacao(this.medida);
  final Medida medida;

  @override
  State<_ModalContestacao> createState() => _ModalContestacaoState();
}

class _ModalContestacaoState extends State<_ModalContestacao> with SomeComASessao {
  final _versao = TextEditingController();
  final _anexos = <({String id, String rotulo})>[];
  bool _anexando = false;

  static const _maximoBytes = 10 * 1024 * 1024;
  static const _maximoAnexos = 10;
  static const _aceitos = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

  @override
  void limparSigiloso() {
    _anexos.clear();
    _versao.clear();
  }

  /// Escolher -> pedir o link -> PUT. O anexo só entra na lista se o envio terminar.
  Future<void> _anexar() async {
    if (_anexando || _enviando) return;
    setState(() {
      _anexando = true;
      _erro = null;
    });
    try {
      final a = await seletorDeArquivo(_aceitos.join(','), _maximoBytes);
      if (a == null || !mounted || !context.sessao.logado) return;
      final problema = problemaDoArquivo(a, _aceitos, maximoBytes: _maximoBytes);
      if (problema != null) {
        setState(() => _erro = problema);
        return;
      }
      final api = context.api;
      final envio = await api.pedirAnexoContestacao(widget.medida.id,
          nomeArquivo: a.nome, tipoConteudo: a.tipo, tamanhoBytes: a.tamanho);
      if (!mounted || !context.sessao.logado) return;
      await api.enviarArquivo(envio.url, tipoConteudo: a.tipo, bytes: a.bytes);
      if (mounted && context.sessao.logado) {
        setState(() => _anexos.add((id: envio.id, rotulo: '${a.nome} · ${tamanhoLegivel(a.tamanho)}')));
      }
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _anexando = false);
    }
  }
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _versao.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.registrarContestacaoMedida(widget.medida.id,
          versao: _versao.text.trim(), anexos: [for (final a in _anexos) a.id]);
      if (!mounted) return;
      mostrarAviso(context, 'Contestação registrada.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CorpoModal(
      titulo: 'Registrar contestação do atendimento?',
      consequencia: 'Use quando o usuário contestou pelo atendimento. Depois de registrada, o texto não muda.',
      filhos: [
        if (_erro != null) ...[
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
        TextField(
          controller: _versao,
          minLines: 3,
          maxLines: 6,
          maxLength: 4000,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Versão do usuário, nas palavras dele'),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Text('Provas do usuário (opcional): foto ou PDF de até 10 MB, no máximo $_maximoAnexos.',
            style: TipografiaTrato.legenda),
        for (final a in _anexos)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: EspacosTrato.x2,
            children: [
              Text(a.rotulo, style: TipografiaTrato.corpo),
              BotaoTrato.link('Retirar',
                  aoPressionar: _enviando || _anexando ? null : () => setState(() => _anexos.remove(a))),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoTrato.secundario(
            'Anexar arquivo',
            aoPressionar: _enviando || _anexando || _anexos.length >= _maximoAnexos ? null : _anexar,
            carregando: _anexando,
            rotuloCarregando: 'Enviando',
          ),
        ),
        const AvisoAuditoria(texto: 'O registro fica na auditoria com seu nome.'),
      ],
      acoes: [
        BotaoTrato.secundario('Cancelar', aoPressionar: _enviando || _anexando ? null : () => Navigator.of(context).pop(false)),
        BotaoTrato.primario(
          'Registrar',
          carregando: _enviando,
          rotuloCarregando: 'Registrando',
          aoPressionar: _enviando || _anexando || _versao.text.trim().isEmpty ? null : _registrar,
        ),
      ],
    );
  }
}
