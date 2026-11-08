-- v114 — Uma comissão em percentagem fica entre 0 e 100 % (validado no servidor, não só no formulário).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'regras_comissao_percentagem_valida') then
    alter table public.regras_comissao add constraint regras_comissao_percentagem_valida
      check (valor >= 0 and (tipo_valor::text <> 'percentagem' or valor <= 100)) not valid;
  end if;
end $$;
