import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Gestão da equipe e acessos (RF-EQP-01 a RF-EQP-04).
class EquipeTela extends StatefulWidget {
  const EquipeTela({super.key});

  @override
  State<EquipeTela> createState() => _EquipeTelaState();
}

class _EquipeTelaState extends State<EquipeTela> {
  int _versao = 0;

  static (String, Tom) status(MembroEquipeAdmin m) => switch (m.status) {
        'revogado' => ('Revogado', Tom.neutro),
        'convite_enviado' => ('Convite enviado', Tom.info),
        _ => ('Ativo', Tom.ok),
      };

  static String alcada(int centavos) => centavos > 0 ? formatarReais(centavos) : 'Sem alçada financeira';

  /// "Hoje, 14:20", "Ontem, 18:02", "01/11/2026" ou "Nunca acessou".
  static String ultimoAcesso(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return 'Nunca acessou';
    final hoje = DateTime.now();
    String hm() => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final dias = DateTime(hoje.year, hoje.month, hoje.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (dias == 0) return 'Hoje, ${hm()}';
    if (dias == 1) return 'Ontem, ${hm()}';
    return formatarDia(d);
  }

  Future<void> _conceder(List<MembroEquipeAdmin> existentes) async {
    final api = context.api;
    final tetos = await api.tetosDosPapeis().catchError((_) => <String, int>{});
    if (!mounted) return;
    final nome = TextEditingController();
    final email = TextEditingController();
    final alcadaCtrl = TextEditingController();
    var papel = Papel.atendenteN1.codigo;

    String? erroEmail() {
      final e = email.text.trim().toLowerCase();
      if (e.isEmpty) return null;
      if (!e.contains('@') || !e.contains('.')) return 'Informe um e-mail válido';
      if (existentes.any((m) => m.email.toLowerCase() == e && m.ativo)) {
        return 'Este e-mail já tem acesso. Edite o colaborador existente.';
      }
      return null;
    }

    int teto() => tetos[papel] ?? 0;
    int? alcadaDigitada() => alcadaCtrl.text.trim().isEmpty ? 0 : lerReaisEmCentavos(alcadaCtrl.text);
    String? erroAlcada() {
      final v = alcadaDigitada();
      if (v == null) return 'Informe um valor em reais';
      if (v > teto()) return 'Passa do teto do papel (${formatarReais(teto())})';
      return null;
    }

    final r = await pedirFormulario<Map<String, Object>>(
      context,
      titulo: 'Conceder acesso',
      consequencia: 'A pessoa precisa já ter conta no Trato. Você não pode dar papel ou alçada maiores que os seus.',
      rotuloConfirmar: 'Conceder acesso',
      campos: (ctx, rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: nome, onChanged: (_) => rebuild(), decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => rebuild(),
            decoration: InputDecoration(labelText: 'E-mail corporativo', errorText: erroEmail()),
          ),
          const SizedBox(height: EspacosTrato.x3),
          SeletorTrato<String>(
            rotulo: 'Papel',
            valor: papel,
            opcoes: [for (final p in Papel.values) (p.codigo, p.rotulo)],
            aoMudar: (v) {
              papel = v;
              rebuild();
            },
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: alcadaCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => rebuild(),
            decoration: InputDecoration(
              labelText: 'Alçada',
              prefixText: 'R\$ ',
              helperText: 'Teto do papel: ${formatarReais(teto())}. Vazio = sem alçada financeira.',
              errorText: erroAlcada(),
            ),
          ),
        ],
      ),
      camposValidos: () =>
          nome.text.trim().length >= 2 && email.text.trim().isNotEmpty && erroEmail() == null && erroAlcada() == null,
      resultado: (motivo) => {
        'nome': nome.text.trim(),
        'email': email.text.trim(),
        'papel': papel,
        'alcada': alcadaDigitada() ?? 0,
        'motivo': motivo,
      },
    );
    if (r == null || !mounted) return;
    final ok = await executar(
      context,
      () => api.adicionarMembroEquipe(
        nome: r['nome']! as String,
        email: r['email']! as String,
        papel: r['papel']! as String,
        alcadaCentavos: r['alcada']! as int,
        motivo: r['motivo']! as String,
      ),
      sucesso: 'Acesso concedido.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _editar(MembroEquipeAdmin m) async {
    final api = context.api;
    final tetos = await api.tetosDosPapeis().catchError((_) => <String, int>{});
    if (!mounted) return;
    var papel = m.papel;
    final alcadaCtrl = TextEditingController(text: m.alcadaCentavos == 0 ? '' : (m.alcadaCentavos / 100).toStringAsFixed(2).replaceAll('.', ','));
    int teto() => tetos[papel] ?? m.tetoPapelCentavos;
    int? alcadaDigitada() => alcadaCtrl.text.trim().isEmpty ? 0 : lerReaisEmCentavos(alcadaCtrl.text);
    String? erroAlcada() {
      final v = alcadaDigitada();
      if (v == null) return 'Informe um valor em reais';
      if (v > teto()) return 'Passa do teto do papel (${formatarReais(teto())})';
      return null;
    }

    final r = await pedirFormulario<Map<String, Object>>(
      context,
      titulo: 'Editar ${m.nome}',
      consequencia: 'A mudança vale na próxima ação da pessoa. O motivo fica registrado.',
      rotuloConfirmar: 'Salvar alterações',
      campos: (ctx, rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SeletorTrato<String>(
            rotulo: 'Papel',
            valor: papel,
            opcoes: [for (final p in Papel.values) (p.codigo, p.rotulo)],
            aoMudar: (v) {
              papel = v;
              rebuild();
            },
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: alcadaCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => rebuild(),
            decoration: InputDecoration(
              labelText: 'Alçada',
              prefixText: 'R\$ ',
              helperText: 'Teto do papel: ${formatarReais(teto())}',
              errorText: erroAlcada(),
            ),
          ),
        ],
      ),
      camposValidos: () =>
          erroAlcada() == null && (papel != m.papel || (alcadaDigitada() ?? 0) != m.alcadaCentavos),
      resultado: (motivo) => {'papel': papel, 'alcada': alcadaDigitada() ?? 0, 'motivo': motivo},
    );
    if (r == null || !mounted) return;
    final ok = await executar(
      context,
      () => api.editarMembroEquipe(
        m.usuarioId,
        papel: r['papel']! as String,
        alcadaCentavos: r['alcada']! as int,
        motivo: r['motivo']! as String,
      ),
      sucesso: 'Acesso atualizado.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _revogar(MembroEquipeAdmin m) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Revogar o acesso de ${m.nome}?',
      descricao: 'A pessoa perde o acesso ao painel na hora e as sessões abertas são encerradas.',
      rotuloConfirmar: 'Revogar acesso',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.revogarMembroEquipe(m.usuarioId, motivo: motivo),
      sucesso: 'Acesso revogado.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final podeGerenciar = context.pode(Permissao.equipeGerenciar);
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return CarregaDados<List<MembroEquipeAdmin>>(
      key: ValueKey('equipe-$_versao'),
      carregar: context.api.listarEquipe,
      construir: (context, lista, _) {
        final admins = lista.where((m) => m.papel == 'administrador' && m.ativo).toList();
        final unico = admins.length == 1 ? admins.first : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CabecalhoPagina(
              'Gestão da equipe',
              subtitulo: 'Cada pessoa tem um papel e uma alçada limitada ao teto do papel. Revogar encerra as sessões na hora.',
              acoes: [
                if (podeGerenciar)
                  BotaoTrato.primario('Conceder acesso', icone: IconesTrato.adicionar, aoPressionar: () => _conceder(lista)),
              ],
            ),
            if (unico != null)
              Padding(
                padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
                child: BannerInfo(
                  '${unico.nome} é o único Administrador ativo: não pode ser revogado nem rebaixado.',
                  tom: Tom.alerta,
                ),
              ),
            Expanded(
              child: ListaPaginada<MembroEquipeAdmin>(
                itens: lista,
                mensagemVazia: 'Nenhum colaborador cadastrado',
                detalheVazio: 'Conceda o primeiro acesso para a equipe começar a operar.',
                rotuloBusca: 'Buscar por nome ou e-mail',
                rotuloItens: 'colaboradores',
                textoBusca: (m) => '${m.nome} ${m.email}',
                filtros: [
                  FiltroLista<MembroEquipeAdmin>(
                    rotulo: 'Status',
                    opcoes: const [('ativo', 'Ativo'), ('convite_enviado', 'Convite enviado'), ('revogado', 'Revogado')],
                    aplica: (m, v) => m.status == v,
                  ),
                ],
                construirItem: (context, m) {
                  final (txt, tom) = status(m);
                  final papelRotulo = Papel.doCodigo(m.papel)?.rotulo ?? m.papel;
                  return CartaoLista(
                    tituloWidget: Wrap(
                      spacing: EspacosTrato.x2,
                      runSpacing: EspacosTrato.x1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(m.nome, style: TipografiaTrato.corpoForte),
                        ChipPapel(papelRotulo),
                        ChipEstado(txt, tom: tom),
                      ],
                    ),
                    titulo: m.nome,
                    linhas: [
                      m.email,
                      'Alçada ${alcada(m.alcadaCentavos)} · último acesso ${ultimoAcesso(m.ultimoAcesso).toLowerCase()}',
                    ],
                    acoes: [
                      if (podeGerenciar && m.ativo)
                        BotaoIcone(icone: IconesTrato.editar, rotulo: 'Editar ${m.nome}', aoPressionar: () => _editar(m)),
                      if (podeGerenciar && m.ativo && !(unico != null && unico.usuarioId == m.usuarioId))
                        BotaoTrato.destrutivo('Revogar', aoPressionar: () => _revogar(m)),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
