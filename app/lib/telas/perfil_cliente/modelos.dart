/// Ações dos itens do perfil do cliente. A tela só avisa qual foi tocado.
enum AcaoPerfil {
  dadosPessoais,
  enderecos,
  formasPagamento,
  favoritos,
  contatosConfianca,
  notificacoes,
  usarComoProfissional,
  meusDados,
  centralAjuda,
  termos,
}

class ItemPerfil {
  const ItemPerfil({required this.acao, required this.titulo, this.valor});

  final AcaoPerfil acao;
  final String titulo;

  /// Texto à direita, ex.: "2" ou "Pix, Visa".
  final String? valor;
}

class GrupoPerfil {
  const GrupoPerfil({required this.titulo, required this.itens});

  final String titulo;
  final List<ItemPerfil> itens;
}

class PerfilCliente {
  const PerfilCliente({
    required this.nome,
    required this.iniciais,
    required this.resumo,
    required this.grupos,
  });

  final String nome;
  final String iniciais;

  /// "Nota 4,8 como cliente · 6 serviços" (a nota é calculada pelo backend).
  final String resumo;
  final List<GrupoPerfil> grupos;
}
