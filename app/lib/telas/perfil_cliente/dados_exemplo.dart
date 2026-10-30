import 'modelos.dart';

/// DADOS PROVISÓRIOS: textos da tela 22 do protótipo. Serão trocados pelos dados da API.
abstract final class DadosExemplo {
  static const perfil = PerfilCliente(
    nome: 'Mariana Alves',
    iniciais: 'MA',
    resumo: 'Nota 4,8 como cliente · 6 serviços',
    grupos: [
      GrupoPerfil(
        titulo: 'CONTA',
        itens: [
          ItemPerfil(acao: AcaoPerfil.dadosPessoais, titulo: 'Dados pessoais'),
          ItemPerfil(acao: AcaoPerfil.enderecos, titulo: 'Endereços salvos', valor: '2'),
          ItemPerfil(
            acao: AcaoPerfil.formasPagamento,
            titulo: 'Formas de pagamento',
            valor: 'Pix, Visa',
          ),
          ItemPerfil(acao: AcaoPerfil.favoritos, titulo: 'Profissionais favoritos', valor: '3'),
        ],
      ),
      GrupoPerfil(
        titulo: 'SEGURANÇA E AVISOS',
        itens: [
          ItemPerfil(acao: AcaoPerfil.contatosConfianca, titulo: 'Contatos de confiança'),
          ItemPerfil(
            acao: AcaoPerfil.notificacoes,
            titulo: 'Notificações',
            valor: 'Push, WhatsApp',
          ),
          ItemPerfil(acao: AcaoPerfil.usarComoProfissional, titulo: 'Usar como profissional'),
        ],
      ),
      GrupoPerfil(
        titulo: 'PRIVACIDADE E AJUDA',
        itens: [
          ItemPerfil(acao: AcaoPerfil.meusDados, titulo: 'Meus dados (LGPD)'),
          ItemPerfil(acao: AcaoPerfil.centralAjuda, titulo: 'Central de ajuda'),
          ItemPerfil(acao: AcaoPerfil.termos, titulo: 'Termos e políticas'),
        ],
      ),
    ],
  );
}
