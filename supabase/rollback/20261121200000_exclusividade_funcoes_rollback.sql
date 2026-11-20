-- Desfaz 20261121200000_exclusividade_funcoes.sql (só derruba as 4 funções; nenhum dado é apagado).
-- Só rode com o OK do João. Exclusividades já criadas continuam na tabela, mas ninguém mais as processa.

begin;
drop function if exists public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz);
drop function if exists public.exclusividade_expirar(timestamptz);
drop function if exists public.exclusividade_responder(uuid, uuid, text, timestamptz, integer);
drop function if exists public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer);
commit;
