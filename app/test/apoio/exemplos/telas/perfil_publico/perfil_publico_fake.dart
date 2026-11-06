export 'package:trato/telas/cliente/modelos.dart' show Avaliacao;
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/telas/cliente/modelos.dart' show Avaliacao;
import 'package:trato/telas/perfil_publico/perfil_publico.dart';

/// PROVISÓRIO — só para teste e demonstração.
class ServicoPerfilPublicoFake implements ServicoPerfilPublico {
  ServicoPerfilPublicoFake({
    this.perfil = perfilPublicoExemplo,
    this.avaliacoes = avaliacoesRecebidasExemplo,
    this.falharAoCarregar = false,
    bool? temPerfil,
  }) : _temPerfil = temPerfil;

  final PerfilPublico perfil;
  final List<Avaliacao> avaliacoes;
  final bool falharAoCarregar;
  bool? _temPerfil;

  void definirTemPerfil(bool tem) => _temPerfil = tem;

  @override
  Future<PerfilPublico> carregarPerfil() async {
    if (falharAoCarregar) throw Exception('falha de teste');
    final sessao = ServicoAuthPadrao.atual.sessaoAtual;
    if (sessao != null && sessao.nome != null && sessao.nome!.trim().isNotEmpty) {
      final nome = sessao.nome!.trim();
      final partes = nome.split(RegExp(r'\s+'));
      final iniciais = partes.length > 1
          ? '${partes.first[0]}${partes.last[0]}'.toUpperCase()
          : (partes.isNotEmpty && partes.first.isNotEmpty
              ? partes.first[0].toUpperCase()
              : perfil.iniciais);
      return PerfilPublico(
        nome: nome,
        iniciais: iniciais,
        categoria: perfil.categoria,
        verificacao: perfil.verificacao,
        noTratoDesde: perfil.noTratoDesde,
        nota: perfil.nota,
        totalAvaliacoes: perfil.totalAvaliacoes,
        servicosConcluidos: perfil.servicosConcluidos,
        sobre: perfil.sobre,
        cidade: perfil.cidade,
        fotosPortfolio: perfil.fotosPortfolio,
        ultimasAvaliacoes: perfil.ultimasAvaliacoes,
        listaFotosPortfolio: perfil.listaFotosPortfolio,
        fotoReferencia: perfil.fotoReferencia,
      );
    }
    return perfil;
  }

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return avaliacoes;
  }

  @override
  Future<bool> temPerfilProfissional() async =>
      _temPerfil ?? (ServicoAuthPadrao.atual.sessaoAtual?.ehProfissional ?? false);
}

const avaliacoesRecebidasExemplo = [
  Avaliacao(
    cliente: 'Mariana S.',
    servico: 'Troca de tomadas',
    nota: 5,
    comentario: 'Chegou no horário e deixou tudo limpo.',
    detalhes: 'Pontualidade 5 · Qualidade 5 · Limpeza 5',
  ),
  Avaliacao(
    cliente: 'Paulo R.',
    servico: 'Instalação de chuveiro',
    nota: 4,
    comentario: 'Bom serviço, atrasou um pouco.',
    detalhes: 'Pontualidade 3 · Qualidade 5 · Limpeza 4',
  ),
];

const perfilPublicoExemplo = PerfilPublico(
  nome: 'Carlos Almeida',
  iniciais: 'CA',
  categoria: 'Eletricista',
  verificacao: 'Identidade conferida',
  noTratoDesde: 2026,
  nota: 4.8,
  totalAvaliacoes: 32,
  servicosConcluidos: 41,
  sobre: 'Dez anos de experiência em instalações residenciais.',
  cidade: 'Belo Horizonte',
  fotosPortfolio: 3,
  ultimasAvaliacoes: avaliacoesRecebidasExemplo,
);
