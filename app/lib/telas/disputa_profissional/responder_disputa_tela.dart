import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show LinhaValor, formatarReais;
import '../conclusao/campo_longo.dart';
import '../profissional/dinheiro.dart';
import '../profissional_apoio/apoio.dart';
import 'disputa.dart';

/// F6.7: o profissional responde à disputa aberta pelo cliente.
/// O app só coleta a resposta; a decisão e o destino do valor congelado são do backend.
class ResponderDisputaTela extends StatelessWidget {
  const ResponderDisputaTela({
    super.key,
    required this.servico,
    required this.disputaId,
    this.aoAdicionarEvidencia,
    this.aoRespondida,
  });

  final ServicoDisputaProfissional servico;
  final String disputaId;
  final CapturarFoto? aoAdicionarEvidencia;
  final ValueChanged<TipoRespostaDisputa>? aoRespondida;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<DetalheDisputa?>(
      titulo: 'Responder problema',
      carregar: () => servico.carregarDisputa(disputaId),
      estaVazio: (d) => d == null,
      iconeVazio: Icons.task_alt,
      tituloVazio: 'Nenhum problema aberto',
      textoVazio: 'Não há disputa esperando a sua resposta.',
      construir: (context, d) => _Corpo(
        disputa: d!,
        servico: servico,
        aoAdicionarEvidencia: aoAdicionarEvidencia,
        aoRespondida: aoRespondida,
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({
    required this.disputa,
    required this.servico,
    required this.aoAdicionarEvidencia,
    required this.aoRespondida,
  });

  final DetalheDisputa disputa;
  final ServicoDisputaProfissional servico;
  final CapturarFoto? aoAdicionarEvidencia;
  final ValueChanged<TipoRespostaDisputa>? aoRespondida;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  final _mensagem = TextEditingController();
  final _reembolso = TextEditingController();
  final _evidencias = <String>[];
  TipoRespostaDisputa _tipo = TipoRespostaDisputa.atenderRetrabalho;
  bool _tentou = false;
  bool _enviando = false;
  bool _enviada = false;
  String? _erro;

  @override
  void dispose() {
    _mensagem.dispose();
    _reembolso.dispose();
    super.dispose();
  }

  int? get _centavos {
    final c = Dinheiro.lerCentavos(_reembolso.text);
    return (c == null || c <= 0) ? null : c;
  }

  String? get _erroMensagem =>
      _mensagem.text.trim().length < 5 ? 'Escreva uma resposta curta' : null;
  String? get _erroReembolso => _tipo == TipoRespostaDisputa.proporReembolsoParcial && _centavos == null
      ? 'Informe o valor que você propõe devolver'
      : null;

  Future<void> _evidencia() async {
    final ref = await widget.aoAdicionarEvidencia?.call();
    if (ref != null && mounted) setState(() => _evidencias.add(ref));
  }

  Future<void> _enviar() async {
    setState(() {
      _tentou = true;
      _erro = null;
    });
    if (_erroMensagem != null || _erroReembolso != null) return;
    setState(() => _enviando = true);
    try {
      await widget.servico.responder(RespostaDisputa(
        disputaId: widget.disputa.id,
        tipo: _tipo,
        mensagem: _mensagem.text.trim(),
        reembolsoParcialCentavos:
            _tipo == TipoRespostaDisputa.proporReembolsoParcial ? _centavos : null,
        evidencias: [..._evidencias],
      ));
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _enviada = true;
      });
      widget.aoRespondida?.call(_tipo);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Não foi possível enviar sua resposta. Tente de novo.';
      });
    }
  }

  Widget _opcao(TipoRespostaDisputa tipo, String titulo, String ajuda) {
    final marcada = _tipo == tipo;
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
      child: CartaoTrato(
        aoTocar: _enviada ? null : () => setState(() => _tipo = tipo),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: CoresTrato.petroleo,
              semanticLabel: marcada ? 'Selecionado' : 'Não selecionado',
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TipografiaTrato.corpoForte),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(ajuda, style: TipografiaTrato.corpoPequeno),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.disputa;
    return CorpoRolavel(
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erro != null) ...[
            AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_enviada)
            const AvisoFaixa(
              texto: 'Resposta enviada. O cliente será avisado.',
              tipo: TipoStatus.sucesso,
              icone: Icons.check_circle_outline,
            )
          else
            BotaoPrimario(texto: 'Enviar resposta', carregando: _enviando, aoTocar: _enviar),
        ],
      ),
      children: [
        Text('${d.cliente} relatou um problema', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(d.titulo, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario)),
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipStatus(
                texto: 'Responder em até ${d.prazoRespostaHoras} h',
                tipo: TipoStatus.alerta,
                icone: Icons.schedule,
              ),
              const SizedBox(height: EspacosTrato.x3),
              Text(d.motivo, style: TipografiaTrato.corpoForte),
              const SizedBox(height: EspacosTrato.x1),
              Text(d.descricao, style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x3),
              LinhaValor(rotulo: 'O cliente pede', valor: d.solucaoPedida),
              const SizedBox(height: EspacosTrato.x2),
              LinhaValor(
                rotulo: 'Valor congelado até a decisão',
                valor: formatarReais(d.valorCongeladoCentavos),
              ),
            ],
          ),
        ),
        const TituloSecao('Como você quer responder?'),
        _opcao(TipoRespostaDisputa.atenderRetrabalho, 'Atender o retrabalho',
            'Você volta e refaz o que está combinado, sem custo para o cliente.'),
        _opcao(TipoRespostaDisputa.proporReembolsoParcial, 'Propor reembolso parcial',
            'Você sugere devolver parte do valor. O cliente decide se aceita.'),
        _opcao(TipoRespostaDisputa.discordar, 'Discordar',
            'Você conta a sua versão e envia provas. O Trato analisa os dois lados.'),
        if (_tipo == TipoRespostaDisputa.proporReembolsoParcial) ...[
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(
            rotulo: 'Valor que você propõe devolver',
            controlador: _reembolso,
            prefixo: 'R\$ ',
            teclado: const TextInputType.numberWithOptions(decimal: true),
            erro: _tentou ? _erroReembolso : null,
            aoMudar: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        CampoLongo(
          rotulo: 'Sua resposta',
          controlador: _mensagem,
          dica: 'Explique o que aconteceu e o que você propõe',
          aoMudar: (_) => setState(() {}),
        ),
        if (_tentou && _erroMensagem != null)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Text(
              _erroMensagem!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto),
            ),
          ),
        const SizedBox(height: EspacosTrato.x4),
        Text(
          _evidencias.isEmpty
              ? 'Provas (fotos) ajudam na análise.'
              : '${_evidencias.length} ${_evidencias.length == 1 ? 'foto anexada' : 'fotos anexadas'}.',
          style: TipografiaTrato.legenda,
        ),
        const SizedBox(height: EspacosTrato.x2),
        BotaoSecundario(
          texto: 'Anexar foto',
          icone: Icons.add_a_photo_outlined,
          aoTocar: widget.aoAdicionarEvidencia == null || _enviada ? null : _evidencia,
        ),
      ],
    );
  }
}
