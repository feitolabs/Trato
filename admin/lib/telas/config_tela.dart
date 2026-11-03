import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../nucleo/parametros_config.dart';
import '../tema/tema.dart';

/// Configurações (RF-CFG-01 a RF-CFG-05): toda mudança vira proposta, só vale depois que outra
/// pessoa aprovar, e a versão anterior fica disponível para reverter. Nome, unidade e faixa vêm do
/// banco; nenhum valor de taxa, prazo ou limite é escrito aqui.
class ConfigTela extends StatelessWidget {
  const ConfigTela({super.key});

  static (String, Tom) chip(StatusVersao s) => switch (s) {
        StatusVersao.rascunho => ('Rascunho', Tom.neutro),
        StatusVersao.aguardandoAprovacao => ('Aguardando aprovação', Tom.alerta),
        StatusVersao.aprovada => ('Aprovada, falta publicar', Tom.alerta),
        StatusVersao.vigente => ('Atual', Tom.ok),
        StatusVersao.substituida => ('Substituída', Tom.neutro),
        StatusVersao.revertida => ('Revertida', Tom.info),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Configurações',
          subtitulo: 'Toda mudança vira proposta e só vale depois que outra pessoa aprovar. A versão anterior fica disponível para reverter.',
        ),
        Expanded(
          child: CarregaDados<ConfigAtual>(
            carregar: context.api.carregarConfig,
            estaVazio: (c) => c.definicoes.isEmpty,
            mensagemVazia: 'Nenhum parâmetro cadastrado.',
            detalheVazio: 'Os parâmetros de taxa, prazos e limites aparecem aqui.',
            construir: (context, config, recarregar) => _Conteudo(config: config, aoMudar: recarregar),
          ),
        ),
      ],
    );
  }
}

class _Conteudo extends StatefulWidget {
  const _Conteudo({required this.config, required this.aoMudar});
  final ConfigAtual config;
  final Future<void> Function() aoMudar;

  @override
  State<_Conteudo> createState() => _ConteudoState();
}

class _ConteudoState extends State<_Conteudo> {
  String _grupo = gruposConfig.first;
  final _campos = <String, TextEditingController>{};

  ConfigVersao? get _vigente => widget.config.versoes.where((v) => v.status == StatusVersao.vigente).firstOrNull;

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controle(ConfigDefinicao d) {
    return _campos.putIfAbsent(
      d.chave,
      () => TextEditingController(text: valorParaCampo(_vigente?.valores[d.chave] ?? 0, d)),
    );
  }

  int _atual(ConfigDefinicao d) => _vigente?.valores[d.chave] ?? 0;

  /// Valor proposto digitado, ou null quando o texto não vale.
  int? _digitado(ConfigDefinicao d) => campoParaValor(_controle(d).text, d);

  /// Valor em horas de um parâmetro de disputa, para a validação entre parâmetros (RF-CFG-05).
  int? _horasDe(String chave, int Function(int) paraHoras) {
    final d = widget.config.definicoes.where((x) => x.chave == chave).firstOrNull;
    if (d == null) return null;
    final v = _campos.containsKey(chave) ? (_digitado(d) ?? _atual(d)) : _atual(d);
    return paraHoras(v);
  }

  String? _erro(ConfigDefinicao d) {
    final v = _digitado(d);
    if (_controle(d).text.trim().isEmpty || v == null) return 'Digite um número válido';
    if (v < d.minimo || v > d.maximo) return 'Fora da faixa: ${faixaLegivel(d)}';
    // Resposta da disputa precisa ser menor que o prazo de decisão.
    if (d.chave == 'prazo_resposta_disputa_horas' || d.chave == 'prazo_decisao_disputa_dias_uteis') {
      final resposta = d.chave == 'prazo_resposta_disputa_horas' ? v : _horasDe('prazo_resposta_disputa_horas', (x) => x);
      final decisao = d.chave == 'prazo_decisao_disputa_dias_uteis'
          ? v * 24
          : _horasDe('prazo_decisao_disputa_dias_uteis', (x) => x * 24);
      if (resposta != null && decisao != null && resposta >= decisao) {
        return 'A resposta precisa ser menor que a decisão';
      }
    }
    return null;
  }

  Future<void> _propor(ConfigDefinicao d) async {
    final api = context.api;
    final novo = _digitado(d)!;
    final antes = _atual(d);
    final motivo = await pedirFormulario<String>(
      context,
      titulo: 'Propor mudança em "${d.descricao}"?',
      consequencia: 'Outra pessoa precisa aprovar antes de valer. Vale só para novos contratos.',
      rotuloConfirmar: 'Enviar para aprovação',
      campos: (ctx, rebuild) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: CampoLeitura('Valor atual', valorLegivel(antes, d))),
              const Icon(Icons.arrow_forward, size: 18, color: CoresTrato.textoMudo),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: CampoLeitura('Valor proposto', valorLegivel(novo, d))),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text('Faixa permitida: ${faixaLegivel(d)}', style: TipografiaTrato.legenda),
        ],
      ),
      camposValidos: () => true,
      resultado: (m) => m,
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => api.proporConfig({d.chave: novo}, motivo),
      sucesso: 'Mudança enviada para aprovação.',
    );
    if (ok) {
      _campos[d.chave]?.dispose();
      _campos.remove(d.chave);
      await widget.aoMudar();
    }
  }

  Future<void> _aprovar(ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Aprovar a mudança da versão ${v.numero}?',
      descricao: 'A versão passa a valer para novos contratos. Contratos em andamento mantêm a versão com que foram fechados.',
      rotuloConfirmar: 'Aprovar mudança',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(context, () => api.aprovarConfig(v.id, motivo), sucesso: 'Mudança aprovada.');
    if (ok) await widget.aoMudar();
  }

  Future<void> _publicar(ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Publicar a versão ${v.numero}?',
      descricao: 'A versão passa a valer para novos contratos.',
      rotuloConfirmar: 'Publicar versão',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(context, () => api.publicarConfig(v.id, motivo), sucesso: 'Versão publicada.');
    if (ok) await widget.aoMudar();
  }

  Future<void> _recusar(ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Recusar a proposta da versão ${v.numero}?',
      descricao: 'A proposta é descartada e a versão atual continua valendo. Quem propôs é avisado pelo motivo.',
      rotuloConfirmar: 'Recusar proposta',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(context, () => api.recusarConfig(v.id, motivo), sucesso: 'Proposta recusada.');
    if (ok) await widget.aoMudar();
  }

  Future<void> _reverter(ConfigVersao v) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Reverter para a versão ${v.numero}?',
      descricao: 'Cria uma nova versão com os valores desta e envia para aprovação. O histórico não é apagado.',
      rotuloConfirmar: 'Pedir reversão',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(context, () => api.reverterConfig(v.id, motivo), sucesso: 'Reversão enviada para aprovação.');
    if (ok) await widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final celular = FaixaPainel.de(context).ehCelular;
    final vigente = _vigente;
    final defs = widget.config.definicoes;
    final meuId = context.eu?.id;
    final pendentes = widget.config.versoes.where((v) => v.status == StatusVersao.aguardandoAprovacao).toList();
    final aprovadasSemPublicar = widget.config.versoes.where((v) => v.status == StatusVersao.aprovada).toList();
    final podePropor = context.pode(Permissao.configPropor);
    final podeAprovar = context.pode(Permissao.configAprovar);

    final doGrupo = [for (final d in defs) if (infoDe(d.chave).grupo == _grupo) d];

    return ListView(
      padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x6),
      children: [
        for (final v in pendentes)
          Padding(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
            child: _BannerPendente(
              versao: v,
              vigente: vigente,
              definicoes: defs,
              minha: v.criadaPor == meuId,
              podeAprovar: podeAprovar,
              aoAprovar: () => _aprovar(v),
              aoRecusar: () => _recusar(v),
            ),
          ),
        for (final v in aprovadasSemPublicar)
          Padding(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
            child: BannerInfo(
              'A versão ${v.numero} foi aprovada e falta publicar.',
              titulo: 'Aprovada.',
              tom: Tom.alerta,
              icone: Icons.pending_actions_outlined,
            ),
          ),
        // Temas.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final g in gruposConfig)
                Padding(
                  padding: const EdgeInsets.only(right: EspacosTrato.x2),
                  child: ChoiceChip(
                    label: Text(g),
                    selected: _grupo == g,
                    onSelected: (_) => setState(() => _grupo = g),
                    labelStyle: TipografiaTrato.corpoForte.copyWith(
                      color: _grupo == g ? CoresTrato.primaria : CoresTrato.textoMudo,
                    ),
                    side: BorderSide(color: _grupo == g ? CoresTrato.bordaSelecionada : CoresTrato.bordaForte),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (vigente == null)
          const BannerInfo('Ainda não há versão vigente de configuração.', tom: Tom.alerta)
        else if (doGrupo.isEmpty)
          const EstadoVazio('Nenhum parâmetro neste tema')
        else
          CartaoSecao(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (!celular) const _CabecalhoTabela(),
                for (final d in doGrupo)
                  celular
                      ? _LinhaCartao(
                          def: d,
                          atual: _atual(d),
                          controle: _controle(d),
                          erro: _erro(d),
                          mudou: _digitado(d) != null && _digitado(d) != _atual(d),
                          podePropor: podePropor,
                          aoMudar: () => setState(() {}),
                          aoPropor: () => _propor(d),
                        )
                      : _LinhaTabela(
                          def: d,
                          atual: _atual(d),
                          controle: _controle(d),
                          erro: _erro(d),
                          mudou: _digitado(d) != null && _digitado(d) != _atual(d),
                          podePropor: podePropor,
                          aoMudar: () => setState(() {}),
                          aoPropor: () => _propor(d),
                        ),
              ],
            ),
          ),
        const SizedBox(height: EspacosTrato.x5),
        Text('Histórico de versões', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x3),
        for (var i = 0; i < widget.config.versoes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
            child: _VersaoCartao(
              versao: widget.config.versoes[i],
              anterior: i + 1 < widget.config.versoes.length ? widget.config.versoes[i + 1] : null,
              definicoes: defs,
              podeReverter: podePropor &&
                  (widget.config.versoes[i].status == StatusVersao.substituida ||
                      widget.config.versoes[i].status == StatusVersao.revertida),
              aoReverter: () => _reverter(widget.config.versoes[i]),
              podePublicar: podeAprovar && widget.config.versoes[i].status == StatusVersao.aprovada,
              aoPublicar: () => _publicar(widget.config.versoes[i]),
            ),
          ),
      ],
    );
  }
}

class _BannerPendente extends StatelessWidget {
  const _BannerPendente({
    required this.versao,
    required this.vigente,
    required this.definicoes,
    required this.minha,
    required this.podeAprovar,
    required this.aoAprovar,
    required this.aoRecusar,
  });

  final ConfigVersao versao;
  final ConfigVersao? vigente;
  final List<ConfigDefinicao> definicoes;
  final bool minha;
  final bool podeAprovar;
  final VoidCallback aoAprovar;
  final VoidCallback aoRecusar;

  @override
  Widget build(BuildContext context) {
    final mudancas = vigente == null ? <String>[] : diferencas(versao, vigente!, definicoes);
    final quem = versao.criadaPorNome ?? 'Alguém da equipe';
    final resumo = mudancas.isEmpty
        ? 'propôs uma mudança.'
        : mudancas.length == 1
            ? 'propôs mudar ${_minusculo(mudancas.first)}.'
            : 'propôs ${mudancas.length} mudanças.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BannerInfo(
          '$quem $resumo Motivo: “${versao.motivo}”',
          titulo: 'Aprovação pendente.',
          tom: Tom.alerta,
          icone: Icons.pending_actions_outlined,
        ),
        if (mudancas.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(EspacosTrato.x4, EspacosTrato.x2, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final m in mudancas) Text('• $m', style: TipografiaTrato.corpo)],
            ),
          ),
        const SizedBox(height: EspacosTrato.x2),
        if (minha)
          Text('Você propôs esta versão. Outra pessoa precisa aprovar (aprovação dupla).', style: TipografiaTrato.legenda)
        else if (podeAprovar)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: EspacosTrato.x3,
              runSpacing: EspacosTrato.x2,
              children: [
                BotaoTrato.secundario('Recusar proposta', aoPressionar: aoRecusar),
                BotaoTrato.primario('Aprovar mudança', aoPressionar: aoAprovar),
              ],
            ),
          ),
      ],
    );
  }

  static String _minusculo(String t) => t.isEmpty ? t : '${t[0].toLowerCase()}${t.substring(1)}';
}

const _flexTabela = [34, 18, 16, 22, 10];

class _CabecalhoTabela extends StatelessWidget {
  const _CabecalhoTabela();

  @override
  Widget build(BuildContext context) {
    Widget c(String t, int i) => Expanded(
          flex: _flexTabela[i],
          child: Text(t, style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
      child: Row(children: [c('Parâmetro', 0), c('Faixa permitida', 1), c('Valor atual', 2), c('Valor proposto', 3), c('', 4)]),
    );
  }
}

/// Campo do valor proposto, com % ou R$ e a unidade visível.
Widget _campoProposto(ConfigDefinicao d, TextEditingController controle, String? erro, bool habilitado, VoidCallback aoMudar) {
  if (d.unidade == UnidadeConfig.quantidade && d.minimo == 0 && d.maximo == 1) {
    return SeletorTrato<String>(
      rotulo: 'Valor proposto',
      valor: controle.text.trim().isEmpty ? '0' : controle.text.trim(),
      opcoes: const [('0', 'Desligada'), ('1', 'Ligada')],
      aoMudar: (v) {
        controle.text = v;
        aoMudar();
      },
    );
  }
  final (prefixo, sufixo) = switch (d.unidade) {
    UnidadeConfig.bps => (null, '%'),
    UnidadeConfig.centavos => ('R\$ ', null),
    UnidadeConfig.horas => (null, 'horas'),
    UnidadeConfig.dias => (null, 'dias'),
    UnidadeConfig.diasUteis => (null, 'dias úteis'),
    _ => (null, null),
  };
  return Semantics(
    label: 'Valor proposto para ${d.descricao}',
    child: TextField(
      key: ValueKey('campo-${d.chave}'),
      controller: controle,
      enabled: habilitado,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => aoMudar(),
      decoration: InputDecoration(
        labelText: 'Valor proposto',
        prefixText: prefixo,
        suffixText: sufixo,
        errorText: erro,
      ),
    ),
  );
}

class _LinhaTabela extends StatelessWidget {
  const _LinhaTabela({
    required this.def,
    required this.atual,
    required this.controle,
    required this.erro,
    required this.mudou,
    required this.podePropor,
    required this.aoMudar,
    required this.aoPropor,
  });

  final ConfigDefinicao def;
  final int atual;
  final TextEditingController controle;
  final String? erro;
  final bool mudou;
  final bool podePropor;
  final VoidCallback aoMudar;
  final VoidCallback aoPropor;

  @override
  Widget build(BuildContext context) {
    final ajuda = infoDe(def.chave).ajuda;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: _flexTabela[0],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.descricao, style: TipografiaTrato.corpoForte),
                if (ajuda.isNotEmpty) Text(ajuda, style: TipografiaTrato.legenda),
                if (def.exigeDuplaAprovacao) Text('Aprovação dupla', style: TipografiaTrato.legenda),
              ],
            ),
          ),
          Expanded(flex: _flexTabela[1], child: Text(faixaLegivel(def), style: TipografiaTrato.numeroTabular)),
          Expanded(
            flex: _flexTabela[2],
            child: Text(valorLegivel(atual, def), style: TipografiaTrato.numeroTabular.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            flex: _flexTabela[3],
            child: Padding(
              padding: const EdgeInsets.only(right: EspacosTrato.x3),
              child: _campoProposto(def, controle, mudou ? erro : (erro != null && controle.text.isNotEmpty ? erro : null), podePropor, aoMudar),
            ),
          ),
          Expanded(
            flex: _flexTabela[4],
            child: podePropor
                ? BotaoTrato.secundario('Propor', aoPressionar: mudou && erro == null ? aoPropor : null)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _LinhaCartao extends StatelessWidget {
  const _LinhaCartao({
    required this.def,
    required this.atual,
    required this.controle,
    required this.erro,
    required this.mudou,
    required this.podePropor,
    required this.aoMudar,
    required this.aoPropor,
  });

  final ConfigDefinicao def;
  final int atual;
  final TextEditingController controle;
  final String? erro;
  final bool mudou;
  final bool podePropor;
  final VoidCallback aoMudar;
  final VoidCallback aoPropor;

  @override
  Widget build(BuildContext context) {
    final ajuda = infoDe(def.chave).ajuda;
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(def.descricao, style: TipografiaTrato.corpoForte),
          if (ajuda.isNotEmpty) Text(ajuda, style: TipografiaTrato.legenda),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Faixa permitida', faixaLegivel(def)),
          Linha('Valor atual', valorLegivel(atual, def)),
          const SizedBox(height: EspacosTrato.x2),
          _campoProposto(def, controle, erro, podePropor, aoMudar),
          if (podePropor) ...[
            const SizedBox(height: EspacosTrato.x2),
            Align(
              alignment: Alignment.centerRight,
              child: BotaoTrato.secundario('Propor', aoPressionar: mudou && erro == null ? aoPropor : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _VersaoCartao extends StatelessWidget {
  const _VersaoCartao({
    required this.versao,
    required this.anterior,
    required this.definicoes,
    required this.podeReverter,
    required this.aoReverter,
    required this.podePublicar,
    required this.aoPublicar,
  });

  final ConfigVersao versao;
  final ConfigVersao? anterior;
  final List<ConfigDefinicao> definicoes;
  final bool podeReverter;
  final VoidCallback aoReverter;
  final bool podePublicar;
  final VoidCallback aoPublicar;

  @override
  Widget build(BuildContext context) {
    final (txt, tom) = ConfigTela.chip(versao.status);
    final mudancas = anterior == null ? <String>[] : diferencas(versao, anterior!, definicoes);
    return CartaoSecao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Versão ${versao.numero}${versao.status == StatusVersao.vigente ? ' · atual' : ''}',
                  style: TipografiaTrato.secao,
                ),
              ),
              ChipEstado(txt, tom: tom),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          if (mudancas.isEmpty)
            Text(versao.motivo, style: TipografiaTrato.corpo)
          else
            for (final m in mudancas) Text(m, style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            [
              if (versao.motivo.isNotEmpty && mudancas.isNotEmpty) 'Motivo: “${versao.motivo}”',
              'Proposto por ${versao.criadaPorNome ?? 'alguém da equipe'}',
              if (versao.aprovadaPorNome != null) 'aprovado por ${versao.aprovadaPorNome}',
              formatarData(versao.criadaEm),
            ].join(' · '),
            style: TipografiaTrato.legenda,
          ),
          if (podeReverter || podePublicar) ...[
            const SizedBox(height: EspacosTrato.x2),
            Wrap(
              spacing: EspacosTrato.x3,
              children: [
                if (podePublicar) BotaoTrato.primario('Publicar versão', aoPressionar: aoPublicar),
                if (podeReverter) BotaoTrato.secundario('Reverter', aoPressionar: aoReverter),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
