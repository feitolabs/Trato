import 'dart:async';

import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/agenda/modelos.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/servicos/modelos.dart';
import 'catalogo_exemplo.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_catalogo.dart';

// MODO DEMONSTRAÇÃO. O filtro e a ordem imitam o backend só para a tela poder ser mostrada.

String _sem(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

class RepositorioCatalogoFake implements RepositorioCatalogo {
  RepositorioCatalogoFake({
    List<CategoriaServico>? categorias,
    List<Profissional>? profissionais,
    this.falhar = false,
    this.travar = false,
  })  : _categorias = categorias ?? categoriasExemplo,
        _profissionais = profissionais ?? profissionaisExemplo;

  final List<CategoriaServico> _categorias;
  final List<Profissional> _profissionais;

  /// Para testar o estado de erro e o de carregando.
  bool falhar;
  bool travar;

  Future<T> _responder<T>(T Function() valor) {
    if (travar) return Completer<T>().future;
    if (falhar) {
      return Future.error(const ErroTrato(TipoErro.semInternet, 'Não foi possível carregar agora.'));
    }
    return Future.value(valor());
  }

  @override
  Future<List<CategoriaServico>> categorias() => _responder(() => List.of(_categorias));

  @override
  Future<List<Profissional>> profissionais(String categoriaId, FiltroProfissionais filtro) =>
      _responder(() {
        final lista = [
          for (final p in _profissionais)
            if (p.categoriaId == categoriaId &&
                (filtro.bairro == null ||
                    filtro.bairro!.isEmpty ||
                    _sem(p.regiao ?? '').contains(_sem(filtro.bairro!))) &&
                (filtro.precoMaxCentavos == null ||
                    (p.precoAPartirCentavos ?? 0) <= filtro.precoMaxCentavos!) &&
                (filtro.notaMinima == null || p.nota >= filtro.notaMinima!) &&
                (!filtro.soDisponiveisHoje || p.atendeHoje))
              p,
        ]..sort((a, b) => b.nota.compareTo(a.nota));
        return lista;
      });

  @override
  Future<List<Profissional>> buscar(String termo) => _responder(() {
        final t = _sem(termo.trim());
        if (t.isEmpty) return <Profissional>[];
        return [
          for (final p in _profissionais)
            if (_sem(p.nome).contains(t) ||
                _sem(p.especialidade).contains(t) ||
                _sem(_nomeCategoria(p.categoriaId)).contains(t) ||
                (p.detalhe?.servicos.any((s) => _sem(s).contains(t)) ?? false))
              p,
        ];
      });

  String _nomeCategoria(String? id) =>
      _categorias.where((c) => c.id == id).firstOrNull?.nome ?? '';

  @override
  Future<Profissional> perfil(String profissionalId) => _responder(() {
        final p = _profissionais.where((x) => x.id == profissionalId).firstOrNull;
        if (p == null) throw const ErroTrato(TipoErro.naoEncontrado, 'Perfil indisponível.');
        return p;
      });

  @override
  Future<FormularioPedido> formulario(String categoriaId) => _responder(() {
        final c = _categorias.where((x) => x.id == categoriaId).firstOrNull;
        if (c == null) throw const ErroTrato(TipoErro.naoEncontrado, 'Categoria indisponível.');
        return formularioDaCategoria(c);
      });
}

const _carlos = ProfissionalDoServico(
  id: 'prof-carlos',
  nome: 'Carlos Mendes',
  iniciais: 'CM',
  verificacao: 'Verificado Plus',
);

/// Ids dos serviços de exemplo (cada um num estado do pedido).
abstract final class ServicosExemplo {
  static const pintura = 'srv-pintura';
  static const tomadas = 'srv-tomadas';
  static const ventilador = 'srv-ventilador';
  static const vazamento = 'srv-vazamento';
  static const tomadasEmPagamento = 'srv-pagamento';
  static const orcamentos = 'srv-orcamentos';
}

class RepositorioServicosClienteFake implements RepositorioServicosCliente {
  RepositorioServicosClienteFake({this.falhar = false});

  final bool falhar;

  @override
  Future<List<ServicoRecente>> recentes() async {
    if (falhar) throw const ErroTrato(TipoErro.semInternet, 'Não foi possível carregar agora.');
    return const [
      ServicoRecente(
        pedidoId: ServicosExemplo.pintura,
        titulo: 'Pintura da sala',
        profissional: 'Rafael Souza',
        data: '02/10/2026',
        garantia: 'Garantia ativa até 31/12/2026',
      ),
      ServicoRecente(
        pedidoId: 'srv-limpeza',
        titulo: 'Limpeza pós-obra',
        profissional: 'Lia Carvalho',
        data: '18/09/2026',
        garantia: 'Garantia encerrada em 18/12/2026',
      ),
    ];
  }

  @override
  Future<PedidoEmAndamento?> emAndamento() async {
    if (falhar) throw const ErroTrato(TipoErro.semInternet, 'Não foi possível carregar agora.');
    return const PedidoEmAndamento(
      pedidoId: ServicosExemplo.orcamentos,
      titulo: 'Troca de tomadas e chuveiro',
      situacao: 'Recebendo orçamentos por mais 31 horas',
      aviso: '3 orçamentos novos',
    );
  }

  static const _contratado = EtapaLinhaDoTempo(
    titulo: 'Contratado',
    detalhe: 'Ter, 27/10 · contrato digital gerado',
    estado: EstadoEtapa.feita,
  );

  @override
  Future<DetalheServico> detalhe(String pedidoId) async {
    if (falhar) throw const ErroTrato(TipoErro.semInternet, 'Não foi possível carregar agora.');
    return switch (pedidoId) {
      ServicosExemplo.orcamentos => const DetalheServico(
          pedidoId: ServicosExemplo.orcamentos,
          numero: '#4821',
          titulo: 'Troca de tomadas e chuveiro',
          estadoApi: 'aberto',
          statusTexto: '3 orçamentos novos',
          statusTipo: TipoStatus.destaque,
          abertoEm: 'Aberto em 27/10 · recebendo orçamentos por mais 31 horas',
          descricao: 'Duas tomadas da cozinha esquentam e o chuveiro desarma o disjuntor.',
          etapas: [
            EtapaLinhaDoTempo(
              titulo: 'Pedido enviado',
              detalhe: 'Ter, 27/10',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Orçamentos',
              detalhe: 'Você recebe até 5 em 48 horas',
              estado: EstadoEtapa.atual,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Contratação',
              detalhe: 'Você escolhe e aceita um orçamento',
              estado: EstadoEtapa.futura,
            ),
          ],
        ),
      ServicosExemplo.ventilador => const DetalheServico(
          pedidoId: ServicosExemplo.ventilador,
          numero: '#7A31',
          titulo: 'Instalar ventilador de teto',
          estadoApi: 'aberto',
          statusTexto: '2 orçamentos recebidos',
          statusTipo: TipoStatus.info,
          abertoEm: 'Aberto em 27/10 · fecha em 20 horas',
          descricao: 'Sala com teto de 2,7 m. O ventilador já foi comprado.',
          etapas: [
            EtapaLinhaDoTempo(
              titulo: 'Pedido enviado',
              detalhe: 'Ter, 27/10',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Orçamentos',
              detalhe: 'Você recebe até 5 em 48 horas',
              estado: EstadoEtapa.atual,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Contratação',
              detalhe: 'Você escolhe e aceita um orçamento',
              estado: EstadoEtapa.futura,
            ),
          ],
        ),
      ServicosExemplo.tomadasEmPagamento => const DetalheServico(
          pedidoId: ServicosExemplo.tomadasEmPagamento,
          numero: '#C90D',
          titulo: 'Instalar 4 luminárias',
          estadoApi: 'orcamento_aceito',
          statusTexto: 'Aguardando pagamento',
          statusTipo: TipoStatus.alerta,
          abertoEm: 'Aberto em 25/10',
          profissional: ProfissionalDoServico(
            id: 'prof-andre',
            nome: 'André Lopes',
            iniciais: 'AL',
            verificacao: 'Verificado',
          ),
          valores: [LinhaValor('Orçamento aceito', 28000, destaque: true)],
          avisoValores: 'O valor e as condições de pagamento aparecem na tela de pagamento.',
          etapas: [
            EtapaLinhaDoTempo(
              titulo: 'Orçamento aceito',
              detalhe: 'Dom, 25/10',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Pagamento',
              detalhe: 'Confirmado pelo parceiro de pagamento',
              estado: EstadoEtapa.atual,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Agendamento',
              detalhe: 'Depois do pagamento confirmado',
              estado: EstadoEtapa.futura,
            ),
          ],
        ),
      ServicosExemplo.tomadas => const DetalheServico(
          pedidoId: ServicosExemplo.tomadas,
          numero: '#4821',
          titulo: 'Troca de tomadas e chuveiro',
          estadoApi: 'em_andamento',
          statusTexto: 'Em execução · pagamento acompanhado',
          statusTipo: TipoStatus.info,
          abertoEm: 'Aberto em 27/10',
          profissional: _carlos,
          valores: [
            LinhaValor('Orçamento', 38000),
            LinhaValor('Aditivo aprovado', 4500),
            LinhaValor('Total do pedido', 42500, destaque: true),
          ],
          avisoValores: 'Valores informados pelo sistema; não são calculados no app.',
          etapas: [
            _contratado,
            EtapaLinhaDoTempo(
              titulo: 'A caminho',
              detalhe: 'Qui, 29/10 · 13h40',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Chegou',
              detalhe: '14h06 · foto e local registrados',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Em execução',
              detalhe: 'Iniciado com o seu código às 14h10',
              estado: EstadoEtapa.atual,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Finalizado',
              detalhe: 'Você confirma com o código de conclusão',
              estado: EstadoEtapa.futura,
            ),
          ],
        ),
      ServicosExemplo.vazamento || '' => const DetalheServico(
          pedidoId: ServicosExemplo.vazamento,
          numero: '#B2F7',
          titulo: 'Vazamento na pia',
          estadoApi: 'em_disputa',
          statusTexto: 'Disputa aberta · em análise',
          statusTipo: TipoStatus.alerta,
          abertoEm: 'Aberto em 20/10',
          profissional: ProfissionalDoServico(
            id: 'prof-joana',
            nome: 'Joana Ribeiro',
            iniciais: 'JR',
            verificacao: 'Verificado',
          ),
          valores: [LinhaValor('Valor congelado até a análise', 18000, destaque: true)],
          avisoValores: 'Valor informado pelo sistema.',
          etapas: [
            _contratado,
            EtapaLinhaDoTempo(
              titulo: 'Finalizado pelo profissional',
              detalhe: 'Qui, 22/10',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Disputa em análise',
              detalhe: 'Respondemos em até 3 dias úteis',
              estado: EstadoEtapa.atual,
            ),
          ],
        ),
      _ => DetalheServico(
          pedidoId: pedidoId,
          numero: '#5E10',
          titulo: pedidoId == 'srv-limpeza' ? 'Limpeza pós-obra' : 'Pintura da sala',
          estadoApi: 'concluido',
          statusTexto: 'Finalizado',
          statusTipo: TipoStatus.sucesso,
          abertoEm: 'Aberto em 28/09',
          profissional: pedidoId == 'srv-limpeza'
              ? const ProfissionalDoServico(
                  id: 'prof-lia',
                  nome: 'Lia Carvalho',
                  iniciais: 'LC',
                  verificacao: 'Verificado Plus',
                )
              : const ProfissionalDoServico(
                  id: 'prof-rafael',
                  nome: 'Rafael Souza',
                  iniciais: 'RS',
                  verificacao: 'Verificado Plus',
                ),
          valores: const [
            LinhaValor('Orçamento', 120000),
            LinhaValor('Total pago', 120000, destaque: true),
          ],
          avisoValores: 'Valores informados pelo sistema; não são calculados no app.',
          etapas: const [
            _contratado,
            EtapaLinhaDoTempo(
              titulo: 'Em execução',
              detalhe: 'Sex, 02/10',
              estado: EstadoEtapa.feita,
            ),
            EtapaLinhaDoTempo(
              titulo: 'Finalizado',
              detalhe: 'Confirmado por você em 02/10',
              estado: EstadoEtapa.feita,
            ),
          ],
        ),
    };
  }
}

class RepositorioAgendaFake implements RepositorioAgenda {
  RepositorioAgendaFake({DateTime? hoje, this.vazia = false, this.falhar = false})
      : _hoje = DateTime((hoje ?? DateTime.now()).year, (hoje ?? DateTime.now()).month,
            (hoje ?? DateTime.now()).day);

  final DateTime _hoje;
  final bool vazia;
  final bool falhar;

  @override
  Future<List<Agendamento>> listar() async {
    if (falhar) throw const ErroTrato(TipoErro.semInternet, 'Não foi possível carregar agora.');
    if (vazia) return const [];
    DateTime dia(int d) => _hoje.add(Duration(days: d));
    return [
      Agendamento(
        id: 'ag-1',
        pedidoId: 'demo',
        dia: dia(0),
        horario: '14h',
        titulo: 'Troca de tomadas e chuveiro',
        local: 'Rua Antônio de Albuquerque, Savassi',
        cliente: 'Mariana',
        estado: EstadoAgendamento.emAndamento,
      ),
      Agendamento(
        id: 'ag-2',
        pedidoId: 'demo',
        dia: dia(1),
        horario: '9h às 11h',
        titulo: 'Instalar 4 luminárias',
        local: 'Rua Gonçalves Dias, Lourdes',
        cliente: 'Paulo',
      ),
      Agendamento(
        id: 'ag-3',
        pedidoId: 'demo',
        dia: dia(1),
        horario: '15h',
        titulo: 'Disjuntor desarmando',
        local: 'Rua Ceará, Funcionários',
        cliente: 'Renata',
      ),
      Agendamento(
        id: 'ag-4',
        pedidoId: 'demo',
        dia: dia(3),
        horario: '10h',
        titulo: 'Trocar chuveiro',
        local: 'Av. do Contorno, Santa Efigênia',
        cliente: 'Hugo',
      ),
      Agendamento(
        id: 'ag-0',
        pedidoId: 'demo',
        dia: dia(-2),
        horario: '16h',
        titulo: 'Instalar ventilador de teto',
        local: 'Rua Pernambuco, Savassi',
        cliente: 'Bruna',
        estado: EstadoAgendamento.concluido,
      ),
    ];
  }
}
