import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../pedido_novo/pecas_pedido.dart' show ChipOpcao;

/// Motivos aceitos pelo backend em `POST /v1/denuncias` (`motivo`).
enum MotivoDenuncia {
  assedio('assedio', 'Assédio ou desrespeito'),
  fraude('fraude', 'Tentativa de golpe/fraude'),
  cobrancaFora('cobranca_fora', 'Cobrança fora do app'),
  perfilFalso('perfil_falso', 'Perfil falso'),
  outro('outro', 'Outro');

  const MotivoDenuncia(this.codigo, this.rotulo);

  /// Valor enviado à API.
  final String codigo;
  final String rotulo;
}

/// Mínimo de caracteres dos detalhes (o backend recusa menos de 5).
const minimoDetalhesDenuncia = 5;

/// Mensagem ao concluir.
const avisoDenunciaEnviada = 'Denúncia enviada para análise da nossa equipe.';

/// Menu discreto (três pontos) com a ação "Denunciar". Quem usa decide se mostra.
class MenuDenunciar extends StatelessWidget {
  const MenuDenunciar({super.key, required this.aoDenunciar});

  final VoidCallback aoDenunciar;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('menu-denunciar'),
      tooltip: 'Mais opções',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (_) => aoDenunciar(),
      itemBuilder: (_) => const [
        PopupMenuItem<String>(value: 'denunciar', child: Text('Denunciar')),
      ],
    );
  }
}

/// Abre a folha de denúncia. Devolve `true` se a denúncia foi enviada. [enviar] faz a chamada à
/// API; se lançar [ErroTrato], a mensagem aparece na folha e a pessoa pode tentar de novo.
Future<bool?> mostrarFolhaDenuncia(
  BuildContext context, {
  required Future<void> Function(MotivoDenuncia motivo, String detalhes) enviar,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FolhaDenuncia(enviar: enviar),
  );
}

class FolhaDenuncia extends StatefulWidget {
  const FolhaDenuncia({super.key, required this.enviar});

  final Future<void> Function(MotivoDenuncia motivo, String detalhes) enviar;

  @override
  State<FolhaDenuncia> createState() => _FolhaDenunciaState();
}

class _FolhaDenunciaState extends State<FolhaDenuncia> {
  final _detalhes = TextEditingController();
  MotivoDenuncia? _motivo;
  String? _erro;
  var _enviando = false;

  @override
  void dispose() {
    _detalhes.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final motivo = _motivo;
    final detalhes = _detalhes.text.trim();
    if (motivo == null) {
      setState(() => _erro = 'Escolha um motivo.');
      return;
    }
    if (detalhes.length < minimoDetalhesDenuncia) {
      setState(() => _erro = 'Conte um pouco mais (mínimo de $minimoDetalhesDenuncia caracteres).');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.enviar(motivo, detalhes);
      if (mounted) Navigator.of(context).pop(true);
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } on Object {
      if (mounted) {
        setState(() => _erro = 'Não foi possível enviar agora. Tente de novo em instantes.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            EspacosTrato.x5,
            0,
            EspacosTrato.x5,
            EspacosTrato.x4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Denunciar', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'Conte o que aconteceu. Nossa equipe analisa e a outra pessoa não vê quem denunciou.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (final m in MotivoDenuncia.values)
                    ChipOpcao(
                      key: ValueKey('motivo-${m.codigo}'),
                      texto: m.rotulo,
                      marcado: _motivo == m,
                      aoTocar: _enviando ? () {} : () => setState(() => _motivo = m),
                    ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              TextField(
                key: const ValueKey('detalhes-denuncia'),
                controller: _detalhes,
                enabled: !_enviando,
                maxLines: 4,
                minLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                style: TipografiaTrato.corpo,
                decoration: const InputDecoration(
                  labelText: 'Detalhes',
                  hintText: 'O que aconteceu?',
                ),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              if (_erro != null) ...[
                const SizedBox(height: EspacosTrato.x2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _erro!,
                    key: const ValueKey('erro-denuncia'),
                    style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
                  ),
                ),
              ],
              const SizedBox(height: EspacosTrato.x4),
              BotaoPrimario(
                texto: 'Enviar denúncia',
                carregando: _enviando,
                aoTocar: _enviando ? null : _enviar,
              ),
              const SizedBox(height: EspacosTrato.x2),
              BotaoSecundario(
                texto: 'Cancelar',
                aoTocar: _enviando ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
