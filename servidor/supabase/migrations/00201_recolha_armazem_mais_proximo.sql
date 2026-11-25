-- v168 — Preço da recolha a partir do armazém do próprio prestador.
--   · vários armazéns → o mais próximo da morada de recolha (como já era);
--   · um só armazém → esse;
--   · nenhum armazém → a recolha NÃO entra no preço (km = 0) e a aplicação mostra «recolha por juntar ao preço».
-- Antes, um prestador sem armazém recebia os km de outro prestador (ou até à origem do envio), o que dava um valor sem fundamento.
-- Usada em precos_simulacao, enviar_simulacao e admin_registar_pedido; não muda tabelas nem dados.
create or replace function private.km_recolha(p_empresa uuid, p_lat numeric, p_lon numeric, p_km numeric)
returns numeric language plpgsql stable security definer set search_path to 'public' as $$
declare h numeric;
begin
  if not exists (select 1 from armazens a where a.empresa_id = p_empresa and a.ativo) then return 0; end if;   -- sem armazém: por juntar
  if p_lat is null or p_lon is null then return greatest(coalesce(p_km, 0), 0); end if;
  select min(private.km_linha(p_lat, p_lon, a.latitude, a.longitude)) into h
    from armazens a where a.empresa_id = p_empresa and a.ativo and a.latitude is not null;
  if h is null then return greatest(coalesce(p_km, 0), 0); end if;                    -- armazéns sem coordenadas: km indicado
  if p_km is null or p_km < h * 0.9 - 1 or p_km > h * 4 + 30 then return round(h * 1.3, 1); end if;
  return round(p_km, 1);
end $$;
