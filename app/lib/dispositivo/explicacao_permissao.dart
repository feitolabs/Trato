import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../tema/tema.dart';
import 'permissao.dart';

/// Texto da tela que vem ANTES do pedido do sistema: para que serve e por quanto tempo fica.
class TextoPermissao {
  const TextoPermissao({required this.titulo, required this.finalidade, required this.retencao});

  final String titulo;
  final String finalidade;
  final String retencao;

  static const cameraCheckIn = TextoPermissao(
    titulo: 'Usar a câmera',
    finalidade: 'A foto mostra que você chegou ao local e como o serviço ficou.',
    retencao: 'Guardamos a foto junto do pedido, para o caso de dúvida ou disputa. '
        'Depois do prazo legal, apagamos.',
  );
  static const cameraDocumento = TextoPermissao(
    titulo: 'Usar a câmera para a verificação',
    finalidade: 'Conferir se o documento e o rosto são da mesma pessoa que fez o cadastro.',
    retencao: 'Guardamos pelo tempo que a lei pede, em local protegido, e depois apagamos. '
        'Nunca aparecem para o cliente.',
  );
  static const cameraFoto = TextoPermissao(
    titulo: 'Usar a câmera',
    finalidade: 'Tirar a foto que você vai anexar.',
    retencao: 'A foto fica no pedido e só é vista por quem participa dele e pela análise do Trato.',
  );
  static const localizacao = TextoPermissao(
    titulo: 'Usar sua localização',
    finalidade: 'Conferir que você está no endereço do serviço quando começa e quando termina.',
    retencao: 'Usamos só agora, com o app aberto. Guardamos o ponto junto do pedido, '
        'para o caso de dúvida ou disputa, e depois apagamos. Não acompanhamos seu trajeto.',
  );
}

/// Garante a permissão no momento do uso. Devolve `true` se a pessoa pode seguir.
///
/// 1. Já concedida: segue, sem tela nenhuma.
/// 2. Negada: mostra a explicação; só se a pessoa tocar em "Continuar" o sistema pergunta.
/// 3. Negada para sempre: não adianta perguntar; leva às configurações do aparelho.
Future<bool> garantirPermissao(
  BuildContext context,
  ServicoPermissao servico,
  TipoPermissao tipo,
  TextoPermissao texto,
) async {
  var estado = await servico.estado(tipo);
  if (estado == EstadoPermissao.concedida) return true;
  if (!context.mounted) return false;

  if (estado == EstadoPermissao.negada) {
    final seguir = await _folha<bool>(context, _FolhaExplicacao(texto: texto));
    if (seguir != true) return false;
    estado = await servico.pedir(tipo);
    if (estado == EstadoPermissao.concedida) return true;
    if (!context.mounted) return false;
  }
  if (estado == EstadoPermissao.negadaParaSempre) {
    final abrir = await _folha<bool>(context, _FolhaBloqueada(texto: texto));
    if (abrir == true) await servico.abrirConfiguracoes();
  }
  return false;
}

Future<T?> _folha<T>(BuildContext context, Widget conteudo) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: CoresTrato.superficie,
      showDragHandle: true,
      builder: (_) => SingleChildScrollView(child: conteudo),
    );

class _FolhaExplicacao extends StatelessWidget {
  const _FolhaExplicacao({required this.texto});

  final TextoPermissao texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EspacosTrato.margemTela,
        0,
        EspacosTrato.margemTela,
        EspacosTrato.x5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(texto.titulo, style: TipografiaTrato.titulo),
          const SizedBox(height: EspacosTrato.x4),
          Text('Para que serve', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          Text(texto.finalidade, style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x3),
          Text('Por quanto tempo guardamos', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          Text(texto.retencao, style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x5),
          BotaoPrimario(texto: 'Continuar', aoTocar: () => Navigator.of(context).pop(true)),
          const SizedBox(height: EspacosTrato.x2),
          Center(
            child: BotaoLink(texto: 'Agora não', aoTocar: () => Navigator.of(context).pop(false)),
          ),
        ],
      ),
    );
  }
}

class _FolhaBloqueada extends StatelessWidget {
  const _FolhaBloqueada({required this.texto});

  final TextoPermissao texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EspacosTrato.margemTela,
        0,
        EspacosTrato.margemTela,
        EspacosTrato.x5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Permissão desligada', style: TipografiaTrato.titulo),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'O acesso está bloqueado nas configurações do aparelho. ${texto.finalidade} '
            'Para continuar, abra as configurações e permita.',
            style: TipografiaTrato.corpo,
          ),
          const SizedBox(height: EspacosTrato.x5),
          BotaoPrimario(
            texto: 'Abrir configurações',
            aoTocar: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Center(
            child: BotaoLink(texto: 'Agora não', aoTocar: () => Navigator.of(context).pop(false)),
          ),
        ],
      ),
    );
  }
}
