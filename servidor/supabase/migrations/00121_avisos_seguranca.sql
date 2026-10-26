-- =====================================================================
-- Elolog · 0012 · Correções dos avisos de segurança do Supabase (aplicada no projeto «Elolog T» a 24/10/2026)
-- Depende de 0001–0011.
--   1. A vista empresas_disponiveis passa a respeitar as permissões de quem consulta (security_invoker)
--      e deixa de estar exposta na API: só as funções do servidor a usam (calcular_propostas, enviar_simulacao),
--      e essas correm como dono, por isso continuam a ver todas as empresas aprovadas.
--   2. search_path fixo nas funções internas que ainda não o tinham.
--   3. Tabelas internas (segredos, sessões, tentativas, fila de e-mails, contadores) sem qualquer privilégio
--      para anon/authenticated. O RLS já as bloqueava; isto é uma segunda camada.
-- =====================================================================
alter view public.empresas_disponiveis set (security_invoker = true);
revoke all on public.empresas_disponiveis from anon, authenticated;

alter function private.set_updated_at()                                   set search_path = public;
alter function private.bloquear_estado_direto()                           set search_path = public;
alter function private.proteger_preco_encomenda()                         set search_path = public;
alter function private.custo_recolha_por_km()                             set search_path = public;
alter function private.preco_com_tarifa(tarifas, int, numeric, numeric)   set search_path = public;
alter function private.permissoes_validas(text[])                         set search_path = public;
alter function private.tipo_envia_email(text)                             set search_path = public;

revoke all on public.empresa_segredos, public.sessoes_empresa, public.tentativas_gate,
              public.emails_fila, public.contadores from anon, authenticated;
