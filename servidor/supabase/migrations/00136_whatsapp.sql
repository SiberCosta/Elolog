-- v66 — Assistente ELO no WhatsApp (WhatsApp Business Cloud API da Meta).
-- A Edge Function «whatsapp-elo» recebe as mensagens e responde; estas funções só correm com a chave de serviço.

create table if not exists whatsapp_conversas (
  telefone     text primary key,                 -- número do cliente, só dígitos, com indicativo
  nome         text,
  passo        text,
  dados        jsonb not null default '{}',
  humano_desde timestamptz,
  mensagens    int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table whatsapp_conversas enable row level security;
revoke all on whatsapp_conversas from anon, authenticated;

-- Estado de uma encomenda pedido por WhatsApp: só responde se o número de quem pergunta for o do cliente,
-- o da encomenda ou o do destinatário (últimos 9 dígitos). Caso contrário não revela nada.
create or replace function public.servico_whatsapp_estado(p_codigo text, p_telefone text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; v_tel text := right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 9); v_ok boolean;
begin
  if length(v_tel) < 9 then return jsonb_build_object('autorizado', false); end if;
  select * into e from encomendas where upper(codigo) = upper(trim(p_codigo));
  if not found then return jsonb_build_object('autorizado', false); end if;
  select v_tel in (
           right(regexp_replace(coalesce(e.cliente_telefone, ''), '\D', '', 'g'), 9),
           right(regexp_replace(coalesce(e.destinatario->>'telefone', ''), '\D', '', 'g'), 9),
           right(regexp_replace(coalesce((select c.telefone from clientes c where c.id = e.cliente_id), ''), '\D', '', 'g'), 9))
    into v_ok;
  if not coalesce(v_ok, false) then return jsonb_build_object('autorizado', false); end if;
  return jsonb_build_object('autorizado', true, 'codigo', e.codigo, 'estado', e.estado::text, 'origem', e.origem,
    'destino', e.destino, 'data_prevista', e.data_prevista, 'atualizado', e.updated_at,
    'prestador', (select coalesce(m.nome_comercial, m.nome) from empresas m where m.id = e.empresa_id));
end $$;

-- Pedido de atendimento humano: avisa a administração (notificação + email) e marca a conversa.
create or replace function public.servico_whatsapp_pedido_humano(p_telefone text, p_nome text, p_mensagem text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into notificacoes (para_plataforma, tipo, titulo, corpo)
  values (true, 'apoio', 'Pedido de contacto por WhatsApp',
          left(coalesce(nullif(trim(p_nome), ''), 'Sem nome') || ' · +' || regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')
               || coalesce(' · «' || nullif(trim(p_mensagem), '') || '»', ''), 480));
  update whatsapp_conversas set humano_desde = now(), updated_at = now() where telefone = regexp_replace(p_telefone, '\D', '', 'g');
end $$;

revoke all on function public.servico_whatsapp_estado(text, text), public.servico_whatsapp_pedido_humano(text, text, text) from public, anon, authenticated;
grant execute on function public.servico_whatsapp_estado(text, text), public.servico_whatsapp_pedido_humano(text, text, text) to service_role;
grant select, insert, update on whatsapp_conversas to service_role;
