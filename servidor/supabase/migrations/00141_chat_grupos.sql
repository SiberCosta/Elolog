-- v71 — Chat: dentro da mesma organização todos falam com todos (sem hierarquia) e podem criar grupos.
-- A equipa Elolog continua separada de cada prestador; empresas diferentes nunca se veem.

create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select x.org = y.org from private.chat_perfil(a) x, private.chat_perfil(b) y
    where x.org is not null and y.org is not null), false)
$$;

create table if not exists chat_grupos (
  id         uuid primary key default gen_random_uuid(),
  org        text not null,                         -- 'elolog' ou id da empresa
  nome       text not null check (length(nome) between 1 and 80),
  criado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists chat_grupo_membros (
  grupo_id uuid not null references chat_grupos(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  lido_ate timestamptz not null default now(),
  primary key (grupo_id, user_id)
);
create table if not exists chat_grupo_mensagens (
  id         uuid primary key default gen_random_uuid(),
  grupo_id   uuid not null references chat_grupos(id) on delete cascade,
  de         uuid not null references auth.users(id) on delete cascade,
  texto      text not null check (length(texto) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists chat_grupo_msgs on chat_grupo_mensagens (grupo_id, created_at desc);
alter table chat_grupos enable row level security; alter table chat_grupo_membros enable row level security; alter table chat_grupo_mensagens enable row level security;
revoke all on chat_grupos, chat_grupo_membros, chat_grupo_mensagens from anon, authenticated;

-- Membro ativo do grupo (e ainda funcionário ativo da organização do grupo).
create or replace function private.chat_membro(p_user uuid, p_grupo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_grupo_membros m join chat_grupos g on g.id = m.grupo_id
    where m.grupo_id = p_grupo and m.user_id = p_user and g.org = (select org from private.chat_perfil(p_user)))
$$;

create or replace function public.chat_grupo_criar(p_nome text, p_membros uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); v_org text := (select org from private.chat_perfil(auth.uid())); g uuid; m uuid;
begin
  if v_org is null then raise exception 'Sem permissão para criar grupos.'; end if;
  if length(trim(coalesce(p_nome, ''))) = 0 then raise exception 'Dê um nome ao grupo.'; end if;
  if coalesce(array_length(p_membros, 1), 0) = 0 then raise exception 'Escolha pelo menos um colega.'; end if;
  if (select count(*) from chat_grupos where criado_por = eu and created_at > now() - interval '1 hour') >= 20 then raise exception 'Demasiados grupos criados. Aguarde.'; end if;
  insert into chat_grupos (org, nome, criado_por) values (v_org, left(trim(p_nome), 80), eu) returning id into g;
  insert into chat_grupo_membros (grupo_id, user_id) values (g, eu);
  foreach m in array p_membros loop
    if private.chat_pode(eu, m) then insert into chat_grupo_membros (grupo_id, user_id) values (g, m) on conflict do nothing; end if;
  end loop;
  return g;
end $$;

create or replace function public.chat_grupo_adicionar(p_grupo uuid, p_membros uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); m uuid;
begin
  if not private.chat_membro(eu, p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  foreach m in array coalesce(p_membros, '{}') loop
    if private.chat_pode(eu, m) then insert into chat_grupo_membros (grupo_id, user_id) values (p_grupo, m) on conflict do nothing; end if;
  end loop;
end $$;

create or replace function public.chat_grupo_sair(p_grupo uuid) returns void
language sql security definer set search_path = public as $$
  delete from chat_grupo_membros where grupo_id = p_grupo and user_id = auth.uid()
$$;

create or replace function public.chat_grupos()
returns table (id uuid, nome text, membros int, por_ler int, ultima text, ultima_em timestamptz, nomes text)
language sql stable security definer set search_path = public as $$
  select g.id, g.nome, (select count(*)::int from chat_grupo_membros x where x.grupo_id = g.id),
    (select count(*)::int from chat_grupo_mensagens t where t.grupo_id = g.id and t.de <> auth.uid() and t.created_at > m.lido_ate),
    (select left(t.texto, 80) from chat_grupo_mensagens t where t.grupo_id = g.id order by t.created_at desc limit 1),
    (select max(t.created_at) from chat_grupo_mensagens t where t.grupo_id = g.id),
    (select string_agg(p.nome, ', ' order by p.nome) from chat_grupo_membros x, private.chat_perfil(x.user_id) p where x.grupo_id = g.id and p.nome is not null)
  from chat_grupos g join chat_grupo_membros m on m.grupo_id = g.id and m.user_id = auth.uid()
  where private.chat_membro(auth.uid(), g.id) order by 6 desc nulls last, 2
$$;

create or replace function public.chat_grupo_conversa(p_grupo uuid)
returns table (id uuid, de uuid, nome_de text, texto text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not private.chat_membro(auth.uid(), p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  update chat_grupo_membros set lido_ate = now() where grupo_id = p_grupo and user_id = auth.uid();
  return query select t.id, t.de, (select nome from private.chat_perfil(t.de)), t.texto, t.created_at from (
    select * from chat_grupo_mensagens x where x.grupo_id = p_grupo order by x.created_at desc limit 80) t order by t.created_at;
end $$;

create or replace function public.chat_grupo_enviar(p_grupo uuid, p_texto text)
returns chat_grupo_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); r chat_grupo_mensagens;
begin
  if not private.chat_membro(eu, p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  if length(trim(coalesce(p_texto, ''))) = 0 then raise exception 'Escreva a mensagem.'; end if;
  if (select count(*) from chat_grupo_mensagens where de = eu and created_at > now() - interval '1 minute') >= 30 then raise exception 'Demasiadas mensagens seguidas. Aguarde um minuto.'; end if;
  insert into chat_grupo_mensagens (grupo_id, de, texto) values (p_grupo, eu, left(trim(p_texto), 2000)) returning * into r;
  update chat_grupo_membros set lido_ate = now() where grupo_id = p_grupo and user_id = eu;
  return r;
end $$;

-- Contador: mensagens diretas + mensagens de grupo por ler.
create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select (select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null and private.chat_pode(auth.uid(), de))
       + (select count(*)::int from chat_grupo_mensagens t join chat_grupo_membros m on m.grupo_id = t.grupo_id and m.user_id = auth.uid()
           where t.de <> auth.uid() and t.created_at > m.lido_ate and private.chat_membro(auth.uid(), t.grupo_id))
$$;

revoke all on function private.chat_membro(uuid, uuid), public.chat_grupo_criar(text, uuid[]), public.chat_grupo_adicionar(uuid, uuid[]), public.chat_grupo_sair(uuid),
  public.chat_grupos(), public.chat_grupo_conversa(uuid), public.chat_grupo_enviar(uuid, text) from public, anon;
grant execute on function public.chat_grupo_criar(text, uuid[]), public.chat_grupo_adicionar(uuid, uuid[]), public.chat_grupo_sair(uuid),
  public.chat_grupos(), public.chat_grupo_conversa(uuid), public.chat_grupo_enviar(uuid, text) to authenticated;
