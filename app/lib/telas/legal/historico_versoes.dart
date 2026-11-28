/// Termos 23.7: histórico de versões. Versões, datas e textos vêm do servidor; o app só mostra.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'texto_legal_tela.dart';

class VersaoDosTermosPublicada {
  const VersaoDosTermosPublicada({
    required this.versao,
    this.desde,
    this.ate,
    this.atual = false,
    this.textoDisponivel = false,
  });

  final String versao;
  final DateTime? desde;

  /// Último dia em que valeu. Nulo: não informado (ou é a atual).
  final DateTime? ate;
  final bool atual;
  final bool textoDisponivel;

  /// Nulo: veio sem o número da versão.
  static VersaoDosTermosPublicada? deJson(Object? json) {
    if (json is! Map) return null;
    final versao = json['versao'];
    if (versao is! String || versao.trim().isEmpty) return null;
    DateTime? dia(String chave) => DateTime.tryParse('${json[chave] ?? ''}');
    return VersaoDosTermosPublicada(
      versao: versao.trim(),
      desde: dia('vigente_desde'),
      ate: dia('vigente_ate'),
      atual: json['atual'] == true,
      textoDisponivel: json['texto_disponivel'] == true,
    );
  }

  String get vigencia {
    String data(DateTime d) {
      String dois(int n) => n.toString().padLeft(2, '0');
      return '${dois(d.day)}/${dois(d.month)}/${d.year}';
    }

    final inicio = desde;
    if (inicio == null) return 'Data de vigência não informada';
    final fim = ate;
    if (atual) return 'Em vigor desde ${data(inicio)}';
    return fim == null
        ? 'Passou a valer em ${data(inicio)}'
        : 'Valeu de ${data(inicio)} a ${data(fim)}';
  }
}

abstract interface class ConsultaDeVersoes {
  /// `GET /v1/termos/versoes`, na ordem do servidor. Nulo: o servidor não tem o histórico.
  Future<List<VersaoDosTermosPublicada>?> versoesDosTermos();

  /// `GET /v1/termos/versoes/{versao}`. Nulo: o texto dessa versão não está disponível.
  Future<String?> textoDaVersao(String versao);
}

class HistoricoDeVersoesTela extends StatelessWidget {
  const HistoricoDeVersoesTela({super.key, required this.consulta});

  final ConsultaDeVersoes consulta;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    return MolduraTelaComum(
      titulo: 'Histórico de versões',
      child: CarregadorTela<_Historico>(
        carregar: () async => _Historico(await consulta.versoesDosTermos()),
        construir: (context, historico, _) {
          final itens = historico.itens;
          if (itens == null || itens.isEmpty) {
            return ListView(
              children: [
                Text(
                  itens == null
                      ? 'O histórico de versões está indisponível agora.'
                      : 'Ainda não há versões para mostrar.',
                  style: corpo,
                ),
              ],
            );
          }
          return ListView(
            children: [
              for (final v in itens)
                Padding(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                  child: CartaoTrato(
                    key: ValueKey('versao-${v.versao}'),
                    aoTocar: v.textoDisponivel
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TextoDaVersaoTela(consulta: consulta, versao: v),
                              ),
                            )
                        : null,
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Versão ${v.versao}', style: TipografiaTrato.tituloCartao),
                          Text(v.vigencia, style: corpo),
                          Text(
                            v.textoDisponivel ? 'Ler o texto' : 'Texto não disponível no app',
                            style: TipografiaTrato.corpoPequeno.copyWith(
                              color: v.textoDisponivel ? c.azulTexto : c.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Embrulho para o carregador distinguir "sem histórico" de "carregando".
class _Historico {
  const _Historico(this.itens);

  final List<VersaoDosTermosPublicada>? itens;
}

class TextoDaVersaoTela extends StatelessWidget {
  const TextoDaVersaoTela({super.key, required this.consulta, required this.versao});

  final ConsultaDeVersoes consulta;
  final VersaoDosTermosPublicada versao;

  @override
  Widget build(BuildContext context) {
    final corpo = TipografiaTrato.corpo.copyWith(color: context.cores.texto);
    return MolduraTelaComum(
      titulo: 'Termos, versão ${versao.versao}',
      child: CarregadorTela<List<BlocoLegal>>(
        carregar: () async {
          final texto = await consulta.textoDaVersao(versao.versao);
          if (texto == null || texto.trim().isEmpty) {
            throw const ErroTrato(
              TipoErro.recusado,
              'O texto desta versão não está disponível.',
            );
          }
          return interpretarTextoLegal(texto);
        },
        construir: (context, blocos, _) => ListView(
          children: [
            Text(versao.vigencia, style: corpo),
            const SizedBox(height: EspacosTrato.x3),
            for (final b in blocos) LinhaDoTextoLegal(bloco: b),
          ],
        ),
      ),
    );
  }
}
