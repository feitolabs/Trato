import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../tema/tema.dart';

/// Vitrine dos componentes, montada com os textos do protótipo para comparar lado a lado.
/// Abrir: flutter run --dart-define=GALERIA=true
class GaleriaComponentes extends StatefulWidget {
  const GaleriaComponentes({super.key});

  @override
  State<GaleriaComponentes> createState() => _GaleriaComponentesState();
}

class _GaleriaComponentesState extends State<GaleriaComponentes> {
  var _aba = 2;
  var _euForneco = true;

  @override
  Widget build(BuildContext context) {
    const vao = SizedBox(height: EspacosTrato.x4);
    return Scaffold(
      appBar: AppBar(title: const Text('Galeria de componentes')),
      bottomNavigationBar: BarraAbasTrato(
        abas: abasCliente,
        indiceAtual: _aba,
        aoSelecionar: (i) => setState(() => _aba = i),
      ),
      body: ListView(
        padding: const EdgeInsets.all(EspacosTrato.margemTela),
        children: [
          Text('Seus pedidos', style: TipografiaTrato.tituloGrande),
          vao,
          CartaoTrato(
            aoTocar: () {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Troca de tomadas e chuveiro', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  'Carlos Mendes · hoje, 14h',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
                const SizedBox(height: EspacosTrato.x2),
                const ChipStatus(texto: 'Em execução · pagamento retido', tipo: TipoStatus.info),
              ],
            ),
          ),
          vao,
          const Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              ChipStatus(texto: 'Disputa aberta · valor congelado', tipo: TipoStatus.alerta),
              ChipStatus(texto: 'Finalizado', tipo: TipoStatus.sucesso, icone: Icons.check),
              ChipStatus(texto: '3 orçamentos novos', tipo: TipoStatus.destaque),
              ChipStatus(texto: 'SOS', tipo: TipoStatus.perigo, icone: Icons.warning_amber),
            ],
          ),
          const SizedBox(height: EspacosTrato.x6),
          Text('Linha do tempo', style: TipografiaTrato.titulo),
          vao,
          const LinhaDoTempo(
            etapas: [
              EtapaLinhaDoTempo(
                titulo: 'Contratado',
                detalhe: 'Ter, 27/10 · contrato digital gerado',
                estado: EstadoEtapa.feita,
              ),
              EtapaLinhaDoTempo(
                titulo: 'Chegou',
                detalhe: '14h06 · foto e local registrados',
                estado: EstadoEtapa.feita,
              ),
              EtapaLinhaDoTempo(
                titulo: 'Em execução',
                detalhe: 'Iniciado com o seu código às 14h10',
                estado: EstadoEtapa.atual,
              ),
              EtapaLinhaDoTempo(
                titulo: 'Finalizado',
                detalhe: 'Você confirma com o código de conclusão',
                estado: EstadoEtapa.futura,
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x6),
          const CampoTrato(rotulo: 'Nome completo', dica: 'Mariana Alves'),
          vao,
          const CampoTrato(
            rotulo: 'Senha',
            senha: true,
            ajuda: 'Pelo menos 8 caracteres, com letra e número.',
          ),
          vao,
          const Row(
            children: [
              Expanded(child: CampoTrato(rotulo: 'Deslocamento', prefixo: 'R\$ ', dica: '30')),
              SizedBox(width: EspacosTrato.x3),
              Expanded(child: CampoTrato(rotulo: 'Horas', sufixo: 'h', dica: '3')),
            ],
          ),
          vao,
          Row(
            children: [
              Expanded(
                child: BotaoSecundario(
                  texto: 'Eu forneço',
                  selecionado: _euForneco,
                  aoTocar: () => setState(() => _euForneco = true),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: BotaoSecundario(
                  texto: 'Cliente fornece',
                  selecionado: !_euForneco,
                  aoTocar: () => setState(() => _euForneco = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x6),
          CartaoTrato(
            escuro: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descreva o problema',
                  style: TipografiaTrato.titulo.copyWith(color: CoresTrato.creme),
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  'Receba até 5 orçamentos de profissionais com identidade verificada.',
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.creme),
                ),
                vao,
                BotaoSecundario(texto: 'Pedir orçamento', aoTocar: () {}),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x6),
          Row(
            children: [
              Expanded(child: BotaoSecundario(texto: 'Recusar', aoTocar: () {})),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: BotaoPrimario(texto: 'Aprovar aditivo', aoTocar: () {})),
            ],
          ),
          vao,
          BotaoPrimario(texto: 'Próximo', aoTocar: () {}),
          vao,
          BotaoSecundario(texto: 'Conversar', icone: Icons.chat_bubble_outline, aoTocar: () {}),
          Center(child: BotaoLink(texto: 'Já tenho conta', aoTocar: () {})),
        ],
      ),
    );
  }
}
