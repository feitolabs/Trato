import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';

/// Preferências de notificação por categoria e canal (`GET`/`PUT /v1/notificacoes/preferencias`).
class PreferenciasNotificacoesTela extends StatelessWidget {
  const PreferenciasNotificacoesTela({super.key, required this.repositorio});

  final RepositorioNotificacoes repositorio;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Preferências de alertas',
      child: CarregadorTela<List<PreferenciaNotificacao>>(
        carregar: repositorio.carregarPreferencias,
        construir: (context, itens, _) => _CorpoPreferencias(
          repositorio: repositorio,
          iniciais: itens,
        ),
      ),
    );
  }
}

class _CorpoPreferencias extends StatefulWidget {
  const _CorpoPreferencias({required this.repositorio, required this.iniciais});

  final RepositorioNotificacoes repositorio;
  final List<PreferenciaNotificacao> iniciais;

  @override
  State<_CorpoPreferencias> createState() => _CorpoPreferenciasState();
}

class _CorpoPreferenciasState extends State<_CorpoPreferencias> {
  static const _padroes = [
    'orcamentos',
    'pagamentos',
    'agenda',
    'execucao',
    'disputas',
    'avaliacoes',
    'mensagens',
  ];

  /// Termos 15.2: disputa e pagamento/estorno chegam sempre pelo app e por e-mail. O campo
  /// `obrigatorias` do servidor manda quando vier (e trava também o push); sem ele, vale esta
  /// lista.
  static const _obrigatoriasPadrao = {'pagamentos', 'disputas'};

  static bool _ehObrigatoria(PreferenciaNotificacao p) =>
      p.obrigatoria ?? _obrigatoriasPadrao.contains(p.categoria);

  static PreferenciaNotificacao _comObrigatorios(PreferenciaNotificacao p) => _ehObrigatoria(p)
      ? p.copiarCom(app: true, email: true, push: p.obrigatoria == true ? true : null)
      : p;

  late List<PreferenciaNotificacao> _itens = widget.iniciais.isNotEmpty
      ? [for (final p in widget.iniciais) _comObrigatorios(p)]
      : [for (final c in _padroes) PreferenciaNotificacao(categoria: c)];

  var _salvando = false;
  String? _erro;
  String? _aviso;

  static (String, String) _textosDaCategoria(String categoria) => switch (categoria) {
        'orcamentos' => ('Orçamentos e convites', 'Novos orçamentos e convites de serviço.'),
        'pagamentos' => (
            'Pagamentos e estornos',
            'Confirmações, estornos, aditivos e liberação de valores.'
          ),
        'agenda' => ('Agenda de visitas', 'Sugestões de horário, confirmações e remarcações.'),
        'execucao' => ('Andamento do serviço', 'Check-in, início e conclusão do serviço.'),
        'disputas' => ('Disputas e suporte', 'Atualizações de ocorrências e prazos.'),
        'avaliacoes' => ('Avaliações', 'Pedidos para avaliar após a conclusão.'),
        'mensagens' => ('Mensagens do chat', 'Avisos quando houver nova conversa no pedido.'),
        _ => (categoria, 'Alertas desta categoria.'),
      };

  /// Salva NA HORA, a cada interruptor. Enquanto grava, os interruptores ficam travados ("Salvando…").
  /// Se falhar, o interruptor volta ao valor anterior e aparece o erro com "Tentar de novo".
  Future<void> _alterar(int indice, PreferenciaNotificacao novo) async {
    if (_salvando) return;
    final anterior = _itens[indice];
    setState(() {
      _itens[indice] = novo;
      _salvando = true;
      _erro = null;
      _aviso = null;
      _repetir = null;
    });
    try {
      final gravado = await widget.repositorio.salvarPreferencias(_itens);
      if (!mounted) return;
      setState(() {
        if (gravado.isNotEmpty) {
          _itens = [for (final p in gravado) _comObrigatorios(p)];
        }
        _aviso = 'Preferência salva.';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _itens[indice] = anterior; // volta ao que está gravado
        _erro = e is ErroTrato ? e.mensagem : 'Não foi possível salvar. Tente de novo.';
        _repetir = () => _alterar(indice, novo);
      });
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Refaz a última alteração que falhou.
  VoidCallback? _repetir;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        Text(
          'Escolha como quer receber cada tipo de aviso. Alertas críticos de segurança ou conta continuam sendo enviados quando necessário.',
          style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x3),
        // O retorno fica NO TOPO: quem mexe num interruptor vê na hora se gravou ou deu erro.
        if (_salvando)
          Text(
            'Salvando…',
            key: const Key('preferencias-salvando'),
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
          )
        else if (_erro != null) ...[
          Text(
            _erro!,
            key: const Key('preferencias-erro'),
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
          ),
          if (_repetir != null)
            BotaoLink(
              key: const Key('preferencias-tentar-de-novo'),
              texto: 'Tentar de novo',
              aoTocar: _repetir,
            ),
        ] else if (_aviso != null)
          Text(
            _aviso!,
            key: const Key('preferencias-salvas'),
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.verdeTexto),
          ),
        const SizedBox(height: EspacosTrato.x3),
        for (var i = 0; i < _itens.length; i++) ...[
          () {
            final item = _itens[i];
            final (titulo, subtitulo) = _textosDaCategoria(item.categoria);
            final obrigatoria = _ehObrigatoria(item);
            final travaPush = item.obrigatoria == true;
            return CartaoTrato(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TipografiaTrato.tituloCartao),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    subtitulo,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: context.cores.textoSecundario,
                    ),
                  ),
                  if (obrigatoria) ...[
                    const SizedBox(height: EspacosTrato.x1),
                    Text(
                      travaPush
                          ? 'Estes avisos ficam sempre ligados porque afetam os seus direitos.'
                          : 'No app e por e-mail, estes avisos ficam sempre ligados porque afetam '
                              'os seus direitos.',
                      key: Key('aviso-obrigatorio-${item.categoria}'),
                      style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.texto),
                    ),
                  ],
                  const SizedBox(height: EspacosTrato.x2),
                  SwitchListTile(
                    key: Key('switch-push-${item.categoria}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notificação no celular (Push)'),
                    value: item.push,
                    onChanged: _salvando || travaPush
                        ? null
                        : (v) => _alterar(i, item.copiarCom(push: v)),
                  ),
                  SwitchListTile(
                    key: Key('switch-app-${item.categoria}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alertas dentro do app'),
                    value: item.app,
                    onChanged: _salvando || obrigatoria
                        ? null
                        : (v) => _alterar(i, item.copiarCom(app: v)),
                  ),
                  SwitchListTile(
                    key: Key('switch-email-${item.categoria}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('E-mail'),
                    value: item.email,
                    onChanged: _salvando || obrigatoria
                        ? null
                        : (v) => _alterar(i, item.copiarCom(email: v)),
                  ),
                ],
              ),
            );
          }(),
          const SizedBox(height: EspacosTrato.x3),
        ],
      ],
    );
  }
}
