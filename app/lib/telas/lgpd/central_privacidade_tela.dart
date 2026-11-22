import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho;
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'excluir_conta_tela.dart';
import 'modelos.dart';

/// F5.13 — Central de privacidade (LGPD). Sem protótipo da tela; o item "Meus dados (LGPD)"
/// do Perfil (tela 22) abre esta. Ver consentimentos, pedir cópia dos dados e excluir a conta.
class CentralPrivacidadeTela extends StatelessWidget {
  const CentralPrivacidadeTela({
    super.key,
    required this.servico,
    this.aoAbrirTermos,
    this.aoContaExcluida,
    this.carregarExclusaoAgendada,
    this.aoCancelarExclusao,
  });

  final ServicoPrivacidade servico;

  /// Data da exclusão agendada (`exclusao_agendada_em` de `GET /v1/me`); nulo = sem exclusão.
  final Future<DateTime?> Function()? carregarExclusaoAgendada;

  /// Cancela a exclusão agendada; devolve verdadeiro se deu certo.
  final Future<bool> Function()? aoCancelarExclusao;

  /// "Termos e políticas" (texto legal vem de fora).
  final VoidCallback? aoAbrirTermos;

  /// Chamado depois que o backend aceitou a exclusão: quem liga as rotas faz o logout.
  final VoidCallback? aoContaExcluida;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Meus dados',
      child: CarregadorTela<List<Consentimento>>(
        carregar: servico.consentimentos,
        construir: (context, itens, _) => _Corpo(
          servico: servico,
          itens: itens,
          aoAbrirTermos: aoAbrirTermos,
          aoContaExcluida: aoContaExcluida,
          carregarExclusaoAgendada: carregarExclusaoAgendada,
          aoCancelarExclusao: aoCancelarExclusao,
        ),
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({
    required this.servico,
    required this.itens,
    this.aoAbrirTermos,
    this.aoContaExcluida,
    this.carregarExclusaoAgendada,
    this.aoCancelarExclusao,
  });

  final Future<DateTime?> Function()? carregarExclusaoAgendada;
  final Future<bool> Function()? aoCancelarExclusao;
  final ServicoPrivacidade servico;
  final List<Consentimento> itens;
  final VoidCallback? aoAbrirTermos;
  final VoidCallback? aoContaExcluida;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  late final Map<String, bool> _ativos = {for (final c in widget.itens) c.id: c.ativo};
  var _exportando = false;
  String? _aviso;
  DateTime? _exclusaoAgendadaEm;
  var _cancelandoExclusao = false;

  @override
  void initState() {
    super.initState();
    _lerExclusaoAgendada();
  }

  Future<void> _lerExclusaoAgendada() async {
    final carregar = widget.carregarExclusaoAgendada;
    if (carregar == null) return;
    try {
      final data = await carregar();
      if (mounted) setState(() => _exclusaoAgendadaEm = data);
    } on Object {
      // Sem o dado, a tela só não mostra o aviso.
    }
  }

  Future<void> _cancelarExclusao() async {
    final cancelar = widget.aoCancelarExclusao;
    if (cancelar == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _cancelandoExclusao = true);
    final ok = await cancelar();
    if (!mounted) return;
    setState(() {
      _cancelandoExclusao = false;
      if (ok) _exclusaoAgendadaEm = null;
    });
    if (ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Exclusão cancelada. Sua conta continua ativa.')),
        );
    }
  }

  Future<void> _alterar(Consentimento c, bool valor) async {
    final anterior = _ativos[c.id]!;
    setState(() => _ativos[c.id] = valor);
    try {
      await widget.servico.alterarConsentimento(c.id, ativo: valor);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ativos[c.id] = anterior;
        _aviso = 'Não foi possível salvar a mudança. Tente de novo.';
      });
    }
  }

  Future<void> _exportar() async {
    setState(() {
      _exportando = true;
      _aviso = null;
    });
    try {
      final copia = await widget.servico.solicitarExportacao();
      if (!mounted) return;
      setState(() => _aviso = 'Cópia dos seus dados gerada.');
      if (copia != null && copia.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Cópia dos seus dados'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(copia, style: TipografiaTrato.corpoPequeno),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: copia));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cópia dos dados copiada.')),
                  );
                },
                child: const Text('Copiar dados'),
              ),
              TextButton(
                onPressed: () => Navigator.of(d).pop(),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _aviso = 'Não foi possível gerar a cópia agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  void _abrirExclusao() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExcluirContaTela(
          servico: widget.servico,
          aoContaExcluida: widget.aoContaExcluida,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recarregar = AtualizadorTela.de(context);
    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        Text(
          'Aqui você vê o que usamos dos seus dados, pede uma cópia e decide o que fazer com a sua conta.',
          style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
        ),
        if (_exclusaoAgendadaEm != null) ...[
          const SizedBox(height: EspacosTrato.x4),
          AvisoFaixa(
            key: const ValueKey('aviso-exclusao-agendada'),
            texto: 'Exclusão da conta agendada para ${diaMesDoAparelho(_exclusaoAgendadaEm!)}. '
                'Você pode cancelar antes desse prazo.',
            tipo: TipoStatus.alerta,
            icone: Icons.schedule,
          ),
          if (widget.aoCancelarExclusao != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            BotaoSecundario(
              key: const ValueKey('botao-cancelar-exclusao'),
              texto: _cancelandoExclusao ? 'Cancelando...' : 'Cancelar exclusão',
              aoTocar: _cancelandoExclusao ? null : _cancelarExclusao,
            ),
          ],
        ],
        const SizedBox(height: EspacosTrato.x5),
        Text('CONSENTIMENTOS', style: TipografiaTrato.sobretitulo),
        const SizedBox(height: EspacosTrato.x3),
        CartaoTrato(
          child: Column(
            children: [
              for (final c in widget.itens)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.titulo, style: TipografiaTrato.corpoForte),
                  subtitle: Text(
                    c.descricao,
                    style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
                  ),
                  value: _ativos[c.id]!,
                  onChanged: c.obrigatorio ? null : (v) => _alterar(c, v),
                ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x5),
        Text('SEUS DIREITOS', style: TipografiaTrato.sobretitulo),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(
          texto: 'Exportar meus dados',
          icone: Icons.download_outlined,
          aoTocar: _exportando ? null : _exportar,
        ),
        if (_aviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Semantics(
            liveRegion: true,
            child: Text(_aviso!, style: TipografiaTrato.corpoPequeno),
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(
          texto: 'Excluir minha conta',
          icone: Icons.delete_outline,
          aoTocar: _abrirExclusao,
        ),
        const SizedBox(height: EspacosTrato.x3),
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoLink(texto: 'Termos e políticas', aoTocar: widget.aoAbrirTermos),
        ),
      ],
    );
    return recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista);
  }
}
