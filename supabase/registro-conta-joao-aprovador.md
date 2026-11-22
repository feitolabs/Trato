# Registro: conta de login do João (aprovador de config)

- **Data:** 2026-11-20 (escrita no Supabase de produção com o OK do João).
- **E-mail:** cardosojoaovitor23@outlook.com
- **Nome:** João Vitor
- **Id do usuário criado:** `c65ef7fb-f6a0-46d0-b385-5312d5ac0e94`
- **Antes:** SELECT mostrou que o e-mail não existia no Auth.

## O que foi escrito (só isto)

1. Usuário no Supabase Auth, criado pela API admin do Auth (e-mail já confirmado, nome nos metadados).
   A senha inicial foi aleatória e forte, descartada na hora: não foi impressa nem salva, ninguém a conhece.
2. Uma linha em `public.usuarios` (`id`, `nome` = 'João Vitor'; status padrão `ativo`).
3. Disparo do e-mail de redefinição de senha (recuperação do Auth) para o e-mail acima. A API respondeu 200.

Nada em `equipe`: a conta NÃO tem papel de admin. Conferido: `equipe` tem 0 linhas para esse id.

## Como o João define a senha

Abrir o e-mail de redefinição enviado e escolher a própria senha. Se o e-mail não chegar (olhar o spam) ou o link expirar, usar "Esqueci a senha" na tela de login com esse e-mail.

## Próximo passo

Um admin ativo concede o acesso pelo painel ("Conceder acesso") para esse e-mail.

## Para desfazer

1. Se já tiver acesso na equipe: revogar o acesso no painel.
2. Apagar a linha de `public.usuarios` (a chave estrangeira usa `on delete restrict`, então ela sai antes):
   `delete from public.usuarios where id = 'c65ef7fb-f6a0-46d0-b385-5312d5ac0e94';`
3. Apagar o usuário do Auth: painel do Supabase (Authentication > Users) ou API admin `DELETE /auth/v1/admin/users/c65ef7fb-f6a0-46d0-b385-5312d5ac0e94`.
   Se a conta já tiver usado o app, outras tabelas podem apontar para o id e bloquear o delete; nesse caso, bloquear a conta em vez de apagar.
