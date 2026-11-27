# Pré-publicação (relato do DevOps, 27/11, só leitura): NÃO pronto

## Bloqueios
1. Código sem commit; CI nunca rodou nele. Deixar fora PDFs, prints e .claude/launch.json.
2. Banco: 20 migrations antes do backend (docs/ordem-publicacao-banco.md); seed prazo_resposta_disputa_horas 48 para 24; configs em supabase/seeds/seed_config_definicoes_termos.sql; 12 sem nova revisão de segurança.
3. Segredo CONTA_IMPEDIMENTO_PEPPER ausente em .env.example e fly.toml (não trocar depois de gravado). CORS para o painel não confirmado.
4. Agendador ligado: 1º ciclo libera saldos vencidos. Decidir ligado ou TRATO_AGENDADOR_EMBUTIDO=false.
5. pg_local.py não aplica 231800, 231900 nem 20261127001000.
6. iOS: não é bloqueio. Conferido pelo Mestre: o Info.plist tinha a chave de localização repetida; só a cópia saiu, a permissão continua.
7. App: build-number 58 ou maior; painel 0.1.31+32.
8. Termos 1.1 no app/backend; 1.2 com campos [PREENCHER].
Painel antigo deve quebrar em Chamados: publicar o painel junto.

## Passos (escrita, push, deploy e segredo pedem OK do João)
resolver 3-5, 7 e 8 e harness/verificar; commit/merge/CI; backup e pré-checagens; segredos em stage; migrations 1-20 (2+3 e 12+14 juntas) e seed; backend de worktree limpo; painel e web; app assinado; chaves e tag.

## Voltar atrás
Backend: flyctl releases --image -a trato; flyctl deploy -a trato --image <ref> (não testado; "releases rollback" não existe). Banco: rollback 20 para 1 depois do backend (pode perder dados). Dinheiro liberado: só estorno. App: não rebaixa versão.
