import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dispositivo/abrir_mapa.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_de_usuario.dart';
import '../comuns/desconto_moedas.dart' show textoTratinhos;
import '../comuns/formato_aparelho.dart' show horaDoAparelho;
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
    this.aoPedirExclusividade,
  });

  final DetalhePedido dados;
  final VoidCallback? aoFazerOrcamento;
  final VoidCallback? aoPerguntar;

  /// Chamado depois que o profissional escolhe o motivo e confirma.
  final ValueChanged<MotivoRecusa>? aoRecusar;

  /// Pede exclusividade de 48h passando a chave de idempotência gerada uma vez por toque.
  final Future<ExclusividadeProfissional> Function(String chaveIdempotencia)? aoPedirExclusividade;

  @override
  State<DetalhePedidoTela> createState() => _DetalhePedidoTelaState();
}

class _DetalhePedidoTelaState extends State<DetalhePedidoTela> {
  var _pedindoExclusividade = false;
  var _tentativa = 0;
  String? _erroExclusividade;
  ExclusividadeProfissional? _exclusividadeLocal;
  ResumoExclusividades? _resumoLocal;

  ExclusividadeProfissional? get _exclusividade =>
      _exclusividadeLocal ?? widget.dados.exclusividade ?? widget.dados.pedido.exclusividade;

  ResumoExclusividades? get _resumo => _resumoLocal ?? widget.dados.exclusividades;

  Future<void> _recusar(BuildContext context) async {
    final motivo = await pedirMotivoRecusa(context);
    if (motivo != null) widget.aoRecusar?.call(motivo);
  }

  String? _motivoDesabilitado(PedidoAberto pedido, ResumoExclusividades resumo) {
    if (pedido.urgente) return 'Pedidos urgentes não têm exclusividade.';
    if (!pedido.permiteExclusividade) return 'Esta categoria não permite exclusividade.';
    if (widget.dados.bloqueadoRecusa || _exclusividade?.status == 'recusada') {
      return 'Você já teve uma oferta recusada por este cliente recentemente.';
    }
    if (resumo.ativasOuPendentes >= resumo.limiteMaximo) {
      return 'Você já atingiu o limite de ${resumo.limiteMaximo} exclusividades em andamento.';
    }
    if (resumo.saldoProfissional < 100) {
      return 'Saldo insuficiente: você precisa de 100 Tratinhos.';
    }
    return null;
  }

  String _mensagemErroServidor(Object erro) {
    if (erro is ErroTrato) {
      return switch (erro.codigo) {
        'saldo_insuficiente' => 'Você não tem 100 Tratinhos disponíveis para pedir exclusividade.',
        'limite_simultaneas' => 'Você já atingiu o limite de exclusividades em andamento.',
        'pedido_indisponivel' => 'Este pedido não está mais disponível para exclusividade.',
        'bloqueado_recusa' =>
          'Você precisa aguardar antes de pedir exclusividade para este cliente de novo.',
        'pedido_urgente' => 'Pedidos urgentes não têm exclusividade.',
        'categoria_sem_exclusividade' => 'Esta categoria não permite exclusividade.',
        'proprio_pedido' => 'Você não pode pedir exclusividade no seu próprio pedido.',
        'fora_da_area' => 'Você não atende a categoria ou a região deste pedido.',
        'indisponivel' =>
          'A exclusividade está indisponível no momento. Tente de novo em instantes.',
        _ => erro.mensagem,
      };
    }
    return 'Não foi possível pedir exclusividade agora. Tente de novo.';
  }

  Future<void> _abrirFolhaExclusividade() async {
    if (_pedindoExclusividade || widget.aoPedirExclusividade == null) return;
    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EspacosTrato.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pedir exclusividade de 48 horas', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x3),
              Text(
                '1. O cliente tem 6 horas para responder.',
                style: TipografiaTrato.corpo,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                '2. Se ele recusar ou não responder, os 100 Tratinhos voltam.',
                style: TipografiaTrato.corpo,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                '3. Se ele aceitar, você tem 48 horas e precisa enviar o orçamento.',
                style: TipografiaTrato.corpo,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                '4. Se não atender, os 100 não voltam.',
                style: TipografiaTrato.corpo,
              ),
              const SizedBox(height: EspacosTrato.x5),
              BotaoPrimario(
                texto: 'Confirmar por 100 Tratinhos',
                aoTocar: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: EspacosTrato.x2),
              Center(
                child: BotaoLink(
                  texto: 'Cancelar',
                  aoTocar: () => Navigator.of(ctx).pop(false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmado != true || !mounted) return;
    final chave =
        'exc-${widget.dados.pedido.id}-${DateTime.now().microsecondsSinceEpoch}-${++_tentativa}';
    setState(() {
      _pedindoExclusividade = true;
      _erroExclusividade = null;
    });
    try {
      final nova = await widget.aoPedirExclusividade!(chave);
      if (!mounted) return;
      setState(() {
        _pedindoExclusividade = false;
        _exclusividadeLocal = nova;
        if (_resumo != null) {
          _resumoLocal = _resumo!.comNovaOferta(nova);
        }
      });
    } on Object catch (erro) {
      if (!mounted) return;
      setState(() {
        _pedindoExclusividade = false;
        _erroExclusividade = _mensagemErroServidor(erro);
      });
    }
  }

  Widget _secaoExclusividade(PedidoAberto pedido) {
    final ex = _exclusividade;
    if (pedido.reservado || (ex?.ativa ?? false)) {
      final expira = ex?.expiraEm;
      final ate = expira == null ? '' : ' · termina às ${horaDoAparelho(expira.toLocal())}';
      return AvisoFaixa(
        texto: 'Reservado para você$ate',
        tipo: TipoStatus.sucesso,
        icone: Icons.verified_outlined,
      );
    }
    if (ex?.aguardandoCliente ?? false) {
      return const AvisoFaixa(
        texto: 'Oferta enviada, aguardando o cliente',
        tipo: TipoStatus.info,
        icone: Icons.hourglass_top_outlined,
      );
    }
    final resumo = _resumo ?? const ResumoExclusividades();
    final motivoDesabilitado = _motivoDesabilitado(pedido, resumo);
    final podeTocar =
        !_pedindoExclusividade && motivoDesabilitado == null && widget.aoPedirExclusividade != null;
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${resumo.ativasOuPendentes} de ${resumo.limiteMaximo} exclusividades em andamento',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ),
              Text(
                textoTratinhos(resumo.saldoProfissional),
                style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            'Use 100 Tratinhos: prioridade que você ganhou avaliando',
            style: TipografiaTrato.corpoPequeno,
          ),
          const SizedBox(height: EspacosTrato.x3),
          BotaoSecundario(
            texto: _pedindoExclusividade
                ? 'Enviando pedido de exclusividade...'
                : 'Pedir exclusividade de 48 horas',
            aoTocar: podeTocar ? _abrirFolhaExclusividade : null,
          ),
          if (motivoDesabilitado != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              motivoDesabilitado,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
          ],
          if (_erroExclusividade != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            AvisoFaixa(
              texto: _erroExclusividade!,
              tipo: TipoStatus.perigo,
              icone: Icons.error_outline,
            ),
          ],
        ],
      ),
    );
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
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
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
                    const SizedBox(height: EspacosTrato.x4),
                    _Mapa(
                      aoTocar: pedido.latitude == null || pedido.longitude == null
                          ? null
                          : () => abrirNoMapa(
                                pedido.latitude!,
                                pedido.longitude!,
                                pedido.bairro.isEmpty ? 'Região do pedido' : pedido.bairro,
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
                            pedido.bairro.isEmpty
                                ? 'Região da sua área. '
                                    'O endereço completo aparece depois da contratação.'
                                : pedido.distanciaKm == null
                                    ? 'Bairro ${pedido.bairro}. '
                                        'O endereço completo aparece depois da contratação.'
                                    : '${pedido.bairro}, a ${textoDistancia(pedido.distanciaKm)}. '
                                        'O endereço completo aparece depois da contratação.',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: CoresTrato.textoSecundario),
                          ),
                        ),
                      ],
                    ),
                    if (widget.aoPedirExclusividade != null ||
                        _exclusividade != null ||
                        _resumo != null ||
                        pedido.reservado) ...[
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

/// Espaço do mapa do protótipo (área aproximada, sem endereço exato).
class _Mapa extends StatelessWidget {
  const _Mapa({this.aoTocar});

  /// Abre o app de mapas no ponto aproximado. Sem ponto, o cartão só ilustra a área.
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: aoTocar == null ? 'Mapa da região aproximada' : 'Abrir região aproximada no mapa',
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
                  aoTocar == null ? 'Área aproximada' : 'Área aproximada · toque para ver no mapa',
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
