import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../auth/estrutura_auth.dart';
import 'dinheiro.dart';
import 'servico_orcamento.dart';

class ItemMaterial {
  const ItemMaterial({required this.nome, required this.centavos});

  final String nome;
  final int centavos;
}

/// O que a tela entrega ao tocar em "Enviar orçamento". O total é só soma para exibir;
/// quem confere e grava é o backend.
class OrcamentoPronto {
  const OrcamentoPronto({
    required this.deslocamentoCentavos,
    required this.decimosDeHora,
    required this.valorHoraCentavos,
    required this.garantiaDias,
    required this.itens,
    required this.materialPorMim,
    required this.pedirSinalMaterial,
    required this.totalCentavos,
  });

  final int deslocamentoCentavos;
  final int decimosDeHora;
  final int valorHoraCentavos;
  final int garantiaDias;
  final List<ItemMaterial> itens;
  final bool materialPorMim;
  final bool pedirSinalMaterial;
  final int totalCentavos;
}

/// Tela 25: "Seu orçamento". Soma deslocamento + horas x valor + material (só para exibir).
/// Taxa e líquido NÃO são calculados aqui: vêm de [servico] (regra de dinheiro é do backend).
class CalculadoraOrcamentoTela extends StatefulWidget {
  const CalculadoraOrcamentoTela({
    super.key,
    required this.servico,
    required this.tituloPedido,
    this.aoEnviar,
    this.deslocamentoInicial,
    this.horasInicial,
    this.valorHoraInicial,
    this.garantiaInicialDias = 90,
    this.itensIniciais = const [],
    this.faixaRegiaoCentavos,
    this.opcoesGarantiaDias = const [30, 60, 90],
    this.validadeDias = 3,
  });

  final ServicoOrcamento servico;
  final String tituloPedido;
  final ValueChanged<OrcamentoPronto>? aoEnviar;
  final String? deslocamentoInicial;
  final String? horasInicial;
  final String? valorHoraInicial;
  final int garantiaInicialDias;
  final List<ItemMaterial> itensIniciais;

  /// "Serviços parecidos na região" (mínimo, máximo), vindo do backend. Sem dado, a linha some.
  final (int, int)? faixaRegiaoCentavos;

  /// Opções de garantia e validade do orçamento: configuração, não número fixo da tela.
  final List<int> opcoesGarantiaDias;
  final int validadeDias;

  @override
  State<CalculadoraOrcamentoTela> createState() => _CalculadoraOrcamentoTelaState();
}

class _CalculadoraOrcamentoTelaState extends State<CalculadoraOrcamentoTela> {
  late final _deslocamento = TextEditingController(text: widget.deslocamentoInicial);
  late final _horas = TextEditingController(text: widget.horasInicial);
  late final _valorHora = TextEditingController(text: widget.valorHoraInicial);
  late int _garantia = widget.garantiaInicialDias;
  late final List<ItemMaterial> _itens = [...widget.itensIniciais];
  bool _materialPorMim = true;
  bool _pedirSinal = false;
  bool _mostrarErros = false;

  ResumoOrcamento? _resumo;
  int _ultimoPedido = -1;

  static final _somenteNumero = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

  @override
  void initState() {
    super.initState();
    _atualizarResumo();
  }

  @override
  void dispose() {
    _deslocamento.dispose();
    _horas.dispose();
    _valorHora.dispose();
    super.dispose();
  }

  int get _materialCentavos =>
      _materialPorMim ? _itens.fold(0, (soma, item) => soma + item.centavos) : 0;

  int get _total {
    final desloc =
        _deslocamento.text.trim().isEmpty ? 0 : (Dinheiro.lerCentavos(_deslocamento.text) ?? 0);
    final decimos = Dinheiro.lerDecimosDeHora(_horas.text) ?? 0;
    final valorHora = Dinheiro.lerCentavos(_valorHora.text) ?? 0;
    return desloc + Dinheiro.valorDasHoras(valorHora, decimos) + _materialCentavos;
  }

  void _mudou() {
    setState(() {});
    _atualizarResumo();
  }

  Future<void> _atualizarResumo() async {
    final total = _total;
    if (total <= 0) {
      _ultimoPedido = -1;
      if (_resumo != null) setState(() => _resumo = null);
      return;
    }
    if (total == _ultimoPedido) return;
    _ultimoPedido = total;
    final resumo = await widget.servico.resumir(total);
    // Resposta atrasada de um total antigo não pode sobrescrever o atual.
    if (mounted && _ultimoPedido == total) setState(() => _resumo = resumo);
  }

  String? _erroDeslocamento() {
    final texto = _deslocamento.text.trim();
    if (texto.isEmpty) return null;
    return Dinheiro.lerCentavos(texto) == null ? 'Use só números, como 30 ou 30,50.' : null;
  }

  String? _erroHoras() {
    final decimos = Dinheiro.lerDecimosDeHora(_horas.text);
    return (decimos == null || decimos <= 0) ? 'Informe as horas, como 3 ou 2,5.' : null;
  }

  String? _erroValorHora() {
    final valor = Dinheiro.lerCentavos(_valorHora.text);
    return (valor == null || valor <= 0) ? 'Informe o valor da hora.' : null;
  }

  Future<void> _adicionarItem() async {
    final item = await showModalBottomSheet<ItemMaterial>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CoresTrato.creme,
      builder: (_) => const _NovoItemMaterial(),
    );
    if (item == null) return;
    _itens.add(item);
    _mudou();
  }

  void _enviar() {
    setState(() => _mostrarErros = true);
    if (_erroDeslocamento() != null || _erroHoras() != null || _erroValorHora() != null) {
      return;
    }
    final desloc =
        _deslocamento.text.trim().isEmpty ? 0 : Dinheiro.lerCentavos(_deslocamento.text)!;
    widget.aoEnviar?.call(
      OrcamentoPronto(
        deslocamentoCentavos: desloc,
        decimosDeHora: Dinheiro.lerDecimosDeHora(_horas.text)!,
        valorHoraCentavos: Dinheiro.lerCentavos(_valorHora.text)!,
        garantiaDias: _garantia,
        itens: List.unmodifiable(_itens),
        materialPorMim: _materialPorMim,
        pedirSinalMaterial: _materialPorMim && _pedirSinal,
        totalCentavos: _total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final faixa = widget.faixaRegiaoCentavos;
    return EstruturaAuth(
      tituloBarra: widget.tituloPedido,
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotaoPrimario(texto: 'Enviar orçamento', aoTocar: _enviar),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Válido por ${widget.validadeDias} dias · você pode editar até o cliente aceitar',
            style: TipografiaTrato.legenda,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      children: [
        Text('Seu orçamento', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CampoTrato(
                rotulo: 'Deslocamento',
                controlador: _deslocamento,
                prefixo: 'R\$ ',
                teclado: TextInputType.number,
                formatadores: _somenteNumero,
                aoMudar: (_) => _mudou(),
                erro: _mostrarErros ? _erroDeslocamento() : null,
              ),
            ),
            const SizedBox(width: EspacosTrato.x4),
            Expanded(
              child: CampoTrato(
                rotulo: 'Horas',
                controlador: _horas,
                sufixo: 'h',
                teclado: TextInputType.number,
                formatadores: _somenteNumero,
                aoMudar: (_) => _mudou(),
                erro: _mostrarErros ? _erroHoras() : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CampoTrato(
                rotulo: 'Valor da hora',
                controlador: _valorHora,
                prefixo: 'R\$ ',
                teclado: TextInputType.number,
                formatadores: _somenteNumero,
                aoMudar: (_) => _mudou(),
                erro: _mostrarErros ? _erroValorHora() : null,
              ),
            ),
            const SizedBox(width: EspacosTrato.x4),
            Expanded(
                child: _CampoGarantia(
              valor: _garantia,
              opcoes: widget.opcoesGarantiaDias,
              aoMudar: (dias) => setState(() => _garantia = dias),
            )),
          ],
        ),
        if (faixa != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Serviços parecidos na região: ${Dinheiro.formatar(faixa.$1)} a ${Dinheiro.formatar(faixa.$2)}.',
            style: TipografiaTrato.legenda,
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        _CartaoMaterial(
          itens: _itens,
          materialPorMim: _materialPorMim,
          pedirSinal: _pedirSinal,
          aoAdicionar: _adicionarItem,
          aoEscolherQuemFornece: (eu) {
            setState(() {
              _materialPorMim = eu;
              _pedirSinal = _pedirSinal && eu;
            });
            _atualizarResumo();
          },
          aoMarcarSinal: (marcado) => setState(() => _pedirSinal = marcado),
        ),
        const SizedBox(height: EspacosTrato.x5),
        _ResumoEscuro(totalCentavos: _total, resumo: _resumo),
      ],
    );
  }
}

class _CampoGarantia extends StatelessWidget {
  const _CampoGarantia({required this.valor, required this.opcoes, required this.aoMudar});

  final int valor;
  final List<int> opcoes;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Garantia', style: TipografiaTrato.corpoForte, maxLines: 1),
        ),
        const SizedBox(height: EspacosTrato.x2),
        DropdownButtonFormField<int>(
          initialValue: opcoes.contains(valor) ? valor : null,
          isExpanded: true,
          style: TipografiaTrato.corpo,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: [
            for (final dias in opcoes)
              DropdownMenuItem(value: dias, child: Text('$dias dias', maxLines: 1)),
          ],
          onChanged: (dias) {
            if (dias != null) aoMudar(dias);
          },
        ),
      ],
    );
  }
}

class _CartaoMaterial extends StatelessWidget {
  const _CartaoMaterial({
    required this.itens,
    required this.materialPorMim,
    required this.pedirSinal,
    required this.aoAdicionar,
    required this.aoEscolherQuemFornece,
    required this.aoMarcarSinal,
  });

  final List<ItemMaterial> itens;
  final bool materialPorMim;
  final bool pedirSinal;
  final VoidCallback aoAdicionar;
  final ValueChanged<bool> aoEscolherQuemFornece;
  final ValueChanged<bool> aoMarcarSinal;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Material', style: TipografiaTrato.titulo),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: BotaoLink(texto: 'Adicionar item', aoTocar: aoAdicionar),
                ),
              ),
            ],
          ),
          for (final item in itens)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
              child: Row(
                children: [
                  Expanded(child: Text(item.nome, style: TipografiaTrato.corpo)),
                  const SizedBox(width: EspacosTrato.x3),
                  Text(Dinheiro.formatar(item.centavos), style: TipografiaTrato.corpoForte),
                ],
              ),
            ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              Expanded(
                child: BotaoSecundario(
                  texto: 'Eu forneço',
                  selecionado: materialPorMim,
                  aoTocar: () => aoEscolherQuemFornece(true),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: BotaoSecundario(
                  texto: 'Cliente fornece',
                  selecionado: !materialPorMim,
                  aoTocar: () => aoEscolherQuemFornece(false),
                ),
              ),
            ],
          ),
          if (materialPorMim) ...[
            const SizedBox(height: EspacosTrato.x3),
            InkWell(
              onTap: () => aoMarcarSinal(!pedirSinal),
              borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(value: pedirSinal, onChanged: (v) => aoMarcarSinal(v ?? false)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: EspacosTrato.x3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pedir sinal para o material', style: TipografiaTrato.corpoForte),
                          Text(
                            'Liberado quando você enviar a foto da nota.',
                            style: TipografiaTrato.legenda,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResumoEscuro extends StatelessWidget {
  const _ResumoEscuro({required this.totalCentavos, required this.resumo});

  final int totalCentavos;
  final ResumoOrcamento? resumo;

  @override
  Widget build(BuildContext context) {
    final claro = TipografiaTrato.corpo.copyWith(color: CoresTrato.creme);
    final claroForte = TipografiaTrato.corpoForte.copyWith(color: CoresTrato.creme);
    final r = resumo;
    // O rótulo com a porcentagem vem do dado do backend, nunca de um texto fixo.
    final rotuloTaxa = r == null ? 'Taxa Trato' : 'Taxa Trato (${Dinheiro.formatarBps(r.taxaBps)})';
    return CartaoTrato(
      escuro: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LinhaResumo(
            rotulo: 'Cliente paga',
            valor: totalCentavos > 0 ? Dinheiro.formatar(totalCentavos) : '—',
            estiloRotulo: claro,
            estiloValor: claroForte,
          ),
          const SizedBox(height: EspacosTrato.x2),
          _LinhaResumo(
            rotulo: rotuloTaxa,
            valor: r == null ? '—' : '– ${Dinheiro.formatar(r.taxaCentavos)}',
            estiloRotulo: claro,
            estiloValor: claro,
          ),
          const SizedBox(height: EspacosTrato.x3),
          const Divider(color: CoresTrato.pontoSobrePetroleo, height: 1),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Você recebe', style: claroForte),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    r == null ? '—' : Dinheiro.formatar(r.liquidoCentavos),
                    style: TipografiaTrato.tituloGrande.copyWith(
                      color: CoresTrato.creme,
                      fontSize: 34,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'A taxa só é cobrada quando o pagamento for liberado. '
            'Pedido cancelado antes do início não paga taxa.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.creme),
          ),
        ],
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({
    required this.rotulo,
    required this.valor,
    required this.estiloRotulo,
    required this.estiloValor,
  });

  final String rotulo;
  final String valor;
  final TextStyle estiloRotulo;
  final TextStyle estiloValor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(rotulo, style: estiloRotulo)),
        const SizedBox(width: EspacosTrato.x3),
        Text(valor, style: estiloValor),
      ],
    );
  }
}

class _NovoItemMaterial extends StatefulWidget {
  const _NovoItemMaterial();

  @override
  State<_NovoItemMaterial> createState() => _NovoItemMaterialState();
}

class _NovoItemMaterialState extends State<_NovoItemMaterial> {
  final _nome = TextEditingController();
  final _valor = TextEditingController();
  bool _tentou = false;

  @override
  void dispose() {
    _nome.dispose();
    _valor.dispose();
    super.dispose();
  }

  void _confirmar() {
    setState(() => _tentou = true);
    final centavos = Dinheiro.lerCentavos(_valor.text);
    if (_nome.text.trim().isEmpty || centavos == null || centavos <= 0) return;
    Navigator.of(context).pop(ItemMaterial(nome: _nome.text.trim(), centavos: centavos));
  }

  @override
  Widget build(BuildContext context) {
    final centavos = Dinheiro.lerCentavos(_valor.text);
    return Padding(
      padding: EdgeInsets.only(
        left: EspacosTrato.x5,
        right: EspacosTrato.x5,
        top: EspacosTrato.x5,
        bottom: MediaQuery.viewInsetsOf(context).bottom + EspacosTrato.x5,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adicionar item', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x4),
            CampoTrato(
              rotulo: 'Item',
              controlador: _nome,
              dica: 'Ex.: 2 tomadas 20 A',
              erro: _tentou && _nome.text.trim().isEmpty ? 'Informe o item.' : null,
            ),
            const SizedBox(height: EspacosTrato.x4),
            CampoTrato(
              rotulo: 'Valor',
              controlador: _valor,
              prefixo: 'R\$ ',
              teclado: TextInputType.number,
              formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              erro: _tentou && (centavos == null || centavos <= 0) ? 'Informe o valor.' : null,
            ),
            const SizedBox(height: EspacosTrato.x5),
            BotaoPrimario(texto: 'Adicionar', aoTocar: _confirmar),
          ],
        ),
      ),
    );
  }
}
