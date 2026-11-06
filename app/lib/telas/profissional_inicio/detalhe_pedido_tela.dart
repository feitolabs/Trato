import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../../dispositivo/abrir_mapa.dart';
import '../cliente/avatar_de_usuario.dart';
import '../conclusao/apoio_conclusao.dart' show EspacoFoto;
import 'dados_exemplo.dart';
import 'modelos.dart';
import 'pecas_profissional.dart';
import 'recusar_pedido_folha.dart';

String _iniciais(String nome) {
  final partes = nome.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return 'C';
  final a = partes.first[0].toUpperCase();
  return partes.length == 1 ? a : '$a${partes.last[0].toUpperCase()}';
}

/// Tela 24 do protótipo: detalhe de um pedido aberto, visto pelo profissional.
/// Mostra só bairro e distância: o endereço completo aparece depois da contratação.
class DetalhePedidoTela extends StatelessWidget {
  const DetalhePedidoTela({
    super.key,
    this.dados = detalhePedidoExemplo,
    this.aoFazerOrcamento,
    this.aoPerguntar,
    this.aoRecusar,
  });

  final DetalhePedido dados;
  final VoidCallback? aoFazerOrcamento;
  final VoidCallback? aoPerguntar;

  /// Chamado depois que o profissional escolhe o motivo e confirma.
  final ValueChanged<MotivoRecusa>? aoRecusar;

  Future<void> _recusar(BuildContext context) async {
    final motivo = await pedirMotivoRecusa(context);
    if (motivo != null) aoRecusar?.call(motivo);
  }

  @override
  Widget build(BuildContext context) {
    final pedido = dados.pedido;
    final linhas = [
      ...dados.linhas,
      LinhaDetalhe('Prazo', _capitalizar(pedido.prazo)),
      LinhaDetalhe('Cliente pensa gastar', textoFaixa(pedido)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          [dados.fechaEm, textoOrcamentos(pedido)]
              .where((t) => t.isNotEmpty)
              .join(' · '),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                  top: EspacosTrato.x2, bottom: EspacosTrato.x6),
              child: ConteudoResponsivo(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pedido.clienteId != null) ...[
                      Row(
                        children: [
                          AvatarDeUsuario(
                            iniciais: _iniciais(pedido.clienteNome ?? ''),
                            usuarioId: pedido.clienteId,
                            tamanho: 40,
                          ),
                          const SizedBox(width: EspacosTrato.x3),
                          Expanded(
                            child: Text(
                              pedido.clienteNome ?? 'Cliente',
                              style: TipografiaTrato.corpoForte,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                    ],
                    Text(pedido.titulo, style: TipografiaTrato.tituloGrande),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      dados.clienteResumo,
                      style: TipografiaTrato.corpo
                          .copyWith(color: CoresTrato.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x5),
                    Row(
                      children: [
                        for (var i = 0;
                            i < dados.legendasFotos.length;
                            i++) ...[
                          if (i > 0) const SizedBox(width: EspacosTrato.x2),
                          Expanded(
                              child:
                                  EspacoFoto(legenda: dados.legendasFotos[i])),
                        ],
                      ],
                    ),
                    const SizedBox(height: EspacosTrato.x5),
                    Text(dados.descricao, style: TipografiaTrato.corpo),
                    const SizedBox(height: EspacosTrato.x5),
                    CartaoTrato(
                      child: Column(
                        children: [
                          for (var i = 0; i < linhas.length; i++) ...[
                            if (i > 0) const Divider(height: EspacosTrato.x6),
                            _LinhaDoCartao(linha: linhas[i]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    _Mapa(
                      aoTocar:
                          pedido.latitude == null || pedido.longitude == null
                              ? null
                              : () => abrirNoMapa(
                                    pedido.latitude!,
                                    pedido.longitude!,
                                    pedido.bairro.isEmpty
                                        ? 'Região do pedido'
                                        : pedido.bairro,
                                  ),
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline, size: EspacosTrato.x5),
                        const SizedBox(width: EspacosTrato.x2),
                        Expanded(
                          child: Text(
                            '${pedido.bairro.isEmpty ? 'Distância' : '${pedido.bairro}, a'} '
                            '${textoDistancia(pedido.distanciaKm)}. '
                            'O endereço completo aparece depois da contratação.',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: CoresTrato.textoSecundario),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    Center(
                      child: BotaoLink(
                        texto: 'Recusar pedido',
                        aoTocar: () => _recusar(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: CoresTrato.superficie,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                child: ConteudoResponsivo(
                  child: Row(
                    children: [
                      Expanded(
                          child: BotaoSecundario(
                              texto: 'Perguntar',
                              aoTocar: aoPerguntar ?? () {})),
                      const SizedBox(width: EspacosTrato.x3),
                      Expanded(
                          child: BotaoPrimario(
                              texto: 'Fazer orçamento',
                              aoTocar: aoFazerOrcamento ?? () {})),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalizar(String t) =>
      t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

class _LinhaDoCartao extends StatelessWidget {
  const _LinhaDoCartao({required this.linha});

  final LinhaDetalhe linha;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            linha.rotulo,
            style: TipografiaTrato.corpo
                .copyWith(color: CoresTrato.textoSecundario),
          ),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Expanded(
          flex: 3,
          child: Text(linha.valor,
              textAlign: TextAlign.end, style: TipografiaTrato.corpoForte),
        ),
      ],
    );
  }
}

/// Espaço do mapa do protótipo (área aproximada, sem endereço exato).
class _Mapa extends StatelessWidget {
  const _Mapa({this.aoTocar});

  /// Abre o app de mapas no ponto aproximado. Sem ponto, o cartão só ilustra a área.
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: aoTocar == null
          ? 'Mapa da região aproximada'
          : 'Abrir região aproximada no mapa',
      button: aoTocar != null,
      child: GestureDetector(
        onTap: aoTocar,
        child: Container(
          height: 160,
          width: double.infinity,
          padding: const EdgeInsets.all(EspacosTrato.x3),
          decoration: BoxDecoration(
            color: CoresTrato.azulSuave,
            borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
            border: Border.all(color: CoresTrato.borda),
          ),
          child: Stack(
            children: [
              Align(
                alignment: const Alignment(0, -0.45),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: CoresTrato.azulClaro,
                    shape: BoxShape.circle,
                    border: Border.all(color: CoresTrato.azulTexto, width: 1.5),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  aoTocar == null
                      ? 'Área aproximada'
                      : 'Área aproximada · toque para ver no mapa',
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: CoresTrato.petroleo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
