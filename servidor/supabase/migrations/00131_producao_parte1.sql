-- Elolog — produção, parte 1: tarefas agendadas (emails), documentos no armazenamento e faturas certificadas.
-- Depois de aplicar: select private.agendar_tarefas('https://<projeto>.supabase.co');  (uma vez por projeto)

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- ---------- 1. Tarefas agendadas ----------------------------------------------
-- O segredo do agendador é gerado aqui e fica no cofre (vault): nunca aparece em ficheiros nem no navegador.
-- As funções de servidor leem-no com a chave de serviço (servico_segredo_cron).
create or replace function private.chamar_funcao(p_nome text, p_corpo jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_url text; v_seg text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'url_projeto';
  select decrypted_secret into v_seg from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_seg is null then return null; end if;
  return net.http_post(url := v_url || '/functions/v1/' || p_nome,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_seg),
    body := p_corpo, timeout_milliseconds := 55000);
end $$;
revoke all on function private.chamar_funcao(text, jsonb) from public, anon, authenticated;

create or replace function private.agendar_tarefas(p_url text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if p_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'Endereço do projeto inválido: %', p_url; end if;
  if exists (select 1 from vault.secrets where name = 'url_projeto') then
    update vault.secrets set secret = p_url where name = 'url_projeto';
  else perform vault.create_secret(p_url, 'url_projeto', 'Endereço do projeto (tarefas agendadas)'); end if;
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_secret', 'Segredo das funções agendadas');
  end if;
  perform cron.schedule('elolog-emails', '*/5 * * * *', $c$select private.chamar_funcao('enviar-emails')$c$);
  perform cron.schedule('elolog-navios', '7,37 * * * *', $c$select private.chamar_funcao('navios-ais')$c$);
  perform cron.schedule('elolog-pagamentos', '*/10 * * * *', $c$select private.chamar_funcao('pagamentos', '{"acao":"verificar"}'::jsonb)$c$);
  perform cron.schedule('elolog-limpar-net', '17 3 * * *', $c$delete from net._http_response where created < now() - interval '2 days'$c$);
  return 'Tarefas agendadas: emails (5 min), navios (30 min), pagamentos (10 min), limpeza diária.';
end $$;
revoke all on function private.agendar_tarefas(text) from public, anon, authenticated;

create or replace function public.servico_segredo_cron() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret' $$;
revoke all on function public.servico_segredo_cron() from public, anon, authenticated;
grant execute on function public.servico_segredo_cron() to service_role;

-- ---------- 2. Documentos no armazenamento ------------------------------------
-- Limite de 20 MB e só formatos de documento e imagem.
update storage.buckets set file_size_limit = 20971520,
  allowed_mime_types = array['application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  where id = 'documentos';

-- A empresa vê os documentos que o cliente juntou às encomendas dela.
drop policy if exists docs_empresa_ver_cliente on documentos;
create policy docs_empresa_ver_cliente on documentos for select to authenticated
  using (encomenda_id is not null and exists (select 1 from encomendas en
         where en.id = documentos.encomenda_id and en.empresa_id = private.minha_empresa()));

-- O cliente só junta documentos às suas encomendas (ou ao seu perfil, sem encomenda).
drop policy if exists docs_cliente_criar on documentos;
create policy docs_cliente_criar on documentos for insert to authenticated
  with check (cliente_id = auth.uid() and empresa_id is null and enviado_por = auth.uid()
    and (encomenda_id is null or exists (select 1 from encomendas en where en.id = documentos.encomenda_id and en.cliente_id = auth.uid())));

-- ---------- 3. Faturas certificadas -------------------------------------------
-- A Elolog não emite faturas: a empresa carrega o PDF do seu programa certificado pela AT.
-- O QR da fatura (Portaria 195/2020) é lido no navegador e validado aqui antes de ficar registado.
create table if not exists faturas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid references encomendas(id) on delete set null,
  cliente_id uuid,
  documento_id uuid references documentos(id) on delete set null,
  tipo_documento text not null,            -- FT, FR, FS, NC, ND
  numero text not null,                    -- ex.: FT A/123
  atcud text not null,                     -- ex.: JJHC3KYL-123
  data_emissao date not null,
  nif_emitente text not null,
  nif_adquirente text not null,
  total numeric(12,2) not null check (total >= 0),
  total_iva numeric(12,2) not null default 0,
  hash4 text,
  certificado text,
  qr_texto text not null,
  estado text not null default 'valida' check (estado in ('valida','anulada')),
  registada_por uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (empresa_id, numero),
  unique (empresa_id, atcud)
);
alter table faturas enable row level security;
create policy faturas_empresa_ver on faturas for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy faturas_cliente_ver on faturas for select to authenticated using (cliente_id = auth.uid());
create policy faturas_admin_ver on faturas for select to authenticated using (private.e_admin_plataforma());
revoke insert, update, delete on faturas from anon, authenticated;

create or replace function private.nif_valido(p text) returns boolean language plpgsql immutable set search_path = '' as $$
declare s int := 0; i int; d int;
begin
  if p = '999999990' then return true; end if;                -- consumidor final
  if p !~ '^[1-9][0-9]{8}$' then return false; end if;
  for i in 1..8 loop s := s + substr(p, i, 1)::int * (10 - i); end loop;
  d := 11 - (s % 11); if d >= 10 then d := 0; end if;
  return d = substr(p, 9, 1)::int;
end $$;
