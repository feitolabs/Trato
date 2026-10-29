import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional/dinheiro.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';

/// Tela 14 — Pagamento. Sem regra de dinheiro: mostra o valor que vem em [dados] e,
/// ao tocar no botão, chama [aoPagar] com o método escolhido (o backend cobra).
class PagamentoTela extends StatefulWidget {
  const PagamentoTela({
    super.key,
    this.dados = DadosExemplo.pagamento,
    this.aoPagar,
    this.aoVoltar,
  });

  final DadosPagamento dados;
  final ValueChanged<MetodoPagamento>? aoPagar;

  /// Padrão: `Navigator.maybePop`.
  final VoidCallback? aoVoltar;

  @override
  State<PagamentoTela> createState() => _PagamentoTelaState();
}

class _PagamentoTelaState extends State<PagamentoTela> {
  late MetodoPagamento _metodo = widget.dados.opcoes.first.metodo;

  static const _passos = [
    'Você paga e o app mostra "Aguardando confirmação do pagamento" até o parceiro confirmar.',
    'O pagamento é processado por parceiro e acompanhado no app.',
    'Você confirma o serviço ao final. Se algo der errado, abra uma disputa: '
        'o caso passa por suporte e análise de problemas.',
  ];

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    final valor = Dinheiro.formatar(dados.valorAgoraCentavos);
    final comoPagar = _metodo == MetodoPagamento.pix ? 'com Pix' : 'com cartão';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ConteudoResponsivo(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Voltar',
                        onPressed: widget.aoVoltar ?? () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      ),
                    ),
                    Text('Pagamento', style: TipografiaTrato.tituloGrande),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      dados.subtitulo,
                      style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x3),
                    Text(valor, style: TipografiaTrato.marcaPequena.copyWith(fontSize: 36)),
                    if (dados.rotuloValor != null) ...[
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        dados.rotuloValor!,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.textoSecundario,
                        ),
                      ),
                    ],
                    const SizedBox(height: EspacosTrato.x6),
                    Text('Como você quer pagar?', style: TipografiaTrato.corpoForte),
                    const SizedBox(height: EspacosTrato.x3),
                    for (final opcao in dados.opcoes) ...[
                      _OpcaoMetodo(
                        opcao: opcao,
                        selecionada: opcao.metodo == _metodo,
                        aoTocar: () => setState(() => _metodo = opcao.metodo),
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                    ],
                    const SizedBox(height: EspacosTrato.x3),
                    CartaoTrato(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Como funciona o pagamento', style: TipografiaTrato.tituloOpcao),
                          const SizedBox(height: EspacosTrato.x4),
                          for (var i = 0; i < _passos.length; i++) ...[
                            if (i > 0) const SizedBox(height: EspacosTrato.x3),
                            _Passo(numero: i + 1, texto: _passos[i]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 20,
                          color: CoresTrato.textoSecundario,
                        ),
                        const SizedBox(width: EspacosTrato.x3),
                        Expanded(
                          child: Text(
                            'Pix e cartão só no nome do seu CPF. '
                            'O Trato não guarda o número do seu cartão.',
                            style: TipografiaTrato.corpoPequeno.copyWith(
                              color: CoresTrato.textoSecundario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: CoresTrato.superficie,
                border: Border(top: BorderSide(color: CoresTrato.borda)),
              ),
              child: ConteudoResponsivo(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  child: BotaoPrimario(
                    texto: 'Pagar $valor $comoPagar',
                    aoTocar: () => widget.aoPagar?.call(_metodo),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcaoMetodo extends StatelessWidget {
  const _OpcaoMetodo({required this.opcao, required this.selecionada, required this.aoTocar});

  final OpcaoPagamento opcao;
  final bool selecionada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raioGrande);
    return Semantics(
      button: true,
      selected: selecionada,
      child: Material(
        color: selecionada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: selecionada ? CoresTrato.petroleo : CoresTrato.borda,
            width: selecionada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              children: [
                Icon(
                  selecionada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 28,
                  color: selecionada ? CoresTrato.petroleo : CoresTrato.textoSecundario,
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opcao.titulo, style: TipografiaTrato.tituloCartao),
                      const SizedBox(height: 2),
                      Text(
                        opcao.descricao,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.textoSecundario,
                        ),
                      ),
                    ],
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

class _Passo extends StatelessWidget {
  const _Passo({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: CoresTrato.azulSuave, shape: BoxShape.circle),
          child: Text(
            '$numero',
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: CoresTrato.azulTexto,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Expanded(child: Text(texto, style: TipografiaTrato.corpoGrande.copyWith(height: 1.5))),
      ],
    );
  }
}
