import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.5 — configurações com validação, aprovação dupla, histórico e reversão.
/// Taxa, prazos e limites vêm da API; nenhum valor ou limite é escrito aqui.
class ConfigTela extends StatelessWidget {
  const ConfigTela({super.key});

  static (String, Tom) _chip(StatusVersao s) => switch (s) {
        StatusVersao.rascunho => ('Rascunho', Tom.neutro),
        StatusVersao.aguardandoAprovacao => ('Aguardando aprovação', Tom.alerta),
        StatusVersao.aprovada => ('Aprovada, falta publicar', Tom.alerta),
        StatusVersao.vigente => ('Vigente', Tom.ok),
        StatusVersao.substituida => ('Substituída', Tom.neutro),
        StatusVersao.revertida => ('Revertida', Tom.info),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CabecalhoPagina('Configurações', subtitulo: 'Taxa, prazos e limites com histórico'),
        Expanded(
          child: CarregaDados<ConfigAtual>(
            carregar: context.api.carregarConfig,
            estaVazio: (c) => c.definicoes.isEmpty,
            mensagemVazia: 'Nenhum parâmetro cadastrado.',
            construir: (context, config, recarregar) =>
                _ConfigConteudo(config: config, aoMudar: recarregar),
          ),
        ),
      ],
    );
  }
}

class _ConfigConteudo extends StatelessWidget {
  const _ConfigConteudo({required this.config, required this.aoMudar});

  final ConfigAtual config;
  final Future<void> Function() aoMudar;

  Future<void> _aprovar(BuildContext context, ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Aprovar versão ${v.numero}',
      descricao: 'A versão passa a valer para novos contratos. Contratos em andamento mantêm a versão com que foram fechados.',
      rotuloConfirmar: 'Aprovar',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(context, () => api.aprovarConfig(v.id, motivo), sucesso: 'Versão aprovada.');
    if (ok) await aoMudar();
  }

  Future<void> _publicar(BuildContext context, ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Publicar versão ${v.numero}',
      descricao: 'A versão passa a valer para novos contratos.',
      rotuloConfirmar: 'Publicar',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(context, () => api.publicarConfig(v.id, motivo), sucesso: 'Versão publicada.');
    if (ok) await aoMudar();
  }

  Future<void> _reverter(BuildContext context, ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Reverter para a versão ${v.numero}',
      descricao: 'Cria uma nova versão com os valores desta e envia para aprovação. O histórico não é apagado.',
      rotuloConfirmar: 'Pedir reversão',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(context, () => api.reverterConfig(v.id, motivo), sucesso: 'Reversão enviada para aprovação.');
    if (ok) await aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final vigente = config.versoes.where((v) => v.status == StatusVersao.vigente).firstOrNull;
    final meuId = context.eu?.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(EspacosTrato.x6, 0, EspacosTrato.x6, EspacosTrato.x8),
      children: [
        if (vigente != null) ...[
          Text('Versão vigente: ${vigente.numero}', style: TipografiaTrato.tituloCartao),
          const SizedBox(height: EspacosTrato.x2),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(EspacosTrato.x4),
              child: Column(
                children: [
                  for (final d in config.definicoes)
                    Linha(d.descricao, formatarConfig(vigente.valores[d.chave] ?? 0, d.unidade.codigo)),
                ],
              ),
            ),
          ),
        ],
        if (context.pode(Permissao.configPropor) && vigente != null) ...[
          const SizedBox(height: EspacosTrato.x6),
          Text('Propor mudança', style: TipografiaTrato.tituloCartao),
          const SizedBox(height: EspacosTrato.x2),
          FormularioConfig(definicoes: config.definicoes, vigente: vigente, aoEnviado: aoMudar),
        ],
        const SizedBox(height: EspacosTrato.x6),
        Text('Histórico', style: TipografiaTrato.tituloCartao),
        const SizedBox(height: EspacosTrato.x2),
        for (final v in config.versoes)
          Card(
            margin: const EdgeInsets.only(bottom: EspacosTrato.x2),
            child: Padding(
              padding: const EdgeInsets.all(EspacosTrato.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Versão ${v.numero}', style: TipografiaTrato.tituloCartao)),
                      ChipEstado(ConfigTela._chip(v.status).$1, tom: ConfigTela._chip(v.status).$2),
                    ],
                  ),
                  Text(v.motivo, style: TipografiaTrato.corpoPequeno),
                  Text(
                    'Proposta por ${v.criadaPor} em ${formatarData(v.criadaEm)}'
                    '${v.aprovadaPor != null ? ' · aprovada por ${v.aprovadaPor}' : ''}',
                    style: TipografiaTrato.legenda,
                  ),
                  if (vigente != null && v.id != vigente.id) ..._diferencas(v, vigente),
                  if (v.status == StatusVersao.aguardandoAprovacao && context.pode(Permissao.configAprovar))
                    Padding(
                      padding: const EdgeInsets.only(top: EspacosTrato.x3),
                      child: v.criadaPor == meuId
                          ? const BannerInfo(
                              'Você propôs esta versão. Outra pessoa precisa aprovar (aprovação dupla).',
                              tom: Tom.alerta,
                            )
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 200,
                                child: FilledButton(
                                  onPressed: () => _aprovar(context, v),
                                  child: const Text('Aprovar versão'),
                                ),
                              ),
                            ),
                    ),
                  if (v.status == StatusVersao.aprovada && context.pode(Permissao.configAprovar))
                    Padding(
                      padding: const EdgeInsets.only(top: EspacosTrato.x3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 200,
                          child: FilledButton(
                            onPressed: () => _publicar(context, v),
                            child: const Text('Publicar versão'),
                          ),
                        ),
                      ),
                    ),
                  if ((v.status == StatusVersao.substituida || v.status == StatusVersao.revertida) &&
                      context.pode(Permissao.configPropor))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _reverter(context, v),
                        child: const Text('Reverter para esta versão'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _diferencas(ConfigVersao v, ConfigVersao vigente) {
    final linhas = <Widget>[];
    for (final d in config.definicoes) {
      final novo = v.valores[d.chave];
      final atual = vigente.valores[d.chave];
      if (novo != null && novo != atual) {
        linhas.add(Text(
          '${d.descricao}: ${formatarConfig(atual ?? 0, d.unidade.codigo)} → ${formatarConfig(novo, d.unidade.codigo)}',
          style: TipografiaTrato.corpoPequeno,
        ));
      }
    }
    if (linhas.isEmpty) return const [];
    return [
      const SizedBox(height: EspacosTrato.x2),
      Text('Diferença para a vigente', style: TipografiaTrato.legenda),
      ...linhas,
    ];
  }
}

/// Edita os valores. Faixa mínima e máxima vêm da definição (banco); o backend valida de novo.
class FormularioConfig extends StatefulWidget {
  const FormularioConfig({super.key, required this.definicoes, required this.vigente, required this.aoEnviado});

  final List<ConfigDefinicao> definicoes;
  final ConfigVersao vigente;
  final Future<void> Function() aoEnviado;

  @override
  State<FormularioConfig> createState() => _FormularioConfigState();
}

class _FormularioConfigState extends State<FormularioConfig> {
  late final Map<String, TextEditingController> _campos = {
    for (final d in widget.definicoes)
      d.chave: TextEditingController(text: '${widget.vigente.valores[d.chave] ?? ''}'),
  };
  bool _tentou = false;

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _erro(ConfigDefinicao d) {
    final v = int.tryParse(_campos[d.chave]!.text.trim());
    if (v == null) return 'Digite um número inteiro.';
    if (v < d.minimo || v > d.maximo) return 'Deve ficar entre ${d.minimo} e ${d.maximo}.';
    return null;
  }

  Map<String, int> get _valores => {for (final d in widget.definicoes) d.chave: int.tryParse(_campos[d.chave]!.text.trim()) ?? 0};

  bool get _mudou => widget.definicoes.any((d) => _valores[d.chave] != widget.vigente.valores[d.chave]);

  Future<void> _enviar() async {
    setState(() => _tentou = true);
    if (widget.definicoes.any((d) => _erro(d) != null) || !_mudou) return;
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Enviar mudança para aprovação',
      descricao: 'Outra pessoa precisa aprovar antes de valer. Só vale para novos contratos.',
      rotuloConfirmar: 'Enviar',
    );
    if (motivo == null || !mounted) return;
    final valores = _valores;
    final ok = await executar(context, () => api.proporConfig(valores, motivo), sucesso: 'Enviada para aprovação.');
    if (ok) await widget.aoEnviado();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final d in widget.definicoes)
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                child: TextField(
                  key: ValueKey('campo-${d.chave}'),
                  controller: _campos[d.chave],
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${d.descricao} (${d.unidade.codigo})${d.exigeDuplaAprovacao ? ' · aprovação dupla' : ''}',
                    helperText:
                        'Atual: ${formatarConfig(int.tryParse(_campos[d.chave]!.text.trim()) ?? 0, d.unidade.codigo)} · faixa ${d.minimo} a ${d.maximo}',
                    errorText: _tentou ? _erro(d) : null,
                  ),
                ),
              ),
            if (_tentou && !_mudou) const BannerInfo('Nenhum valor mudou.', tom: Tom.alerta),
            const SizedBox(height: EspacosTrato.x2),
            const AvisoAuditoria(),
            const SizedBox(height: EspacosTrato.x3),
            FilledButton(onPressed: _enviar, child: const Text('Enviar para aprovação')),
          ],
        ),
      ),
    );
  }
}
