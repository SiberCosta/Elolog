-- Elolog v152: o cliente passa a poder gravar as coordenadas e as distâncias de recolha da sua simulação.
-- A migração 00177 criou estas colunas mas não deu permissão de escrita: com recolha na morada, o servidor
-- recusava a simulação (403) e o pedido não chegava ao prestador. Só acrescenta permissões; não apaga nem altera dados.
-- As regras de acesso (RLS) ficam iguais: cada cliente só escreve as suas simulações em rascunho.
grant insert (recolha_lat, recolha_lon, recolha_kms) on public.simulacoes to authenticated;
grant update (recolha_lat, recolha_lon, recolha_kms) on public.simulacoes to authenticated;
