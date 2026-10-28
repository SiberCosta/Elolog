-- v72 — Novas referências: encomendas ELO_<REF>-000123 (REF = referência do prestador) e simulações ELO_SM-000045.
-- A referência do prestador é criada sozinha a partir do nome (ex.: «Transatlântico Demo, Lda.» → TRAN) e é única.
-- As encomendas e simulações antigas (TR-AAAA-NNNNNN / SIM-AAAA-NNNNNN) passam para o formato novo.

alter table empresas add column if not exists referencia text;

-- Referência curta e única a partir do nome: 4 letras da primeira palavra (sem acentos); se faltar, completa com a seguinte; se já existir, junta um número.
create or replace function private.referencia_empresa(p_nome text, p_id uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_base text; v_ref text; n int := 1;
begin
  v_base := upper(translate(coalesce(p_nome, ''), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ', 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn'));
  v_base := regexp_replace(v_base, '\m(LDA|LIMITADA|SA|S\.A|UNIPESSOAL|SOCIEDADE|COMPANHIA|CIA)\M', '', 'g');
  v_base := left(regexp_replace(v_base, '[^A-Z]', '', 'g'), 4);
  if length(v_base) < 3 then v_base := rpad(coalesce(nullif(v_base, ''), 'PRS'), 3, 'X'); end if;
  v_ref := v_base;
  while exists (select 1 from empresas where referencia = v_ref and id <> p_id) loop n := n + 1; v_ref := v_base || n; end loop;
  return v_ref;
end $$;

do $$ declare e record; begin
  for e in select id, coalesce(nullif(nome_comercial, ''), nome) n from empresas where referencia is null order by created_at loop
    update empresas set referencia = private.referencia_empresa(e.n, e.id) where id = e.id;
  end loop;
end $$;
create unique index if not exists empresas_referencia on empresas (referencia);
do $$ begin
  alter table empresas add constraint empresas_referencia_chk check (referencia ~ '^[A-Z0-9]{2,8}$');
exception when duplicate_object then null; end $$;

create or replace function private.empresa_referencia_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.referencia is null or new.referencia = '' then new.referencia := private.referencia_empresa(coalesce(nullif(new.nome_comercial, ''), new.nome), new.id); end if;
  new.referencia := upper(new.referencia);
  return new;
end $$;
create or replace trigger empresas_referencia_auto before insert or update of referencia on empresas for each row execute function private.empresa_referencia_auto();

-- Numeração contínua (não recomeça no ano novo): contadores com ano = 0.
create or replace function private.codigo_elo(p_prefixo text) returns text
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  insert into contadores (prefixo, ano, valor) values (p_prefixo, 0, 1)
  on conflict (prefixo, ano) do update set valor = contadores.valor + 1 returning valor into v;
  return p_prefixo || '-' || lpad(v::text, 6, '0');
end $$;
grant execute on function private.codigo_elo(text) to authenticated, service_role;

-- Encomendas: o código é dado pelo servidor ao criar (ELO_<REF>-NNNNNN).
alter table encomendas alter column codigo set default '';
create or replace function private.encomenda_codigo_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.codigo, '') = '' then
    new.codigo := private.codigo_elo('ELO_' || coalesce((select referencia from empresas where id = new.empresa_id), 'PRS'));
  end if;
  return new;
end $$;
create or replace trigger encomendas_codigo_auto before insert on encomendas for each row execute function private.encomenda_codigo_auto();

-- Simulações: ELO_SM-NNNNNN.
alter table simulacoes alter column codigo set default private.codigo_elo('ELO_SM');

-- Converter os códigos antigos (só os do formato automático).
do $$ declare r record; begin
  for r in select e.id, m.referencia from encomendas e join empresas m on m.id = e.empresa_id where e.codigo ~ '^TR-\d{4}-\d{6}$' order by e.created_at loop
    update encomendas set codigo = private.codigo_elo('ELO_' || r.referencia) where id = r.id;
  end loop;
  for r in select id from simulacoes where codigo ~ '^SIM-\d{4}-\d{6}$' order by created_at loop
    update simulacoes set codigo = private.codigo_elo('ELO_SM') where id = r.id;
  end loop;
end $$;
