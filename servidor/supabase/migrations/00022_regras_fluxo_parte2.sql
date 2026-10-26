create trigger trg_tarifa_usada before update on tarifas
  for each row execute function private.proteger_tarifa_usada();

-- ---------- 8. Manifestos: só o admin confirma/cancela; confirmados não se alteram
create function private.regras_manifesto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estado in ('confirmado','cancelado') and new.estado is distinct from old.estado
     and not (private.meu_papel() = 'admin_empresa' or private.e_admin_plataforma()) then
    raise exception 'Só o administrador da empresa pode confirmar ou cancelar manifestos.';
  end if;
  if old.estado in ('confirmado','em_transito','concluido') and (
       (new.numero, new.versao, new.origem, new.destino, new.numero_viagem, new.partida, new.chegada,
        new.transportador, new.total_unidades, new.total_peso_kg, new.total_volume_m3)
       is distinct from
       (old.numero, old.versao, old.origem, old.destino, old.numero_viagem, old.partida, old.chegada,
        old.transportador, old.total_unidades, old.total_peso_kg, old.total_volume_m3)) then
    raise exception 'Manifesto confirmado não se altera: crie uma nova versão.';
  end if;
  return new;
end $$;
create trigger trg_manifesto_regras before update on manifestos
  for each row execute function private.regras_manifesto();

-- ---------- 9. Notificações persistentes para a administração ---------
create function private.notificar_plataforma() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tipo text; v_titulo text;
begin
  if tg_table_name = 'empresas' then
    v_tipo := 'novo_prestador';      v_titulo := 'Novo pedido de inscrição de prestador';
  elsif tg_table_name = 'subscricoes' then
    v_tipo := 'pedido_subscricao';   v_titulo := 'Novo pedido de subscrição';
  elsif tg_table_name = 'pedidos_cliente' then
    v_tipo := 'pedido_cliente';      v_titulo := 'Pedido do cliente: ' || new.tipo;
  else
    v_tipo := 'apoio';               v_titulo := 'Novo pedido de apoio ou reclamação';
  end if;
  insert into notificacoes (para_plataforma, tipo, titulo, referencia_tabela, referencia_id)
    values (true, v_tipo, v_titulo, tg_table_name, new.id);
  return new;
end $$;

create trigger trg_notif_empresas  after insert on empresas
  for each row execute function private.notificar_plataforma();
create trigger trg_notif_subscricoes after insert on subscricoes
  for each row execute function private.notificar_plataforma();
create trigger trg_notif_pedidos after insert on pedidos_cliente
  for each row execute function private.notificar_plataforma();
create trigger trg_notif_tickets after insert on tickets
  for each row when (new.origem in ('cliente','reclamacao') or new.escalado)
  execute function private.notificar_plataforma();

-- ---------- 10. Execução das funções públicas -------------------------
revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;
revoke execute on function public.aceitar_proposta(uuid) from public, anon;
revoke execute on function public.decidir_empresa(uuid, boolean, text) from public, anon;
grant  execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;
grant  execute on function public.aceitar_proposta(uuid) to authenticated;
grant  execute on function public.decidir_empresa(uuid, boolean, text) to authenticated;
