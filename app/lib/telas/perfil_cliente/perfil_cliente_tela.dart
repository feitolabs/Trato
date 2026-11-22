import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../comuns/desconto_moedas.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho;
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import '../comuns/moeda_trato.dart';
import '../profissional/dinheiro.dart';
import 'extrato_tratinhos_tela.dart';
import 'modelos.dart';

/// Tela 22 — Perfil do cliente. Cada item avisa [aoTocarItem]; "Usar como profissional"
/// é o item [AcaoPerfil.usarComoProfissional]. A barra inferior é da casca do app.
class PerfilClienteTela extends StatefulWidget {
  const PerfilClienteTela({
    super.key,
    required this.perfil,
    this.aoTocarItem,
    this.aoAbrirConfiguracoes,
    this.aoCapturarFotoPerfil,
    this.aoCancelarExclusao,
    this.aoAbrirTratinhos,
  });

  final PerfilCliente perfil;
  final VoidCallback? aoAbrirTratinhos;
  final ValueChanged<AcaoPerfil>? aoTocarItem;

  /// Abre as configurações; a engrenagem só aparece se vier.
  final VoidCallback? aoAbrirConfiguracoes;
  final Future<String?> Function()? aoCapturarFotoPerfil;
  final Future<bool> Function()? aoCancelarExclusao;

  /// Limpa a foto guardada em memória ao encerrar a sessão.
  static void limparFotoSessao() => _PerfilClienteTelaState._fotoSalvaSessao = null;

  @override
  State<PerfilClienteTela> createState() => _PerfilClienteTelaState();
}

class _PerfilClienteTelaState extends State<PerfilClienteTela> {
  static String? _fotoSalvaSessao;
  String? _fotoAtual;
  var _exclusaoCancelada = false;
  var _cancelandoExclusao = false;

  @override
  void initState() {
    super.initState();
    _fotoAtual = widget.perfil.fotoReferencia ?? _fotoSalvaSessao;
  }

  Future<void> _tocarAvatar() async {
    final capturar = widget.aoCapturarFotoPerfil;
    if (capturar == null) return;
    final temFoto = _fotoAtual != null && _fotoAtual!.isNotEmpty;
    if (temFoto) {
      final c = context.cores;
      final acao = await showModalBottomSheet<String>(
        context: context,
        builder: (folha) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.zoom_in, color: c.petroleo),
                title: const Text('Ver foto de perfil'),
                onTap: () => Navigator.of(folha).pop('ver'),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: c.petroleo),
                title: const Text('Trocar foto de perfil'),
                onTap: () => Navigator.of(folha).pop('trocar'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || acao == null) return;
      if (acao == 'ver') {
        await abrirPreviewImagem(
          context,
          referencia: _fotoAtual!,
          legenda: widget.perfil.nome,
        );
        return;
      }
    }
    final nova = await capturar();
    if (nova != null && mounted) {
      setState(() {
        _fotoAtual = nova;
        _fotoSalvaSessao = nova;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final perfil = widget.perfil;
    final recarregar = AtualizadorTela.de(context);
    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        top: EspacosTrato.x6,
        bottom: BarraAbasFlutuante.alturaReservada + EspacosTrato.x6,
      ),
      children: [
        Row(
          children: [
            AvatarIniciais(
              iniciais: perfil.iniciais,
              tamanho: 72,
              fotoReferencia: _fotoAtual,
              aoTocar: widget.aoCapturarFotoPerfil == null ? null : _tocarAvatar,
            ),
            const SizedBox(width: EspacosTrato.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    perfil.nome,
                    style: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    perfil.resumo,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: c.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.aoAbrirConfiguracoes != null)
              IconButton(
                tooltip: 'Configurações',
                icon: Icon(Icons.settings_outlined, color: c.petroleo),
                onPressed: widget.aoAbrirConfiguracoes,
              ),
          ],
        ),
        if (perfil.exclusaoAgendadaEm != null && !_exclusaoCancelada) ...[
          const SizedBox(height: EspacosTrato.x4),
          AvisoFaixa(
            key: const ValueKey('aviso-exclusao-agendada'),
            texto:
                'Exclusão da conta agendada para ${diaMesDoAparelho(perfil.exclusaoAgendadaEm!)}. '
                'Você pode cancelar antes desse prazo.',
            tipo: TipoStatus.alerta,
            icone: Icons.schedule,
          ),
          if (widget.aoCancelarExclusao != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            BotaoSecundario(
              key: const ValueKey('botao-cancelar-exclusao'),
              texto: _cancelandoExclusao ? 'Cancelando...' : 'Cancelar exclusão',
              aoTocar: _cancelandoExclusao
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _cancelandoExclusao = true);
                      final ok = await widget.aoCancelarExclusao!();
                      if (!mounted) return;
                      setState(() {
                        _cancelandoExclusao = false;
                        if (ok) _exclusaoCancelada = true;
                      });
                      if (ok) {
                        messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Exclusão cancelada. Sua conta continua ativa.'),
                            ),
                          );
                      }
                    },
            ),
          ],
        ],
        if ((perfil.moedas ?? 0) > 0 ||
            perfil.moedasPendentes > 0 ||
            perfil.moedasExtrato.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x5),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const ValueKey('cartao-seus-tratinhos'),
              leading: const MoedaTrato(tamanho: 32),
              title: const Text('Seus Tratinhos'),
              subtitle: perfil.moedasValorCentavos == null
                  ? null
                  : Text(
                      textoTratinhosEmReais(
                        perfil.moedas ?? 0,
                        perfil.moedasValorCentavos,
                      ),
                      key: const Key('moedas-em-reais'),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${perfil.moedas ?? 0}',
                    style: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
                  ),
                  const SizedBox(width: EspacosTrato.x1),
                  Icon(Icons.chevron_right, color: c.textoSecundario),
                ],
              ),
              onTap: widget.aoAbrirTratinhos ??
                  () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExtratoTratinhosTela(perfil: perfil),
                        ),
                      ),
            ),
          ),
          if (perfil.moedasPendentes > 0) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              textoTratinhosPendentes(
                perfil.moedasPendentes,
                perfil.moedasProximaLiberacao,
                perfil.moedasValorCentavos,
              )!,
              key: const Key('moedas-pendentes'),
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: c.textoSecundario,
              ),
            ),
          ],
          if (perfil.moedasVenceEm != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'Tratinhos vencem em ${formatarDiaMes(perfil.moedasVenceEm!)}',
              key: const Key('moedas-vencem'),
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: c.textoSecundario,
              ),
            ),
          ],
          if (perfil.descontoUsadoMesCentavos != null &&
              perfil.tetoDescontoMesCentavos != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'Desconto usado no mês: ${Dinheiro.formatar(perfil.descontoUsadoMesCentavos!)} '
              'de ${Dinheiro.formatar(perfil.tetoDescontoMesCentavos!)}',
              key: const Key('moedas-desconto-mes'),
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: c.textoSecundario,
              ),
            ),
          ],
          if (!perfil.moedasDescontoDisponivel) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              mensagemDescontoIndisponivel(
                perfil.moedasDescontoMotivo,
                voltaEm: perfil.moedasDescontoVoltaEm,
              ),
              key: const Key('moedas-desconto-indisponivel'),
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: c.textoSecundario,
              ),
            ),
          ],
        ],
        for (final grupo in perfil.grupos) ...[
          const SizedBox(height: EspacosTrato.x5),
          Text(
            grupo.titulo,
            style: TipografiaTrato.sobretitulo.copyWith(color: c.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x3),
          _CartaoGrupo(grupo: grupo, aoTocar: widget.aoTocarItem),
        ],
        const SizedBox(height: EspacosTrato.x6),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LogoFeitoLabs(tamanho: 28, sobreFundoClaro: true),
                    const SizedBox(width: EspacosTrato.x2),
                    Flexible(
                      child: Text(
                        'um app Feito Labs',
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: c.textoSecundario,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ConteudoResponsivo(
          child: recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista),
        ),
      ),
    );
  }
}

class _CartaoGrupo extends StatelessWidget {
  const _CartaoGrupo({required this.grupo, required this.aoTocar});

  final GrupoPerfil grupo;
  final ValueChanged<AcaoPerfil>? aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < grupo.itens.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: EspacosTrato.x4,
                endIndent: EspacosTrato.x4,
                color: c.borda,
              ),
            _LinhaItem(item: grupo.itens[i], aoTocar: () => aoTocar?.call(grupo.itens[i].acao)),
          ],
        ],
      ),
    );
  }
}

class _LinhaItem extends StatelessWidget {
  const _LinhaItem({required this.item, required this.aoTocar});

  final ItemPerfil item;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: EspacosTrato.x4,
          vertical: (EspacosTrato.alturaLinhaLista - 24) / 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.titulo,
                style: TipografiaTrato.corpo.copyWith(color: c.texto),
              ),
            ),
            if (item.valor != null) ...[
              const SizedBox(width: EspacosTrato.x2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  item.valor!,
                  textAlign: TextAlign.end,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                ),
              ),
            ],
            const SizedBox(width: EspacosTrato.x2),
            Icon(Icons.chevron_right, color: c.petroleo),
          ],
        ),
      ),
    );
  }
}
