import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/prazo_avaliacao.dart';
import '../conclusao/campo_longo.dart';
import '../conclusao/estrelas_nota.dart';
import '../profissional_apoio/apoio.dart';

/// O profissional avalia o cliente depois do serviço concluído (uma vez por pedido). Só pede e
/// manda: quem aceita, recusa e guarda é o servidor.
class AvaliarClienteTela extends StatefulWidget {
  const AvaliarClienteTela({
    super.key,
    required this.pedidoNumero,
    required this.aoEnviar,
    this.prazo = PrazoAvaliacao.desconhecido,
  });

  final String pedidoNumero;

  /// Termos 12.1: até quando dá para avaliar (do servidor).
  final PrazoAvaliacao prazo;

  /// Manda a avaliação e devolve os Tratinhos ganhos (0 ou null se nenhum). Lança erro se o servidor recusar.
  final Future<Object?> Function(int nota, String comentario) aoEnviar;

  @override
  State<AvaliarClienteTela> createState() => _AvaliarClienteTelaState();
}

class _AvaliarClienteTelaState extends State<AvaliarClienteTela> {
  static String _tratinhos(int n) => '+$n ${n == 1 ? 'Tratinho' : 'Tratinhos'}';

  /// Quantidade e validade só quando o servidor informa; prazo de liberação nunca é fixado aqui.
  String get _textoDoBonus {
    final n = widget.prazo.bonusMoedas;
    final premio = n == null ? 'pode render Tratinhos' : 'rende ${_tratinhos(n)}';
    final base = 'Avaliar o cliente $premio, com qualquer nota, positiva ou negativa.';
    final dias = widget.prazo.bonusValidadeDias;
    return dias != null && dias > 0 ? '$base ${textoValidadeBonusDias(dias)}' : base;
  }

  final _comentario = TextEditingController();
  var _nota = 0;
  var _enviando = false;
  int? _moedasGanhas;
  String? _erro;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final resultado = await widget.aoEnviar(_nota, _comentario.text.trim());
      if (!mounted) return;
      final ganhas = resultado is int ? resultado : 0;
      if (ganhas > 0) {
        setState(() {
          _enviando = false;
          _moedasGanhas = ganhas;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        if (e is ErroTrato && e.codigoHttp == 409) {
          _recusa = e.mensagem;
        } else {
          _erro = e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.';
        }
      });
    }
  }

  /// O servidor recusou o envio (409): prazo terminado, já avaliado...
  String? _recusa;

  @override
  Widget build(BuildContext context) {
    final fechada = _recusa ?? (widget.prazo.encerrado ? textoPrazoEncerrado : null);
    if (fechada != null) {
      return PaginaTrato(
        titulo: 'Avaliar o cliente',
        rodape: BotaoPrimario(texto: 'Voltar', aoTocar: () => Navigator.of(context).maybePop()),
        children: [
          Text('Não dá para avaliar', style: TipografiaTrato.tituloGrande),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            fechada,
            key: const ValueKey('avaliacao-fechada'),
            style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
          ),
        ],
      );
    }
    return PaginaTrato(
      titulo: 'Avaliar o cliente',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erro != null) ...[
            AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_moedasGanhas != null)
            BotaoPrimario(
              texto: 'Continuar',
              aoTocar: () => Navigator.of(context).pop(true),
            )
          else ...[
            Text(
              _textoDoBonus,
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
            if (widget.prazo.ate != null) ...[
              const SizedBox(height: EspacosTrato.x2),
              Text(
                textoAvaliarAte(widget.prazo.ate!),
                key: const ValueKey('avaliar-ate'),
                textAlign: TextAlign.center,
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
              ),
            ],
            const SizedBox(height: EspacosTrato.x3),
            BotaoPrimario(
              texto: 'Enviar avaliação',
              carregando: _enviando,
              aoTocar: _nota == 0 ? null : _enviar,
            ),
          ],
        ],
      ),
      children: [
        Text('Como foi atender neste pedido?', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Pedido ${widget.pedidoNumero}. Sua nota ajuda outros profissionais.',
          style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        EstrelasNota(
          rotulo: 'Nota do cliente',
          nota: _nota,
          aoMudar: (n) => setState(() => _nota = n),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoLongo(
          rotulo: 'Comentário (opcional)',
          controlador: _comentario,
          dica: 'Ex.: local organizado, pagamento em dia',
          linhas: 3,
        ),
        if (_moedasGanhas != null && _moedasGanhas! > 0) ...[
          const SizedBox(height: EspacosTrato.x4),
          AvisoFaixa(
            texto: widget.prazo.bonusValidadeDias != null && widget.prazo.bonusValidadeDias! > 0
                ? '${_tratinhos(_moedasGanhas!)} a liberar (se não houver disputa). '
                    '${textoValidadeBonusDias(widget.prazo.bonusValidadeDias!)}'
                : '${_tratinhos(_moedasGanhas!)} a liberar (se não houver disputa).',
            tipo: TipoStatus.sucesso,
            icone: Icons.stars_outlined,
          ),
        ],
      ],
    );
  }
}
