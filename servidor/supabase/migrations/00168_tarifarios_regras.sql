-- v114 — Centro de Gestão de Tarifários (2/3): regras validadas no servidor (o navegador não decide nada).
-- Prestador: cria, atualiza (nova versão), desativa e submete. Administração: aprova, rejeita, suspende, pede alterações, reativa.
-- Uma tarifa aprovada nunca muda de valor: as alterações são uma nova versão que só substitui a anterior quando for aprovada.

-- ---------- Guarda das tarifas dos prestadores ----------
create or replace function private.tarifa_guarda() returns trigger language plpgsql security definer set search_path = public as $$
-- de confiança: sem sessão de utilizador (base de dados, instalador, chave de serviço), que já não passa pelas regras de acesso
declare confiavel boolean := auth.uid() is null; admin boolean := confiavel or private.e_admin_plataforma();
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    if confiavel and new.estado = 'rascunho' and new.decidida_em is null then new.estado := case when new.ativa then 'aprovada' else 'inativa' end; end if;
    if not admin and new.estado not in ('rascunho', 'pendente') then new.estado := 'pendente'; end if;
    if new.estado = 'pendente' then new.submetida_em := now(); end if;
    if not admin then new.decidida_em := null; new.decidida_por := null; new.motivo_decisao := null; end if;
  else
    if not admin then
      new.decidida_em := old.decidida_em; new.decidida_por := old.decidida_por; new.motivo_decisao := old.motivo_decisao;
      if new.estado is distinct from old.estado and not ((old.estado, new.estado) in
         (('rascunho','pendente'), ('alteracoes_pedidas','pendente'), ('rejeitada','pendente'), ('inativa','pendente'), ('pendente','rascunho'), ('aprovada','inativa'))) then
        raise exception 'Só a administração Elolog pode aprovar, rejeitar ou suspender tarifas.' using errcode = '42501';
      end if;
      if old.estado in ('aprovada', 'suspensa', 'substituida', 'inativa') and
         (new.aplicacao, new.metodo, new.valor, new.moeda, new.quantidade_minima, new.preco_minimo, new.preco_maximo, new.limite_min, new.limite_max,
          new.origem, new.destino, new.tipo_carga, new.transporte, new.regras::text, new.validade_inicio, new.validade_fim) is distinct from
         (old.aplicacao, old.metodo, old.valor, old.moeda, old.quantidade_minima, old.preco_minimo, old.preco_maximo, old.limite_min, old.limite_max,
          old.origem, old.destino, old.tipo_carga, old.transporte, old.regras::text, old.validade_inicio, old.validade_fim) then
        raise exception 'Uma tarifa aprovada não muda de preço nem de condições: crie uma nova versão e submeta-a.';
      end if;
      if new.estado = 'pendente' and old.estado <> 'pendente' then new.submetida_em := now(); end if;
    end if;
  end if;
  new.ativa := new.estado = 'aprovada';
  return new;
end $$;
create or replace trigger tarifas_guarda before insert or update on public.tarifas for each row execute function private.tarifa_guarda();

-- ---------- Guarda dos suplementos e dos tarifários gerais ----------
create or replace function private.suplemento_guarda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not private.e_admin_plataforma() then
    if new.empresa_id is null then raise exception 'Os suplementos gerais são da administração Elolog.' using errcode = '42501'; end if;
    if tg_op = 'INSERT' then new.estado := 'pendente'; new.motivo_decisao := null;
    else
      new.motivo_decisao := old.motivo_decisao;
      if old.estado = 'aprovado' and (new.tipo, new.valor, new.chave, new.servico, new.tipo_carga, new.automatico) is distinct from (old.tipo, old.valor, old.chave, old.servico, old.tipo_carga, old.automatico)
        then new.estado := 'pendente'; end if;   -- mudar um suplemento aprovado volta a precisar de aprovação
      if new.estado not in ('pendente', 'inativo') and new.estado is distinct from old.estado then
        raise exception 'Só a administração Elolog pode aprovar ou suspender suplementos.' using errcode = '42501'; end if;
    end if;
  end if;
  return new;
end $$;
create or replace trigger tarifa_suplementos_guarda before insert or update on public.tarifa_suplementos for each row execute function private.suplemento_guarda();

create or replace function private.tarifa_geral_codigo() returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if new.codigo is null then new.codigo := 'TG-' || lpad(nextval('public.tarifas_gerais_seq')::text, 4, '0'); end if;
  if tg_op = 'UPDATE' and old.estado = 'substituida' and new.estado <> 'substituida' then raise exception 'Esta versão já foi substituída.'; end if;
  -- mudar o preço ou as condições de um tarifário em vigor exige motivo e cria nova versão (o histórico guarda os valores anteriores)
  if tg_op = 'UPDATE' and old.estado = 'ativa' and (new.metodo, new.valor, new.moeda, new.preco_minimo, new.preco_maximo, new.limite_min, new.limite_max, new.origem, new.destino,
      new.tipo_carga, new.servico, new.regras::text, new.validade_inicio, new.validade_fim, new.prestadores, new.uso) is distinct from
     (old.metodo, old.valor, old.moeda, old.preco_minimo, old.preco_maximo, old.limite_min, old.limite_max, old.origem, old.destino,
      old.tipo_carga, old.servico, old.regras::text, old.validade_inicio, old.validade_fim, old.prestadores, old.uso) then
    if coalesce(trim(new.motivo_alteracao), '') = '' or new.motivo_alteracao is not distinct from old.motivo_alteracao then
      raise exception 'Indique o motivo da alteração: fica no histórico.'; end if;
    new.versao := old.versao + 1;
  end if;
  return new;
end $$;
create or replace trigger tarifas_gerais_codigo before insert or update on public.tarifas_gerais for each row execute function private.tarifa_geral_codigo();

-- ---------- Prestador: guardar (nova tarifa ou nova versão) e submeter, validado no servidor ----------
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
  end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), case when p_base is null then 'Nova tarifa' else 'Nova versão' end), true);
  insert into tarifas (empresa_id, tarifa_pai_id, versao, nome, aplicacao, tipo_carga, metodo, valor, moeda, quantidade_minima, preco_minimo, preco_maximo,
                       limite_min, limite_max, transporte, origem, destino, validade_inicio, validade_fim, regras, notas, estado, criado_por)
  values (v_emp, p_base, coalesce(v_base.versao, 0) + 1, trim(p_dados ->> 'nome'), coalesce(nullif(p_dados ->> 'aplicacao', ''), 'carga')::aplicacao_tarifa,
          nullif(trim(p_dados ->> 'tipo_carga'), ''), (p_dados ->> 'metodo')::metodo_cobranca, round(v_valor, 4), coalesce(nullif(p_dados ->> 'moeda', ''), 'EUR'),
          coalesce(nullif(p_dados ->> 'quantidade_minima', '')::numeric, 0), coalesce(nullif(p_dados ->> 'preco_minimo', '')::numeric, 0), nullif(p_dados ->> 'preco_maximo', '')::numeric,
          v_min, v_max, nullif(trim(p_dados ->> 'transporte'), ''), nullif(trim(p_dados ->> 'origem'), ''), nullif(trim(p_dados ->> 'destino'), ''),
          nullif(p_dados ->> 'validade_inicio', '')::date, nullif(p_dados ->> 'validade_fim', '')::date, coalesce(p_dados -> 'regras', '{}'), nullif(trim(p_dados ->> 'notas'), ''),
          case when p_submeter then 'pendente' else 'rascunho' end, auth.uid())
  returning * into v_nova;
  if p_submeter then
    insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (true, 'tarifa_submetida', 'Uma tarifa espera aprovação',
            (select nome from empresas where id = v_emp) || ' submeteu «' || v_nova.nome || '» (versão ' || v_nova.versao || ').', 'tarifas', v_nova.id);
  end if;
  perform set_config('elolog.motivo', '', true);
  return v_nova;
end $$;
revoke all on function public.tarifa_guardar(jsonb, uuid, boolean, text) from public, anon;
grant execute on function public.tarifa_guardar(jsonb, uuid, boolean, text) to authenticated;

-- ---------- Administração: decidir sobre tarifas e suplementos dos prestadores ----------
create or replace function public.tarifa_decidir(p_tarifa uuid, p_decisao text, p_motivo text default null)
returns public.tarifas language plpgsql security definer set search_path = public as $$
declare v tarifas; v_para text; v_tit text;
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog decide sobre tarifas.' using errcode = '42501'; end if;
  select * into v from tarifas where id = p_tarifa for update;
  if not found then raise exception 'Tarifa inexistente.'; end if;
  v_para := case p_decisao when 'aprovar' then 'aprovada' when 'rejeitar' then 'rejeitada' when 'pedir_alteracoes' then 'alteracoes_pedidas'
                           when 'suspender' then 'suspensa' when 'reativar' then 'aprovada' end;
  if v_para is null then raise exception 'Decisão desconhecida.'; end if;
  if p_decisao in ('aprovar', 'rejeitar', 'pedir_alteracoes') and v.estado <> 'pendente' then raise exception 'Só uma tarifa submetida pode ser %.', replace(p_decisao, '_', ' '); end if;
  if p_decisao = 'suspender' and v.estado <> 'aprovada' then raise exception 'Só uma tarifa aprovada pode ser suspensa.'; end if;
  if p_decisao = 'reativar' and v.estado <> 'suspensa' then raise exception 'Só uma tarifa suspensa pode ser reativada.'; end if;
  if p_decisao <> 'aprovar' and p_decisao <> 'reativar' and coalesce(trim(p_motivo), '') = '' then raise exception 'Indique o motivo: o prestador vai lê-lo.'; end if;
  if v_para = 'aprovada' and v.validade_fim is not null and v.validade_fim < current_date then raise exception 'Esta tarifa já expirou a %.', to_char(v.validade_fim, 'DD/MM/YYYY'); end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), initcap(replace(p_decisao, '_', ' '))), true);
  update tarifas set estado = v_para, decidida_em = now(), decidida_por = auth.uid(), motivo_decisao = nullif(trim(p_motivo), '') where id = v.id returning * into v;
  if p_decisao = 'aprovar' and v.tarifa_pai_id is not null then
    perform set_config('elolog.motivo', 'Substituída pela versão ' || v.versao, true);
    update tarifas set estado = 'substituida' where id = v.tarifa_pai_id and estado in ('aprovada', 'suspensa', 'inativa', 'pendente', 'alteracoes_pedidas', 'rejeitada');
  end if;
  v_tit := case p_decisao when 'aprovar' then 'Tarifa aprovada: já entra nas simulações' when 'rejeitar' then 'Tarifa rejeitada'
           when 'pedir_alteracoes' then 'A Elolog pediu alterações a uma tarifa' when 'suspender' then 'Tarifa suspensa' else 'Tarifa reativada' end;
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (v.empresa_id, 'tarifa_decisao', v_tit, '«' || v.nome || '» (versão ' || v.versao || ')' || coalesce('. ' || nullif(trim(p_motivo), ''), '.'), 'tarifas', v.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois, motivo)
  values (v.empresa_id, auth.uid(), 'admin_plataforma', 'tarifa_' || p_decisao, 'tarifas', v.id::text, jsonb_build_object('estado', v.estado, 'versao', v.versao), nullif(trim(p_motivo), ''));
  perform set_config('elolog.motivo', '', true);
  return v;
end $$;
revoke all on function public.tarifa_decidir(uuid, text, text) from public, anon;
grant execute on function public.tarifa_decidir(uuid, text, text) to authenticated;

create or replace function public.suplemento_decidir(p_suplemento uuid, p_decisao text, p_motivo text default null)
returns public.tarifa_suplementos language plpgsql security definer set search_path = public as $$
declare v tarifa_suplementos; v_para text := case p_decisao when 'aprovar' then 'aprovado' when 'rejeitar' then 'rejeitado' when 'suspender' then 'suspenso' when 'reativar' then 'aprovado' end;
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog decide sobre suplementos.' using errcode = '42501'; end if;
  if v_para is null then raise exception 'Decisão desconhecida.'; end if;
  if p_decisao in ('rejeitar', 'suspender') and coalesce(trim(p_motivo), '') = '' then raise exception 'Indique o motivo: o prestador vai lê-lo.'; end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), initcap(p_decisao)), true);
  update tarifa_suplementos set estado = v_para, motivo_decisao = nullif(trim(p_motivo), '') where id = p_suplemento returning * into v;
  if not found then raise exception 'Suplemento inexistente.'; end if;
  if v.empresa_id is not null then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v.empresa_id, 'suplemento_decisao', 'Suplemento ' || v_para, '«' || v.nome || '»' || coalesce('. ' || nullif(trim(p_motivo), ''), '.'), 'tarifa_suplementos', v.id);
  end if;
  perform set_config('elolog.motivo', '', true);
  return v;
end $$;
revoke all on function public.suplemento_decidir(uuid, text, text) from public, anon;
grant execute on function public.suplemento_decidir(uuid, text, text) to authenticated;
