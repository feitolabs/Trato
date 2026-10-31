# Placeholders do app (`EmBreveTela`) — inventário e destino

`EmBreveTela` (`app/lib/telas/em_breve_tela.dart`) mostra "Esta tela chega nas próximas etapas".
O app não pode terminar nela. Este arquivo registra o que existia, o que abre agora e o que sobrou.
O teste `app/test/navegacao_sem_placeholder_test.dart` percorre os toques de cada aba (cliente e
profissional) e falha se o texto aparecer.

## 1. Usos que existiam e o destino atual

| Antes (arquivo) | De onde se chegava | Agora |
|---|---|---|
| `cliente/inicio_tela.dart` (sino) | Início → sino | Notificações (`RotasTrato.abrirNotificacoes`) |
| `cliente/inicio_tela.dart` ("Pedir orçamento") | Início → cartão escuro | Escolha da categoria → Novo pedido |
| `cliente/inicio_tela.dart` (pedido em andamento) | Início → cartão | Detalhe do serviço |
| `cliente/inicio_tela.dart` (categoria, "Ver todas") | Início → grade | Categoria / Todas as categorias |
| `cliente/inicio_tela.dart` (serviço recente) | Início → "Pintura da sala" | Detalhe do serviço (+ "Ver todos" → lista) |
| `cliente/buscar_tela.dart` (tela 9, só protótipo) | perfil sem detalhe | aviso "Perfil indisponível" (tela não é usada no fluxo do app) |
| `cliente/perfil_profissional_tela.dart` (favoritar) | perfil → coração | **Removido**: favoritos estão fora do MVP (sem rota) |
| idem ("Pedir orçamento ao X") | perfil | Novo pedido na categoria do profissional |
| idem ("Ver as N" avaliações) | perfil | Lista de avaliações do profissional |
| `orcamentos/detalhe_orcamento_tela.dart` ("Conversar") | detalhe do orçamento | Chat do pedido (só na demonstração; no modo `api` o botão some: sem rota de conversa antes de contratar) |
| idem ("Fazer contraproposta") | detalhe do orçamento | Chat do pedido (demonstração); some no modo `api`: **sem rota de contraproposta** |
| `orcamentos/orcamentos_recebidos_tela.dart` (sem detalhe) | lista de orçamentos | Perfil público do profissional |
| `pedido_novo/novo_pedido_tela.dart` ("Trocar" categoria) | Novo pedido | Escolha da categoria |
| idem ("Mudar" endereço) | Novo pedido | **Botão some**: sem tela/rota de endereços |
| idem ("Adicionar" foto) | Novo pedido | Câmera/galeria (`aoCapturarFoto`) |
| idem ("Próximo" sem callback) | Novo pedido | só existe no widget isolado; no app envia o pedido |
| `profissional_inicio/casca_profissional_tela.dart` (Filtros) | Início do profissional | Tela de filtros dos pedidos abertos |
| idem (aba Pedidos) | barra inferior | Pedidos abertos + conversas |
| idem (aba Agenda) | barra inferior | Agenda por dia com check-in |
| idem (abas Carteira e Perfil sem conteúdo) | barra inferior | Extrato / perfil público (demonstração se não ligadas) |

## 2. Telas de acesso (`telas/auth/`) — resolvidas

| Arquivo | Uso | Destino |
|---|---|---|
| `criar_conta_tela.dart` | Termos e Política | `TextoLegalTela` (rascunhos de `docs/juridico/`, com aviso de revisão) |
| `recuperar_senha_tela.dart` | "Fale com o suporte" | Central de ajuda (`AjudaTela`) |
| `login_tela.dart` | biometria | botão **removido** (fora do MVP) |
| `confirmar_celular_tela.dart` | reenvio por WhatsApp | item **removido** (código só por SMS) |

Nenhum uso de `EmBreveTela` resta em `app/lib/`; a classe foi apagada.

## 3. Telas que existiam sem ponto de entrada ou só com dado fixo

| Tela | Situação antes | Agora |
|---|---|---|
| `notificacoes/` | só alcançada pelo Perfil; destino só para disputa/retrabalho | sino no Início (cliente e profissional); destino por tipo (pedido, orçamento, chat, pagamento, disputa, retrabalho) |
| `mensagens/` | só no cliente, lista fixa | cliente (modo `api`: uma conversa por pedido) e aba Pedidos do profissional |
| `cliente/perfil_profissional_tela.dart` | só abria para 1 profissional fixo | abre da busca, da categoria, do orçamento e do serviço, via catálogo |
| `profissional_inicio/inicio_profissional_tela.dart` | "Filtros" sem tela | `FiltrosPedidosAbertosTela` + `FiltroPedidosAbertos` |
| `profissional/area_profissional_provisoria.dart` | sem uso | continua sem uso (candidata a apagar) |
| `cliente/buscar_tela.dart` (tela 9) | só no protótipo e nos goldens | continua assim; a aba Buscar usa `BuscaProfissionaisTela` |
| `perfil_cliente/` | itens sem tela eram escondidos | "Termos e políticas" agora abre os textos; restam escondidos: dados pessoais, endereços, formas de pagamento, favoritos, contatos de confiança |

## 4. Fora do MVP (item removido da tela, não é placeholder)

Registrado para voltar quando houver rota e decisão: favoritos; endereços salvos e "Mudar endereço"
no Novo pedido; formas de pagamento salvas; contatos de confiança; dados pessoais; contraproposta;
conversa antes de contratar (modo `api`); convite a um profissional específico ao pedir orçamento
(o pedido sai para a categoria); mapa na busca ("Mapa em breve" só na tela 9 do protótipo).

## 5. Dados em demonstração mesmo no modo `api`

Categorias, lista por categoria, busca e perguntas do Novo pedido (faltam rotas de catálogo);
agenda (só o próximo atendimento do início); lista de conversas do profissional (só o de hoje).
Perfil público e detalhe do serviço usam a API (`GET /v1/profissionais/{id}`, `/v1/pedidos/{id}`).
Ver `docs/app-ligacao.md` e `docs/app-divergencias.md`.
