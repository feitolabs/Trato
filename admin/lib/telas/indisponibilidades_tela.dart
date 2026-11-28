import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

const kOrigensDaFalha = {'app': 'Aplicativo', 'pagamento': 'Pagamento'};

/// Espelha `backend/src/trato/disputas/indisponibilidade.py` e os usos dele.
const kAlcanceDaProrrogacao = 'A falha prorroga hoje: confirmação automática, expiração de pagamento, expiração do pedido sem orçamento, ausência e '
    'justificativa, orçamento, disputa (resposta e congelamento do repasse), avaliação, contestação de medida, '
    'exclusividade, reserva de Tratinhos do Pix e visita recorrente. A falha do aplicativo alcança todos esses; a de '
    'pagamento, só a expiração de pagamento, o orçamento, a reserva do Pix e a visita recorrente. Não muda o QR do Pix '
    'no provedor nem avisos já enviados, e não desfaz prazo que já venceu (Termos 22.3).';

const kRiscoDaFalhaAberta = 'Falha deixada aberta suspende os prazos que ela alcança. Na do aplicativo isso inclui as '
    'ofertas de exclusividade, o que prende Tratinhos e vagas. Encerre assim que o problema for resolvido.';

const _avisosDaProrrogacao = Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    BannerInfo(kAlcanceDaProrrogacao, tom: Tom.info),
    SizedBox(height: EspacosTrato.x2),
    BannerInfo(kRiscoDaFalhaAberta, tom: Tom.alerta),
  ],
);

const kErroDataHora = 'Use DD/MM/AAAA HH:mm';

const _kMotivoMaximo = 1000;

String nomeDaOrigem(String origem) => kOrigensDaFalha[origem] ?? origem;

/// "27/11/2026 14:30" em horário de Brasília (America/Sao_Paulo, UTC-3 sem horário de verão) para
/// ISO com fuso. Null se o texto não for uma data e hora que existem. Quem confere futuro e ordem
/// é o servidor.
String? lerDataHoraDeBrasilia(String texto) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})$').firstMatch(texto.trim());
  if (m == null) return null;
  final [dia, mes, ano, hora, minuto] = [for (var i = 1; i <= 5; i++) int.parse(m.group(i)!)];
  final d = DateTime.utc(ano, mes, dia, hora, minuto);
  if (d.day != dia || d.month != mes || d.hour != hora || d.minute != minuto) return null;
  return '${m.group(3)}-${m.group(2)}-${m.group(1)}T${m.group(4)}:${m.group(5)}:00-03:00';
}

/// Falhas da plataforma que adiam prazos (Termos 22.3). Pede `indisponibilidades_gerenciar`;
/// quem decide é o backend.
class IndisponibilidadesTela extends StatefulWidget {
  const IndisponibilidadesTela({super.key});

  @override
  State<IndisponibilidadesTela> createState() => _IndisponibilidadesTelaState();
}

class _IndisponibilidadesTelaState extends State<IndisponibilidadesTela> {
  String? _origem;
  bool _abertas = false;
  int _versao = 0;

  Future<void> _abrirModal(JanelaIndisponibilidade? janela) async {
    final gravou = await mostrarModal<bool>(context, construir: (_) => _ModalFalha(janela));
    if (gravou == true && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtro = (_origem, _abertas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Falhas da plataforma',
          subtitulo: 'Registro e encerramento de indisponibilidades (Termos 22.3)',
          acoes: [BotaoTrato.primario('Registrar falha', aoPressionar: () => _abrirModal(null))],
        ),
        Expanded(
          child: FilaRemota<JanelaIndisponibilidade>(
            key: ValueKey('fila-falhas-$_versao'),
            filtro: filtro,
            porPagina: 20,
            chave: (j) => j.id,
            carregar: (deslocamento, limite) => context.api.listarIndisponibilidades(
                origem: _origem, abertas: _abertas, deslocamento: deslocamento, limite: limite),
            construir: (context, fila) => ListView(
              padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x6),
              children: [
                _avisosDaProrrogacao,
                const SizedBox(height: EspacosTrato.x3),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final (valor, rotulo) in [
                      (null, 'Todas as origens'),
                      for (final e in kOrigensDaFalha.entries) (e.key, e.value),
                    ])
                      ChoiceChip(
                        label: Text(rotulo),
                        selected: _origem == valor,
                        onSelected: (_) => setState(() => _origem = valor),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    FilterChip(
                      label: const Text('Só abertas'),
                      selected: _abertas,
                      onSelected: (v) => setState(() => _abertas = v),
                    ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x3),
                if (fila.itens.isEmpty)
                  const EstadoVazio('Nenhuma falha com esse filtro.')
                else ...[
                  for (final j in fila.itens)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                      child: _CartaoFalha(j, aoEncerrar: () => _abrirModal(j)),
                    ),
                  RodapeFila(fila, rotuloItens: 'falhas'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CartaoFalha extends StatelessWidget {
  const _CartaoFalha(this.janela, {required this.aoEncerrar});
  final JanelaIndisponibilidade janela;
  final VoidCallback aoEncerrar;

  @override
  Widget build(BuildContext context) {
    final j = janela;
    String quem(String id) => id.replaceAll('-', '') == context.eu?.id.replaceAll('-', '') ? 'Você' : id;
    return CartaoSecao(
      titulo: 'Falha de ${nomeDaOrigem(j.origem).toLowerCase()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ChipEstado(j.ativa ? 'Ativa' : 'Encerrada', tom: j.ativa ? Tom.alerta : Tom.neutro),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Início', formatarDataBrasilia(j.inicioEm)),
          Linha('Fim', j.fimEm == null ? 'A falha continua' : formatarDataBrasilia(j.fimEm!)),
          Linha('Motivo do registro', j.motivo),
          Linha('Registrada por', quem(j.criadaPor)),
          if (j.encerradaPor case final id?) Linha('Encerrada por', quem(id)),
          if (j.ativa)
            Align(
              alignment: Alignment.centerRight,
              child: BotaoTrato.secundario('Encerrar falha', aoPressionar: aoEncerrar),
            ),
        ],
      ),
    );
  }
}

/// Registrar ([janela] nula) ou encerrar: preencher, conferir e confirmar. A recusa do servidor
/// aparece aqui e o que foi digitado fica.
class _ModalFalha extends StatefulWidget {
  const _ModalFalha(this.janela);
  final JanelaIndisponibilidade? janela;

  @override
  State<_ModalFalha> createState() => _ModalFalhaState();
}

class _ModalFalhaState extends State<_ModalFalha> {
  final _inicio = TextEditingController();
  final _fim = TextEditingController();
  final _motivo = TextEditingController();
  String? _origem;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  bool get _registro => widget.janela == null;

  @override
  void dispose() {
    _inicio.dispose();
    _fim.dispose();
    _motivo.dispose();
    super.dispose();
  }

  bool get _fimValido => _fim.text.trim().isEmpty || lerDataHoraDeBrasilia(_fim.text) != null;

  bool get _valido =>
      _motivo.text.trim().length >= kMotivoMinimo &&
      _fimValido &&
      (!_registro || (_origem != null && lerDataHoraDeBrasilia(_inicio.text) != null));

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final api = context.api;
    final fim = lerDataHoraDeBrasilia(_fim.text);
    final motivo = _motivo.text.trim();
    try {
      var aviso = 'Falha encerrada.';
      if (_registro) {
        final r = await api.registrarIndisponibilidade(
            origem: _origem!, inicioEm: lerDataHoraDeBrasilia(_inicio.text)!, fimEm: fim, motivo: motivo);
        aviso = r.repetida ? 'Essa falha já estava registrada. Nada novo foi criado.' : 'Falha registrada.';
      } else {
        await api.encerrarIndisponibilidade(widget.janela!.id, fimEm: fim, motivo: motivo);
      }
      if (!mounted) return;
      mostrarAviso(context, aviso);
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

  Widget _campoDataHora(String rotulo, TextEditingController c, {required String ajuda, required bool valido}) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.datetime,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            hintText: 'DD/MM/AAAA HH:mm',
            helperText: ajuda,
            helperMaxLines: 2,
            errorText: valido ? null : kErroDataHora,
          ),
        ),
      );

  List<Widget> _formulario() => [
        if (_registro) ...[
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final e in kOrigensDaFalha.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _origem == e.key,
                  onSelected: (_) => setState(() => _origem = e.key),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          _campoDataHora('Início da falha', _inicio,
              ajuda: 'Horário de Brasília.',
              valido: _inicio.text.trim().isEmpty || lerDataHoraDeBrasilia(_inicio.text) != null),
        ] else
          Linha('Início', formatarDataBrasilia(widget.janela!.inicioEm)),
        _campoDataHora('Fim da falha (opcional)', _fim,
            ajuda: _registro
                ? 'Horário de Brasília. Vazio = a falha continua.'
                : 'Horário de Brasília. Vazio = agora.',
            valido: _fimValido),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _motivo,
          minLines: 2,
          maxLines: 5,
          maxLength: _kMotivoMaximo,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Motivo', helperText: 'Pelo menos $kMotivoMinimo caracteres'),
        ),
      ];

  List<Widget> _revisao() {
    String quando(TextEditingController c, String vazio) =>
        c.text.trim().isEmpty ? vazio : '${c.text.trim()} (horário de Brasília)';
    return [
      Linha('Origem', nomeDaOrigem(_origem ?? widget.janela!.origem)),
      Linha('Início', _registro ? quando(_inicio, '') : formatarDataBrasilia(widget.janela!.inicioEm)),
      Linha('Fim', quando(_fim, _registro ? 'A falha continua' : 'Agora')),
      Linha('Motivo', _motivo.text.trim()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando
            ? (_registro ? 'Confirmar o registro?' : 'Confirmar o encerramento?')
            : (_registro ? 'Registrar falha' : 'Encerrar falha de ${nomeDaOrigem(widget.janela!.origem).toLowerCase()}'),
        consequencia: _registro
            ? 'A falha registrada pode adiar prazos e não pode ser apagada.'
            : 'Uma falha só é encerrada uma vez.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          _avisosDaProrrogacao,
          const SizedBox(height: EspacosTrato.x3),
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
                  _registro ? 'Confirmar registro' : 'Confirmar encerramento',
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
