import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import 'dados_exemplo.dart';
import 'modelos.dart';
import 'pecas_profissional.dart';

/// Tela 23 do protótipo: Início do profissional ("Pedidos perto de você").
/// Todos os botões chamam callbacks opcionais; sem callback, não fazem nada.
class InicioProfissionalTela extends StatefulWidget {
  const InicioProfissionalTela({
    super.key,
    this.dados = inicioProfissionalExemplo,
    this.aoAlterarDisponivel,
    this.aoFazerCheckIn,
    this.aoAbrirCarteira,
    this.aoAbrirFiltros,
    this.aoAbrirPedido,
  });

  final InicioProfissional dados;
  final ValueChanged<bool>? aoAlterarDisponivel;
  final VoidCallback? aoFazerCheckIn;
  final VoidCallback? aoAbrirCarteira;
  final VoidCallback? aoAbrirFiltros;
  final ValueChanged<PedidoAberto>? aoAbrirPedido;

  @override
  State<InicioProfissionalTela> createState() => _InicioProfissionalTelaState();
}

class _InicioProfissionalTelaState extends State<InicioProfissionalTela> {
  late bool _disponivel = widget.dados.disponivelAgora;

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, ${dados.nome}',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
                const SizedBox(height: EspacosTrato.x1),
                Text('Pedidos perto de você', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x4),
                _CartaoDisponivel(
                  ligado: _disponivel,
                  aoMudar: (v) {
                    setState(() => _disponivel = v);
                    widget.aoAlterarDisponivel?.call(v);
                  },
                ),
                if (dados.proximo != null) ...[
                  const SizedBox(height: EspacosTrato.x4),
                  _CartaoProximo(proximo: dados.proximo!, aoFazerCheckIn: widget.aoFazerCheckIn),
                ],
                const SizedBox(height: EspacosTrato.x4),
                _CartaoCarteira(carteira: dados.carteira, aoTocar: widget.aoAbrirCarteira),
                const SizedBox(height: EspacosTrato.x5),
                Row(
                  children: [
                    Expanded(child: Text('Pedidos abertos', style: TipografiaTrato.titulo)),
                    BotaoLink(texto: 'Filtros', aoTocar: widget.aoAbrirFiltros ?? () {}),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x2),
                for (final pedido in dados.pedidos) ...[
                  _CartaoPedido(
                    pedido: pedido,
                    aoTocar: widget.aoAbrirPedido == null
                        ? null
                        : () => widget.aoAbrirPedido!(pedido),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartaoDisponivel extends StatelessWidget {
  const _CartaoDisponivel({required this.ligado, required this.aoMudar});

  final bool ligado;
  final ValueChanged<bool> aoMudar;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disponível agora', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  'Você recebe pedidos urgentes da sua região',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Semantics(
            label: 'Disponível agora',
            child: Switch(
              value: ligado,
              onChanged: aoMudar,
              activeTrackColor: CoresTrato.petroleo,
              activeThumbColor: CoresTrato.creme,
              inactiveTrackColor: CoresTrato.borda,
              inactiveThumbColor: CoresTrato.superficie,
              trackOutlineColor: const WidgetStatePropertyAll(CoresTrato.petroleo),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoProximo extends StatelessWidget {
  const _CartaoProximo({required this.proximo, required this.aoFazerCheckIn});

  final ProximoAtendimento proximo;
  final VoidCallback? aoFazerCheckIn;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      escuro: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proximo.quando.toUpperCase(),
            style: TipografiaTrato.sobretitulo.copyWith(color: CoresTrato.creme),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            proximo.titulo,
            style: TipografiaTrato.titulo.copyWith(color: CoresTrato.creme),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, color: CoresTrato.creme),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: Text(
                  proximo.endereco,
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.creme),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x4),
          BotaoSecundario(texto: 'Fazer check-in', aoTocar: aoFazerCheckIn ?? () {}),
        ],
      ),
    );
  }
}

class _CartaoCarteira extends StatelessWidget {
  const _CartaoCarteira({required this.carteira, required this.aoTocar});

  final ResumoCarteira carteira;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      aoTocar: aoTocar ?? () {},
      child: Row(
        children: [
          Expanded(child: _Valor(rotulo: 'Em andamento', centavos: carteira.retidoCentavos)),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(child: _Valor(rotulo: 'Para sacar', centavos: carteira.paraSacarCentavos)),
        ],
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({required this.rotulo, required this.centavos});

  final String rotulo;
  final int centavos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(formatarReais(centavos), style: TipografiaTrato.tituloCartao, maxLines: 1),
        ),
      ],
    );
  }
}

class _CartaoPedido extends StatelessWidget {
  const _CartaoPedido({required this.pedido, required this.aoTocar});

  final PedidoAberto pedido;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: aoTocar,
        behavior: HitTestBehavior.opaque,
        child: CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(pedido.titulo, style: TipografiaTrato.tituloCartao)),
                  if (pedido.urgente) ...[
                    const SizedBox(width: EspacosTrato.x2),
                    const ChipStatus(texto: 'Urgente', tipo: TipoStatus.destaque),
                  ],
                ],
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                '${pedido.bairro} · ${textoDistancia(pedido.distanciaKm)} · ${pedido.prazo}',
                style: secundario,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: EspacosTrato.x3,
                children: [
                  Text(textoFaixa(pedido), style: TipografiaTrato.corpoForte),
                  Text(textoOrcamentos(pedido), style: secundario),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
