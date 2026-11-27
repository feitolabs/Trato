/// Termos 1.7 e 23.4: aceite pedido na tela quando o servidor diz que há um pendente. O app nunca
/// registra o aceite sozinho, e a pessoa pode deixar para depois.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/textos_dos_termos.dart';
import 'texto_legal_tela.dart';

/// Existe só quando há o que pedir.
class AceitePendente {
  const AceitePendente({required this.versaoVigente});

  final String versaoVigente;

  /// Nulo: nada a mostrar (sem pendência, sem registro no servidor ou campo ausente).
  static AceitePendente? deJson(Object? json) {
    if (json is! Map) return null;
    if (json['registro_disponivel'] != true || json['aceite_pendente'] != true) return null;
    final versao = json['versao_vigente'];
    if (versao is! String || versao.trim().isEmpty) return null;
    return AceitePendente(versaoVigente: versao.trim());
  }
}

abstract interface class ServicoAceiteDosTermos {
  /// Nulo: não mostrar nada (inclui servidor antigo, 404/503, e conta bloqueada, 403).
  Future<AceitePendente?> aceitePendente();

  /// [versaoMostrada] é a do texto que a pessoa viu.
  Future<void> aceitarTermos(String versaoMostrada);
}

class AceiteDosTermosTela extends StatefulWidget {
  const AceiteDosTermosTela({
    super.key,
    required this.servico,
    required this.pendente,
    this.carregarTexto,
  });

  final ServicoAceiteDosTermos servico;
  final AceitePendente pendente;

  /// Padrão: o texto dos Termos que vai no app (os testes trocam).
  final Future<String> Function()? carregarTexto;

  @override
  State<AceiteDosTermosTela> createState() => _AceiteDosTermosTelaState();
}

class _AceiteDosTermosTelaState extends State<AceiteDosTermosTela> {
  var _marcado = false;
  var _enviando = false;
  String? _erro;

  /// Só aceita quem leu a versão em vigor.
  bool get _versaoConfere => widget.pendente.versaoVigente == versaoDosTermos;

  Future<void> _aceitar() async {
    if (!_marcado || _enviando || !_versaoConfere) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.servico.aceitarTermos(versaoDosTermos);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Aceite registrado.')));
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = e is ErroTrato && (e.codigoHttp == 404 || e.codigoHttp == 503)
            ? 'O registro do aceite está indisponível agora. Tente mais tarde.'
            : e is ErroTrato
                ? e.mensagem
                : 'Não foi possível registrar o aceite. Tente de novo.';
      });
    }
  }

  Widget _depois() => Center(
        child: BotaoLink(
          key: const ValueKey('termos-depois'),
          texto: 'Deixar para depois',
          aoTocar: () => Navigator.of(context).maybePop(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    if (!_versaoConfere) {
      return MolduraTelaComum(
        titulo: 'Termos de uso',
        child: ListView(
          children: [
            Text(
              'Há uma versão dos Termos (${widget.pendente.versaoVigente}) diferente da que '
              'este app mostra ($versaoDosTermos). Atualize o app para ler e aceitar.',
              key: const ValueKey('termos-atualize-o-app'),
              style: corpo,
            ),
            const SizedBox(height: EspacosTrato.x4),
            _depois(),
          ],
        ),
      );
    }
    return MolduraTelaComum(
      titulo: 'Termos de uso',
      child: CarregadorTela<String>(
        carregar: () async {
          final texto = await (widget.carregarTexto ?? TextoLegal.termos.carregar)();
          if (texto.trim().isEmpty) {
            throw const ErroTrato(TipoErro.recusado, 'Não foi possível abrir o texto dos Termos.');
          }
          return texto;
        },
        construir: (context, texto, _) {
          final blocos = interpretarTextoLegal(texto);
          return LayoutBuilder(
            builder: (context, limites) => Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    key: const ValueKey('texto-dos-termos'),
                    padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
                    itemCount: blocos.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                            child: Text(
                              'Versão $versaoDosTermos. Leia antes de aceitar.',
                              style: corpo,
                            ),
                          )
                        : LinhaDoTextoLegal(bloco: blocos[i - 1]),
                  ),
                ),
                const Divider(height: 1),
                // Com fonte grande em tela baixa, o rodapé rola em vez de estourar.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: limites.maxHeight * 0.65),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CheckboxListTile(
                            key: const ValueKey('termos-marcar'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _marcado,
                            onChanged:
                                _enviando ? null : (v) => setState(() => _marcado = v ?? false),
                            title: Text(
                              'Li e aceito os Termos de uso (versão $versaoDosTermos).',
                              style: corpo,
                            ),
                          ),
                          if (_erro != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _erro!,
                                style: TipografiaTrato.corpoPequeno.copyWith(
                                  color: c.vermelhoTexto,
                                ),
                              ),
                            ),
                            const SizedBox(height: EspacosTrato.x2),
                          ],
                          BotaoPrimario(
                            key: const ValueKey('termos-aceitar'),
                            texto: 'Aceitar',
                            carregando: _enviando,
                            aoTocar: _marcado ? _aceitar : null,
                          ),
                          _depois(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
