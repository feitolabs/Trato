import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// "2026-11" ou "2026-11-01" -> "11/2026". Texto fora do padrão volta como veio.
String mesDeReferencia(String mesRef) {
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(mesRef);
  return m == null ? mesRef : '${m.group(2)}/${m.group(1)}';
}

/// "84%" ou "84,5%". O percentual já vem calculado do backend; aqui só se escreve.
String formatarPercentual(double p) {
  final inteiro = p == p.roundToDouble();
  return inteiro ? '${p.round()}%' : '${p.toStringAsFixed(1).replaceAll('.', ',')}%';
}

/// "2026-11-20" -> "20/11/2026". Texto fora do padrão volta como veio.
String diaDeReferencia(String diaRef) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(diaRef);
  return m == null ? diaRef : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

/// 1050 -> "10,50" (para preencher o campo em reais).
String centavosParaCampo(int centavos) => '${centavos ~/ 100},${(centavos % 100).toString().padLeft(2, '0')}';

/// Tratinhos (moedas): uso do orçamento de desconto do mês e configuração do programa.
class MoedasTela extends StatefulWidget {
  const MoedasTela({super.key});

  @override
  State<MoedasTela> createState() => _MoedasTelaState();
}

class _MoedasTelaState extends State<MoedasTela> {
  int _versao = 0;

  Future<void> _salvar(MoedasConfig nova) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Salvar a configuração dos Tratinhos?',
      descricao: 'As novas regras valem para os próximos bônus e descontos. A alteração fica na auditoria.',
      rotuloConfirmar: 'Salvar configuração',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.salvarMoedasConfig(nova, motivo: motivo),
      sucesso: 'Configuração dos Tratinhos salva.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Tratinhos',
          subtitulo: 'Uso do orçamento de desconto do mês e regras do programa. Quem decide é o servidor.',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarregaDados<MoedasOrcamento>(
                  key: ValueKey('moedas-orcamento-$_versao'),
                  carregar: api.orcamentoMoedas,
                  esqueleto: const SizedBox(height: 160, child: EsqueletoCartoes()),
                  estaVazio: (o) => o.orcamentoCentavos == 0 && o.usadoCentavos == 0,
                  mensagemVazia: 'Orçamento do mês ainda não definido',
                  detalheVazio: 'Defina o orçamento mensal de desconto na configuração abaixo.',
                  construir: (context, o, _) => CartaoOrcamentoMoedas(orcamento: o),
                ),
                const SizedBox(height: EspacosTrato.x4),
                CarregaDados<MoedasConfig>(
                  key: ValueKey('moedas-config-$_versao'),
                  carregar: api.carregarMoedasConfig,
                  esqueleto: const SizedBox(height: 320, child: EsqueletoLista(linhas: 3)),
                  construir: (context, c, _) => _FormularioMoedas(config: c, aoSalvar: _salvar),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra de uso do orçamento do mês, com o selo "Desconto fechado" quando o orçamento acabou.
class CartaoOrcamentoMoedas extends StatelessWidget {
  const CartaoOrcamentoMoedas({super.key, required this.orcamento});
  final MoedasOrcamento orcamento;

  @override
  Widget build(BuildContext context) {
    final o = orcamento;
    final fechado = o.fechado;
    final cor = fechado ? CoresTrato.perigoTexto : (o.aviso ? CoresTrato.avisoTexto : CoresTrato.primaria);
    final fracao = (o.percentualUsado / 100).clamp(0.0, 1.0);
    return CartaoSecao(
      titulo: 'Orçamento de desconto · ${mesDeReferencia(o.mesRef)}',
      acao: fechado
          ? const ChipEstado('Desconto fechado', tom: Tom.erro)
          : (o.aviso ? const ChipEstado('Perto do limite', tom: Tom.alerta) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: EspacosTrato.x3,
            children: [
              Text(
                '${formatarReais(o.usadoCentavos)} de ${formatarReais(o.orcamentoCentavos)}',
                style: TipografiaTrato.secao,
              ),
              Text(formatarPercentual(o.percentualUsado), style: TipografiaTrato.numeroTabular),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Semantics(
            label: 'Uso do orçamento do mês: ${formatarPercentual(o.percentualUsado)}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
              child: LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    Container(key: const ValueKey('moedas-barra-fundo'), height: 14, width: c.maxWidth, color: CoresTrato.neutroFundo),
                    Container(key: const ValueKey('moedas-barra'), height: 14, width: c.maxWidth * fracao, color: cor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            fechado
                ? 'O orçamento do mês acabou: novos descontos com Tratinhos ficam fechados até o próximo mês.'
                : 'Quando o uso chega ao percentual de aviso, o painel mostra um alerta.',
            style: TipografiaTrato.legenda,
          ),
          if (o.tetoDiaCentavos > 0 || o.usadoDiaCentavos > 0) ...[
            const SizedBox(height: EspacosTrato.x4),
            _BarraHoje(orcamento: o),
          ],
        ],
      ),
    );
  }
}

/// Segunda barra: quanto do teto de desconto de hoje já foi usado.
class _BarraHoje extends StatelessWidget {
  const _BarraHoje({required this.orcamento});
  final MoedasOrcamento orcamento;

  @override
  Widget build(BuildContext context) {
    final o = orcamento;
    final atingido = o.limiteDiaAtingido;
    final fracao = o.tetoDiaCentavos <= 0 ? 1.0 : (o.usadoDiaCentavos / o.tetoDiaCentavos).clamp(0.0, 1.0);
    final dia = diaDeReferencia(o.diaRef);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: EspacosTrato.x3,
          runSpacing: EspacosTrato.x1,
          children: [
            Text(
              'Hoje${dia.isEmpty ? '' : ' ($dia)'}: ${formatarReais(o.usadoDiaCentavos)} de ${formatarReais(o.tetoDiaCentavos)}',
              style: TipografiaTrato.corpoForte,
            ),
            if (atingido) const ChipEstado('Limite de hoje atingido', tom: Tom.erro),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Semantics(
          label: 'Uso do teto de desconto de hoje',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Container(height: 10, width: c.maxWidth, color: CoresTrato.neutroFundo),
                  Container(
                    key: const ValueKey('moedas-barra-hoje'),
                    height: 10,
                    width: c.maxWidth * fracao,
                    color: atingido ? CoresTrato.perigoTexto : CoresTrato.primaria,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (atingido) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text('O desconto com Tratinhos volta amanhã.', style: TipografiaTrato.legenda),
        ],
      ],
    );
  }
}

/// Formulário da configuração. Dinheiro aparece em reais e vai em centavos inteiros; os limites e
/// as regras são do backend (ele recusa o que não vale).
class _FormularioMoedas extends StatefulWidget {
  const _FormularioMoedas({required this.config, required this.aoSalvar});
  final MoedasConfig config;
  final Future<void> Function(MoedasConfig nova) aoSalvar;

  @override
  State<_FormularioMoedas> createState() => _FormularioMoedasState();
}

class _CampoConfig {
  _CampoConfig(this.chave, this.rotulo, this.texto, {this.reais = false, this.sufixo, this.ajuda});
  final String chave;
  final String rotulo;
  final TextEditingController texto;
  final bool reais;
  final String? sufixo;
  final String? ajuda;

  /// Valor inteiro (centavos nos campos em reais). Nulo = ainda não é um número válido.
  int? get valor {
    final t = texto.text.trim();
    if (reais) return lerReaisEmCentavos(t);
    return RegExp(r'^\d+$').hasMatch(t) ? int.parse(t) : null;
  }
}

class _FormularioMoedasState extends State<_FormularioMoedas> {
  late bool _ativo = widget.config.ativo;
  late final Map<String, _CampoConfig> _campos = _montar(widget.config);

  static Map<String, _CampoConfig> _montar(MoedasConfig c) {
    _CampoConfig n(String chave, String rotulo, int v, {String? sufixo, String? ajuda}) =>
        _CampoConfig(chave, rotulo, TextEditingController(text: '$v'), sufixo: sufixo, ajuda: ajuda);
    _CampoConfig r(String chave, String rotulo, int centavos, {String? ajuda}) =>
        _CampoConfig(chave, rotulo, TextEditingController(text: centavosParaCampo(centavos)), reais: true, ajuda: ajuda);
    final lista = [
      n('bonus_avaliacao_moedas', 'Bônus por avaliação', c.bonusAvaliacaoMoedas, sufixo: 'Tratinhos'),
      r('valor_moeda_centavos', 'Valor de cada Tratinho', c.valorMoedaCentavos),
      n('teto_mensal_moedas', 'Teto mensal de Tratinhos', c.tetoMensalMoedas, sufixo: 'Tratinhos'),
      r('min_servico_centavos', 'Serviço mínimo para ganhar', c.minServicoCentavos),
      n('max_bonus_por_profissional_mes', 'Máx. de bônus por profissional no mês', c.maxBonusPorProfissionalMes,
          sufixo: 'Tratinhos'),
      n('max_desconto_percentual', 'Desconto máximo por pedido', c.maxDescontoPercentual, sufixo: '%'),
      n('validade_dias', 'Validade dos Tratinhos', c.validadeDias, sufixo: 'dias'),
      r('orcamento_mensal_desconto_centavos', 'Orçamento mensal de desconto', c.orcamentoMensalDescontoCentavos),
      n('aviso_percentual', 'Avisar quando o uso chegar a', c.avisoPercentual, sufixo: '%'),
      r('teto_desconto_cliente_mes_centavos', 'Teto de desconto por cliente no mês', c.tetoDescontoClienteMesCentavos),
      r('teto_diario_desconto_centavos', 'Teto de desconto por dia', c.tetoDiarioDescontoCentavos),
      n('dias_liberacao_bonus', 'Dias até liberar o bônus', c.diasLiberacaoBonus, sufixo: 'dias'),
    ];
    return {for (final c in lista) c.chave: c};
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.texto.dispose();
    }
    super.dispose();
  }

  bool get _valido => _campos.values.every((c) => c.valor != null);

  MoedasConfig _montarConfig() {
    int v(String chave) => _campos[chave]!.valor!;
    return MoedasConfig(
      ativo: _ativo,
      bonusAvaliacaoMoedas: v('bonus_avaliacao_moedas'),
      valorMoedaCentavos: v('valor_moeda_centavos'),
      tetoMensalMoedas: v('teto_mensal_moedas'),
      minServicoCentavos: v('min_servico_centavos'),
      maxBonusPorProfissionalMes: v('max_bonus_por_profissional_mes'),
      maxDescontoPercentual: v('max_desconto_percentual'),
      validadeDias: v('validade_dias'),
      orcamentoMensalDescontoCentavos: v('orcamento_mensal_desconto_centavos'),
      avisoPercentual: v('aviso_percentual'),
      tetoDescontoClienteMesCentavos: v('teto_desconto_cliente_mes_centavos'),
      tetoDiarioDescontoCentavos: v('teto_diario_desconto_centavos'),
      diasLiberacaoBonus: v('dias_liberacao_bonus'),
    );
  }

  Widget _campo(_CampoConfig c) {
    final invalido = c.texto.text.trim().isNotEmpty && c.valor == null;
    return TextField(
      key: ValueKey('moedas-campo-${c.chave}'),
      controller: c.texto,
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: c.rotulo,
        prefixText: c.reais ? 'R\$ ' : null,
        suffixText: c.sufixo,
        helperText: c.ajuda,
        errorText: invalido ? (c.reais ? 'Informe um valor em reais' : 'Informe um número inteiro') : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CartaoSecao(
      titulo: 'Configuração do programa',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Programa de Tratinhos ativo', style: TipografiaTrato.corpoForte),
                    Text(
                      _ativo ? 'Ativo: os Tratinhos são ganhos e usados.' : 'Desligado: ninguém ganha nem usa Tratinhos.',
                      style: TipografiaTrato.legenda,
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Programa de Tratinhos ativo',
                child: Switch(
                  key: const ValueKey('moedas-ativo'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          LayoutBuilder(builder: (context, c) {
            final colunas = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
            final largura = (c.maxWidth - EspacosTrato.x4 * (colunas - 1)) / colunas;
            return Wrap(
              spacing: EspacosTrato.x4,
              runSpacing: EspacosTrato.x4,
              children: [for (final campo in _campos.values) SizedBox(width: largura, child: _campo(campo))],
            );
          }),
          const SizedBox(height: EspacosTrato.x4),
          Align(
            alignment: Alignment.centerRight,
            child: BotaoTrato.primario(
              'Salvar configuração',
              aoPressionar: _valido ? () => widget.aoSalvar(_montarConfig()) : null,
            ),
          ),
        ],
      ),
    );
  }
}
