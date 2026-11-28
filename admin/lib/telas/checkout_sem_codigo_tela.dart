import 'dart:math';

import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

const kCanaisContatoCheckout = {
  'telefone': 'Telefone',
  'whatsapp': 'WhatsApp',
  'email': 'E-mail',
  'outro': 'Outro',
};

const kDecisoesCheckout = {
  'liberar': 'Liberar pagamento',
  'estornar': 'Estornar ao cliente',
};

const kAvisoCheckoutSemCodigo =
    'Fila de check-outs sem o Código Final (Termos 5.7). Casos vencidos aparecem primeiro, '
    'seguidos pelos ainda sem contato. Você pode registrar o contato manual para iniciar o prazo '
    'de resposta e decidir o caso (liberar pagamento ou estornar ao cliente) conforme a alçada '
    'conferida pelo servidor.';

const kDecisaoTravadaCheckout =
    'O envio anterior ficou sem resposta e pode ter sido gravado. Repita com a mesma decisão e o '
    'mesmo motivo: eles ficam travados porque uma mudança seria ignorada sem aviso. Se precisar '
    'mudar, confira antes na auditoria se a decisão já foi gravada.';

const _kMotivoMaximo = 500;

String nomeDoCanalCheckout(String? canal) => switch (canal) {
      null || '' => '—',
      'app+email' => 'App + e-mail',
      final c => kCanaisContatoCheckout[c] ?? c,
    };

String nomeDaDecisaoCheckout(String? decisao) => switch (decisao) {
      null || '' => '—',
      final d => kDecisoesCheckout[d] ?? d,
    };

/// Uma chave por tentativa de decisão (8 a 120 caracteres); reutilizada na repetição após erro
/// sem resposta ou 5xx.
String gerarChaveDecisaoCheckout([Random? sorteio]) {
  final r = sorteio ?? Random.secure();
  return 'csc-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

String mensagemErroContatoCheckout(Object erro) {
  if (erro is ErroApi) {
    return switch (erro.status) {
      404 => '${erro.mensagem} Atualize a fila para ver os casos ainda abertos.',
      409 => '${erro.mensagem} Atualize a fila para conferir o estado atual do caso.',
      503 => '${erro.mensagem} Tente novamente em alguns instantes.',
      _ => erro.mensagem,
    };
  }
  return erro.toString();
}

String mensagemErroDecisaoCheckout(Object erro) {
  if (erro is ErroApi) {
    return switch (erro.status) {
      403 => '${erro.mensagem} Confira se o seu papel ou alçada permite esta decisão.',
      404 => '${erro.mensagem} Atualize a fila para ver os casos ainda abertos.',
      409 => '${erro.mensagem} Atualize a fila para conferir o estado atual do caso.',
      422 => erro.mensagem,
      503 => '${erro.mensagem} Tente novamente em alguns instantes.',
      _ => erro.mensagem,
    };
  }
  return erro.toString();
}

/// Estado da tentativa de decisão por caso: preserva chave, decisão e motivo entre repetições
/// quando o envio anterior fica sem resposta definitiva.
class _TentativaDecisao {
  String chave = gerarChaveDecisaoCheckout();
  String? decisao;
  String motivo = '';
  bool semResposta = false;
}

/// Fila de check-out sem o Código Final (Termos 5.7). Pede `checkout_sem_codigo_tratar`;
/// quem valida alçada, decide o dinheiro e audita é o backend.
class CheckoutSemCodigoTela extends StatefulWidget {
  const CheckoutSemCodigoTela({super.key});

  @override
  State<CheckoutSemCodigoTela> createState() => _CheckoutSemCodigoTelaState();
}

class _CheckoutSemCodigoTelaState extends State<CheckoutSemCodigoTela> {
  int _versao = 0;
  final Map<String, _TentativaDecisao> _tentativasDecisao = {};

  Future<void> _abrirRegistroContato(CasoCheckoutSemCodigo caso) async {
    final gravou = await mostrarModal<bool>(
      context,
      construir: (_) => _ModalRegistrarContato(caso),
    );
    if (gravou == true && mounted) setState(() => _versao++);
  }

  Future<void> _abrirDecisao(CasoCheckoutSemCodigo caso) async {
    final tentativa = _tentativasDecisao.putIfAbsent(caso.id, _TentativaDecisao.new);
    final decidiu = await mostrarModal<bool>(
      context,
      construir: (_) => _ModalDecidirCaso(
        caso: caso,
        tentativa: tentativa,
        aoGravar: () => _tentativasDecisao.remove(caso.id),
      ),
    );
    if (decidiu == true && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Check-out sem código',
          subtitulo: 'Contato manual e decisão de check-outs sem Código Final (Termos 5.7)',
        ),
        Expanded(
          child: FilaRemota<CasoCheckoutSemCodigo>(
            key: ValueKey('fila-checkout-sem-codigo-$_versao'),
            filtro: _versao,
            porPagina: 20,
            chave: (c) => c.id,
            carregar: (deslocamento, limite) => context.api.listarCheckoutSemCodigo(
              deslocamento: deslocamento,
              limite: limite,
            ),
            construir: (context, fila) => ListView(
              padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x6),
              children: [
                const BannerInfo(kAvisoCheckoutSemCodigo, tom: Tom.info),
                const SizedBox(height: EspacosTrato.x3),
                if (fila.itens.isEmpty)
                  const EstadoVazio('Nenhum caso de check-out sem código na fila.')
                else ...[
                  for (final caso in fila.itens)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                      child: _CartaoCasoCheckout(
                        caso,
                        aoRegistrarContato: () => _abrirRegistroContato(caso),
                        aoDecidir: () => _abrirDecisao(caso),
                      ),
                    ),
                  RodapeFila(fila, rotuloItens: 'casos'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CartaoCasoCheckout extends StatelessWidget {
  const _CartaoCasoCheckout(
    this.caso, {
    required this.aoRegistrarContato,
    required this.aoDecidir,
  });

  final CasoCheckoutSemCodigo caso;
  final VoidCallback aoRegistrarContato;
  final VoidCallback aoDecidir;

  @override
  Widget build(BuildContext context) {
    final c = caso;
    return CartaoSecao(
      titulo: 'Pedido ${c.pedidoId}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (c.vencido)
                const ChipEstado('Prazo vencido', tom: Tom.erro)
              else if (c.semContato)
                const ChipEstado('Sem contato', tom: Tom.alerta)
              else
                const ChipEstado('Aguardando resposta', tom: Tom.info),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Pedido', c.pedidoId),
          Linha('Cliente', c.clienteId),
          Linha('Profissional', c.profissionalId ?? '—'),
          Linha('Check-out em', formatarDataBrasilia(c.checkOutEm)),
          Linha(
            'Contatado em',
            c.contatadoEm == null ? 'Ainda não contatado' : formatarDataBrasilia(c.contatadoEm!),
          ),
          Linha('Canal', nomeDoCanalCheckout(c.canal)),
          Linha(
            'Responder até',
            c.responderAte == null ? 'Inicia após o contato' : formatarDataBrasilia(c.responderAte!),
          ),
          if (c.semContato || !c.vencido) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              c.semContato
                  ? 'Registre o contato e aguarde o fim do prazo de resposta para decidir.'
                  : 'Aguarde o fim do prazo de resposta para decidir.',
              style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoMudo),
            ),
          ],
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (c.semContato) BotaoTrato.secundario('Registrar contato', aoPressionar: aoRegistrarContato),
              BotaoTrato.primario(
                'Decidir caso',
                aoPressionar: !c.semContato && c.vencido ? aoDecidir : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Modal para registrar o contato manual. Se o servidor recusar (404/409/503),
/// mostra o aviso e preserva o canal e o motivo digitados.
class _ModalRegistrarContato extends StatefulWidget {
  const _ModalRegistrarContato(this.caso);

  final CasoCheckoutSemCodigo caso;

  @override
  State<_ModalRegistrarContato> createState() => _ModalRegistrarContatoState();
}

class _ModalRegistrarContatoState extends State<_ModalRegistrarContato> {
  final _motivo = TextEditingController();
  String? _canal;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _valido {
    final tamanho = _motivo.text.trim().length;
    return _canal != null && tamanho >= kMotivoMinimo && tamanho <= _kMotivoMaximo;
  }

  Future<void> _enviar() async {
    if (_enviando || _canal == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final api = context.api;
    final canal = _canal!;
    final motivo = _motivo.text.trim();
    try {
      await api.registrarContatoCheckoutSemCodigo(widget.caso.id, canal: canal, motivo: motivo);
      if (!mounted) return;
      mostrarAviso(context, 'Contato registrado.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = mensagemErroContatoCheckout(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  List<Widget> _formulario() => [
        Linha('Pedido', widget.caso.pedidoId),
        Linha('Check-out em', formatarDataBrasilia(widget.caso.checkOutEm)),
        const SizedBox(height: EspacosTrato.x2),
        Text('Canal do contato', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final e in kCanaisContatoCheckout.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _canal == e.key,
                onSelected: (_) => setState(() => _canal = e.key),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _motivo,
          minLines: 2,
          maxLines: 5,
          maxLength: _kMotivoMaximo,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Motivo',
            helperText: 'Entre $kMotivoMinimo e $_kMotivoMaximo caracteres',
          ),
        ),
      ];

  List<Widget> _revisao() => [
        Linha('Pedido', widget.caso.pedidoId),
        Linha('Canal', nomeDoCanalCheckout(_canal)),
        Linha('Motivo', _motivo.text.trim()),
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar registro de contato?' : 'Registrar contato',
        consequencia: 'Vale o primeiro contato registrado e ele inicia o prazo de resposta. '
            'Nenhum valor é liberado ou estornado ao registrar o contato.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi possível registrar o contato.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(_revisando ? _revisao() : _formulario()),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar registro',
                  carregando: _enviando,
                  rotuloCarregando: 'Enviando',
                  aoPressionar: _enviando ? null : _enviar,
                )
              : BotaoTrato.primario(
                  'Revisar',
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

/// Modal para decidir o caso (liberar pagamento ou estornar ao cliente).
/// Mantém a mesma chave e trava decisão/motivo após erro sem resposta/5xx; gera nova chave após
/// erro definitivo (409/422, ou 403/404 se não houve envio sem resposta antes).
class _ModalDecidirCaso extends StatefulWidget {
  const _ModalDecidirCaso({
    required this.caso,
    required this.tentativa,
    required this.aoGravar,
  });

  final CasoCheckoutSemCodigo caso;
  final _TentativaDecisao tentativa;
  final VoidCallback aoGravar;

  @override
  State<_ModalDecidirCaso> createState() => _ModalDecidirCasoState();
}

class _ModalDecidirCasoState extends State<_ModalDecidirCaso> {
  late final _motivo = TextEditingController(text: widget.tentativa.motivo);
  late String? _decisao = widget.tentativa.decisao;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _valido {
    final tamanho = _motivo.text.trim().length;
    return _decisao != null && tamanho >= kMotivoMinimo && tamanho <= _kMotivoMaximo;
  }

  Future<void> _enviar() async {
    if (_enviando || _decisao == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final tentativa = widget.tentativa;
    final decisao = tentativa.decisao = _decisao!;
    final motivo = tentativa.motivo = _motivo.text.trim();
    try {
      final r = await context.api.decidirCheckoutSemCodigo(
        widget.caso.id,
        decisao: decisao,
        motivo: motivo,
        chaveIdempotencia: tentativa.chave,
      );
      widget.aoGravar();
      if (!mounted) return;
      final aviso = r.idempotente
          ? 'Essa decisão já estava registrada. Nada novo foi criado.'
          : (r.decisao == 'liberar'
              ? 'Decisão registrada: pagamento liberado.'
              : 'Decisão registrada: estorno ao cliente.');
      mostrarAviso(context, aviso);
      Navigator.of(context).pop(true);
    } catch (e) {
      // 409 e 422 provam que nada foi gravado com esta chave. 403 e 404 podem ser barrados antes
      // de o servidor olhar a chave: só liberam se não houve envio sem resposta antes. No resto
      // (sem resposta, 5xx), a chave, a decisão e o motivo ficam travados.
      final status = e is ErroApi ? e.status : null;
      if (status == 409 || status == 422 || (!tentativa.semResposta && (status == 403 || status == 404))) {
        tentativa
          ..chave = gerarChaveDecisaoCheckout()
          ..semResposta = false;
      } else {
        tentativa.semResposta = true;
      }
      if (mounted) {
        setState(() {
          _erro = mensagemErroDecisaoCheckout(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  List<Widget> _formulario() {
    final travado = widget.tentativa.semResposta;
    return [
      Linha('Pedido', widget.caso.pedidoId),
      Linha('Check-out em', formatarDataBrasilia(widget.caso.checkOutEm)),
      const SizedBox(height: EspacosTrato.x2),
      if (travado) ...[
        const BannerInfo(kDecisaoTravadaCheckout, titulo: 'Decisão e motivo travados.', tom: Tom.info),
        const SizedBox(height: EspacosTrato.x3),
      ],
      Text('Decisão', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: EspacosTrato.x2),
      Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          for (final e in kDecisoesCheckout.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _decisao == e.key,
              onSelected: travado ? null : (_) => setState(() => _decisao = e.key),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      const SizedBox(height: EspacosTrato.x3),
      TextField(
        controller: _motivo,
        readOnly: travado,
        minLines: 2,
        maxLines: 5,
        maxLength: _kMotivoMaximo,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Motivo',
          helperText: 'Entre $kMotivoMinimo e $_kMotivoMaximo caracteres',
        ),
      ),
    ];
  }

  List<Widget> _revisao() => [
        Linha('Pedido', widget.caso.pedidoId),
        Linha('Decisão', nomeDaDecisaoCheckout(_decisao)),
        Linha('Motivo', _motivo.text.trim()),
      ];

  @override
  Widget build(BuildContext context) {
    final consequencia = switch (_decisao) {
      'liberar' => 'O servidor confere a alçada e libera o pagamento ao profissional. A ação é auditada e irreversível.',
      'estornar' => 'O servidor confere a alçada e estorna o valor ao cliente. A ação é auditada e irreversível.',
      _ => 'A decisão movimenta o valor do pedido conforme a alçada conferida pelo servidor e fica registrada na auditoria.',
    };
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar decisão do caso?' : 'Decidir caso',
        consequencia: consequencia,
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi possível concluir a decisão.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(_revisando ? _revisao() : _formulario()),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar decisão',
                  carregando: _enviando,
                  rotuloCarregando: 'Enviando',
                  aoPressionar: _enviando ? null : _enviar,
                )
              : BotaoTrato.primario(
                  'Revisar',
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
