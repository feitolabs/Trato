-- ===========================================================================
-- 20261122100000_avaliacao_nota_decimal.sql
-- RASCUNHO. NÃO aplicada no Supabase. Aguarda o OK do João.
--
-- Problema: o cliente dá 5/5/5/5/4 (média 4,8), o app manda só `nota_geral` inteira (5) e o
-- perfil do profissional mostra 5,0 em vez de 4,8. `avaliacoes.nota_geral` é smallint (1 a 5) e
-- `recalcular_perfil_profissional` faz avg(nota_geral).
--
-- Mudança mínima e compatível:
--   1. Coluna nova `avaliacoes.nota_decimal numeric(3,2)`, ANULÁVEL, sem default. Linhas
--      antigas ficam com NULL (nenhum UPDATE de dados). `nota_geral` continua como está: o
--      backend atual segue lendo e gravando o inteiro sem mudar nada.
--   2. Check: nota_decimal entre 1 e 5 e a no máximo 0,5 de distância de nota_geral (assim o
--      inteiro continua sendo o arredondamento da decimal, inclusive em 4,5).
--   3. A nota decimal é imutável como a inteira (trigger avaliacoes_proteger passa a listá-la).
--   4. `recalcular_perfil_profissional` passa a tirar a média de coalesce(nota_decimal,
--      nota_geral): avaliações antigas (NULL) dão o mesmo resultado de antes, as novas com
--      decimal dão 4,8. Mantém security definer e o mesmo EXECUTE (create or replace preserva
--      os privilégios); só o search_path fica vazio.
--
-- Idempotente (add column if not exists, drop constraint/trigger if exists, create or replace).
-- Nada de UPDATE de dados: o perfil dos profissionais já existentes não muda até chegar uma
-- avaliação com nota_decimal.
--
-- DEPOIS DE APLICAR (backend): gravar nota_decimal junto com nota_geral em
-- persistencia/dinheiro.py e devolver a decimal nas leituras. Só então o app mostra 4,8.
--
-- Rollback: supabase/rollback/20261122100000_avaliacao_nota_decimal_rollback.sql
-- ===========================================================================

begin;

alter table public.avaliacoes
  add column if not exists nota_decimal numeric(3, 2);

alter table public.avaliacoes
  drop constraint if exists avaliacoes_nota_decimal_check;
alter table public.avaliacoes
  add constraint avaliacoes_nota_decimal_check
  check (
    nota_decimal is null
    or (nota_decimal between 1 and 5
        and nota_decimal between nota_geral - 0.5 and nota_geral + 0.5)
  );

comment on column public.avaliacoes.nota_decimal is
  'Média dos critérios com 2 casas (ex.: 4,80). NULL em avaliação antiga; nota_geral é o inteiro arredondado.';

-- Imutável como nota_geral (a lista é a original da F3.6 mais nota_decimal).
drop trigger if exists avaliacoes_proteger on public.avaliacoes;
create trigger avaliacoes_proteger before update on public.avaliacoes
  for each row execute function public.proteger_colunas(
    'contrato_id', 'direcao', 'avaliador_id', 'avaliado_id', 'nota_geral', 'nota_decimal',
    'comentario', 'etiquetas', 'criada_em');

create or replace function public.recalcular_perfil_profissional(p_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.perfis_profissional p
     set servicos_concluidos = (
           select count(*)
             from public.contratos c
             join public.pedidos x on x.id = c.pedido_id
            where c.profissional_id = p_id and x.status = 'concluido'),
         nota_publica = (
           select round(avg(coalesce(a.nota_decimal, a.nota_geral::numeric)), 2)
             from public.avaliacoes a
            where a.avaliado_id = p_id and a.direcao = 'cliente_para_profissional')
   where p.usuario_id = p_id;
$$;

commit;
