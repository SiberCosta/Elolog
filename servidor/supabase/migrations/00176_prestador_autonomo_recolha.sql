-- v116 — 1) As tarifas, veículos e suplementos criados pelo prestador entram logo em vigor (não dependem da administração;
--          a Elolog mantém só o poder de suspender, que só ela levanta). 2) Toda a equipa do prestador lê as tarifas em vigor.
--       3) Tarifas de veículos podem ser eliminadas (fica no histórico). 4) Limites de fotografias e documentos definidos pelo prestador.
--       5) Distância da recolha medida a partir dos armazéns do prestador guardados no servidor (validada no servidor).

-- ---------- 1. Tarifas do prestador: em vigor ao guardar ----------
create or replace function private.tarifa_guarda() returns trigger language plpgsql security definer set search_path = public as $$
declare confiavel boolean := auth.uid() is null; admin boolean := confiavel or private.e_admin_plataforma();
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    if confiavel and new.estado = 'rascunho' and new.decidida_em is null then new.estado := case when new.ativa then 'aprovada' else 'inativa' end; end if;
    if not admin then
      if new.estado not in ('rascunho', 'inativa') then new.estado := 'aprovada'; end if;   -- o prestador publica: entra logo em vigor
      new.decidida_em := null; new.decidida_por := null; new.motivo_decisao := null;
    end if;
  else
    if not admin then
      new.decidida_em := old.decidida_em; new.decidida_por := old.decidida_por; new.motivo_decisao := old.motivo_decisao;
      if new.estado = 'pendente' then new.estado := 'aprovada'; end if;
      if new.estado is distinct from old.estado and (old.estado = 'suspensa' or new.estado in ('suspensa', 'rejeitada', 'alteracoes_pedidas')) then
        raise exception 'Esta tarifa foi suspensa pela Elolog: só a Elolog a pode reativar.' using errcode = '42501';
      end if;
      if old.estado in ('aprovada', 'suspensa', 'substituida', 'inativa') and
         (new.aplicacao, new.metodo, new.valor, new.moeda, new.quantidade_minima, new.preco_minimo, new.preco_maximo, new.limite_min, new.limite_max,
          new.origem, new.destino, new.tipo_carga, new.transporte, new.regras::text, new.validade_inicio, new.validade_fim) is distinct from
         (old.aplicacao, old.metodo, old.valor, old.moeda, old.quantidade_minima, old.preco_minimo, old.preco_maximo, old.limite_min, old.limite_max,
          old.origem, old.destino, old.tipo_carga, old.transporte, old.regras::text, old.validade_inicio, old.validade_fim) then
        raise exception 'Uma tarifa em vigor não muda de preço nem de condições: guarde uma nova versão (as encomendas já aceites mantêm o preço).';
      end if;
    end if;
  end if;
  new.ativa := new.estado = 'aprovada';
  return new;
end $$;

create or replace function public.tarifa_guardar(p_dados jsonb, p_base uuid default null, p_submeter boolean default true, p_motivo text default null)
returns public.tarifas language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_base tarifas; v_nova tarifas; v_valor numeric := (p_dados ->> 'valor')::numeric;
        v_min numeric := nullif(p_dados ->> 'limite_min', '')::numeric; v_max numeric := nullif(p_dados ->> 'limite_max', '')::numeric;
begin
  if v_emp is null or not private.papel_em(array['admin_empresa', 'financeiro']) then raise exception 'Só o administrador ou o financeiro da empresa podem gravar tarifas.' using errcode = '42501'; end if;
  if coalesce(trim(p_dados ->> 'nome'), '') = '' or length(p_dados ->> 'nome') > 120 then raise exception 'Indique o nome da tarifa (até 120 caracteres).'; end if;
  if v_valor is null or v_valor < 0 or v_valor > 10000000 then raise exception 'Indique um valor entre 0 e 10 000 000.'; end if;
  if v_min is not null and v_max is not null and v_max < v_min then raise exception 'O limite máximo é menor do que o mínimo.'; end if;
  if nullif(p_dados ->> 'validade_fim', '')::date < current_date then raise exception 'A data de fim já passou: esta tarifa nasceria expirada.'; end if;
  if p_base is not null then
    select * into v_base from tarifas where id = p_base and empresa_id = v_emp;
    if not found then raise exception 'Tarifa de origem inexistente.'; end if;
    if v_base.estado = 'substituida' then raise exception 'Esta versão já foi substituída; parta da versão em vigor.'; end if;
    if v_base.estado = 'suspensa' then raise exception 'Esta tarifa foi suspensa pela Elolog: fale com a Elolog antes de a alterar.'; end if;
  end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), case when p_base is null then 'Nova tarifa' else 'Nova versão' end), true);
  insert into tarifas (empresa_id, tarifa_pai_id, versao, nome, aplicacao, tipo_carga, metodo, valor, moeda, quantidade_minima, preco_minimo, preco_maximo,
                       limite_min, limite_max, transporte, origem, destino, validade_inicio, validade_fim, regras, notas, estado, criado_por)
  values (v_emp, p_base, coalesce(v_base.versao, 0) + 1, trim(p_dados ->> 'nome'), coalesce(nullif(p_dados ->> 'aplicacao', ''), 'carga')::aplicacao_tarifa,
          nullif(trim(p_dados ->> 'tipo_carga'), ''), (p_dados ->> 'metodo')::metodo_cobranca, round(v_valor, 4), coalesce(nullif(p_dados ->> 'moeda', ''), 'EUR'),
          coalesce(nullif(p_dados ->> 'quantidade_minima', '')::numeric, 0), coalesce(nullif(p_dados ->> 'preco_minimo', '')::numeric, 0), nullif(p_dados ->> 'preco_maximo', '')::numeric,
          v_min, v_max, nullif(trim(p_dados ->> 'transporte'), ''), nullif(trim(p_dados ->> 'origem'), ''), nullif(trim(p_dados ->> 'destino'), ''),
          nullif(p_dados ->> 'validade_inicio', '')::date, nullif(p_dados ->> 'validade_fim', '')::date, coalesce(p_dados -> 'regras', '{}'), nullif(trim(p_dados ->> 'notas'), ''),
          case when p_submeter then 'aprovada' else 'rascunho' end, auth.uid())
  returning * into v_nova;
  -- a nova versão em vigor substitui a anterior (as encomendas já aceites guardam a cópia do preço)
  if p_submeter and p_base is not null and v_base.estado in ('aprovada', 'inativa', 'rascunho', 'pendente', 'alteracoes_pedidas', 'rejeitada') then
    update tarifas set estado = 'substituida' where id = p_base;
  end if;
  perform set_config('elolog.motivo', '', true);
  return v_nova;
end $$;
revoke all on function public.tarifa_guardar(jsonb, uuid, boolean, text) from public, anon;
grant execute on function public.tarifa_guardar(jsonb, uuid, boolean, text) to authenticated;

-- o que estava à espera da Elolog entra em vigor agora (a anterior versão fica substituída)
update tarifas p set estado = 'substituida'
 where p.estado = 'aprovada' and exists (select 1 from tarifas n where n.tarifa_pai_id = p.id and n.estado = 'pendente');
update tarifas set estado = 'aprovada' where estado = 'pendente';

-- veículos e suplementos do prestador: em vigor ao guardar
create or replace function private.veiculo_guarda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not private.e_admin_plataforma() then
    if new.empresa_id is null then raise exception 'As tarifas gerais de veículos são da administração Elolog.' using errcode = '42501'; end if;
    if tg_op = 'INSERT' then new.estado := case when new.estado = 'inativo' then 'inativo' else 'aprovado' end; new.motivo_decisao := null; new.versao := 1;
    else
      new.motivo_decisao := old.motivo_decisao; new.empresa_id := old.empresa_id;
      if new.estado = 'pendente' then new.estado := 'aprovado'; end if;
      if new.estado is distinct from old.estado and (old.estado = 'suspenso' or new.estado not in ('aprovado', 'inativo')) then
        raise exception 'Esta tarifa de veículo foi suspensa pela Elolog: só a Elolog a pode reativar.' using errcode = '42501'; end if;
    end if;
  end if;
  if tg_op = 'UPDATE' and (new.preco_saida, new.preco_km, new.preco_minimo, new.capacidade_kg, new.capacidade_m3)
     is distinct from (old.preco_saida, old.preco_km, old.preco_minimo, old.capacidade_kg, old.capacidade_m3) then new.versao := old.versao + 1; end if;
  return new;
end $$;
create or replace function private.veiculo_aviso() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.empresa_id is not null then
    insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (true, 'veiculo_publicado', 'Um prestador publicou uma tarifa de veículo',
            coalesce((select nome from empresas where id = new.empresa_id), 'Um prestador') || ' publicou «' || new.nome || '».', 'tarifas_veiculos', new.id);
  end if;
  return new;
end $$;
update tarifas_veiculos set estado = 'aprovado' where estado = 'pendente';

create or replace function private.suplemento_guarda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not private.e_admin_plataforma() then
    if new.empresa_id is null then raise exception 'Os suplementos gerais são da administração Elolog.' using errcode = '42501'; end if;
    if tg_op = 'INSERT' then new.estado := case when new.estado = 'inativo' then 'inativo' else 'aprovado' end; new.motivo_decisao := null;
    else
      new.motivo_decisao := old.motivo_decisao;
      if new.estado = 'pendente' then new.estado := 'aprovado'; end if;
      if new.estado is distinct from old.estado and (old.estado = 'suspenso' or new.estado not in ('aprovado', 'inativo')) then
        raise exception 'Este suplemento foi suspenso pela Elolog: só a Elolog o pode reativar.' using errcode = '42501'; end if;
    end if;
  end if;
  return new;
end $$;
update tarifa_suplementos set estado = 'aprovado' where estado = 'pendente' and empresa_id is not null;

-- ---------- 2. Toda a equipa do prestador lê as tarifas em vigor (operadores, armazém, terreno) ----------
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas' and policyname = 'tarifas_ver_equipa') then
  create policy tarifas_ver_equipa on public.tarifas for select to authenticated using (empresa_id = private.minha_empresa() and estado = 'aprovada');
end if; end $$;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_equipa_ve') then
  create policy tv_equipa_ve on public.tarifas_veiculos for select to authenticated using (empresa_id = private.minha_empresa() and estado = 'aprovado');
end if; end $$;

-- ---------- 3. Eliminar tarifas de veículos (o prestador as suas; a administração qualquer uma) — fica no histórico ----------
grant delete on public.tarifas_veiculos to authenticated;
create or replace function private.tarifa_registo_eliminada() returns trigger language plpgsql security definer set search_path = public as $$
declare nome text;
begin
  select coalesce((select f.nome from funcionarios f where f.id = auth.uid()), (select ap.nome from administradores_plataforma ap where ap.user_id = auth.uid()), 'Sistema') into nome;
  insert into tarifas_historico (entidade, registo_id, empresa_id, versao, estado_anterior, estado_novo, antes, depois, motivo, user_id, user_nome)
  values (tg_table_name, old.id, old.empresa_id, old.versao, old.estado, 'eliminada', to_jsonb(old), null,
          coalesce(nullif(current_setting('elolog.motivo', true), ''), 'Eliminada'), auth.uid(), nome);
  return old;
end $$;
create or replace trigger tarifas_veiculos_eliminada after delete on public.tarifas_veiculos for each row execute function private.tarifa_registo_eliminada();
