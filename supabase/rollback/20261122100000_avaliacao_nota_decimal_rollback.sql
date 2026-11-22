-- Rollback de 20261122100000_avaliacao_nota_decimal.sql
-- Restaura a função, o trigger e a tabela como estavam antes (nota só inteira).
--
-- SEGURO: se alguma avaliação já tem nota_decimal, o rollback falha e desfaz tudo, porque
-- apagar a coluna perde a nota exata (4,8 voltaria a 5). Para forçar mesmo assim, na mesma
-- sessão: set trato.forcar_rollback_nota_decimal = 'sim';
--
-- Depois de forçar, as notas públicas ficam com o valor decimal até o próximo recálculo.
-- Comando para recalcular pelo banco (só com OK do João):
--   select public.recalcular_perfil_profissional(usuario_id) from public.perfis_profissional;

begin;

-- Só olha a coluna se ela ainda existe (rodar o rollback duas vezes não pode dar erro).
do $$
declare
  tem_dados boolean := false;
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'avaliacoes' and column_name = 'nota_decimal'
  ) then
    execute 'select exists (select 1 from public.avaliacoes where nota_decimal is not null)'
      into tem_dados;
  end if;
  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_nota_decimal', true), '') <> 'sim' then
    raise exception
      'Há avaliações com nota_decimal: apagar a coluna perde a nota exata. Para forçar: set trato.forcar_rollback_nota_decimal = ''sim'';';
  end if;
end $$;

-- Função original (20261114120000_perfil_nota_e_concluidos.sql).
create or replace function public.recalcular_perfil_profissional(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.perfis_profissional p
     set servicos_concluidos = (
           select count(*)
             from public.contratos c
             join public.pedidos x on x.id = c.pedido_id
            where c.profissional_id = p_id and x.status = 'concluido'),
         nota_publica = (
           select round(avg(a.nota_geral)::numeric, 2)
             from public.avaliacoes a
            where a.avaliado_id = p_id and a.direcao = 'cliente_para_profissional')
   where p.usuario_id = p_id;
$$;

-- Trigger original (20261029030300_f36).
drop trigger if exists avaliacoes_proteger on public.avaliacoes;
create trigger avaliacoes_proteger before update on public.avaliacoes
  for each row execute function public.proteger_colunas(
    'contrato_id', 'direcao', 'avaliador_id', 'avaliado_id', 'nota_geral', 'comentario', 'etiquetas', 'criada_em');

alter table public.avaliacoes drop constraint if exists avaliacoes_nota_decimal_check;
alter table public.avaliacoes drop column if exists nota_decimal;

commit;
