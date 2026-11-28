import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// Avisos com antecedência: mudança dos Termos (23.2) e conta sem uso (4.9).
/// Aqui só sai o aviso. Prazo mínimo, destinatários e texto final são do servidor.
enum TipoAvisoPrevio { termos, inatividade }

/// Texto fixo do alcance do aviso de inatividade (Termos 4.9): não inativa automaticamente;
/// após 30 dias e a data de vigência, a inativação é feita manualmente na tela Busca.
const kInatividadeSoAvisa =
    'Isto só envia o aviso — a conta não é inativada automaticamente. '
    'Após 30 dias e a data de vigência, inative a conta na tela Busca.';

Future<void> abrirAvisoPrevio(BuildContext context, TipoAvisoPrevio tipo) =>
    mostrarModal<void>(context, largura: 600, construir: (_) => _ModalAvisoPrevio(tipo));

class CartaoAvisosPrevios extends StatelessWidget {
  const CartaoAvisosPrevios({super.key});

  @override
  Widget build(BuildContext context) => CartaoSecao(
        titulo: 'Avisos com antecedência',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mudança dos Termos (Termos 23.2) e aviso manual de conta sem uso (Termos 4.9). $kInatividadeSoAvisa',
              style: TipografiaTrato.corpo,
            ),
            const SizedBox(height: EspacosTrato.x3),
            Wrap(
              spacing: EspacosTrato.x2,
              runSpacing: EspacosTrato.x2,
              children: [
                BotaoTrato.secundario('Aviso de mudança dos Termos',
                    aoPressionar: () => abrirAvisoPrevio(context, TipoAvisoPrevio.termos)),
                BotaoTrato.secundario('Aviso de conta sem uso',
                    aoPressionar: () => abrirAvisoPrevio(context, TipoAvisoPrevio.inatividade)),
              ],
            ),
          ],
        ),
      );
}

class _ModalAvisoPrevio extends StatefulWidget {
  const _ModalAvisoPrevio(this.tipo);
  final TipoAvisoPrevio tipo;

  @override
  State<_ModalAvisoPrevio> createState() => _ModalAvisoPrevioState();
}

class _ModalAvisoPrevioState extends State<_ModalAvisoPrevio> {
  final _usuario = TextEditingController();
  final _referencia = TextEditingController();
  final _resumo = TextEditingController();
  final _motivo = TextEditingController();
  final _link = TextEditingController();
  DateTime? _vigencia;
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;
  ResultadoAvisoPrevio? _resultado;

  bool get _termos => widget.tipo == TipoAvisoPrevio.termos;

  @override
  void dispose() {
    for (final c in [_usuario, _referencia, _resumo, _motivo, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _referenciaValida => RegExp(r'^[A-Za-z0-9._-]{1,60}$').hasMatch(_referencia.text.trim());
  bool get _linkValido => RegExp(r'^https://\S+$').hasMatch(_link.text.trim());

  bool get _valido =>
      _referenciaValida &&
      _vigencia != null &&
      (_termos
          ? _resumo.text.trim().length >= kMotivoMinimo &&
              _motivo.text.trim().length >= kMotivoMinimo &&
              _linkValido
          : _usuario.text.trim().isNotEmpty);

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = _termos
          ? await context.api.enviarAvisoTermos(
              referencia: _referencia.text.trim(),
              vigencia: _vigencia!,
              resumo: _resumo.text.trim(),
              motivo: _motivo.text.trim(),
              link: _link.text.trim(),
            )
          : await context.api.enviarAvisoInatividade(
              usuarioId: _usuario.text.trim(),
              referencia: _referencia.text.trim(),
              vigencia: _vigencia!,
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
        if (!_termos) ...[
          const BannerInfo(kInatividadeSoAvisa, tom: Tom.alerta),
          _texto('Código da conta', _usuario, maximo: 64),
        ],
        _texto('Referência do aviso', _referencia,
            ajuda: 'Letras, números, ponto, hífen e _. Identifica este aviso.',
            falha: _referencia.text.isNotEmpty && !_referenciaValida ? 'Referência inválida' : null),
        const SizedBox(height: EspacosTrato.x3),
        CampoData(
          rotulo: _termos ? 'Passa a valer em' : 'Pode ser inativada a partir de',
          valor: _vigencia,
          ajuda: 'O servidor exige antecedência de pelo menos 30 dias.',
          aoMudar: (d) => setState(() => _vigencia = d),
        ),
        if (_termos) ...[
          _texto('Resumo que o usuário vai ler', _resumo,
              maximo: 2000, linhas: 3, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
          _texto('Motivo da mudança (o usuário lê)', _motivo,
              maximo: 1000, linhas: 2, ajuda: 'Pelo menos $kMotivoMinimo caracteres. Também vai para a auditoria.'),
          _texto('Link da versão completa', _link,
              maximo: 500,
              ajuda: 'Começa com https://',
              falha: _link.text.isNotEmpty && !_linkValido ? 'Use um link que comece com https://, sem espaços' : null),
        ],
      ];

  List<Widget> _revisao() => [
        BannerInfo(
          _termos
              ? 'O aviso vai para os usuários e não dá para desfazer. Ele não publica os novos Termos.'
              : 'O aviso vai para o usuário dono da conta e não dá para desfazer. $kInatividadeSoAvisa',
          titulo: 'Confira antes de enviar.',
          tom: Tom.alerta,
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (!_termos) Linha('Conta', _usuario.text.trim()),
        Linha('Referência', _referencia.text.trim()),
        Linha(_termos ? 'Passa a valer em' : 'Pode ser inativada a partir de', formatarDia(_vigencia!)),
        if (_termos) ...[
          Linha('Resumo', _resumo.text.trim()),
          Linha('Motivo', _motivo.text.trim()),
          Linha('Link', _link.text.trim()),
        ],
      ];

  static bool _vale(ResultadoAvisoPrevio r) => r.falhas == 0 && r.destinatarios > 0;

  List<Widget> _doResultado(ResultadoAvisoPrevio r) => [
        BannerInfo(
          _vale(r)
              ? (_termos
                  ? 'O aviso não publica os novos Termos. A antecedência mínima é de ${r.antecedenciaMinimaDias} dias.'
                  : kInatividadeSoAvisa)
              : r.falhas > 0
                  ? '${r.falhas} pessoa(s) não foram avisadas. Este envio não vale: repita o envio.'
                  : 'Nenhuma pessoa recebeu o aviso. Este envio não vale.',
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
            : _revisando
                ? (_termos ? 'Enviar o aviso aos usuários?' : 'Enviar o aviso ao usuário?')
                : (_termos ? 'Aviso de mudança dos Termos' : 'Aviso de conta sem uso'),
        consequencia: _termos ? 'Termos 23.2.' : 'Termos 4.9.',
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
              _termos ? 'Enviar aos usuários' : 'Enviar ao usuário',
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
