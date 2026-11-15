-- Elolog v147: manifestos completos no servidor (contentor, selo, viatura, notas, anexos, registo de alterações).
-- Só acrescenta uma coluna; não apaga nem altera dados existentes.
alter table public.manifestos add column if not exists detalhes jsonb not null default '{}'::jsonb;
alter table public.manifestos add constraint manifestos_detalhes_objeto check (jsonb_typeof(detalhes) = 'object' and pg_column_size(detalhes) < 200000);
comment on column public.manifestos.detalhes is 'Detalhes do manifesto (contentor, selo, viatura, notas, anexos, registo de alterações) — v146';
