import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../conclusao/campo_longo.dart';
import '../conclusao/estrelas_nota.dart';
import '../profissional_apoio/apoio.dart';

/// O profissional avalia o cliente depois do serviço concluído (uma vez por pedido). Só pede e
/// manda: quem aceita, recusa e guarda é o servidor.
class AvaliarClienteTela extends StatefulWidget {
  const AvaliarClienteTela({super.key, required this.pedidoNumero, required this.aoEnviar});

  final String pedidoNumero;

  /// Manda a avaliação e devolve os Tratinhos ganhos (0 ou null se nenhum). Lança erro se o servidor recusar.
  final Future<Object?> Function(int nota, String comentario) aoEnviar;

  @override
  State<AvaliarClienteTela> createState() => _AvaliarClienteTelaState();
}

class _AvaliarClienteTelaState extends State<AvaliarClienteTela> {
  /// Data (dd/mm) 7 dias depois de hoje, o prazo que o app já informa para os Tratinhos.
  String _dataLiberacao() {
    final d = DateTime.now().add(const Duration(days: 7));
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
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
        _erro = e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Avaliar o cliente vale +50 Tratinhos (1 por cliente). '
              'Tratinhos liberados: ${_dataLiberacao()} (7 dias, se não houver disputa).',
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
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
            texto: '+$_moedasGanhas Tratinhos a liberar em 7 dias (se não houver disputa). '
                'Tratinhos liberados: ${_dataLiberacao()}',
            tipo: TipoStatus.sucesso,
            icone: Icons.stars_outlined,
          ),
        ],
      ],
    );
  }
}
