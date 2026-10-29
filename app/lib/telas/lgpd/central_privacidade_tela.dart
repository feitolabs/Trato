import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
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
  });

  final ServicoPrivacidade servico;

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
        ),
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({required this.servico, required this.itens, this.aoAbrirTermos, this.aoContaExcluida});

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
      await widget.servico.solicitarExportacao();
      if (!mounted) return;
      setState(() => _aviso = 'Pedido registrado. Avisamos você quando a cópia estiver pronta.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _aviso = 'Não foi possível pedir a cópia agora. Tente de novo.');
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
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        Text(
          'Aqui você vê o que usamos dos seus dados, pede uma cópia e decide o que fazer com a sua conta.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
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
                    style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
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
  }
}
