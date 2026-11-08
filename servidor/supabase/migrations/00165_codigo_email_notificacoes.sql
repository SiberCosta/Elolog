-- v107 — 1) Código de 6 dígitos por email no 2.º passo do administrador da empresa (alternativa à aplicação de autenticação).
--         O código é criado só pelo serviço (Edge Function recuperar-acesso, ação «codigo_entrada»), guardado cifrado,
--         vale 10 minutos, máx. 5 tentativas, e só serve para a sessão onde foi pedido. Quando certo, reforça essa sessão
--         durante 12 horas (o mesmo mecanismo do código de reserva: sessoes_reserva → private.sessao_reforcada()).
--       2) Notificações: quem as pode ver passa a poder marcá-las como lidas (só a coluna lida_em; as regras RLS já existiam).
--       3) Segurança: TRUNCATE retirado a anon/authenticated (passava por cima das regras de acesso; a aplicação nunca o usa).
-- Só acrescenta; não altera dados, perfis nem fluxos.

create table if not exists public.codigos_email (
  user_id uuid primary key references auth.users(id) on delete cascade,
  session_id uuid not null,
  hash text not null,
  expira_em timestamptz not null,
  tentativas int not null default 0,
  created_at timestamptz not null default now());
alter table public.codigos_email enable row level security;
revoke all on public.codigos_email from anon, authenticated;

create or replace function public.servico_codigo_email_criar(p_user uuid, p_sessao uuid)
returns table (codigo text, email text, nome text)
language plpgsql security definer set search_path = public as $$
declare v_b bytea := extensions.gen_random_bytes(4); v_c text; v_f funcionarios;
begin
  select * into v_f from funcionarios where id = p_user and ativo;
  if not found or coalesce(v_f.email, '') = '' or p_sessao is null then return; end if;
  v_c := lpad(((get_byte(v_b,0)::bigint * 16777216 + get_byte(v_b,1) * 65536 + get_byte(v_b,2) * 256 + get_byte(v_b,3)) % 1000000)::text, 6, '0');
  insert into codigos_email (user_id, session_id, hash, expira_em, tentativas, created_at)
    values (p_user, p_sessao, extensions.crypt(v_c, extensions.gen_salt('bf')), now() + interval '10 minutes', 0, now())
    on conflict (user_id) do update set session_id = excluded.session_id, hash = excluded.hash, expira_em = excluded.expira_em, tentativas = 0, created_at = now();
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (v_f.empresa_id, p_user, v_f.papel::text, 'codigo_email_enviado', 'codigos_email', p_user::text);
  return query select v_c, v_f.email, v_f.nome;
end $$;
revoke all on function public.servico_codigo_email_criar(uuid, uuid) from public, anon, authenticated;
grant execute on function public.servico_codigo_email_criar(uuid, uuid) to service_role;

create or replace function public.confirmar_codigo_email(p_codigo text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_sess uuid; v_r codigos_email; v_c text := regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g');
begin
  if auth.uid() is null then return false; end if;
  begin v_sess := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sess := null; end;
  if v_sess is null then return false; end if;
  select * into v_r from codigos_email where user_id = auth.uid() for update;
  if not found or v_r.expira_em < now() or v_r.session_id <> v_sess or v_r.tentativas >= 5 then return false; end if;
  if length(v_c) <> 6 or extensions.crypt(v_c, v_r.hash) <> v_r.hash then
    update codigos_email set tentativas = tentativas + 1 where user_id = auth.uid();
    insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_email_errado', 'codigos_email', auth.uid()::text);
    return false;
  end if;
  update codigos_email set expira_em = now() - interval '1 second', tentativas = 99 where user_id = auth.uid();   -- uso único
  insert into sessoes_reserva (session_id, user_id, valida_ate) values (v_sess, auth.uid(), now() + interval '12 hours')
    on conflict (session_id) do update set valida_ate = excluded.valida_ate where sessoes_reserva.user_id = auth.uid();
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_email_usado', 'codigos_email', auth.uid()::text);
  return true;
end $$;
revoke all on function public.confirmar_codigo_email(text) from public, anon;
grant execute on function public.confirmar_codigo_email(text) to authenticated;

grant update (lida_em) on public.notificacoes to authenticated;

revoke truncate on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke truncate on tables from anon, authenticated;
