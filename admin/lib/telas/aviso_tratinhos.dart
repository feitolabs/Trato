import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// Termos 13.11 e I.12: campos da configuração dos Tratinhos. `uso` = mudança que o servidor recusa
/// enquanto houver saldo válido, mesmo com aviso. Quem decide o que é piora é o backend.
const kCamposTratinhos = <String, ({String rotulo, bool uso})>{
  'valor_moeda_centavos': (rotulo: 'Valor de cada Tratinho', uso: true),
  'max_desconto_percentual': (rotulo: 'Desconto máximo por serviço (%)', uso: true),
  'orcamento_mensal_desconto_centavos': (rotulo: 'Orçamento mensal de desconto', uso: true),
  'teto_diario_desconto_centavos': (rotulo: 'Teto diário de desconto', uso: true),
  'teto_desconto_cliente_mes_centavos': (rotulo: 'Teto mensal por cliente', uso: true),
  'max_reservas_abertas': (rotulo: 'Cobranças abertas com desconto', uso: true),
  'reserva_minutos': (rotulo: 'Minutos de reserva do desconto', uso: true),
  'exclusividade_custo_moedas': (rotulo: 'Custo da exclusividade (Tratinhos)', uso: true),
  'exclusividade_duracao_horas': (rotulo: 'Duração da exclusividade (horas)', uso: true),
  'ativo': (rotulo: 'Programa ativo', uso: false),
  'bonus_avaliacao_moedas': (rotulo: 'Bônus por avaliação do cliente', uso: false),
  'bonus_avaliacao_profissional_moedas': (rotulo: 'Bônus por avaliação do profissional', uso: false),
  'teto_mensal_moedas': (rotulo: 'Teto mensal de Tratinhos ganhos', uso: false),
  'max_bonus_por_profissional_mes': (rotulo: 'Bônus por profissional no mês', uso: false),
  'min_servico_centavos': (rotulo: 'Serviço mínimo para ganhar', uso: false),
  'validade_dias': (rotulo: 'Validade dos novos Tratinhos (dias)', uso: false),
  'dias_liberacao_bonus': (rotulo: 'Dias para liberar o bônus', uso: false),
};

String rotuloDoCampoTratinhos(String chave) => kCamposTratinhos[chave]?.rotulo ?? chave;

/// Data do servidor em horário de Brasília (UTC-3, sem horário de verão). Só dia: sem hora.
String dataEmBrasilia(String iso) {
  final dia = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (dia != null) return '${dia.group(3)}/${dia.group(2)}/${dia.group(1)} (horário de Brasília)';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return formatarDataBrasilia(d);
}

/// Recusa do servidor à publicação: mensagem, campos afetados e quando pode valer.
class RecusaDaConfigTratinhos extends StatelessWidget {
  const RecusaDaConfigTratinhos(this.erro, {super.key});
  final ErroApi erro;

  @override
  Widget build(BuildContext context) {
    final partes = [
      erro.mensagem,
      if (erro.campos.isNotEmpty) 'Campos afetados: ${erro.campos.map(rotuloDoCampoTratinhos).join(', ')}.',
      if (erro.podeValerEm case final quando?) 'Pode valer a partir de ${dataEmBrasilia(quando)}.',
    ];
    return BannerInfo(partes.join('\n'), titulo: 'A configuração não foi salva.', tom: Tom.erro);
  }
}

Future<void> abrirAvisoTratinhos(BuildContext context) =>
    mostrarModal<void>(context, largura: 600, construir: (_) => const _ModalAviso());

class _ModalAviso extends StatefulWidget {
  const _ModalAviso();

  @override
  State<_ModalAviso> createState() => _ModalAvisoState();
}

class _ModalAvisoState extends State<_ModalAviso> {
  final _referencia = TextEditingController();
  final _resumo = TextEditingController();
  final _motivo = TextEditingController();
  final _valores = <String, TextEditingController>{};
  bool _ativo = false;
  DateTime? _vigencia;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;
  ResultadoAvisoPrevio? _resultado;

  @override
  void dispose() {
    for (final c in [_referencia, _resumo, _motivo, ..._valores.values]) {
      c.dispose();
    }
    super.dispose();
  }

  static bool _emReais(String chave) => chave.endsWith('_centavos');

  Object? _valor(String chave) {
    if (chave == 'ativo') return _ativo;
    final t = _valores[chave]!.text.trim();
    if (_emReais(chave)) return lerReaisEmCentavos(t);
    return RegExp(r'^\d{1,9}$').hasMatch(t) ? int.parse(t) : null;
  }

  bool get _referenciaValida => RegExp(r'^[A-Za-z0-9._-]{1,60}$').hasMatch(_referencia.text.trim());

  bool get _valido =>
      _referenciaValida &&
      _vigencia != null &&
      _resumo.text.trim().length >= kMotivoMinimo &&
      _motivo.text.trim().length >= kMotivoMinimo &&
      _valores.keys.every((c) => _valor(c) != null);

  String _mostrar(String chave) {
    final v = _valor(chave);
    if (v is bool) return v ? 'Sim' : 'Não (programa encerrado)';
    return _emReais(chave) ? formatarReais(v! as int) : '$v';
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await context.api.enviarAvisoTratinhos(
        referencia: _referencia.text.trim(),
        vigencia: _vigencia!,
        resumo: _resumo.text.trim(),
        motivo: _motivo.text.trim(),
        mudancas: {for (final c in _valores.keys) c: _valor(c)!},
      );
      if (mounted) {
        setState(() {
          _resultado = r;
          _enviando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _enviando = false;
          _revisando = false;
          _resultado = null;
        });
      }
    }
  }

  Widget _texto(String rotulo, TextEditingController c, {int maximo = 60, int linhas = 1, String? ajuda, String? falha}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: rotulo, helperText: ajuda, helperMaxLines: 2, errorText: falha, counterText: ''),
        ),
      );

  List<Widget> _formulario() => [
        _texto('Referência do aviso', _referencia,
            ajuda: 'Letras, números, ponto, hífen e _. Você usa a mesma ao salvar a configuração.',
            falha: _referencia.text.isNotEmpty && !_referenciaValida ? 'Referência inválida' : null),
        const SizedBox(height: EspacosTrato.x3),
        CampoData(
          rotulo: 'Passa a valer em',
          valor: _vigencia,
          ajuda: 'O servidor exige antecedência de pelo menos 30 dias.',
          aoMudar: (d) => setState(() => _vigencia = d),
        ),
        _texto('Resumo que o usuário vai ler', _resumo,
            maximo: 2000, linhas: 3, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
        _texto('Motivo (auditoria)', _motivo, maximo: 1000, linhas: 2, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
        const SizedBox(height: EspacosTrato.x4),
        Text('Mudanças anunciadas', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        const BannerInfo(
          'Sem mudanças, o aviso não libera nenhuma piora. Campos marcados como "uso" (valor, descontos, '
          'orçamento, tetos, reservas e exclusividade) não podem piorar enquanto houver Tratinhos válidos: '
          'o servidor recusa, mesmo com aviso.',
          tom: Tom.alerta,
        ),
        for (final chave in _valores.keys)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x3),
            child: Row(
              children: [
                Expanded(
                  child: chave == 'ativo'
                      ? Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Programa ativo', style: TipografiaTrato.corpo),
                            subtitle: Text(_ativo ? 'Continua ativo' : 'Será encerrado',
                                style: TipografiaTrato.legenda),
                            value: _ativo,
                            onChanged: (v) => setState(() => _ativo = v),
                          ),
                        )
                      : TextField(
                          key: ValueKey('aviso-valor-$chave'),
                          controller: _valores[chave],
                          keyboardType: TextInputType.numberWithOptions(decimal: _emReais(chave)),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Novo valor: ${rotuloDoCampoTratinhos(chave)}',
                            prefixText: _emReais(chave) ? 'R\$ ' : null,
                            errorText: _valores[chave]!.text.isNotEmpty && _valor(chave) == null
                                ? (_emReais(chave) ? kErroReais : 'Informe um número inteiro')
                                : null,
                            errorMaxLines: 3,
                          ),
                        ),
                ),
                BotaoTrato.link('Retirar', aoPressionar: () => setState(() => _valores.remove(chave))),
              ],
            ),
          ),
        const SizedBox(height: EspacosTrato.x3),
        DropdownButtonFormField<String>(
          key: ValueKey('aviso-campo-${_valores.length}-${_valores.keys.join()}'),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Adicionar mudança'),
          items: [
            for (final e in kCamposTratinhos.entries)
              if (!_valores.containsKey(e.key))
                DropdownMenuItem(value: e.key, child: Text('${e.value.rotulo}${e.value.uso ? ' (uso)' : ''}')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _valores[v] = TextEditingController());
          },
        ),
      ];

  List<Widget> _revisao() => [
        const BannerInfo(
          'O aviso vai para os usuários e não dá para desfazer. Ele não muda a configuração.',
          titulo: 'Confira antes de enviar.',
          tom: Tom.alerta,
        ),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Referência', _referencia.text.trim()),
        Linha('Passa a valer em', formatarDia(_vigencia!)),
        Linha('Resumo', _resumo.text.trim()),
        Linha('Motivo (auditoria)', _motivo.text.trim()),
        if (_valores.isEmpty) const Linha('Mudanças', 'Nenhuma: este aviso não libera piora.'),
        for (final c in _valores.keys) Linha(rotuloDoCampoTratinhos(c), _mostrar(c)),
      ];

  static bool _vale(ResultadoAvisoPrevio r) => r.falhas == 0 && r.destinatarios > 0;

  List<Widget> _doResultado(ResultadoAvisoPrevio r) => [
        BannerInfo(
          _vale(r)
              ? 'Para aplicar uma mudança anunciada, salve a configuração com a referência "${_referencia.text.trim()}" '
                  'depois do prazo (pelo menos ${r.antecedenciaMinimaDias} dias). O servidor confere.'
              : r.falhas > 0
                  ? '${r.falhas} pessoa(s) não foram avisadas. Este envio não vale para liberar mudança: repita o envio.'
                  : 'Nenhuma pessoa recebeu o aviso. Este envio não vale para liberar mudança.',
          titulo: _vale(r) ? 'Aviso enviado.' : 'O aviso não vale.',
          tom: _vale(r) ? Tom.ok : Tom.erro,
        ),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Pessoas', '${r.destinatarios}'),
        Linha('Registros criados agora', '${r.avisosNovos}'),
        Linha('Falhas', '${r.falhas}'),
      ];

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: r != null
            ? 'Resultado do envio'
            : (_revisando ? 'Enviar o aviso aos usuários?' : 'Aviso prévio dos Tratinhos'),
        consequencia: 'Termos 13.11 e I.12.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi enviado.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          ...(r != null ? _doResultado(r) : (_revisando ? _revisao() : _formulario())),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            r != null ? 'Fechar' : (_revisando ? 'Voltar' : 'Cancelar'),
            aoPressionar: _enviando
                ? null
                : () => r == null && _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
          ),
          if (r != null) ...[
            if (!_vale(r))
              BotaoTrato.primario(
                'Repetir envio',
                carregando: _enviando,
                rotuloCarregando: 'Enviando',
                aoPressionar: _enviando ? null : _enviar,
              ),
          ] else if (_revisando)
            BotaoTrato.primario(
              'Enviar aos usuários',
              carregando: _enviando,
              rotuloCarregando: 'Enviando',
              aoPressionar: _enviando ? null : _enviar,
            )
          else
            BotaoTrato.primario(
              'Revisar aviso',
              aoPressionar: _valido ? () => setState(() => _revisando = true) : null,
            ),
        ],
      ),
    );
  }
}
