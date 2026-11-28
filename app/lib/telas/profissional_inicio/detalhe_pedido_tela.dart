import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dispositivo/abrir_mapa.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_de_usuario.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho, horaDoAparelho;
import '../conclusao/apoio_conclusao.dart' show EspacoFoto;
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'modelos.dart';
import 'pecas_profissional.dart';
import 'recusar_pedido_folha.dart';

String _iniciais(String nome) {
  final partes = nome.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return 'C';
  final a = partes.first[0].toUpperCase();
  return partes.length == 1 ? a : '$a${partes.last[0].toUpperCase()}';
}

Widget _fotoPedido(int indice, String item) {
  final ehImagemReal =
      item.startsWith('http://') || item.startsWith('https://') || item.startsWith('/');
  return ehImagemReal
      ? EspacoFoto(legenda: 'Foto ${indice + 1}', referencia: item)
      : EspacoFoto(legenda: item);
}

/// Tela 24 do protótipo: detalhe de um pedido aberto, visto pelo profissional.
/// Mostra só bairro e distância: o endereço completo aparece depois da contratação.
class DetalhePedidoTela extends StatefulWidget {
  const DetalhePedidoTela({
    super.key,
    required this.dados,
    this.aoFazerOrcamento,
    this.aoPerguntar,
    this.aoRecusar,
    this.aoDesistirExclusividade,
    this.aoAbrirMapa,
  });

  /// Abre o app de mapas no ponto aproximado (padrão: `abrirNoMapa`). Existe para testes.
  final void Function(double latitude, double longitude, String rotulo)? aoAbrirMapa;

  final DetalhePedido dados;
  final VoidCallback? aoFazerOrcamento;
  final VoidCallback? aoPerguntar;

  /// Chamado depois que o profissional escolhe o motivo e confirma.
  final ValueChanged<MotivoRecusa>? aoRecusar;

  /// Desistir da exclusividade que o cliente pediu (Termos 13.6).
  final Future<void> Function(String exclusividadeId)? aoDesistirExclusividade;

  @override
  State<DetalhePedidoTela> createState() => _DetalhePedidoTelaState();
}

class _DetalhePedidoTelaState extends State<DetalhePedidoTela> {
  var _desistindo = false;
  var _desistiu = false;
  String? _erroExclusividade;

  ExclusividadeProfissional? get _exclusividade =>
      widget.dados.exclusividade ?? widget.dados.pedido.exclusividade;

  Future<void> _recusar(BuildContext context) async {
    final motivo = await pedirMotivoRecusa(context);
    if (motivo != null) widget.aoRecusar?.call(motivo);
  }

  Future<void> _desistir(String id) async {
    if (_desistindo) return;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Desistir da exclusividade?'),
        content: const Text(
          'Os Tratinhos voltam ao cliente e o pedido deixa de ficar reservado para você.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Desistir'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;
    setState(() {
      _desistindo = true;
      _erroExclusividade = null;
    });
    try {
      await widget.aoDesistirExclusividade!(id);
      if (mounted) setState(() => _desistiu = true);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _erroExclusividade =
            e is ErroTrato ? e.mensagem : 'Não foi possível desistir agora. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _desistindo = false);
    }
  }

  /// Só mostra o que já existe: o profissional não pede mais exclusividade.
  Widget _secaoExclusividade(PedidoAberto pedido) {
    final ex = _exclusividade;
    if (_desistiu) {
      return const AvisoFaixa(
        texto: 'Você desistiu da exclusividade. Os Tratinhos voltaram ao cliente.',
        tipo: TipoStatus.info,
        icone: Icons.info_outline,
      );
    }
    if (pedido.reservado || (ex?.ativa ?? false)) {
      final expira = ex?.expiraEm?.toLocal();
      final ate = expira == null
          ? ''
          : ' · termina em ${diaMesDoAparelho(expira)} às ${horaDoAparelho(expira)}';
      final podeDesistir = ex != null &&
          ex.ativa &&
          ex.doCliente &&
          widget.aoDesistirExclusividade != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AvisoFaixa(
            texto: ex?.doCliente == true
                ? 'O cliente reservou este pedido para você$ate'
                : 'Reservado para você$ate',
            tipo: TipoStatus.sucesso,
            icone: Icons.verified_outlined,
          ),
          if (_erroExclusividade != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              _erroExclusividade!,
              key: const ValueKey('erro-desistir-exclusividade'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
            ),
          ],
          if (podeDesistir)
            Center(
              child: BotaoLink(
                key: const ValueKey('desistir-exclusividade'),
                texto: _desistindo ? 'Desistindo…' : 'Desistir da exclusividade',
                destrutivo: true,
                aoTocar: () => _desistir(ex.id),
              ),
            ),
        ],
      );
    }
    if (ex?.aguardandoCliente ?? false) {
      final ate = ex?.responderAte?.toLocal();
      final prazo = ex!.prazoSuspenso
          ? '. Prazo suspenso: o Trato está com uma falha, e o tempo de resposta não está '
              'correndo.'
          : ate == null
              ? ' (prazo de 6h)'
              : ' (responde em até 6h · até ${horaDoAparelho(ate)})';
      return AvisoFaixa(
        texto: 'Oferta enviada, aguardando o cliente$prazo',
        tipo: TipoStatus.info,
        icone: Icons.hourglass_top_outlined,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    final pedido = dados.pedido;
    final linhas = [
      ...dados.linhas,
      if (!pedido.urgente || pedido.prazo.toLowerCase() != 'urgente')
        LinhaDetalhe('Quando precisa', _capitalizar(pedido.prazo)),
      LinhaDetalhe('Orçamento estimado', textoFaixa(pedido)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          [dados.fechaEm, textoOrcamentos(pedido)].where((t) => t.isNotEmpty).join(' · '),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: EspacosTrato.x2, bottom: EspacosTrato.x6),
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
                    if (dados.clienteResumo.isNotEmpty) ...[
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        dados.clienteResumo,
                        style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
                      ),
                    ],
                    if (dados.legendasFotos.isNotEmpty) ...[
                      const SizedBox(height: EspacosTrato.x5),
                      for (var inicio = 0; inicio < dados.legendasFotos.length; inicio += 3) ...[
                        if (inicio > 0) const SizedBox(height: EspacosTrato.x2),
                        Row(
                          children: [
                            for (var i = inicio;
                                i < inicio + 3 && i < dados.legendasFotos.length;
                                i++) ...[
                              if (i > inicio) const SizedBox(width: EspacosTrato.x2),
                              Expanded(child: _fotoPedido(i, dados.legendasFotos[i])),
                            ],
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: EspacosTrato.x5),
                    Text(dados.descricao, style: TipografiaTrato.corpo),
                    const SizedBox(height: EspacosTrato.x5),
                    CartaoTrato(
                      child: Column(
                        children: [
                          for (var i = 0; i < linhas.length; i++) ...[
                            if (i > 0) const Divider(height: EspacosTrato.x6),
                            LinhaDetalheCartao(
                              rotulo: linhas[i].rotulo,
                              valor: linhas[i].valor,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!pedido.remoto) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      _CartaoRegiao(
                        bairro: pedido.bairro,
                        distanciaKm: pedido.distanciaKm,
                        aoAbrirNoMapa: pedido.latitude == null || pedido.longitude == null
                            ? null
                            : () => (widget.aoAbrirMapa ?? abrirNoMapa)(
                                  pedido.latitude!,
                                  pedido.longitude!,
                                  pedido.bairro.isEmpty ? 'Região do pedido' : pedido.bairro,
                                ),
                      ),
                    ],
                    if (pedido.reservado ||
                        (_exclusividade?.emAndamento ?? false)) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      _secaoExclusividade(pedido),
                    ],
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
            color: context.cores.superficie,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                child: ConteudoResponsivo(
                  child: Row(
                    children: [
                      Expanded(
                          child: BotaoSecundario(
                              texto: 'Perguntar', aoTocar: widget.aoPerguntar ?? () {})),
                      const SizedBox(width: EspacosTrato.x3),
                      Expanded(
                          child: BotaoPrimario(
                              texto: 'Fazer orçamento', aoTocar: widget.aoFazerOrcamento ?? () {})),
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

  static String _capitalizar(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// Etapa 1 do mapa: um cartão honesto com a região aproximada (bairro e distância), sem desenho
/// de mapa nem pino. O botão abre o app de mapas no ponto aproximado, quando há coordenada.
class _CartaoRegiao extends StatelessWidget {
  const _CartaoRegiao({required this.bairro, this.distanciaKm, this.aoAbrirNoMapa});

  final String bairro;
  final double? distanciaKm;
  final VoidCallback? aoAbrirNoMapa;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    return CartaoTrato(
      key: const ValueKey('cartao-regiao'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: context.cores.petroleo),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(child: Text('Região aproximada', style: TipografiaTrato.corpoForte)),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            bairro.isEmpty ? 'Região da sua área' : bairro,
            key: const ValueKey('regiao-bairro'),
            style: TipografiaTrato.tituloGrande,
          ),
          if (distanciaKm != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              'a ${textoDistancia(distanciaKm)} de você',
              key: const ValueKey('regiao-distancia'),
              style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
            ),
          ],
          const SizedBox(height: EspacosTrato.x2),
          Text('O endereço completo aparece depois da contratação.', style: secundario),
          if (aoAbrirNoMapa != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            BotaoSecundario(
              key: const ValueKey('abrir-no-mapa'),
              texto: 'Abrir no mapa',
              icone: Icons.map_outlined,
              aoTocar: aoAbrirNoMapa!,
            ),
          ],
        ],
      ),
    );
  }
}
