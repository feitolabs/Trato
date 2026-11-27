import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'lista_exclusividades.dart';

/// Limite do motivo no backend para esta rota.
const _motivoMaximo = 1000;

/// "Registrar falha do Trato" (Termos 13.6). O painel só pede: quem diz se cabe devolução e
/// quantos Tratinhos voltam é o backend. A exclusividade é escolhida na lista antes de confirmar.
Future<void> abrirFalhaTrato(BuildContext context) =>
    mostrarModal<void>(context, largura: 600, construir: (_) => const _FalhaTratoModal());

class _FalhaTratoModal extends StatefulWidget {
  const _FalhaTratoModal();

  @override
  State<_FalhaTratoModal> createState() => _FalhaTratoModalState();
}

class _FalhaTratoModalState extends State<_FalhaTratoModal> {
  ExclusividadeCliente? _escolhida;
  final _motivo = TextEditingController();
  bool _confirmando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _valido {
    final n = _motivo.text.trim().length;
    return _escolhida != null && n >= kMotivoMinimo && n <= _motivoMaximo;
  }

  static String _tratinhos(int n) => '${formatarMilhar(n)} ${n == 1 ? 'Tratinho' : 'Tratinhos'}';

  /// Recusas vêm como `{detail, codigo}`; o código vira frase.
  static String mensagemDeErro(Object e) {
    if (e is! ErroApi) return 'Algo deu errado. Tente de novo.';
    final t = e.mensagem;
    switch (e.codigo) {
      case 'nao_encontrada':
        return 'O servidor não achou esta exclusividade paga pelo cliente. Atualize a lista.';
      case 'nao_elegivel':
        return 'Esta exclusividade já foi concluída: não cabe devolução.';
      case 'analista_invalido':
        return 'Sua conta não está habilitada como analista no servidor.';
      case 'indisponivel':
        return t;
    }
    return switch (e.status) {
      404 => 'O servidor não encontrou esta ação. Confira se o backend novo já está publicado.',
      403 => 'Sem permissão. $t',
      503 => t,
      null => '$t Pode repetir: o servidor não devolve duas vezes.',
      _ => t,
    };
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final api = context.api;
    try {
      final r = await api.registrarFalhaTrato(_escolhida!.id, motivo: _motivo.text.trim());
      if (!mounted) return;
      final n = api.ultimoRegistroAuditoria;
      mostrarAviso(
        context,
        r.resultado == 'ja_devolvida'
            ? 'Já tinha sido devolvida antes (${_tratinhos(r.moedasDevolvidas)}). Nada novo foi devolvido.'
            : 'Falha do Trato registrada. ${_tratinhos(r.moedasDevolvidas)} de volta ao cliente.',
        detalhe: n == null ? null : 'Registro de auditoria nº ${formatarMilhar(n)}',
      );
      Navigator.of(context).pop();
    } catch (e) {
      // O modal fica aberto: o código e o motivo continuam preenchidos.
      if (mounted) {
        setState(() {
          _erro = mensagemDeErro(e);
          _enviando = false;
          _confirmando = false;
        });
      }
    }
  }

  static List<Widget> _resumo(ExclusividadeCliente e) => [
        Linha('Cliente', e.clienteNome ?? e.clienteId),
        Linha('Profissional', e.profissionalNome ?? e.profissionalId),
        Linha('Pedido', e.pedidoId),
        Linha('Situação', rotuloStatusExclusividade(e.status)),
        Linha('Tratinhos pagos', _tratinhos(e.moedas)),
        Linha('Já devolvida', e.estornada ? 'Sim' : 'Não'),
        Linha('Código', e.id),
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _confirmando ? 'Confirmar a devolução?' : 'Registrar falha do Trato',
        consequencia: _confirmando
            ? 'Os Tratinhos da exclusividade abaixo voltam ao cliente e ele é avisado. O painel não desfaz.'
            : 'Use quando uma falha do Trato prejudicou uma exclusividade paga pelo cliente. '
                'O servidor devolve os Tratinhos.',
        filhos: [
          // As duas primeiras posições são fixas, para a lista abaixo não ser recriada.
          _erro == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                  child: BannerInfo(_erro!, titulo: 'Não foi registrado.', tom: Tom.erro),
                ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_confirmando) ...[
                ..._resumo(_escolhida!),
                Linha('Motivo', _motivo.text.trim()),
              ],
            ],
          ),
          // Fora da tela na confirmação, mas montada: filtros, páginas e escolha se mantêm.
          Offstage(
            offstage: _confirmando,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListaExclusividades(
                  escolhida: _escolhida,
                  aoEscolher: _enviando ? null : (e) => setState(() => _escolhida = e),
                ),
                const SizedBox(height: EspacosTrato.x3),
                CampoMotivo(controle: _motivo, aoMudar: () => setState(() {})),
                if (_motivo.text.trim().length > _motivoMaximo)
                  Text(
                    'O motivo passa de $_motivoMaximo caracteres.',
                    style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto),
                  ),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _confirmando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _confirmando ? setState(() => _confirmando = false) : Navigator.of(context).pop(),
          ),
          _confirmando
              ? BotaoTrato.primario(
                  'Confirmar devolução',
                  aoPressionar: _enviando ? null : _confirmar,
                  carregando: _enviando,
                  rotuloCarregando: 'Registrando',
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: _valido
                      ? () => setState(() {
                            _erro = null;
                            _confirmando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}
