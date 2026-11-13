import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../profissional/dinheiro.dart';
import 'inicio_profissional_tela.dart' show CartaoPedidoAberto;
import 'modelos.dart';

/// Aba Pedidos do profissional: pedidos abertos (com filtros) e, ao lado, as conversas.
/// A lista e os filtros são os mesmos do Início; quem filtra é o backend.
class PedidosProfissionalTela extends StatefulWidget {
  const PedidosProfissionalTela({
    super.key,
    required this.pedidos,
    required this.conversas,
    this.carregando = false,
    this.filtrosAtivos = 0,
    this.aoAbrirFiltros,
    this.aoAbrirPedido,
    this.contratados = const [],
    this.aoAbrirContratado,
    this.orcamentosEnviados = const [],
    this.aoAbrirOrcamentoEnviado,
    this.aoAbrirMapa,
  });

  /// Abre o endereço no mapa do aparelho (recebe o texto do endereço).
  final ValueChanged<String>? aoAbrirMapa;

  /// Os orçamentos que o profissional enviou e a resposta do cliente (aguardando, aceito...).
  final List<OrcamentoEnviado> orcamentosEnviados;
  final ValueChanged<OrcamentoEnviado>? aoAbrirOrcamentoEnviado;

  final List<PedidoAberto> pedidos;

  /// Pedidos que o cliente já aceitou (do aceite ao fim): não somem quando deixam de ser "abertos".
  final List<PedidoContratado> contratados;
  final ValueChanged<PedidoContratado>? aoAbrirContratado;

  /// Lista de conversas (aba "Conversas").
  final Widget conversas;
  final bool carregando;

  /// Quantos filtros estão ligados (para o contador do botão).
  final int filtrosAtivos;
  final VoidCallback? aoAbrirFiltros;
  final ValueChanged<PedidoAberto>? aoAbrirPedido;

  @override
  State<PedidosProfissionalTela> createState() => _PedidosProfissionalTelaState();
}

enum _Aba { abertos, orcamentos, andamento, conversas }

class _PedidosProfissionalTelaState extends State<PedidosProfissionalTela> {
  var _aba = _Aba.abertos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: EspacosTrato.x4),
              Text('Pedidos', style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x4),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  _Segmento(
                    texto: 'Abertos',
                    ativo: _aba == _Aba.abertos,
                    aoTocar: () => setState(() => _aba = _Aba.abertos),
                  ),
                  _Segmento(
                    texto: widget.orcamentosEnviados.isEmpty
                        ? 'Orçamentos'
                        : 'Orçamentos (${widget.orcamentosEnviados.length})',
                    ativo: _aba == _Aba.orcamentos,
                    aoTocar: () => setState(() => _aba = _Aba.orcamentos),
                  ),
                  _Segmento(
                    texto: widget.contratados.isEmpty
                        ? 'Em andamento'
                        : 'Em andamento (${widget.contratados.length})',
                    ativo: _aba == _Aba.andamento,
                    aoTocar: () => setState(() => _aba = _Aba.andamento),
                  ),
                  _Segmento(
                    texto: 'Conversas',
                    ativo: _aba == _Aba.conversas,
                    aoTocar: () => setState(() => _aba = _Aba.conversas),
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              Expanded(
                child: switch (_aba) {
                  _Aba.conversas => widget.conversas,
                  _Aba.orcamentos => _orcamentos(),
                  _Aba.andamento => _andamento(),
                  _Aba.abertos => _abertos(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orcamentos() {
    if (widget.orcamentosEnviados.isEmpty) {
      return const EstadoVazio(
        icone: Icons.request_quote_outlined,
        titulo: 'Nenhum orçamento enviado',
        texto: 'Os orçamentos que você enviar aparecem aqui, com a resposta do cliente.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      itemCount: widget.orcamentosEnviados.length,
      separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
      itemBuilder: (_, i) {
        final o = widget.orcamentosEnviados[i];
        final (rotulo, tipo) = switch (o.situacao) {
          'aceito' => ('Aceito pelo cliente', TipoStatus.sucesso),
          'aguardando' => ('Aguardando o cliente', TipoStatus.info),
          _ => ('Encerrado (o cliente escolheu outro ou o pedido acabou)', TipoStatus.alerta),
        };
        return CartaoTrato(
          aoTocar: widget.aoAbrirOrcamentoEnviado == null
              ? null
              : () => widget.aoAbrirOrcamentoEnviado!(o),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(o.titulo, style: TipografiaTrato.tituloCartao),
              const SizedBox(height: EspacosTrato.x1),
              Text(
                '${Dinheiro.formatar(o.valorCentavos)}${o.versao > 1 ? ' · versão ${o.versao}' : ''}',
                style: TipografiaTrato.corpoForte,
              ),
              const SizedBox(height: EspacosTrato.x2),
              ChipStatus(texto: rotulo, tipo: tipo),
            ],
          ),
        );
      },
    );
  }

  Widget _andamento() {
    if (widget.contratados.isEmpty) {
      return const EstadoVazio(
        icone: Icons.handyman_outlined,
        titulo: 'Nenhum pedido em andamento',
        texto:
            'Quando um cliente aceitar o seu orçamento, o pedido aparece aqui, do aceite até o fim.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      itemCount: widget.contratados.length,
      separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
      itemBuilder: (_, i) {
        final c = widget.contratados[i];
        return CartaoTrato(
          aoTocar: widget.aoAbrirContratado == null ? null : () => widget.aoAbrirContratado!(c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.titulo, style: TipografiaTrato.tituloCartao),
              const SizedBox(height: EspacosTrato.x1),
              Text(
                c.situacao,
                style: TipografiaTrato.corpoPequeno.copyWith(
                  color: c.aguardandoPagamento ? CoresTrato.laranja : CoresTrato.textoSecundario,
                ),
              ),
              if (c.quando != null) ...[
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  c.quando!,
                  style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
              const SizedBox(height: EspacosTrato.x2),
              if (c.remoto)
                Row(
                  key: const ValueKey('modalidade-remoto'),
                  children: [
                    const Icon(Icons.videocam_outlined, size: 18, color: CoresTrato.petroleo),
                    const SizedBox(width: EspacosTrato.x2),
                    Text('Atendimento remoto', style: TipografiaTrato.corpoPequeno),
                  ],
                )
              else if (c.endereco != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18, color: CoresTrato.petroleo),
                    const SizedBox(width: EspacosTrato.x2),
                    Expanded(
                      child: Text(
                        c.endereco!,
                        key: const ValueKey('endereco-do-pedido'),
                        style: TipografiaTrato.corpoPequeno,
                      ),
                    ),
                  ],
                ),
                if (c.consultaMapa != null && widget.aoAbrirMapa != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BotaoLink(
                      texto: 'Abrir no mapa',
                      aoTocar: () => widget.aoAbrirMapa!(c.consultaMapa!),
                    ),
                  ),
              ] else
                Text(
                  'O cliente ainda não informou o endereço: combine pelo chat.',
                  style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _abertos() {
    if (widget.carregando) return const EstadoCarregando();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoSecundario(
            texto: widget.filtrosAtivos == 0 ? 'Filtros' : 'Filtros (${widget.filtrosAtivos})',
            icone: Icons.tune,
            aoTocar: widget.aoAbrirFiltros,
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Expanded(
          child: widget.pedidos.isEmpty
              ? EstadoVazio(
                  icone: Icons.inbox_outlined,
                  titulo: 'Nenhum pedido aberto',
                  texto: widget.filtrosAtivos == 0
                      ? 'Quando chegar um pedido da sua região e categoria, ele aparece aqui.'
                      : 'Nenhum pedido combina com os filtros. Tente mudar ou limpar.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                  itemCount: widget.pedidos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                  itemBuilder: (_, i) => CartaoPedidoAberto(
                    pedido: widget.pedidos[i],
                    aoTocar: widget.aoAbrirPedido == null
                        ? null
                        : () => widget.aoAbrirPedido!(widget.pedidos[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Segmento extends StatelessWidget {
  const _Segmento({required this.texto, required this.ativo, required this.aoTocar});

  final String texto;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativo,
      child: Material(
        color: ativo ? CoresTrato.petroleo : CoresTrato.superficie,
        shape: StadiumBorder(
          side: BorderSide(color: ativo ? CoresTrato.petroleo : CoresTrato.borda),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x5,
              vertical: EspacosTrato.x3,
            ),
            child: Text(
              texto,
              style: TipografiaTrato.corpoForte.copyWith(
                color: ativo ? CoresTrato.creme : CoresTrato.petroleo,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
