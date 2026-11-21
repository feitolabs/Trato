import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Trilha dos 3 primeiros passos do profissional aprovado. Só leitura do que o app já recebe;
/// sem prêmio, sem cálculo e sem rota nova. A escolha "Dispensar" fica só no aparelho.

/// Para onde "Completar" leva: o cadastro/perfil ou a conta de recebimento.
enum DestinoCompletar { perfil, contaRecebimento }

/// O que a API já devolveu sobre o profissional. Dado que não veio = falso/zero (passo pendente).
class DadosPrimeirosPassos {
  const DadosPrimeirosPassos({
    this.aprovado = false,
    this.temDescricao = false,
    this.temCategoria = false,
    this.temRegiao = false,
    this.contaAtiva = false,
    this.servicosConcluidos = 0,
  });

  /// Lê `GET /v1/profissional/perfil` (status, bio, categorias, regioes, conta_recebimento) e
  /// `servicos_concluidos` de `GET /v1/me`. Qualquer campo ausente ou de tipo errado = pendente.
  factory DadosPrimeirosPassos.deApi({Map<String, dynamic>? perfil, Object? servicosConcluidos}) {
    bool lista(Object? v) => v is List && v.isNotEmpty;
    final conta = perfil?['conta_recebimento'];
    final bio = perfil?['bio'];
    return DadosPrimeirosPassos(
      aprovado: perfil?['status'] == 'aprovado',
      temDescricao: bio is String && bio.trim().isNotEmpty,
      temCategoria: lista(perfil?['categorias']),
      temRegiao: lista(perfil?['regioes']),
      contaAtiva: conta is Map && conta['cadastrada'] == true,
      servicosConcluidos: servicosConcluidos is num ? servicosConcluidos.toInt() : 0,
    );
  }

  final bool aprovado;
  final bool temDescricao;
  final bool temCategoria;
  final bool temRegiao;
  final bool contaAtiva;
  final int servicosConcluidos;

  bool get perfilCompleto => temDescricao && temCategoria && temRegiao && contaAtiva;

  /// Item que falta e leva ao lugar certo: primeiro o perfil, depois a conta de recebimento.
  DestinoCompletar get destinoCompletar => (temDescricao && temCategoria && temRegiao)
      ? DestinoCompletar.contaRecebimento
      : DestinoCompletar.perfil;
}

/// Escolhas guardadas só no aparelho.
abstract final class PreferenciaPrimeirosPassos {
  static const _chaveDispensado = 'primeiros_passos_dispensado';
  static const _chaveConclusaoVista = 'primeiros_passos_conclusao_vista';

  static Future<bool> _ler(String chave) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(chave) ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> _gravar(String chave) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(chave, true);
    } on Object {
      // Sem armazenamento: vale só nesta abertura da tela.
    }
  }

  static Future<bool> dispensado() => _ler(_chaveDispensado);
  static Future<void> dispensar() => _gravar(_chaveDispensado);
  static Future<bool> conclusaoVista() => _ler(_chaveConclusaoVista);
  static Future<void> marcarConclusaoVista() => _gravar(_chaveConclusaoVista);
}

/// Cartão "Seus primeiros passos · N de 3" (ou a mensagem de conclusão, uma vez).
class CartaoPrimeirosPassos extends StatefulWidget {
  const CartaoPrimeirosPassos({
    super.key,
    required this.carregar,
    required this.orcamentosEnviados,
    required this.semPedidosAbertos,
    this.aoCompletar,
    this.aoVerPedidos,
    this.aoVerAgenda,
  });

  /// Busca o que a API já tem; nulo ou com erro = o cartão não aparece.
  final Future<DadosPrimeirosPassos> Function()? carregar;
  final int orcamentosEnviados;

  /// Lista de pedidos abertos vazia: o passo 2 mostra "Ainda não há pedidos perto de você."
  final bool semPedidosAbertos;
  final ValueChanged<DestinoCompletar>? aoCompletar;
  final VoidCallback? aoVerPedidos;
  final VoidCallback? aoVerAgenda;

  @override
  State<CartaoPrimeirosPassos> createState() => _CartaoPrimeirosPassosState();
}

class _CartaoPrimeirosPassosState extends State<CartaoPrimeirosPassos> {
  DadosPrimeirosPassos? _dados;
  var _dispensado = false;
  var _conclusaoVista = false;
  var _carregado = false;
  var _mostrandoConclusao = false;
  var _fechouConclusao = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final carregar = widget.carregar;
    if (carregar == null) return;
    try {
      final resultados = await Future.wait<Object?>([
        PreferenciaPrimeirosPassos.dispensado(),
        PreferenciaPrimeirosPassos.conclusaoVista(),
        carregar(),
      ]);
      if (!mounted) return;
      setState(() {
        _dispensado = resultados[0]! as bool;
        _conclusaoVista = resultados[1]! as bool;
        _dados = resultados[2]! as DadosPrimeirosPassos;
        _carregado = true;
      });
    } on Object {
      // Sem os dados, o cartão simplesmente não aparece.
    }
  }

  Future<void> _dispensar() async {
    setState(() => _dispensado = true);
    await PreferenciaPrimeirosPassos.dispensar();
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    if (!_carregado || dados == null || !dados.aprovado || _dispensado) {
      return const SizedBox.shrink();
    }
    final feito1 = dados.perfilCompleto;
    final feito2 = widget.orcamentosEnviados > 0;
    final feito3 = dados.servicosConcluidos > 0;
    final feitos = [feito1, feito2, feito3].where((f) => f).length;

    if (feitos == 3) {
      if (_conclusaoVista && !_mostrandoConclusao) return const SizedBox.shrink();
      if (_fechouConclusao) return const SizedBox.shrink();
      if (!_mostrandoConclusao) {
        // Mostra uma vez: grava já; nesta abertura ela continua visível até "Fechar".
        _mostrandoConclusao = true;
        PreferenciaPrimeirosPassos.marcarConclusaoVista();
      }
      return _Moldura(
        chave: const Key('primeiros-passos-concluidos'),
        children: [
          Text('Primeiros passos concluídos.', style: TipografiaTrato.tituloCartao),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Você fez os 3. Acompanhe seus pedidos no Início.',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x3),
          BotaoLink(
            key: const Key('fechar-primeiros-passos'),
            texto: 'Fechar',
            aoTocar: () => setState(() => _fechouConclusao = true),
          ),
        ],
      );
    }

    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return _Moldura(
      chave: const Key('cartao-primeiros-passos'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Seus primeiros passos', style: TipografiaTrato.tituloCartao),
            ),
            Text('$feitos de 3', key: const Key('progresso-primeiros-passos'), style: secundario),
          ],
        ),
        const SizedBox(height: EspacosTrato.x1),
        Text('3 passos para começar a atender.', style: secundario),
        const SizedBox(height: EspacosTrato.x3),
        _Passo(
          chave: const Key('passo-1'),
          feito: feito1,
          textoFeito: 'Perfil completo ✓',
          titulo: 'Complete seu perfil.',
          detalhe: 'Leva 2 minutos.',
          botao: 'Completar',
          aoTocar:
              widget.aoCompletar == null ? null : () => widget.aoCompletar!(dados.destinoCompletar),
        ),
        _Passo(
          chave: const Key('passo-2'),
          feito: feito2,
          textoFeito: '1º orçamento enviado ✓',
          titulo: 'Envie seu 1º orçamento.',
          detalhe: widget.semPedidosAbertos
              ? 'Ainda não há pedidos perto de você.'
              : 'Veja os pedidos perto de você.',
          botao: 'Ver pedidos',
          aoTocar: widget.aoVerPedidos,
        ),
        _Passo(
          chave: const Key('passo-3'),
          feito: feito3,
          textoFeito: '1º serviço concluído ✓',
          titulo: 'Faça seu 1º serviço.',
          detalhe: 'Quando um cliente aceitar, ele aparece na Agenda.',
          botao: 'Ver agenda',
          aoTocar: widget.aoVerAgenda,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: BotaoLink(
            key: const Key('dispensar-primeiros-passos'),
            texto: 'Dispensar',
            aoTocar: _dispensar,
          ),
        ),
      ],
    );
  }
}

class _Moldura extends StatelessWidget {
  const _Moldura({required this.chave, required this.children});

  final Key chave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: chave,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({
    required this.chave,
    required this.feito,
    required this.textoFeito,
    required this.titulo,
    required this.detalhe,
    required this.botao,
    required this.aoTocar,
  });

  final Key chave;
  final bool feito;
  final String textoFeito;
  final String titulo;
  final String detalhe;
  final String botao;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: chave,
      padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
      child: feito
          ? Text(
              textoFeito,
              style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: TipografiaTrato.corpoForte),
                      Text(
                        detalhe,
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: CoresTrato.textoSecundario),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: EspacosTrato.x2),
                BotaoLink(texto: botao, aoTocar: aoTocar),
              ],
            ),
    );
  }
}
