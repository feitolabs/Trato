import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import 'avatar_iniciais.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';
import 'perfil_profissional_tela.dart';

enum _Filtro {
  verificado('Verificado'),
  nota('Nota 4,5+'),
  distancia('Até 5 km'),
  hoje('Atende hoje');

  const _Filtro(this.rotulo);

  final String rotulo;

  bool aceita(Profissional p) => switch (this) {
        _Filtro.verificado => p.verificacao.startsWith('Verificado'),
        _Filtro.nota => p.nota >= 4.5,
        _Filtro.distancia => p.distanciaKm <= 5,
        _Filtro.hoje => p.atendeHoje,
      };
}

/// Tela 9 do protótipo: Buscar. Os filtros agem sobre os dados de exemplo; a busca por texto
/// e o mapa dependem do backend.
class BuscarTela extends StatefulWidget {
  const BuscarTela({super.key});

  @override
  State<BuscarTela> createState() => _BuscarTelaState();
}

class _BuscarTelaState extends State<BuscarTela> {
  final _busca = TextEditingController(text: 'eletricista');
  final _ativos = <_Filtro>{_Filtro.verificado};
  var _mapa = false;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _abrirPerfil(Profissional p) {
    final tela = p.detalhe == null
        ? EmBreveTela(titulo: 'Perfil de ${p.nome}')
        : PerfilProfissionalTela(profissional: p);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context) {
    final resultado = [
      for (final p in profissionais)
        if (_ativos.every((f) => f.aceita(p))) p,
    ];
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: EspacosTrato.x4),
                Text('Buscar', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x4),
                TextField(
                  controller: _busca,
                  style: TipografiaTrato.corpo,
                  decoration: const InputDecoration(
                    hintText: 'Serviço ou profissional',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: EspacosTrato.x4),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final f in _Filtro.values)
                      _ChipFiltro(
                        texto: f.rotulo,
                        ativo: _ativos.contains(f),
                        aoTocar: () => setState(
                          () => _ativos.contains(f) ? _ativos.remove(f) : _ativos.add(f),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${resultado.length} ${resultado.length == 1 ? 'profissional' : 'profissionais'}'
                        ' perto de $bairroDaBusca',
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: CoresTrato.textoSecundario),
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x2),
                    _AlternaListaMapa(mapa: _mapa, aoMudar: (m) => setState(() => _mapa = m)),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x3),
                if (_mapa)
                  const _MapaReservado()
                else
                  for (final p in resultado) ...[
                    _CartaoProfissional(profissional: p, aoTocar: () => _abrirPerfil(p)),
                    const SizedBox(height: EspacosTrato.x3),
                  ],
                const SizedBox(height: EspacosTrato.x1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  const _ChipFiltro({required this.texto, required this.ativo, required this.aoTocar});

  final String texto;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativo,
      child: Material(
        color: ativo ? CoresTrato.petroleo : CoresTrato.superficie,
        shape: StadiumBorder(
          side: BorderSide(color: ativo ? CoresTrato.petroleo : CoresTrato.borda),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x4,
              vertical: EspacosTrato.x3,
            ),
            child: Text(
              texto,
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: ativo ? CoresTrato.creme : CoresTrato.petroleo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlternaListaMapa extends StatelessWidget {
  const _AlternaListaMapa({required this.mapa, required this.aoMudar});

  final bool mapa;
  final ValueChanged<bool> aoMudar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const ShapeDecoration(
        color: CoresTrato.superficie,
        shape: StadiumBorder(side: BorderSide(color: CoresTrato.borda)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segmento(texto: 'Lista', ativo: !mapa, aoTocar: () => aoMudar(false)),
          _Segmento(texto: 'Mapa', ativo: mapa, aoTocar: () => aoMudar(true)),
        ],
      ),
    );
  }
}

class _Segmento extends StatelessWidget {
  const _Segmento({required this.texto, required this.ativo, required this.aoTocar});

  final String texto;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativo,
      child: Material(
        color: ativo ? CoresTrato.petroleo : CoresTrato.superficie,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x4,
              vertical: EspacosTrato.x2,
            ),
            child: Text(
              texto,
              style: TipografiaTrato.corpoPequeno.copyWith(
                color: ativo ? CoresTrato.creme : CoresTrato.petroleo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Espaço do mapa. O mapa de verdade vem depois (precisa de pacote e chave de API).
class _MapaReservado extends StatelessWidget {
  const _MapaReservado();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CoresTrato.azulSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, size: 40, color: CoresTrato.azulTexto),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            'Mapa em breve',
            style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.azulTexto),
          ),
        ],
      ),
    );
  }
}

class _CartaoProfissional extends StatelessWidget {
  const _CartaoProfissional({required this.profissional, required this.aoTocar});

  final Profissional profissional;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    final detalhes = [
      p.especialidade,
      '${p.servicosConcluidos} serviços',
      if (p.respostaCurta != null) p.respostaCurta!,
    ].join(' · ');
    return Semantics(
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AvatarIniciais(iniciais: p.iniciais),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nome, style: TipografiaTrato.tituloCartao),
                      const SizedBox(height: EspacosTrato.x1),
                      SeloVerificacao(p.verificacao),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        detalhes,
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: EspacosTrato.x3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatarNota(p.nota), style: TipografiaTrato.tituloCartao),
                    const SizedBox(height: EspacosTrato.x1),
                    Text(
                      formatarDistancia(p.distanciaKm),
                      style:
                          TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
