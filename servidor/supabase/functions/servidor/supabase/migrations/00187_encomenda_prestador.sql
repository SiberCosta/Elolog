-- v128: o prestador cria encomendas NO SERVIDOR (antes ficavam só no navegador de quem as criava e os colegas não as viam).
-- A encomenda entra em «Aprovação» da empresa e aparece a todos os funcionários. O código local (id_local) evita duplicados quando o
-- navegador reenvia encomendas antigas. O preço (incluindo a recolha por km) fica registado em preco_detalhe. Só acrescenta uma tabela e funções.

create table if not exists public.encomendas_origem_local (
  id_local text primary key check (length(id_local) between 4 and 80),
  encomenda_id uuid not null references public.encomendas(id), empresa_id uuid not null references public.empresas(id),
  criado_em timestamptz not null default now());
alter table public.encomendas_origem_local enable row level security;
revoke all on public.encomendas_origem_local from anon, authenticated;

create or replace function public.criar_encomenda_prestador(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_papel text := private.meu_papel()::text; v_id text := trim(coalesce(p ->> 'id_local', '')); e encomendas; v_existe uuid;
        rem jsonb; dest jsonb; vols jsonb := '[]'::jsonb; v jsonb; preco numeric := nullif(p ->> 'preco_total', '')::numeric; km numeric := nullif(p ->> 'km_recolha', '')::numeric;
        t text := '';
begin
  if v_emp is null or v_papel not in ('admin_empresa', 'operador', 'operador_terreno') then raise exception 'Só funcionários da empresa (administração, operação ou terreno) criam encomendas.' using errcode = '42501'; end if;
  if length(v_id) < 4 then raise exception 'Encomenda sem código local.'; end if;
  select encomenda_id into v_existe from encomendas_origem_local where id_local = v_id and empresa_id = v_emp;
  if v_existe is not null then select * into e from encomendas where id = v_existe; return jsonb_build_object('id', e.id, 'codigo', e.codigo, 'repetido', true); end if;
  if coalesce(trim(p ->> 'origem'), '') = '' or coalesce(trim(p ->> 'destino'), '') = '' then raise exception 'Indique a origem e o destino.'; end if;
  if coalesce(trim(p ->> 'cliente_nome'), '') = '' then raise exception 'Indique o cliente ou remetente.'; end if;
  if preco is not null and (preco < 0 or preco > 10000000) then raise exception 'Valor da encomenda inválido.'; end if;
  if km is not null and (km < 0 or km > 5000) then raise exception 'Distância de recolha inválida.'; end if;
  if jsonb_typeof(coalesce(p -> 'volumes', '[]')) <> 'array' or jsonb_array_length(coalesce(p -> 'volumes', '[]')) > 200 then raise exception 'Lista de volumes inválida.'; end if;
  for v in select * from jsonb_array_elements(coalesce(p -> 'volumes', '[]')) loop
    vols := vols || jsonb_strip_nulls(jsonb_build_object('descricao', left(v ->> 'descricao', 200), 'quantidade', nullif(v ->> 'quantidade', '')::numeric, 'peso', nullif(v ->> 'peso', '')::numeric,
      'comprimento', nullif(v ->> 'comprimento', '')::numeric, 'largura', nullif(v ->> 'largura', '')::numeric, 'altura', nullif(v ->> 'altura', '')::numeric, 'valor', nullif(v ->> 'valor', '')::numeric));
  end loop;
  rem := jsonb_strip_nulls(jsonb_build_object('nome', left(nullif(trim(p -> 'remetente' ->> 'nome'), ''), 120), 'telefone', left(nullif(trim(p -> 'remetente' ->> 'telefone'), ''), 40),
    'email', left(nullif(trim(p -> 'remetente' ->> 'email'), ''), 160), 'morada', left(nullif(trim(p -> 'remetente' ->> 'morada'), ''), 300)));
  dest := jsonb_strip_nulls(jsonb_build_object('nome', left(nullif(trim(p -> 'destinatario' ->> 'nome'), ''), 120), 'telefone', left(nullif(trim(p -> 'destinatario' ->> 'telefone'), ''), 40),
    'email', left(nullif(trim(p -> 'destinatario' ->> 'email'), ''), 160), 'nif', left(nullif(trim(p -> 'destinatario' ->> 'nif'), ''), 20), 'morada', left(nullif(trim(p -> 'destinatario' ->> 'morada'), ''), 300)));
  insert into encomendas (empresa_id, cliente_nome, cliente_nif, cliente_telefone, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, estado, criada_no_terreno,
                          preco_total, data_prevista, criado_por, morada_recolha, remetente, destinatario, valor_declarado, observacoes, preco_detalhe)
  values (v_emp, left(trim(p ->> 'cliente_nome'), 160), left(nullif(trim(p ->> 'cliente_nif'), ''), 20), left(nullif(trim(p -> 'remetente' ->> 'telefone'), ''), 40),
          left(trim(p ->> 'origem'), 200), left(trim(p ->> 'destino'), 200), left(nullif(trim(p ->> 'tipo_carga'), ''), 120), left(nullif(trim(p ->> 'descricao'), ''), 1000),
          nullif(p ->> 'quantidade', '')::numeric::int, nullif(p ->> 'peso_kg', '')::numeric, nullif(p ->> 'volume_m3', '')::numeric, vols, 'aprovacao', v_papel = 'operador_terreno',
          preco, nullif(p ->> 'data_prevista', '')::date, auth.uid(), case when coalesce((p ->> 'recolha')::boolean, false) then left(nullif(trim(p ->> 'morada_recolha'), ''), 300) end,
          rem, dest, nullif(p ->> 'valor_declarado', '')::numeric, left(nullif(trim(p ->> 'observacoes'), ''), 1000),
          jsonb_strip_nulls(jsonb_build_object('origem', 'prestador', 'recolha_km', km, 'recolha_valor', nullif(p ->> 'recolha_valor', '')::numeric, 'recolha_tarifa', left(p ->> 'recolha_tarifa', 120),
            'carga_valor', nullif(p ->> 'carga_valor', '')::numeric, 'moeda', 'EUR')))
  returning * into e;
  insert into encomendas_origem_local (id_local, encomenda_id, empresa_id) values (v_id, e.id, v_emp);
  select coalesce(nome, '') into t from funcionarios where id = auth.uid();
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id, codigo, responsavel, prestador)
  values (e.id, v_emp, null, 'aprovacao', 'Encomenda criada pelo prestador', auth.uid(), e.codigo, t, (select coalesce(nome_comercial, nome) from empresas where id = v_emp));
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (v_emp, 'encomenda_nova', 'Nova encomenda para aprovar: ' || e.codigo, t || ' criou a encomenda ' || e.origem || ' → ' || e.destino || '.', 'encomendas', e.id);
  return jsonb_build_object('id', e.id, 'codigo', e.codigo, 'repetido', false);
end $$;
revoke all on function public.criar_encomenda_prestador(jsonb) from public, anon;
grant execute on function public.criar_encomenda_prestador(jsonb) to authenticated;
