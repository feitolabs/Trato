import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.1 — fila de verificação de profissionais.
class VerificacaoTela extends StatelessWidget {
  const VerificacaoTela({super.key});

  static (String, Tom) _chip(StatusVerificacao s) => switch (s) {
        StatusVerificacao.enviada => ('Enviada', Tom.info),
        StatusVerificacao.emAnalise => ('Em análise', Tom.alerta),
        StatusVerificacao.aprovada => ('Aprovada', Tom.ok),
        StatusVerificacao.recusada => ('Recusada', Tom.erro),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CabecalhoPagina('Verificação de profissionais', subtitulo: 'Fila de cadastros para análise'),
        Expanded(
          child: CarregaDados<List<Verificacao>>(
            carregar: context.api.listarVerificacoes,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhum cadastro esperando análise.',
            construir: (context, lista, recarregar) => MestreDetalhe<Verificacao>(
              itens: lista,
              tituloDetalhe: (v) => v.profissional,
              itemBuilder: (context, v, sel) {
                final (texto, tom) = _chip(v.status);
                return CartaoItem(
                  titulo: v.profissional,
                  linhas: [[v.categoria, v.cidade].where((t) => t.isNotEmpty).join(' · '), 'Enviada em ${formatarData(v.enviadaEm)}'],
                  chip: ChipEstado(texto, tom: tom),
                  selecionado: sel,
                );
              },
              detalheBuilder: (context, v) =>
                  DetalheVerificacao(key: ValueKey(v.id), verificacao: v, aoMudar: recarregar),
            ),
          ),
        ),
      ],
    );
  }
}

class DetalheVerificacao extends StatefulWidget {
  const DetalheVerificacao({super.key, required this.verificacao, required this.aoMudar});

  final Verificacao verificacao;
  final Future<void> Function() aoMudar;

  @override
  State<DetalheVerificacao> createState() => _DetalheVerificacaoState();
}

class _DetalheVerificacaoState extends State<DetalheVerificacao> {
  final _reveladas = <String>{};

  Future<void> _revelar(String documento) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Ver $documento',
      descricao: 'O arquivo fica escondido por padrão. Ao abrir, a visualização é gravada.',
      rotuloConfirmar: 'Revelar',
    );
    if (motivo == null || !mounted) return;
    String? url;
    final ok = await executar(context, () async {
      url = await api.revelarDocumento(widget.verificacao.id, documento, motivo);
    });
    if (!ok || !mounted) return;
    setState(() => _reveladas.add(documento));
    // A URL assinada vale poucos segundos e abre em outra aba; nunca é mostrada nem guardada.
    final aberta = url;
    if (aberta != null) await launchUrl(Uri.parse(aberta), webOnlyWindowName: '_blank');
  }

  Future<void> _decidir(bool aprovar) async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: aprovar ? 'Aprovar profissional' : 'Recusar profissional',
      descricao: aprovar
          ? 'O profissional passa a receber pedidos da categoria.'
          : 'O profissional recebe o motivo da recusa e pode enviar de novo.',
      rotuloConfirmar: aprovar ? 'Aprovar' : 'Recusar',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => api.decidirVerificacao(widget.verificacao.id, aprovar: aprovar, motivo: motivo),
      sucesso: aprovar ? 'Profissional aprovado.' : 'Profissional recusado.',
    );
    if (ok) await widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verificacao;
    final decidida = v.status == StatusVerificacao.aprovada || v.status == StatusVerificacao.recusada;
    final podeRevelar = context.pode(Permissao.documentosRevelar);
    final podeDecidir = context.pode(Permissao.verificacoesDecidir) && !decidida;
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(v.profissional, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Categoria', v.categoria),
        if (v.cidade.isNotEmpty) Linha('Cidade', v.cidade),
        Linha('CPF', v.cpfMascarado),
        Linha('Enviada em', formatarData(v.enviadaEm)),
        if (v.motivoDecisao != null) Linha('Motivo da decisão', v.motivoDecisao!),
        const SizedBox(height: EspacosTrato.x4),
        Text('Documentos e selfie', style: TipografiaTrato.tituloCartao),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x3,
          runSpacing: EspacosTrato.x3,
          children: [
            for (final doc in v.documentos)
              _ArquivoMascarado(
                rotulo: doc,
                revelado: _reveladas.contains(doc),
                aoRevelar: podeRevelar ? () => _revelar(doc) : null,
              ),
          ],
        ),
        if (!podeRevelar) ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo('Seu papel não abre documentos. Quem analisa é o time de cadastro.'),
        ],
        if (podeDecidir) ...[
          const SizedBox(height: EspacosTrato.x6),
          const AvisoAuditoria(),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _decidir(false), child: const Text('Recusar')),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: FilledButton(onPressed: () => _decidir(true), child: const Text('Aprovar'))),
            ],
          ),
        ],
      ],
    );
  }
}

class _ArquivoMascarado extends StatelessWidget {
  const _ArquivoMascarado({required this.rotulo, required this.revelado, required this.aoRevelar});

  final String rotulo;
  final bool revelado;
  final VoidCallback? aoRevelar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(
        color: CoresTrato.superficie,
        border: Border.all(color: CoresTrato.borda),
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Column(
        children: [
          Container(
            height: 110,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: revelado ? CoresTrato.verdeSuave : CoresTrato.azulSuave,
              borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
            ),
            child: Icon(
              revelado ? Icons.image_outlined : Icons.lock_outline,
              size: 36,
              color: revelado ? CoresTrato.verdeTexto : CoresTrato.azulTexto,
            ),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(rotulo, style: TipografiaTrato.corpoPequeno),
          Text(revelado ? 'Aberto nesta sessão' : 'Escondido', style: TipografiaTrato.legenda),
          if (!revelado && aoRevelar != null)
            TextButton(onPressed: aoRevelar, child: const Text('Revelar')),
        ],
      ),
    );
  }
}
