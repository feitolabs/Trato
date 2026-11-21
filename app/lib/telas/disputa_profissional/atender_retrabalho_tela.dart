import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/campo_longo.dart';
import '../profissional_apoio/apoio.dart';
import 'disputa.dart';

/// F6.7: o profissional escolhe quando volta para refazer o serviço (retrabalho).
/// Os horários e o prazo vêm do backend.
class AtenderRetrabalhoTela extends StatelessWidget {
  const AtenderRetrabalhoTela({
    super.key,
    required this.servico,
    required this.disputaId,
    this.aoAgendado,
  });

  final ServicoDisputaProfissional servico;
  final String disputaId;
  final ValueChanged<String>? aoAgendado;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<DadosRetrabalho?>(
      titulo: 'Atender retrabalho',
      carregar: () => servico.carregarRetrabalho(disputaId),
      estaVazio: (d) => d == null || (d.estado == 'aberto' && d.opcoesHorario.isEmpty),
      iconeVazio: Icons.event_busy_outlined,
      tituloVazio: 'Sem retrabalho para agendar',
      textoVazio: 'Não há retrabalho pendente ou horários disponíveis agora.',
      construir: (context, d) => _Corpo(dados: d!, servico: servico, aoAgendado: aoAgendado),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({required this.dados, required this.servico, required this.aoAgendado});

  final DadosRetrabalho dados;
  final ServicoDisputaProfissional servico;
  final ValueChanged<String>? aoAgendado;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  final _mensagem = TextEditingController();
  String? _horario;
  bool _enviando = false;
  String? _aviso;
  String? _erro;
  late String _estado = widget.dados.estado;

  @override
  void dispose() {
    _mensagem.dispose();
    super.dispose();
  }

  Future<void> _executar(Future<void> Function() acao, String aviso, String proximo) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await acao();
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _aviso = aviso;
        _estado = proximo;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Não foi possível salvar. Tente de novo.';
      });
    }
  }

  Future<void> _agendar() => _executar(
        () async {
          await widget.servico.agendarRetrabalho(AgendamentoRetrabalho(
            disputaId: widget.dados.disputaId,
            horario: _horario!,
            mensagem: _mensagem.text.trim(),
          ));
          widget.aoAgendado?.call(_horario!);
        },
        'Retrabalho agendado. O cliente será avisado.',
        'aceito',
      );

  Future<void> _iniciar() => _executar(
        () => widget.servico.avancarRetrabalho(widget.dados.disputaId, 'iniciar'),
        'Retrabalho em andamento.',
        'em_execucao',
      );

  Future<void> _resolver() => _executar(
        () => widget.servico.avancarRetrabalho(widget.dados.disputaId, 'resolver'),
        'Retrabalho concluído. O cliente será avisado.',
        'resolvido',
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.dados;
    return CorpoRolavel(
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erro != null) ...[
            AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_aviso != null) ...[
            AvisoFaixa(
              texto: _aviso!,
              tipo: TipoStatus.sucesso,
              icone: Icons.check_circle_outline,
            ),
            if (_estado != 'resolvido') const SizedBox(height: EspacosTrato.x3),
          ],
          if (_estado == 'aberto')
            BotaoPrimario(
              texto: 'Confirmar horário',
              carregando: _enviando,
              aoTocar: _horario == null ? null : _agendar,
            )
          else if (_estado == 'aceito')
            BotaoPrimario(texto: 'Começar o retrabalho', carregando: _enviando, aoTocar: _iniciar)
          else if (_estado == 'em_execucao')
            BotaoPrimario(texto: 'Marcar como resolvido', carregando: _enviando, aoTocar: _resolver),
        ],
      ),
      children: [
        Text('Quando você volta?', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(d.titulo, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario)),
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('O que precisa ser refeito', style: TipografiaTrato.corpoForte),
              const SizedBox(height: EspacosTrato.x1),
              Text(d.descricaoProblema, style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x3),
              Text(
                'Você tem ${d.prazoAtendimentoDias} dias para atender.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              ),
            ],
          ),
        ),
        if (_estado == 'aberto') ...[
          const TituloSecao('Escolha um horário'),
          OpcoesPilula(
            opcoes: d.opcoesHorario,
            selecionadas: {if (_horario != null) _horario!},
            aoAlternar: (v) => setState(() => _horario = v),
          ),
          const SizedBox(height: EspacosTrato.x5),
          CampoLongo(
            rotulo: 'Mensagem ao cliente (opcional)',
            controlador: _mensagem,
            dica: 'Ex.: levo a peça nova para trocar',
            linhas: 3,
          ),
        ],
      ],
    );
  }
}
