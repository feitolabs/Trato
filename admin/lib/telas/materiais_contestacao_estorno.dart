import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// O backend não informa a data da aprovação: o painel só lembra a regra, sem calcular prazo.
const kPrazoDoEstornoMaterial = 'O estorno deve ser pedido em até 2 dias úteis após a aprovação. '
    'O painel não calcula esse prazo.';

const kRotuloPagoNoApp = 'O material foi pago pelo app';

const kAjudaPagoNoApp = 'Marque só depois de conferir. Desmarcada, o servidor não faz o estorno automático e o '
    'caso fica para análise manual.';

const kRepetirEstornoMaterial = 'A execução pode ter sido gravada. Repetir é seguro: o servidor não move o '
    'dinheiro duas vezes.';

const kAvisoNaoSaiu = 'O aviso ao profissional não saiu. Sem aviso, nada é descontado dos repasses.';

const _kMotivoMaximo = 2000;

/// [aoEnviar] avisa que houve um envio, para a fila ser relida mesmo se o modal for fechado.
Future<void> abrirExecucaoDoEstornoMaterial(BuildContext context, ContestacaoMaterial c,
        {required VoidCallback aoEnviar}) =>
    mostrarModal<void>(context, largura: 560, construir: (_) => _ModalExecutarEstorno(c, aoEnviar));

class _ModalExecutarEstorno extends StatefulWidget {
  const _ModalExecutarEstorno(this.contestacao, this.aoEnviar);
  final ContestacaoMaterial contestacao;
  final VoidCallback aoEnviar;

  @override
  State<_ModalExecutarEstorno> createState() => _ModalExecutarEstornoState();
}

class _ModalExecutarEstornoState extends State<_ModalExecutarEstorno> {
  final _motivo = TextEditingController();

  /// Nunca começa marcada nem é lembrada entre aberturas.
  bool _pagoNoApp = false;
  bool _revisando = false;
  bool _enviando = false;
  bool _avisando = false;
  String? _erro;
  String? _erroDoAviso;
  EstornoMaterial? _feito;
  bool? _avisado;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _valido {
    final n = _motivo.text.trim().length;
    return n >= kMotivoMinimo && n <= _kMotivoMaximo;
  }

  static String _mensagemDeErro(Object e) {
    if (e is! ErroApi) return 'Não deu para ler a resposta do servidor. $kRepetirEstornoMaterial';
    // Sem código HTTP: a resposta se perdeu ou o servidor falhou no meio.
    if (e.status == null && !e.proibido && !e.sessao) return '${e.mensagem} $kRepetirEstornoMaterial';
    return e.mensagem;
  }

  Future<void> _executar() async {
    if (_enviando || _feito != null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    widget.aoEnviar();
    try {
      final r = await context.api.executarEstornoMaterial(
        widget.contestacao.id,
        motivo: _motivo.text.trim(),
        materialPagoNoApp: _pagoNoApp,
      );
      if (!mounted) return;
      setState(() {
        _feito = r;
        _avisado = r.profissionalAvisado;
        _enviando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = _mensagemDeErro(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  Future<void> _avisar(String compensacaoId) async {
    if (_avisando) return;
    setState(() {
      _avisando = true;
      _erroDoAviso = null;
    });
    try {
      final r = await context.api.avisarCompensacao(compensacaoId);
      if (!mounted) return;
      setState(() {
        _avisado = r.avisado;
        if (!r.avisado) _erroDoAviso = 'O aviso não saiu de novo.';
      });
    } catch (e) {
      // Falha do aviso não desfaz nem esconde o resultado do estorno.
      if (mounted) setState(() => _erroDoAviso = e.toString());
    } finally {
      if (mounted) setState(() => _avisando = false);
    }
  }

  List<Widget> _formulario() => [
        const BannerInfo(kPrazoDoEstornoMaterial, tom: Tom.alerta),
        const SizedBox(height: EspacosTrato.x3),
        if (widget.contestacao.valorReconhecidoCentavos case final v?)
          Linha('Valor reconhecido na análise', formatarReais(v)),
        Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x3),
          child: TextField(
            controller: _motivo,
            minLines: 3,
            maxLines: 6,
            maxLength: _kMotivoMaximo,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Motivo',
              helperText: 'Pelo menos $kMotivoMinimo caracteres',
              counterText: '',
            ),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            key: const ValueKey('material-pago-no-app'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _pagoNoApp,
            onChanged: (v) => setState(() => _pagoNoApp = v ?? false),
            title: const Text(kRotuloPagoNoApp),
            subtitle: const Text(kAjudaPagoNoApp),
          ),
        ),
      ];

  List<Widget> _revisao() => [
        Linha('Pedido', widget.contestacao.pedidoId),
        if (widget.contestacao.valorReconhecidoCentavos case final v?)
          Linha('Valor reconhecido na análise', formatarReais(v)),
        Linha(kRotuloPagoNoApp, _pagoNoApp ? 'Sim' : 'Não'),
        Linha('Motivo', _motivo.text.trim()),
      ];

  List<Widget> _resultado(EstornoMaterial r) => [
        BannerInfo(
          r.resultado == 'ja_executada'
              ? 'Este estorno já tinha sido executado. Nada novo foi gravado.'
              : 'O servidor registrou a execução. Isso não confirma que o valor já chegou ao cliente.',
          tom: Tom.info,
        ),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Total que o cliente recebe de volta', formatarReais(r.totalEstornadoCentavos)),
        Linha('Valor reconhecido', formatarReais(r.valorReconhecidoCentavos)),
        Linha('Saiu do que não tinha sido liberado', formatarReais(r.valorRetidoCentavos)),
        Linha('Compensação a descontar do profissional', formatarReais(r.valorCompensacaoCentavos)),
        Linha('Custo do parcelamento', formatarReais(r.custoParcelamentoCentavos)),
        if (r.compensacaoId case final id?) Linha('Código da compensação', id),
        if (_avisado == true) const Linha('Aviso ao profissional', 'Enviado'),
        if (_avisado == false) ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo('$kAvisoNaoSaiu Use "Avisar profissional" aqui ou em Compensações.', tom: Tom.alerta),
          if (r.compensacaoId case final id? when context.pode(Permissao.regressoPropor)) ...[
            const SizedBox(height: EspacosTrato.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoTrato.secundario(
                'Avisar profissional',
                aoPressionar: _avisando ? null : () => _avisar(id),
              ),
            ),
          ],
        ],
        if (_erroDoAviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erroDoAviso!, titulo: 'Aviso não enviado.', tom: Tom.erro),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final feito = _feito;
    return PopScope(
      canPop: !_enviando && !_avisando,
      child: CorpoModal(
        titulo: feito != null
            ? 'Resultado do estorno'
            : _revisando
                ? 'Confirmar o estorno?'
                : 'Executar estorno · ${widget.contestacao.protocolo}',
        consequencia: feito != null
            ? widget.contestacao.protocolo
            : 'O servidor calcula os valores, estorna o cliente e, se parte já foi liberada ao profissional, '
                'registra uma compensação. Não dá para desfazer por esta tela.',
        filhos: [
          if (feito != null)
            ..._resultado(feito)
          else ...[
            if (_erro != null) ...[
              BannerInfo(_erro!, titulo: 'Não foi concluído.', tom: Tom.erro),
              const SizedBox(height: EspacosTrato.x3),
            ],
            ...(_revisando ? _revisao() : _formulario()),
            const SizedBox(height: EspacosTrato.x3),
            const AvisoAuditoria(),
          ],
        ],
        acoes: [
          if (feito != null)
            BotaoTrato.primario('Fechar', aoPressionar: _avisando ? null : () => Navigator.of(context).pop())
          else ...[
            BotaoTrato.secundario(
              _revisando ? 'Voltar' : 'Cancelar',
              aoPressionar: _enviando
                  ? null
                  : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
            ),
            if (_revisando)
              BotaoTrato.destrutivo(
                'Confirmar estorno',
                carregando: _enviando,
                rotuloCarregando: 'Enviando',
                aoPressionar: _enviando ? null : _executar,
              )
            else
              BotaoTrato.primario(
                'Revisar',
                aoPressionar: _valido
                    ? () => setState(() {
                          _erro = null;
                          _revisando = true;
                        })
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}
