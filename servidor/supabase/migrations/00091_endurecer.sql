-- =====================================================================
-- Elolog · 0009 · Endurecimento das permissões do papel "anon" (OPCIONAL, recomendado)
-- Depende de 0001–0008.
-- Motivo: no Supabase, cada tabela e função nova em "public" recebe por omissão permissões para anon/authenticated.
-- A 0003 revogou as tabelas do anon, mas as criadas DEPOIS (sessoes_empresa, emails_fila...) voltaram a tê-las.
-- Nada fica exposto (o RLS bloqueia e não há políticas para anon), mas é uma camada de defesa a menos.
-- O visitante sem sessão só precisa de UMA coisa: validar_empresa() (1.º passo do login do prestador).
-- É isto que o teste 01 (01_instalacao.sql) assinala como AVISO.
-- NÃO FOI EXECUTADO: aplicar primeiro no projeto de teste e voltar a correr os testes 01 e 02.
-- =====================================================================
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;
grant  execute on function public.validar_empresa(text, text, text) to anon;

-- Objetos futuros criados por este utilizador (o SQL Editor e as migrações correm como "postgres").
-- Se criar objetos com outro papel (ex.: supabase_admin), repita com "for role <papel>".
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
