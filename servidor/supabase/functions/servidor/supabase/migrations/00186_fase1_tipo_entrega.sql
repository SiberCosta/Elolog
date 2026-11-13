-- v127 — Fase 1: o Centro Documental aceita o tipo «entrega» (comprovativo de entrega). Troca a regra de tipos por uma mais larga;
-- nenhum documento existente é alterado (só se acrescenta um valor permitido).
alter table public.documentos_emitidos drop constraint if exists documentos_emitidos_tipo_check;
alter table public.documentos_emitidos add constraint documentos_emitidos_tipo_check check (tipo in ('guia', 'rececao', 'pagamento', 'entrega'));
