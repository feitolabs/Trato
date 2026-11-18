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

  late List<PreferenciaNotificacao> _itens = widget.iniciais.isNotEmpty
      ? List.of(widget.iniciais)
      : [for (final c in _padroes) PreferenciaNotificacao(categoria: c)];

  var _salvando = false;
  String? _erro;
  String? _aviso;

  static (String, String) _textosDaCategoria(String categoria) => switch (categoria) {
        'orcamentos' => ('Orçamentos e convites', 'Novos orçamentos e convites de serviço.'),
        'pagamentos' => ('Pagamentos e recibos', 'Confirmações, aditivos e liberação de valores.'),
        'agenda' => ('Agenda de visitas', 'Sugestões de horário, confirmações e remarcações.'),
        'execucao' => ('Andamento do serviço', 'Check-in, início e conclusão do serviço.'),
        'disputas' => ('Disputas e suporte', 'Atualizações de ocorrências e prazos.'),
        'avaliacoes' => ('Avaliações', 'Pedidos para avaliar após a conclusão.'),
        'mensagens' => ('Mensagens do chat', 'Avisos quando houver nova conversa no pedido.'),
        _ => (categoria, 'Alertas desta categoria.'),
      };

  void _atualizar(int indice, PreferenciaNotificacao novo) {
    setState(() {
      _itens[indice] = novo;
      _aviso = null;
      _erro = null;
    });
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      final gravado = await widget.repositorio.salvarPreferencias(_itens);
      if (!mounted) return;
      setState(() {
        if (gravado.isNotEmpty) _itens = List.of(gravado);
        _aviso = 'Preferências salvas.';
      });
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } on Object {
      if (mounted) setState(() => _erro = 'Não foi possível salvar suas preferências.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        Text(
          'Escolha como quer receber cada tipo de aviso. Alertas críticos de segurança ou conta continuam sendo enviados quando necessário.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        for (var i = 0; i < _itens.length; i++) ...[
          () {
            final item = _itens[i];
            final (titulo, subtitulo) = _textosDaCategoria(item.categoria);
            return CartaoTrato(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TipografiaTrato.tituloCartao),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    subtitulo,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: CoresTrato.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  SwitchListTile(
                    key: Key('switch-push-${item.categoria}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notificação no celular (Push)'),
                    value: item.push,
                    onChanged: _salvando
                        ? null
                        : (v) => _atualizar(i, item.copiarCom(push: v)),
                  ),
                  SwitchListTile(
                    key: Key('switch-app-${item.categoria}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alertas dentro do app'),
                    value: item.app,
                    onChanged: _salvando
                        ? null
                        : (v) => _atualizar(i, item.copiarCom(app: v)),
                  ),
                  SwitchListTile(
                    key: Key('switch-email-${item.categoria}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('E-mail'),
                    value: item.email,
                    onChanged: _salvando
                        ? null
                        : (v) => _atualizar(i, item.copiarCom(email: v)),
                  ),
                ],
              ),
            );
          }(),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_erro != null) ...[
          Text(
            _erro!,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_aviso != null) ...[
          Text(
            _aviso!,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.verdeTexto),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        BotaoPrimario(
          key: const Key('botao-salvar-preferencias'),
          texto: 'Salvar preferências',
          carregando: _salvando,
          aoTocar: _salvando ? null : _salvar,
        ),
      ],
    );
  }
}
