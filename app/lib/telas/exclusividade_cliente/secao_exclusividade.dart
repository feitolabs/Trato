import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/desconto_moedas.dart';
import '../comuns/formato_aparelho.dart';
import 'modelos.dart';

String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

String _quando(DateTime d) => '${_data(d)}, ${horaDoAparelho(d)}';

/// O que a pessoa lê ANTES de confirmar (Termos 13.6). Os números são os do servidor.
String avisoExclusividade(int custo, int horas) => 'Custa ${textoTratinhos(custo)}. Por '
    '$horas horas, o pedido não vai para outros profissionais. Os Tratinhos não voltam se o '
    'prazo vencer sem contratação, se você aceitar outro profissional ou se cancelar o '
    'pedido. Voltam só por falha do Trato ou desistência do profissional.';

typedef DadosExclusividade = ({
  SituacaoExclusividadeCliente? situacao,
  List<EscolhaExclusividade> escolhas,
});

/// Cartão do pedido aberto. Sem a função no servidor (404/503) não aparece nada.
class SecaoExclusividadeCliente extends StatefulWidget {
  const SecaoExclusividadeCliente({
    super.key,
    required this.carregar,
    required this.pedir,
    this.atualizarQuando,
    this.aoPedir,
  });

  final Future<DadosExclusividade> Function() carregar;
  final Future<void> Function(EscolhaExclusividade escolha, String chave) pedir;
  final Listenable? atualizarQuando;
  final VoidCallback? aoPedir;

  @override
  State<SecaoExclusividadeCliente> createState() => _SecaoExclusividadeClienteState();
}

class _SecaoExclusividadeClienteState extends State<SecaoExclusividadeCliente> {
  DadosExclusividade? _dados;
  var _falhou = false;
  var _geracao = 0;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_buscar);
    _buscar();
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_buscar);
    super.dispose();
  }

  Future<void> _buscar() async {
    final minha = ++_geracao;
    try {
      final dados = await widget.carregar();
      if (mounted && minha == _geracao) {
        setState(() {
          _dados = dados;
          _falhou = false;
        });
      }
    } on Object {
      if (mounted && minha == _geracao) setState(() => _falhou = true);
    }
  }

  Future<void> _abrir(SituacaoExclusividadeCliente s, List<EscolhaExclusividade> escolhas) async {
    final pediu = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaExclusividade(situacao: s, escolhas: escolhas, pedir: widget.pedir),
    );
    if (pediu == true && mounted) {
      widget.aoPedir?.call();
      await _buscar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _dados?.situacao;
    final secundario =
        TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    if (s == null) {
      if (!_falhou) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível ver a exclusividade deste pedido.',
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
            ),
            BotaoLink(texto: 'Tentar de novo', aoTocar: _buscar),
          ],
        ),
      );
    }
    final ex = s.exclusividade;
    final escolhas = _dados!.escolhas;
    final podeOferecer = s.disponivel && !(ex?.ativa ?? false);
    if (ex == null && !podeOferecer) return const SizedBox.shrink();
    final escolhido = ex == null
        ? null
        : escolhas
            .where((e) => e.profissionalId == ex.profissionalId)
            .map((e) => e.rotulo)
            .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: const Key('cartao-exclusividade-cliente'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Exclusividade', style: TipografiaTrato.tituloCartao),
            if (ex != null) ...[
              const SizedBox(height: EspacosTrato.x2),
              Text(
                switch (ex.status) {
                  'ativa' => ex.expiraEm == null
                      ? 'Ativa'
                      : 'Ativa até ${_quando(ex.expiraEm!)}',
                  'concluida' => 'Concluída: você contratou o profissional escolhido.',
                  'expirada_sem_contratacao' => 'Venceu sem contratação.',
                  _ => 'Encerrada.',
                },
                key: const Key('situacao-exclusividade'),
                style: TipografiaTrato.corpoForte,
              ),
              if (escolhido != null) Text(escolhido, style: TipografiaTrato.corpo),
              Text(
                ex.devolvida
                    ? 'Os Tratinhos voltaram ao seu saldo.'
                    : ex.ativa
                        ? 'Os Tratinhos não voltam se o prazo vencer sem contratação, se você '
                            'aceitar outro profissional ou se cancelar o pedido.'
                        : 'Os Tratinhos usados não voltam.',
                style: secundario,
              ),
            ],
            if (podeOferecer) ...[
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'Reserve este pedido para um profissional por ${s.duracaoHoras} horas. '
                'Custa ${textoTratinhos(s.custo)}.',
                style: TipografiaTrato.corpo,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text('Saldo livre: ${textoTratinhos(s.saldoLivre)}', style: secundario),
              for (final c in s.creditos)
                if (c.expiraEm != null)
                  Text('${textoTratinhos(c.moedas)}: vence em ${_data(c.expiraEm!)}',
                      style: secundario),
              const SizedBox(height: EspacosTrato.x3),
              if (escolhas.isEmpty)
                Text(
                  'Quando um orçamento chegar, você pode escolher o profissional aqui.',
                  style: secundario,
                )
              else
                BotaoSecundario(
                  key: const Key('pedir-exclusividade-cliente'),
                  texto: 'Pedir exclusividade de ${s.duracaoHoras} horas',
                  aoTocar: () => _abrir(s, escolhas),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FolhaExclusividade extends StatefulWidget {
  const _FolhaExclusividade({
    required this.situacao,
    required this.escolhas,
    required this.pedir,
  });

  final SituacaoExclusividadeCliente situacao;
  final List<EscolhaExclusividade> escolhas;
  final Future<void> Function(EscolhaExclusividade escolha, String chave) pedir;

  @override
  State<_FolhaExclusividade> createState() => _FolhaExclusividadeState();
}

class _FolhaExclusividadeState extends State<_FolhaExclusividade> {
  EscolhaExclusividade? _escolha;

  /// A mesma escolha repete a mesma chave (sem cobrar duas vezes); outra escolha, outra chave.
  String _chave = '';
  var _enviando = false;
  String? _erro;

  Future<void> _confirmar() async {
    final escolha = _escolha;
    if (escolha == null || _enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.pedir(escolha, _chave);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = e is ErroTrato
              ? e.mensagem
              : 'Não foi possível pedir a exclusividade. Tente de novo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.situacao;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EspacosTrato.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pedir exclusividade', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x3),
            Text(
              avisoExclusividade(s.custo, s.duracaoHoras),
              key: const Key('aviso-exclusividade'),
              style: TipografiaTrato.corpo,
            ),
            const SizedBox(height: EspacosTrato.x3),
            Text('Para quem?', style: TipografiaTrato.corpoForte),
            RadioGroup<EscolhaExclusividade>(
              groupValue: _escolha,
              onChanged: (v) {
                if (_enviando || v == null) return;
                setState(() {
                  _escolha = v;
                  _erro = null;
                  _chave = 'exc-cli-${DateTime.now().microsecondsSinceEpoch}';
                });
              },
              child: Column(
                children: [
                  for (final e in widget.escolhas)
                    RadioListTile<EscolhaExclusividade>(
                      contentPadding: EdgeInsets.zero,
                      value: e,
                      title: Text(e.rotulo, style: TipografiaTrato.corpo),
                    ),
                ],
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: EspacosTrato.x2),
              Text(
                _erro!,
                key: const Key('erro-exclusividade-cliente'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
              ),
            ],
            const SizedBox(height: EspacosTrato.x3),
            BotaoPrimario(
              key: const Key('confirmar-exclusividade-cliente'),
              texto: 'Usar ${textoTratinhos(s.custo)}',
              carregando: _enviando,
              aoTocar: _escolha == null ? null : _confirmar,
            ),
            const SizedBox(height: EspacosTrato.x2),
            Center(
              child: BotaoLink(
                texto: 'Cancelar',
                aoTocar: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
