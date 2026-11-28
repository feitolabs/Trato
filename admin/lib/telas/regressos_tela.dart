import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'compensacoes_tela.dart';

/// A seção "Compensações": cada aba só aparece (e só carrega) para quem tem a permissão dela.
class SecaoCompensacoes extends StatelessWidget {
  const SecaoCompensacoes({super.key});

  @override
  Widget build(BuildContext context) {
    final compensa = context.pode(Permissao.disputasDecidir);
    final regresso = context.pode(Permissao.regressoPropor);
    if (!regresso) return const CompensacoesTela();
    if (!compensa) return const RegressosTela();
    return const AbasTrato(abas: [
      AbaTrato('Descontos', conteudo: CompensacoesTela()),
      AbaTrato('Pedidos de volta', conteudo: RegressosTela()),
    ]);
  }
}

const _status = {'proposta': 'Aguardando decisão', 'aprovada': 'Aprovada', 'recusada': 'Recusada'};

/// Pedido de volta ao profissional (Termos 17.4): uma pessoa propõe e outra aprova ou recusa.
class RegressosTela extends StatefulWidget {
  const RegressosTela({super.key});

  @override
  State<RegressosTela> createState() => _RegressosTelaState();
}

class _RegressosTelaState extends State<RegressosTela> {
  String? _situacao;
  int _versao = 0;

  Future<void> _propor() async {
    await mostrarModal<void>(context, largura: 560, construir: (_) => const _ModalProposta());
    if (mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Pedidos de volta ao profissional',
          subtitulo: 'Um propõe, outra pessoa decide (Termos 17.4)',
          acoes: [
            if (context.pode(Permissao.regressoPropor))
              BotaoTrato.primario('Propor pedido de volta', aoPressionar: _propor),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('regresso-situacao'),
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
          ),
        ),
        Expanded(
          child: FilaRemota<Regresso>(
            key: ValueKey('fila-regressos-$_versao'),
            filtro: _situacao,
            esqueleto: const EsqueletoPagina(),
            chave: (r) => r.id,
            carregar: (deslocamento, limite) =>
                context.api.listarRegressos(status: _situacao, deslocamento: deslocamento, limite: limite),
            construir: (context, fila) => MestreDetalhe<Regresso>(
              itens: fila.itens,
              chave: (r) => r.id,
              mensagemSemItens: 'Nenhum pedido de volta com esse filtro.',
              tituloDetalhe: (r) => formatarReais(r.valorCentavos),
              rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'pedidos'),
              itemBuilder: (context, r, sel) => CartaoLista(
                titulo: '${formatarReais(r.valorCentavos)} · ${_status[r.status] ?? r.status}',
                linhas: ['Pedido ${r.pedidoId}', 'Proposto em ${formatarData(r.propostaEm)}'],
                selecionado: sel,
              ),
              detalheBuilder: (context, r) => _Detalhe(key: ValueKey(r.id), inicial: r, aoMudar: fila.recarregar),
            ),
          ),
        ),
      ],
    );
  }
}

const kRegressoPendenteNoFinanceiro = 'Nada foi gravado e a proposta continua pendente. O caso vai ao financeiro.';

class _Detalhe extends StatefulWidget {
  const _Detalhe({super.key, required this.inicial, required this.aoMudar});
  final Regresso inicial;
  final Future<void> Function() aoMudar;

  @override
  State<_Detalhe> createState() => _DetalheState();
}

class _DetalheState extends State<_Detalhe> {
  Regresso? _atual;
  bool _enviando = false;
  String? _erro;

  @override
  void didUpdateWidget(covariant _Detalhe antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.inicial != widget.inicial) _atual = null;
  }

  Future<void> _enviar(Future<(Regresso, String, bool)> Function() chamada) async {
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
      final maximo = e is ErroApi ? e.maximoCentavos : null;
      if (mounted) {
        setState(() => _erro = e is ErroApi && e.codigo == 'estorno_ja_ordenado'
            ? '$e $kRegressoPendenteNoFinanceiro'
            : maximo == null
                ? e.toString()
                : '$e O máximo é ${formatarReais(maximo)}.');
      }
    } finally {
      try {
        await widget.aoMudar();
      } catch (_) {
        // A releitura falhou: o resultado da ação já está na tela.
      }
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _aprovar(Regresso r) async {
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Aprovar o pedido de volta?',
      texto: 'Registra a dívida de ${formatarReais(r.valorCentavos)}, descontada dos próximos repasses do '
          'profissional depois do aviso, e ordena o estorno. Motivo que ele lê:\n\n${r.motivo}',
      verbo: 'Aprovar pedido de volta',
    );
    if (!ok || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final x = await api.aprovarRegresso(r.id);
      final base = x.resultado == 'ja_aprovada' ? 'Já estava aprovado.' : 'Pedido de volta aprovado.';
      return (
        x.proposta,
        x.avisado ? base : '$base O aviso não saiu: sem aviso, nada é descontado.',
        !x.avisado,
      );
    });
  }

  Future<void> _recusar(Regresso r) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Recusar o pedido de volta?',
      descricao: 'A proposta de ${formatarReais(r.valorCentavos)} é encerrada sem criar dívida.',
      rotuloConfirmar: 'Recusar',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final api = context.api;
    await _enviar(() async {
      final x = await api.recusarRegresso(r.id, motivo: motivo);
      return (x.proposta, x.resultado == 'ja_recusada' ? 'Já estava recusado.' : 'Pedido de volta recusado.', false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _atual ?? widget.inicial;
    String limpo(String? s) => (s ?? '').replaceAll('-', '');
    final minha = limpo(context.eu?.id).isNotEmpty && limpo(r.propostaPor) == limpo(context.eu?.id);
    final podeDecidir = context.pode(Permissao.regressoAprovar);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(formatarReais(r.valorCentavos), style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Situação', _status[r.status] ?? r.status),
        Linha('Pedido', r.pedidoId),
        Linha('Profissional', r.profissionalId),
        Linha('Fato que gerou', r.referencia),
        Linha('Motivo (o profissional lê)', r.motivo),
        Linha('Proposto em', formatarData(r.propostaEm)),
        Linha('Proposto por', minha ? 'Você' : 'Outra pessoa da equipe'),
        if (r.decididaEm != null) Linha('Decidido em', formatarData(r.decididaEm!)),
        if (r.motivoDecisao != null) Linha('Motivo da decisão', r.motivoDecisao!),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (r.status == 'proposta' && !podeDecidir)
          const BannerInfo('Aguarda líder de suporte ou administrador.')
        else if (r.status == 'proposta') ...[
          if (minha) const BannerInfo('Você propôs: a aprovação precisa ser de outra pessoa.', tom: Tom.alerta),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            children: [
              BotaoTrato.destrutivo('Recusar', aoPressionar: _enviando ? null : () => _recusar(r)),
              if (!minha) BotaoTrato.primario('Aprovar', aoPressionar: _enviando ? null : () => _aprovar(r)),
            ],
          ),
        ],
      ],
    );
  }
}

class _ModalProposta extends StatefulWidget {
  const _ModalProposta();

  @override
  State<_ModalProposta> createState() => _ModalPropostaState();
}

class _ModalPropostaState extends State<_ModalProposta> {
  final _pedido = TextEditingController();
  final _referencia = TextEditingController();
  final _valor = TextEditingController();
  final _motivo = TextEditingController();
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_pedido, _referencia, _valor, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _referenciaValida => RegExp(r'^[0-9a-fA-F]{8}-?([0-9a-fA-F]{4}-?){3}[0-9a-fA-F]{12}$')
      .hasMatch(_referencia.text.trim());

  int? get _centavos {
    final v = lerReaisEmCentavos(_valor.text);
    return v == null || v <= 0 ? null : v;
  }

  String? get _erroValor {
    if (_valor.text.trim().isEmpty || _centavos != null) return null;
    return lerReaisEmCentavos(_valor.text) == null ? kErroReais : 'Informe um valor maior que zero';
  }

  bool get _valido {
    final n = _motivo.text.trim().length;
    return _pedido.text.trim().isNotEmpty && _referenciaValida && _centavos != null && n >= kMotivoMinimo && n <= 1000;
  }

  Future<void> _propor() async {
    final centavos = _centavos;
    if (_enviando || centavos == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await context.api.proporRegresso(
        pedidoId: _pedido.text.trim(),
        referencia: _referencia.text.trim(),
        valorCentavos: centavos,
        motivo: _motivo.text.trim(),
      );
      if (!mounted) return;
      final valor = formatarReais(r.proposta.valorCentavos);
      mostrarAviso(
        context,
        r.resultado == 'ja_proposta'
            ? 'Já havia uma proposta para este fato ($valor). Nada novo foi criado.'
            : 'Proposta de $valor registrada. Outra pessoa precisa aprovar.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e is ErroApi && e.status == null && !e.proibido
              ? '${e.mensagem} Confira a lista antes de repetir.'
              : e.toString();
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  Widget _campo(String rotulo, TextEditingController c,
          {int maximo = 64, int linhas = 1, String? ajuda, String? erro, String? prefixo, TextInputType? teclado}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          keyboardType: teclado,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: ajuda,
            helperMaxLines: 3,
            errorText: erro,
            errorMaxLines: 3,
            prefixText: prefixo,
            counterText: '',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final centavos = _centavos;
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar a proposta?' : 'Propor pedido de volta',
        consequencia: 'Só uma proposta: a dívida nasce quando outra pessoa aprovar.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi registrada.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_revisando && centavos != null) ...[
            Linha('Pedido', _pedido.text.trim()),
            Linha('Fato que gerou', _referencia.text.trim()),
            Linha('Valor', formatarReais(centavos)),
            Linha('Motivo (o profissional lê)', _motivo.text.trim()),
          ] else ...[
            _campo('Código do pedido', _pedido),
            _campo('Código do fato que gerou', _referencia,
                ajuda: 'Código completo, por exemplo o do chamado. Uma proposta por fato.',
                erro: _referencia.text.trim().isEmpty || _referenciaValida ? null : 'Código incompleto ou inválido'),
            _campo('Valor a pedir de volta', _valor,
                maximo: 16,
                prefixo: 'R\$ ',
                teclado: const TextInputType.numberWithOptions(decimal: true),
                erro: _erroValor),
            _campo('Motivo (o profissional lê)', _motivo,
                maximo: 1000, linhas: 3, ajuda: 'Pelo menos $kMotivoMinimo caracteres. Não cite dado de terceiros.'),
          ],
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
          ),
          _revisando
              ? BotaoTrato.primario('Confirmar proposta',
                  carregando: _enviando, rotuloCarregando: 'Enviando', aoPressionar: _enviando ? null : _propor)
              : BotaoTrato.primario('Revisar',
                  aoPressionar: _valido ? () => setState(() => _revisando = true) : null),
        ],
      ),
    );
  }
}
