import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../atendimento/modelos.dart' show orientacaoPessoaDiferente;
import '../cliente/avatar_de_usuario.dart';

/// Estados em que o atendimento está de pé: a tela mostra status, a outra parte e Chat/Ajuda/SOS.
const estadosDeAtendimento = {'agendado', 'a_caminho', 'em_andamento'};

String statusDeAtendimento(String? estado) => switch (estado) {
      'em_andamento' => 'Serviço em andamento',
      'a_caminho' => 'Profissional a caminho',
      _ => 'Serviço agendado',
    };

/// "Carlos Eduardo Lima" → "Carlos L.". Um nome só fica como está.
String nomeCurto(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+'));
  if (partes.length < 2) return partes.first;
  return '${partes.first} ${partes.last[0].toUpperCase()}.';
}

String iniciaisDe(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  final primeira = partes.first[0];
  return (partes.length == 1 ? primeira : '$primeira${partes.last[0]}').toUpperCase();
}

/// Status grande, horário e a outra parte (nome curto e foto).
class CabecalhoAtendimento extends StatelessWidget {
  const CabecalhoAtendimento({
    super.key,
    required this.status,
    this.horario,
    required this.papel,
    this.nome,
    this.usuarioId,
  });

  final String status;
  final String? horario;

  /// "Profissional" ou "Cliente".
  final String papel;
  final String? nome;
  final String? usuarioId;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final completo = (nome ?? '').trim();
    return CartaoTrato(
      key: const ValueKey('cabecalho-atendimento'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              status,
              key: const ValueKey('status-atendimento'),
              style: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
            ),
          ),
          if ((horario ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              horario!.trim(),
              key: const ValueKey('horario-atendimento'),
              style: TipografiaTrato.corpoForte.copyWith(color: c.textoSecundario),
            ),
          ],
          const SizedBox(height: EspacosTrato.x4),
          Row(
            children: [
              AvatarDeUsuario(
                iniciais: iniciaisDe(completo.isEmpty ? papel : completo),
                usuarioId: usuarioId,
                tamanho: 56,
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      completo.isEmpty ? papel : nomeCurto(completo),
                      key: const ValueKey('outra-parte'),
                      style: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
                    ),
                    if (completo.isNotEmpty)
                      Text(
                        papel,
                        style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Números de emergência (Termos 9.2).
const numerosDeEmergencia = [('190', 'Polícia'), ('192', 'SAMU'), ('193', 'Bombeiros')];

Future<bool> _discar(String numero) async {
  try {
    return await launchUrl(Uri(scheme: 'tel', path: numero), mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// Diálogo do botão SOS, igual para cliente e profissional, presencial ou remoto.
Future<void> mostrarEmergencia(
  BuildContext context,
  String resumo, {
  Future<bool> Function(String numero) ligar = _discar,
  VoidCallback? aoRelatar,
  bool orientarChegada = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('SOS / Emergência'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Em risco imediato, ligue primeiro. Depois, avise o Trato.'),
          for (final (numero, nome) in numerosDeEmergencia) ...[
            const SizedBox(height: EspacosTrato.x2),
            FilledButton.icon(
              key: ValueKey('ligar-$numero'),
              icon: const Icon(Icons.phone),
              label: Text('Ligar $numero ($nome)'),
              onPressed: () async {
                final avisos = ScaffoldMessenger.maybeOf(context);
                Navigator.of(dialogo).pop();
                if (!await ligar(numero)) {
                  avisos?.showSnackBar(SnackBar(
                    content: Text('Não foi possível abrir o telefone. Disque $numero.'),
                  ));
                }
              },
            ),
          ],
          if (orientarChegada) ...[
            const SizedBox(height: EspacosTrato.x4),
            const Text(orientacaoPessoaDiferente, key: ValueKey('sos-pessoa-diferente')),
          ],
          if (aoRelatar != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            OutlinedButton.icon(
              key: const ValueKey('sos-relatar'),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Relatar um problema de segurança'),
              onPressed: () {
                Navigator.of(dialogo).pop();
                aoRelatar();
              },
            ),
          ],
          const SizedBox(height: EspacosTrato.x4),
          const Text('Você também pode copiar os dados do atendimento para um contato de confiança.'),
          const SizedBox(height: EspacosTrato.x2),
          Text(resumo),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(),
          child: const Text('Fechar'),
        ),
        TextButton(
          onPressed: () async {
            final avisos = ScaffoldMessenger.maybeOf(context);
            await Clipboard.setData(ClipboardData(text: resumo));
            if (dialogo.mounted) Navigator.of(dialogo).pop();
            avisos?.showSnackBar(
              const SnackBar(content: Text('Dados do atendimento copiados.')),
            );
          },
          child: const Text('Copiar dados'),
        ),
      ],
    ),
  );
}

/// Barra fixa com os botões grandes Chat, Ajuda e SOS (sem [aoSos], só os dois primeiros).
class BarraAtendimento extends StatelessWidget {
  const BarraAtendimento({super.key, required this.aoChat, required this.aoAjuda, this.aoSos});

  final VoidCallback aoChat;
  final VoidCallback aoAjuda;
  final VoidCallback? aoSos;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    Widget botao(Key chave, IconData icone, String texto, VoidCallback aoTocar,
            {bool perigo = false}) =>
        Expanded(
          child: Semantics(
            button: true,
            child: Material(
              color: perigo ? c.vermelhoSuave : c.fundo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(EspacosTrato.raio),
                side: BorderSide(color: perigo ? c.vermelhoTexto : c.borda, width: 1.5),
              ),
              child: InkWell(
                key: chave,
                borderRadius: BorderRadius.circular(EspacosTrato.raio),
                onTap: aoTocar,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icone, size: 26, color: perigo ? c.vermelhoTexto : c.petroleo),
                        const SizedBox(height: EspacosTrato.x1),
                        Text(
                          texto,
                          maxLines: 1,
                          style: TipografiaTrato.corpoForte.copyWith(
                            color: perigo ? c.vermelhoTexto : c.petroleo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.superficie,
            border: Border(top: BorderSide(color: c.borda)),
          ),
          child: ConteudoResponsivo(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x3),
              child: Row(
                children: [
                  botao(const ValueKey('atendimento-chat'), Icons.chat_bubble_outline, 'Chat',
                      aoChat),
                  const SizedBox(width: EspacosTrato.x2),
                  botao(const ValueKey('atendimento-ajuda'), Icons.help_outline, 'Ajuda', aoAjuda),
                  if (aoSos != null) ...[
                    const SizedBox(width: EspacosTrato.x2),
                    botao(const ValueKey('botao-sos-emergencia'), Icons.warning_amber_rounded,
                        'SOS', aoSos!,
                        perigo: true),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
