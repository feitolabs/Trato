import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';

/// Tela 8 do protótipo: Início do cliente. [aoBuscar] leva à aba Buscar.
class InicioTela extends StatelessWidget {
  const InicioTela({super.key, required this.aoBuscar});

  final VoidCallback aoBuscar;

  void _emBreve(BuildContext context, String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Olá, $nomeDoCliente',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: CoresTrato.textoSecundario),
                          ),
                          const SizedBox(height: EspacosTrato.x1),
                          Text('O que você precisa hoje?', style: TipografiaTrato.tituloGrande),
                        ],
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x3),
                    _BotaoSino(aoTocar: () => _emBreve(context, 'Notificações')),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x6),
                GestureDetector(
                  onTap: aoBuscar,
                  behavior: HitTestBehavior.opaque,
                  child: const AbsorbPointer(
                    child: CampoTrato(
                      rotulo: 'Buscar',
                      dica: 'Serviço ou profissional',
                      iconeInicio: Icons.search,
                    ),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x5),
                CartaoTrato(
                  escuro: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Descreva o problema',
                        style: TipografiaTrato.titulo.copyWith(color: CoresTrato.creme),
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                      Text(
                        'Receba até 5 orçamentos de profissionais com identidade verificada. '
                        'O pagamento fica retido até a conclusão.',
                        style: TipografiaTrato.corpoGrande.copyWith(color: CoresTrato.creme),
                      ),
                      const SizedBox(height: EspacosTrato.x5),
                      BotaoSecundario(
                        texto: 'Pedir orçamento',
                        aoTocar: () => _emBreve(context, 'Novo pedido'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x4),
                CartaoTrato(
                  aoTocar: () => _emBreve(context, pedidoEmAndamento.titulo),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pedidoEmAndamento.titulo, style: TipografiaTrato.tituloCartao),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        pedidoEmAndamento.situacao,
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child:
                            ChipStatus(texto: pedidoEmAndamento.aviso, tipo: TipoStatus.destaque),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x6),
                Text('Categorias', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                _GradeCategorias(
                  aoTocar: (c) => _emBreve(context, c.nome),
                ),
                const SizedBox(height: EspacosTrato.x6),
                Text('Serviços recentes', style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                for (final servico in servicosRecentes) ...[
                  _CartaoServicoRecente(
                    servico: servico,
                    aoTocar: () => _emBreve(context, servico.titulo),
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

class _BotaoSino extends StatelessWidget {
  const _BotaoSino({required this.aoTocar});

  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Notificações',
      child: Material(
        color: CoresTrato.superficie,
        shape: const CircleBorder(side: BorderSide(color: CoresTrato.borda)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: aoTocar,
          child: const SizedBox.square(
            dimension: 48,
            child: Icon(Icons.notifications_none, color: CoresTrato.petroleo),
          ),
        ),
      ),
    );
  }
}

/// 4 categorias por linha. O rótulo encolhe em vez de quebrar.
class _GradeCategorias extends StatelessWidget {
  const _GradeCategorias({required this.aoTocar});

  final ValueChanged<CategoriaServico> aoTocar;

  static const _porLinha = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var inicio = 0; inicio < categorias.length; inicio += _porLinha) ...[
          if (inicio > 0) const SizedBox(height: EspacosTrato.x2),
          Row(
            children: [
              for (var i = inicio; i < inicio + _porLinha; i++) ...[
                if (i > inicio) const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: _Categoria(categoria: categorias[i], aoTocar: aoTocar),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Categoria extends StatelessWidget {
  const _Categoria({required this.categoria, required this.aoTocar});

  final CategoriaServico categoria;
  final ValueChanged<CategoriaServico> aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      button: true,
      child: Material(
        color: CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: const BorderSide(color: CoresTrato.borda),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: () => aoTocar(categoria),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x1,
              vertical: EspacosTrato.x3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(categoria.icone, color: CoresTrato.petroleo),
                const SizedBox(height: EspacosTrato.x2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    categoria.nome,
                    maxLines: 1,
                    style: TipografiaTrato.corpoPequeno.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartaoServicoRecente extends StatelessWidget {
  const _CartaoServicoRecente({required this.servico, required this.aoTocar});

  final ServicoRecente servico;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      aoTocar: aoTocar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(servico.titulo, style: TipografiaTrato.tituloCartao),
              const ChipStatus(texto: 'Finalizado', tipo: TipoStatus.sucesso, icone: Icons.check),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            '${servico.profissional} · ${servico.data}',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 20, color: CoresTrato.azulTexto),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: Text(
                  servico.garantia,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
