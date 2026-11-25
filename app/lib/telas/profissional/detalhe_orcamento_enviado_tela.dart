import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show formatarData, formatarReais;
import '../profissional_inicio/modelos.dart';

/// Detalhe do orçamento que o profissional já enviou: mostra itens, horas, taxa,
/// prazo, garantia, o que está fora do escopo e permite editar enquanto aguarda o cliente.
class DetalheOrcamentoEnviadoTela extends StatelessWidget {
  const DetalheOrcamentoEnviadoTela({
    super.key,
    required this.detalhe,
    this.aoEditar,
    this.aoAbrirChat,
  });

  final DetalheOrcamentoEnviado detalhe;
  final VoidCallback? aoEditar;
  final VoidCallback? aoAbrirChat;

  @override
  Widget build(BuildContext context) {
    final secundario =
        TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    final (rotuloSituacao, tipoSituacao) = switch (detalhe.situacao) {
      'aceito' => ('Aceito pelo cliente', TipoStatus.sucesso),
      'encerrado' => ('Encerrado', TipoStatus.alerta),
      _ => ('Aguardando cliente', TipoStatus.info),
    };

    return Scaffold(
      appBar: AppBar(title: Text(detalhe.tituloPedido)),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
              child: ConteudoResponsivo(
                child: Column(
                  // Esticado: os cartões só de texto ocupavam metade da largura.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ChipStatus(texto: rotuloSituacao, tipo: tipoSituacao),
                        const SizedBox(width: EspacosTrato.x2),
                        Text('Versão ${detalhe.versao}', style: secundario),
                      ],
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    Text('Seu orçamento', style: TipografiaTrato.tituloGrande),
                    const SizedBox(height: EspacosTrato.x4),
                    CartaoTrato(
                      escuro: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Valor proposto ao cliente',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: context.cores.sobrePetroleo),
                          ),
                          const SizedBox(height: EspacosTrato.x1),
                          Text(
                            formatarReais(detalhe.valorCentavos),
                            style: TipografiaTrato.tituloGrande
                                .copyWith(color: context.cores.sobrePetroleo),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    CartaoTrato(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Prazos e horas', style: TipografiaTrato.tituloCartao),
                          const SizedBox(height: EspacosTrato.x3),
                          if (detalhe.horasDeslocamento != null)
                            _LinhaResumo('Deslocamento', '${detalhe.horasDeslocamento} h'),
                          if (detalhe.horasTrabalhadas != null)
                            _LinhaResumo('Horas trabalhadas', '${detalhe.horasTrabalhadas} h'),
                          if (detalhe.prazoExecucaoDias != null)
                            _LinhaResumo(
                              'Prazo de execução',
                              '${detalhe.prazoExecucaoDias} ${detalhe.prazoExecucaoDias == 1 ? 'dia' : 'dias'}',
                            ),
                          if (detalhe.garantiaDias != null)
                            _LinhaResumo('Garantia', '${detalhe.garantiaDias} dias'),
                          if (detalhe.validoAte != null)
                            _LinhaResumo('Válido até', formatarData(detalhe.validoAte!)),
                        ],
                      ),
                    ),
                    if (detalhe.itens.isNotEmpty) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      CartaoTrato(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Itens da proposta', style: TipografiaTrato.tituloCartao),
                            const SizedBox(height: EspacosTrato.x3),
                            for (var i = 0; i < detalhe.itens.length; i++) ...[
                              if (i > 0) const Divider(),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${detalhe.itens[i].descricao} (${detalhe.itens[i].quantidade})',
                                      style: TipografiaTrato.corpo,
                                    ),
                                  ),
                                  const SizedBox(width: EspacosTrato.x2),
                                  Text(
                                    formatarReais(detalhe.itens[i].totalCentavos),
                                    style: TipografiaTrato.corpoForte,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if ((detalhe.foraDoEscopo ?? '').isNotEmpty) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      CartaoTrato(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Fora do escopo', style: TipografiaTrato.tituloCartao),
                            const SizedBox(height: EspacosTrato.x2),
                            Text(detalhe.foraDoEscopo!, style: TipografiaTrato.corpo),
                          ],
                        ),
                      ),
                    ],
                    if ((detalhe.observacoes ?? '').isNotEmpty) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      CartaoTrato(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Observações', style: TipografiaTrato.tituloCartao),
                            const SizedBox(height: EspacosTrato.x2),
                            Text(detalhe.observacoes!, style: TipografiaTrato.corpo),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if ((aoEditar != null && detalhe.podeEditar) || aoAbrirChat != null)
            Container(
              width: double.infinity,
              color: context.cores.superficie,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  child: ConteudoResponsivo(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (aoEditar != null && detalhe.podeEditar)
                          BotaoPrimario(
                            texto: 'Editar orçamento',
                            aoTocar: aoEditar,
                          ),
                        if (aoEditar != null &&
                            detalhe.podeEditar &&
                            aoAbrirChat != null)
                          const SizedBox(height: EspacosTrato.x3),
                        if (aoAbrirChat != null)
                          (aoEditar != null && detalhe.podeEditar)
                              ? BotaoSecundario(
                                  texto: 'Abrir chat com cliente',
                                  aoTocar: aoAbrirChat,
                                )
                              : BotaoPrimario(
                                  texto: 'Abrir chat com cliente',
                                  aoTocar: aoAbrirChat,
                                ),
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
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: TipografiaTrato.corpoPequeno),
          Text(valor, style: TipografiaTrato.corpoForte),
        ],
      ),
    );
  }
}
