import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Barra fina de progresso no topo do cadastro em passos (1 de 4 até 4 de 4).
class BarraProgressoPassos extends StatelessWidget {
  const BarraProgressoPassos({
    super.key,
    required this.passoAtual,
    required this.totalPassos,
  });

  /// Índice 0-based do passo atual.
  final int passoAtual;
  final int totalPassos;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final atual = (passoAtual + 1).clamp(1, totalPassos);
    final progresso = atual / totalPassos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Etapa $atual de $totalPassos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
              ),
            ),
            const SizedBox(width: EspacosTrato.x2),
            Text(
              '$atual de $totalPassos',
              maxLines: 1,
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: c.petroleo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Semantics(
          label: 'Progresso do cadastro: $atual de $totalPassos',
          value: '${(progresso * 100).round()}%',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(end: progresso),
              builder: (context, valor, _) => LinearProgressIndicator(
                value: valor,
                minHeight: 4,
                backgroundColor: c.borda,
                valueColor: AlwaysStoppedAnimation<Color>(c.petroleo),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cabeçalho limpo de cada passo ou seção.
class CabecalhoPasso extends StatelessWidget {
  const CabecalhoPasso({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.destaque,
  });

  final String titulo;
  final String subtitulo;
  final String? destaque;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          subtitulo,
          style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
        ),
        if (destaque != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x3,
              vertical: EspacosTrato.x2,
            ),
            decoration: BoxDecoration(
              color: c.azulSuave,
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
            ),
            child: Text(
              destaque!,
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: c.azulTexto,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pílulas limpas de seleção compatíveis com tema claro e escuro.
class PilulasSelecao extends StatelessWidget {
  const PilulasSelecao({
    super.key,
    required this.opcoes,
    required this.selecionadas,
    required this.aoAlternar,
    this.travado = false,
  });

  final List<String> opcoes;
  final Set<String> selecionadas;
  final ValueChanged<String> aoAlternar;
  final bool travado;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Wrap(
      spacing: EspacosTrato.x2,
      runSpacing: EspacosTrato.x2,
      children: [
        for (final opcao in opcoes)
          _PilulaItem(
            rotulo: opcao,
            selecionada: selecionadas.contains(opcao),
            travado: travado,
            cores: c,
            aoTocar: travado ? null : () => aoAlternar(opcao),
          ),
      ],
    );
  }
}

class _PilulaItem extends StatelessWidget {
  const _PilulaItem({
    required this.rotulo,
    required this.selecionada,
    required this.travado,
    required this.cores,
    required this.aoTocar,
  });

  final String rotulo;
  final bool selecionada;
  final bool travado;
  final CoresTemaTrato cores;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final fundo = selecionada ? cores.petroleo : cores.superficie;
    final corTexto = selecionada ? cores.sobrePetroleo : cores.texto;
    final corBorda = selecionada ? cores.petroleo : cores.bordaControle;

    return Semantics(
      button: !travado,
      selected: selecionada,
      label: rotulo,
      child: Material(
        color: fundo,
        shape: StadiumBorder(
          side: BorderSide(
            color: corBorda,
            width: selecionada ? EspacosTrato.bordaControle : EspacosTrato.bordaFina,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x4,
              vertical: EspacosTrato.x2 + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selecionada) ...[
                  Icon(
                    travado ? Icons.lock_outline : Icons.check,
                    size: 16,
                    color: corTexto,
                  ),
                  const SizedBox(width: EspacosTrato.x1 + 2),
                ],
                Flexible(
                  child: Text(
                    rotulo,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: corTexto,
                      fontWeight: selecionada ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloco agrupado de disponibilidade (dias e períodos) em uma única superfície limpa.
class BlocoDisponibilidade extends StatelessWidget {
  const BlocoDisponibilidade({
    super.key,
    required this.dias,
    required this.diasSelecionados,
    required this.aoAlternarDia,
    required this.periodos,
    required this.periodosSelecionados,
    required this.aoAlternarPeriodo,
    this.erroDias,
    this.erroPeriodos,
  });

  final List<String> dias;
  final Set<String> diasSelecionados;
  final ValueChanged<String> aoAlternarDia;
  final List<String> periodos;
  final Set<String> periodosSelecionados;
  final ValueChanged<String> aoAlternarPeriodo;
  final String? erroDias;
  final String? erroPeriodos;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: c.borda, width: EspacosTrato.bordaFina),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disponibilidade',
            style: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Você pode mudar quando quiser.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x4),
          Text(
            'Dias da semana',
            style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
          ),
          const SizedBox(height: EspacosTrato.x2),
          PilulasSelecao(
            opcoes: dias,
            selecionadas: diasSelecionados,
            aoAlternar: aoAlternarDia,
          ),
          if (erroDias != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              erroDias!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
            child: Divider(height: 1, color: c.borda),
          ),
          Text(
            'Períodos',
            style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
          ),
          const SizedBox(height: EspacosTrato.x2),
          PilulasSelecao(
            opcoes: periodos,
            selecionadas: periodosSelecionados,
            aoAlternar: aoAlternarPeriodo,
          ),
          if (erroPeriodos != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              erroPeriodos!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grade limpa de fotos do portfólio com botão "+ Adicionar foto" integrado.
class GradePortfolio extends StatelessWidget {
  const GradePortfolio({
    super.key,
    required this.fotos,
    required this.urlsDasFotos,
    required this.aoRemover,
    required this.aoAdicionar,
  });

  final List<String> fotos;
  final Map<String, String> urlsDasFotos;
  final ValueChanged<int> aoRemover;
  final VoidCallback? aoAdicionar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: fotos.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: EspacosTrato.x3,
            mainAxisSpacing: EspacosTrato.x3,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            if (index == fotos.length) {
              return _BotaoAdicionarGrade(
                cores: c,
                aoTocar: aoAdicionar,
              );
            }
            final chave = fotos[index];
            return _MiniFotoGrade(
              numero: index + 1,
              referencia: urlsDasFotos[chave] ?? chave,
              cores: c,
              aoRemover: () => aoRemover(index),
            );
          },
        ),
        if (fotos.isEmpty) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Nenhuma foto adicionada ainda. Você também pode enviar depois pelo seu perfil.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
          ),
        ],
      ],
    );
  }
}

class _BotaoAdicionarGrade extends StatelessWidget {
  const _BotaoAdicionarGrade({
    required this.cores,
    required this.aoTocar,
  });

  final CoresTemaTrato cores;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final habilitado = aoTocar != null;
    final corConteudo = habilitado ? cores.petroleo : cores.textoDica;
    return Semantics(
      button: true,
      enabled: habilitado,
      label: 'Adicionar foto ao portfólio',
      child: Material(
        color: cores.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
          side: BorderSide(
            color: habilitado ? cores.bordaControle : cores.borda,
            width: EspacosTrato.bordaFina,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_outlined, size: 22, color: corConteudo),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  '+ Adicionar foto',
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.legenda.copyWith(
                    color: corConteudo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniFotoGrade extends StatelessWidget {
  const _MiniFotoGrade({
    required this.numero,
    required this.referencia,
    required this.cores,
    required this.aoRemover,
  });

  final int numero;
  final String referencia;
  final CoresTemaTrato cores;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    final imagemReal = construirImagemReal(referencia);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cores.azulSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        border: Border.all(color: cores.borda, width: EspacosTrato.bordaFina),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imagemReal != null)
            ToquePreviewImagem(
              referencia: referencia,
              legenda: 'Foto $numero',
              child: imagemReal,
            ),
          Center(
            child: Container(
              padding: imagemReal != null
                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                  : EdgeInsets.zero,
              decoration: imagemReal != null
                  ? BoxDecoration(
                      color: CoresTrato.overlayFoto,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                'Foto $numero',
                style: imagemReal != null
                    ? TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSobreFoto)
                    : TipografiaTrato.corpoPequeno.copyWith(color: cores.azulTexto),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: imagemReal != null ? CoresTrato.overlayFoto : cores.superficie,
              shape: const CircleBorder(),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Remover foto $numero',
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: imagemReal != null ? CoresTrato.textoSobreFoto : cores.texto,
                ),
                onPressed: aoRemover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Item de resumo de seção no modo edição.
class ResumoSecaoCadastro {
  const ResumoSecaoCadastro({
    required this.titulo,
    required this.resumo,
    required this.icone,
    required this.aoTocar,
    this.pendente = false,
  });

  final String titulo;
  final String resumo;
  final IconData icone;
  final VoidCallback aoTocar;
  final bool pendente;
}

/// Lista limpa com as 4 seções tocáveis do modo edição em uma única superfície.
class ListaSecoesEdicao extends StatelessWidget {
  const ListaSecoesEdicao({
    super.key,
    required this.secoes,
  });

  final List<ResumoSecaoCadastro> secoes;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Container(
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: c.borda, width: EspacosTrato.bordaFina),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < secoes.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: EspacosTrato.x4,
                endIndent: EspacosTrato.x4,
                color: c.borda,
              ),
            _LinhaSecaoEdicao(secao: secoes[i], cores: c),
          ],
        ],
      ),
    );
  }
}

class _LinhaSecaoEdicao extends StatelessWidget {
  const _LinhaSecaoEdicao({
    required this.secao,
    required this.cores,
  });

  final ResumoSecaoCadastro secao;
  final CoresTemaTrato cores;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: secao.aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x4,
            vertical: EspacosTrato.x4,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: secao.pendente ? cores.vermelhoSuave : cores.azulSuave,
                  borderRadius: BorderRadius.circular(EspacosTrato.raio),
                ),
                child: Icon(
                  secao.icone,
                  size: 20,
                  color: secao.pendente ? cores.vermelhoTexto : cores.azulTexto,
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secao.titulo,
                      style: TipografiaTrato.corpoForte.copyWith(color: cores.texto),
                    ),
                    const SizedBox(height: EspacosTrato.x1),
                    Text(
                      secao.resumo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TipografiaTrato.corpoPequeno.copyWith(
                        color: secao.pendente ? cores.vermelhoTexto : cores.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Icon(Icons.chevron_right, color: cores.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}
