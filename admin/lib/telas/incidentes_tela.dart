import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'incidentes_modais.dart';

const kStatusIncidente = {
  'aberto': 'Aberto',
  'cautela_adotada': 'Cautela adotada',
  'em_apuracao': 'Em apuração',
  'encerrado': 'Encerrado',
};

const kTiposIncidente = {
  'furto_roubo': 'Furto, roubo ou sumiço de objeto',
  'agressao_ameaca_assedio': 'Agressão, ameaça ou assédio',
  'acidente_dano': 'Acidente ou dano grave',
  'pessoa_diferente': 'Pessoa diferente da verificada',
  'comportamento_suspeito': 'Comportamento suspeito',
  'pagamento_por_fora': 'Pedido de pagamento por fora ou de dados',
  'outro': 'Outro',
};

const kCanaisIncidente = {
  'telefone': 'Telefone',
  'whatsapp': 'WhatsApp',
  'email': 'E-mail',
  'painel': 'Painel',
  'app': 'Aplicativo',
};

/// `suspender_conta` fica de fora: suspensão é feita em "Medidas de conta" (Termos 20).
const kMedidasIncidente = {
  'bloquear_contato': 'Bloquear o contato entre as partes',
  'preservar_registros': 'Preservar os registros do pedido',
  'reter_valor': 'Reter o valor ainda não liberado',
  'cancelar_pedido_reembolso': 'Cancelar o pedido com reembolso',
  'outro': 'Outra',
};

String rotuloDe(Map<String, String> mapa, String codigo) => mapa[codigo] ?? codigo;

String _nomeDaMedida(String t) => t == 'suspender_conta' ? 'Suspender a conta' : rotuloDe(kMedidasIncidente, t);

(String, Tom) _chip(String s) => (
      rotuloDe(kStatusIncidente, s),
      switch (s) { 'aberto' => Tom.alerta, 'encerrado' => Tom.ok, 'cautela_adotada' || 'em_apuracao' => Tom.info, _ => Tom.neutro },
    );

/// Só em "pessoa diferente", com pedido, a medida de cancelamento age de verdade (Termos 9.5).
bool medidaCancelaDeVerdade(Incidente i, String tipo) =>
    tipo == 'cancelar_pedido_reembolso' && i.tipo == 'pessoa_diferente' && i.pedidoId != null;

/// O que o sistema faz com cada medida neste incidente.
String efeitoDaMedida(Incidente i, String tipo) {
  if (medidaCancelaDeVerdade(i, tipo)) {
    return 'CANCELA o pedido de verdade, com reembolso integral ao cliente e sem retenção. Não dá para desfazer. '
        'Se o serviço já começou ou o pedido não está contratado, o servidor recusa e a medida não é gravada. '
        'Pedido já cancelado: só registra.';
  }
  if (tipo == 'cancelar_pedido_reembolso') {
    return 'Só registra: o sistema não cancela o pedido nem reembolsa neste incidente.';
  }
  if ((tipo == 'bloquear_contato' || tipo == 'preservar_registros') && i.pedidoId == null) {
    return 'Incidente sem pedido: só registra, nada é bloqueado nem adiado.';
  }
  return switch (tipo) {
    'bloquear_contato' => 'Bloqueia mensagens, propostas e sugestões de visita pelo chat entre as duas pessoas do '
        'pedido, em qualquer pedido entre elas, até o incidente ser encerrado. Não esconde telefone nem endereço '
        'já liberados.',
    'preservar_registros' => 'Adia a exclusão de conta das pessoas do pedido e a remoção de arquivos até o '
        'incidente ser encerrado.',
    _ => 'Só registra a medida adotada: o sistema não muda nada por ela.',
  };
}

/// O que o encerramento libera, conforme as medidas registradas. Null se nada.
String? liberadoAoEncerrar(Incidente i) {
  if (i.pedidoId == null) return null;
  final tipos = {for (final m in i.medidas) m.tipo};
  final partes = [
    if (tipos.contains('bloquear_contato')) 'o contato entre as partes volta a ser permitido',
    if (tipos.contains('preservar_registros')) 'a exclusão de conta e a remoção de arquivos deixam de ser adiadas',
  ];
  if (partes.isEmpty) return null;
  return 'Encerrar libera o que este incidente segurava: ${partes.join('; ')}, salvo se outro incidente aberto '
      'mantiver a medida.';
}

/// Incidentes de segurança (Termos 9.3 a 9.6). O prazo da cautela vem do backend.
class IncidentesTela extends StatefulWidget {
  const IncidentesTela({super.key});

  @override
  State<IncidentesTela> createState() => _IncidentesTelaState();
}

class _IncidentesTelaState extends State<IncidentesTela> {
  String? _situacao;
  String _pedido = '';
  int _versao = 0;

  Future<void> _registrar() async {
    await abrirRegistroDeIncidente(context);
    if (mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('incidente-situacao'),
              initialValue: _situacao,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in kStatusIncidente.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _situacao = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(labelText: 'Código do pedido', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _pedido = v.trim()),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Incidentes de segurança',
          subtitulo: 'Cautela em até 24 horas depois do relato (Termos 9.6)',
          acoes: [
            if (context.pode(Permissao.incidentesTratar))
              BotaoTrato.primario('Registrar incidente', aoPressionar: _registrar),
          ],
        ),
        Expanded(
          child: FilaRemota<Incidente>(
            key: ValueKey('fila-incidentes-$_versao'),
            filtro: (_situacao, _pedido),
            esqueleto: const EsqueletoPagina(),
            chave: (i) => i.id,
            carregar: (deslocamento, limite) => context.api.listarIncidentes(
              status: _situacao,
              pedidoId: _pedido.isEmpty ? null : _pedido,
              deslocamento: deslocamento,
              limite: limite,
            ),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<Incidente>(
                      itens: fila.itens,
                      chave: (i) => i.id,
                      mensagemSemItens: 'Nenhum incidente com esse filtro.',
                      tituloDetalhe: (i) => i.protocolo,
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'incidentes'),
                      itemBuilder: (context, i, sel) {
                        final (texto, tom) = _chip(i.status);
                        return CartaoLista(
                          titulo: '${i.protocolo} · ${rotuloDe(kTiposIncidente, i.tipo)}',
                          linhas: [
                            'Aberto em ${formatarData(i.abertoEm)}',
                            if (i.cautelaAdotadaEm == null && !i.encerrado) 'Cautela até ${formatarData(i.cautelaAte)}',
                          ],
                          chips: [
                            if (i.cautelaAtrasada)
                              const ChipEstado('Cautela vencida', tom: Tom.erro),
                            if (i.sinaisAntifraude.isNotEmpty)
                              const ChipEstado('Sinal para análise', tom: Tom.alerta),
                            ChipEstado(texto, tom: tom),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, i) => CarregaDados<Incidente>(
                        key: ValueKey('incidente-${i.id}'),
                        esqueleto: const EsqueletoPagina(),
                        atualizarSozinho: true,
                        carregar: () => context.api.obterIncidente(i.id),
                        construir: (context, completo, recarregar) => _Detalhe(
                          key: ValueKey(i.id),
                          incidente: completo,
                          aoMudar: () async {
                            await recarregar();
                            await fila.recarregar();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const kSinalNaoEProva = 'É um sinal para análise, não é prova de fraude.';

/// Termos 9.5: texto de cada código de `sinais_antifraude`; o desconhecido ganha texto genérico.
String textoDoSinalAntifraude(String codigo) {
  if (codigo == 'relato_durante_espera_de_ausencia') {
    return 'O pedido tem uma ausência registrada ainda no tempo de espera.';
  }
  final repetido = RegExp(r'^relato_repetido_do_cliente:(\d+)$').firstMatch(codigo);
  if (repetido != null) {
    return 'O cliente tem relato de pessoa diferente em ${repetido.group(1)} pedidos (contando este).';
  }
  return 'O sistema marcou outro ponto para conferir neste incidente.';
}

class _Detalhe extends StatefulWidget {
  const _Detalhe({super.key, required this.incidente, required this.aoMudar});
  final Incidente incidente;
  final Future<void> Function() aoMudar;

  @override
  State<_Detalhe> createState() => _DetalheState();
}

class _DetalheState extends State<_Detalhe> {
  bool _enviando = false;
  String? _erro;

  Future<void> _mudarStatus(String status) async {
    if (_enviando) return;
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Mudar a situação?',
      texto: 'O incidente ${widget.incidente.protocolo} passa para "${rotuloDe(kStatusIncidente, status)}". '
          'Não dá para voltar para "Aberto".',
      verbo: 'Mudar situação',
    );
    if (!ok || !mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.mudarStatusIncidente(widget.incidente.id, status);
      if (mounted) mostrarAviso(context, 'Situação atualizada.');
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      await widget.aoMudar();
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirE(Future<bool> Function() modal) async {
    if (await modal() && mounted) await widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incidente;
    final (texto, tom) = _chip(i.status);
    final vencida = i.cautelaAtrasada;
    final trata = context.pode(Permissao.incidentesTratar);
    final encerra = context.pode(Permissao.incidentesEncerrar);
    final adotada = i.cautelaAdotadaEm;
    String limpo(String? s) => (s ?? '').replaceAll('-', '');
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(i.protocolo, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          children: [if (vencida) const ChipEstado('Cautela vencida', tom: Tom.erro), ChipEstado(texto, tom: tom)],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (vencida) ...[
          BannerInfo(
            'O prazo de 24 horas acabou em ${formatarData(i.cautelaAte)} e a cautela não foi adotada.',
            titulo: 'Cautela vencida.',
            tom: Tom.erro,
            icone: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (i.sinaisAntifraude.isNotEmpty) ...[
          BannerInfo(
            [for (final s in i.sinaisAntifraude) textoDoSinalAntifraude(s), kSinalNaoEProva].join('\n'),
            titulo: 'Sinal para análise.',
            tom: Tom.alerta,
            icone: Icons.flag_outlined,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        Linha('Tipo', rotuloDe(kTiposIncidente, i.tipo)),
        Linha('Canal', rotuloDe(kCanaisIncidente, i.canal)),
        Linha('Relato', i.descricao),
        Linha('Contato', i.contato ?? 'Não informado'),
        Linha('Pedido', i.pedidoId ?? 'Sem pedido'),
        Linha('Aberto em', formatarData(i.abertoEm)),
        Linha('Cautela até', formatarData(i.cautelaAte)),
        if (adotada != null)
          Linha('Cautela adotada',
              '${formatarData(adotada)}${adotada.isAfter(i.cautelaAte) ? ' (depois do prazo)' : ''}'),
        Linha(
          'Responsável',
          i.responsavelId == null
              ? 'Sem responsável'
              : (limpo(i.responsavelId) == limpo(context.eu?.id) ? 'Você' : 'Outra pessoa da equipe'),
        ),
        if (i.desfecho != null) Linha('Desfecho', i.desfecho!),
        if (i.encerradoEm != null) Linha('Encerrado em', formatarData(i.encerradoEm!)),
        const SizedBox(height: EspacosTrato.x4),
        Text('Medidas', style: TipografiaTrato.secao),
        if (i.medidas.isEmpty) Text('Nenhuma medida registrada.', style: TipografiaTrato.corpo),
        for (final m in i.medidas)
          Linha(
            _nomeDaMedida(m.tipo),
            '${m.descricao}\n${formatarData(m.aplicadaEm)} · ${m.origem == 'automatica' ? 'automática' : 'equipe'}',
          ),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (i.encerrado)
          const BannerInfo('Incidente encerrado: não recebe mudanças.')
        else ...[
          if (trata && i.medidas.isEmpty && i.status != 'cautela_adotada')
            Text('Para marcar "Cautela adotada", registre uma medida antes.', style: TipografiaTrato.legenda),
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (trata)
                BotaoTrato.secundario('Adicionar medida',
                    aoPressionar: _enviando ? null : () => _abrirE(() => abrirMedidaDeIncidente(context, i))),
              if (trata && i.status != 'cautela_adotada')
                BotaoTrato.primario('Marcar cautela adotada',
                    aoPressionar: _enviando || i.medidas.isEmpty ? null : () => _mudarStatus('cautela_adotada')),
              if (trata && i.status != 'em_apuracao')
                BotaoTrato.secundario('Marcar em apuração',
                    aoPressionar: _enviando ? null : () => _mudarStatus('em_apuracao')),
              if (encerra)
                BotaoTrato.destrutivo('Encerrar incidente',
                    aoPressionar: _enviando ? null : () => _abrirE(() => abrirEncerramentoDeIncidente(context, i))),
            ],
          ),
        ],
      ],
    );
  }
}
