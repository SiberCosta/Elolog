-- v127 — Fase 1 (3/3): comprovativo de entrega/recolha no terreno (quem recebeu, assinatura, fotografias, posição e hora), que funciona sem rede:
-- a aplicação guarda-o no telemóvel e envia-o quando houver ligação; o código local (id_local) impede que seja gravado duas vezes.
-- Um comprovativo nunca se altera nem se apaga. A entrega com assinatura passa a contar como confirmação para concluir a encomenda («entregue»)
-- e emite o documento «Comprovativo de entrega» (EL-ENT) no Centro Documental. Só acrescenta tabelas e funções.

create table if not exists public.comprovativos_terreno (
  id uuid primary key default gen_random_uuid(), id_local uuid not null unique,
  trabalho_id uuid not null references public.trabalhos_terreno(id), encomenda_id uuid references public.encomendas(id),
  empresa_id uuid not null references public.empresas(id), tipo text not null check (tipo in ('recolha', 'entrega')),
  resultado text not null check (resultado in ('entregue', 'recolhido', 'cliente_ausente', 'recusado')),
  recebido_por text check (length(recebido_por) <= 120), identificacao text check (length(identificacao) <= 60),
  assinatura text check (assinatura ~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' and length(assinatura) <= 300000),
  notas text check (length(notas) <= 1000), volumes_conferidos int check (volumes_conferidos between 0 and 100000),
  lat numeric(9,6) check (lat between -90 and 90), lon numeric(9,6) check (lon between -180 and 180), precisao_m int,
  feito_em timestamptz not null, recebido_em timestamptz not null default now(), criado_por uuid not null);
create table if not exists public.comprovativos_terreno_fotos (
  id bigint generated always as identity primary key, comprovativo_id uuid not null references public.comprovativos_terreno(id), n int not null,
  imagem text not null check (imagem ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/=]+$' and length(imagem) <= 700000), unique (comprovativo_id, n));
create index if not exists comprovativos_terreno_encomenda on public.comprovativos_terreno (encomenda_id);
alter table public.comprovativos_terreno enable row level security;
alter table public.comprovativos_terreno_fotos enable row level security;
revoke all on public.comprovativos_terreno, public.comprovativos_terreno_fotos from anon, authenticated;
grant select on public.comprovativos_terreno, public.comprovativos_terreno_fotos to authenticated;
create or replace function private.comprovativo_visivel(c public.comprovativos_terreno) returns boolean language sql stable security definer set search_path = public as $$
  select private.e_admin_plataforma() or (c.empresa_id = private.minha_empresa() and (private.meu_papel() <> 'operador_terreno' or c.criado_por = auth.uid()))
      or exists (select 1 from encomendas e where e.id = c.encomenda_id and e.cliente_id = auth.uid()) $$;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'comprovativos_terreno' and policyname = 'comprovativos_ver') then
    create policy comprovativos_ver on public.comprovativos_terreno for select to authenticated using (private.comprovativo_visivel(comprovativos_terreno)); end if;
  if not exists (select 1 from pg_policies where tablename = 'comprovativos_terreno_fotos' and policyname = 'comprovativos_fotos_ver') then
    create policy comprovativos_fotos_ver on public.comprovativos_terreno_fotos for select to authenticated
      using (exists (select 1 from public.comprovativos_terreno c where c.id = comprovativo_id and private.comprovativo_visivel(c))); end if;
end $$;
create or replace function private.comprovativo_imutavel() returns trigger language plpgsql as $$ begin raise exception 'Um comprovativo do terreno não pode ser alterado nem apagado.'; end $$;
create or replace trigger comprovativos_imutavel before update or delete on public.comprovativos_terreno for each row execute function private.comprovativo_imutavel();
create or replace trigger comprovativos_fotos_imutavel before update or delete on public.comprovativos_terreno_fotos for each row execute function private.comprovativo_imutavel();

-- p = {id_local, trabalho, resultado, recebido_por, identificacao, assinatura, notas, volumes, lat, lon, precisao, feito_em, fotos:[dataURL,…]}
create or replace function public.registar_comprovativo(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare t trabalhos_terreno; c comprovativos_terreno; v_id uuid; v_quando timestamptz; v_res text := p ->> 'resultado'; f text; i int := 0; lim int; aviso text; e encomendas;
begin
  begin v_id := (p ->> 'id_local')::uuid; exception when others then raise exception 'Comprovativo sem código local válido.'; end;
  select * into c from comprovativos_terreno where id_local = v_id;
  if found then return jsonb_build_object('id', c.id, 'repetido', true); end if;   -- reenvio sem rede: já estava gravado
  t := private.trabalho_meu((p ->> 'trabalho')::uuid);
  if t.tipo not in ('recolha', 'entrega') then raise exception 'Este serviço não tem comprovativo.'; end if;
  if v_res not in ('entregue', 'recolhido', 'cliente_ausente', 'recusado') or (t.tipo = 'entrega' and v_res = 'recolhido') or (t.tipo = 'recolha' and v_res = 'entregue') then raise exception 'Resultado inválido.'; end if;
  if v_res in ('entregue', 'recolhido') then
    if length(trim(coalesce(p ->> 'recebido_por', ''))) < 2 then raise exception 'Indique o nome de quem %.', case when v_res = 'entregue' then 'recebeu' else 'entregou a carga' end; end if;
    if coalesce(p ->> 'assinatura', '') = '' then raise exception 'Falta a assinatura.'; end if;
  end if;
  v_quando := coalesce(nullif(p ->> 'feito_em', '')::timestamptz, now());
  if v_quando < now() - interval '7 days' or v_quando > now() + interval '10 minutes' then v_quando := now(); end if;
  lim := nullif((public.limites_anexos(t.empresa_id) ->> 'fotos'), '')::int;
  if lim is not null and jsonb_array_length(coalesce(p -> 'fotos', '[]')) > lim then raise exception 'A empresa permite no máximo % fotografia(s) por serviço.', lim; end if;
  insert into comprovativos_terreno (id_local, trabalho_id, encomenda_id, empresa_id, tipo, resultado, recebido_por, identificacao, assinatura, notas, volumes_conferidos, lat, lon, precisao_m, feito_em, criado_por)
  values (v_id, t.id, t.encomenda_id, t.empresa_id, t.tipo::text, v_res, nullif(trim(p ->> 'recebido_por'), ''), nullif(trim(p ->> 'identificacao'), ''), nullif(p ->> 'assinatura', ''),
          nullif(trim(p ->> 'notas'), ''), nullif(p ->> 'volumes', '')::int, nullif(p ->> 'lat', '')::numeric, nullif(p ->> 'lon', '')::numeric, nullif(p ->> 'precisao', '')::int, v_quando, auth.uid())
  returning * into c;
  for f in select jsonb_array_elements_text(coalesce(p -> 'fotos', '[]')) loop i := i + 1; insert into comprovativos_terreno_fotos (comprovativo_id, n, imagem) values (c.id, i, f); end loop;
  update trabalhos_terreno set estado = case when v_res in ('cliente_ausente', 'recusado') then 'cliente_ausente'::estado_trabalho else 'concluida' end, updated_at = now() where id = t.id;
  update trabalhos_seguimento set terminado_em = coalesce(terminado_em, now()) where trabalho_id = t.id;
  perform private.emitir_evento(t.empresa_id, 'terreno.comprovativo', (select codigo from encomendas where id = t.encomenda_id), jsonb_build_object('servico', t.tipo, 'resultado', v_res, 'feito_em', v_quando));
  if t.tipo = 'entrega' and v_res = 'entregue' and t.encomenda_id is not null then
    insert into entregas (encomenda_id, identificacao, entregue_por, entregue_em) values (t.encomenda_id, coalesce(c.identificacao, c.recebido_por), auth.uid(), v_quando)
      on conflict (encomenda_id) do update set identificacao = excluded.identificacao, entregue_por = excluded.entregue_por, entregue_em = excluded.entregue_em, updated_at = now();
    select * into e from encomendas where id = t.encomenda_id;
    if e.estado = 'disponivel' then
      begin perform public.avancar_encomenda(e.id, 'entregue', 'Entregue a ' || c.recebido_por || ' (comprovativo assinado no terreno)');
      exception when others then aviso := 'Comprovativo guardado; a encomenda não passou a «Entregue»: ' || sqlerrm; end;
    else aviso := 'Comprovativo guardado. A encomenda está em «' || e.estado || '»: o escritório conclui a entrega.'; end if;
    begin perform private.documento_emitir('entrega', t.encomenda_id, null, null, false);
    exception when others then raise warning 'Centro documental: comprovativo de entrega não emitido: %', sqlerrm; end;
  end if;
  return jsonb_build_object('id', c.id, 'repetido', false, 'aviso', aviso);
end $$;

-- a entrega assinada no terreno também confirma o levantamento (além da identificação + assinatura/PIN do escritório)
create or replace function private.entrega_confirmada(p_encomenda uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from entregas en where en.encomenda_id = p_encomenda and coalesce(en.identificacao, '') <> '' and (en.assinatura_documento_id is not null or en.pin_validado))
      or exists (select 1 from comprovativos_terreno c where c.encomenda_id = p_encomenda and c.resultado = 'entregue' and c.assinatura is not null) $$;
revoke all on function private.entrega_confirmada(uuid) from public, anon, authenticated;
revoke all on function private.comprovativo_visivel(comprovativos_terreno) from public, anon;
grant execute on function private.comprovativo_visivel(comprovativos_terreno) to authenticated;   -- usada pela regra de acesso
revoke all on function public.registar_comprovativo(jsonb) from public, anon;
grant execute on function public.registar_comprovativo(jsonb) to authenticated;
