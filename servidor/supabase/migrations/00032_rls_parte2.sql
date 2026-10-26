create policy entregas_ver         on entregas for select to authenticated
  using (exists (select 1 from encomendas en where en.id = encomenda_id));      -- empresa ou cliente da encomenda
create policy entregas_gerir       on entregas for all to authenticated
  using (private.papel_em(array['admin_empresa','operador','operador_terreno'])
         and exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()))
  with check (private.papel_em(array['admin_empresa','operador','operador_terreno'])
         and exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()));

-- ---------- 12. Documentos (versionados: sem UPDATE nem DELETE) -------
create policy docs_empresa_ver     on documentos for select to authenticated using (empresa_id = private.minha_empresa());
create policy docs_cliente_ver     on documentos for select to authenticated
  using (cliente_id = auth.uid()
         or (visibilidade = 'cliente'
             and exists (select 1 from encomendas en where en.id = encomenda_id and en.cliente_id = auth.uid())));
create policy docs_empresa_criar   on documentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and enviado_por = auth.uid());
create policy docs_cliente_criar   on documentos for insert to authenticated
  with check (cliente_id = auth.uid() and empresa_id is null and enviado_por = auth.uid());

-- ---------- 13. Pagamentos (sem DELETE; erros anulam-se com motivo) ---
create policy pag_empresa_ver      on pagamentos for select to authenticated
  using (empresa_id = private.minha_empresa()
         and (private.papel_em(array['admin_empresa','financeiro','operador']) or registado_por = auth.uid()));
create policy pag_cliente_ver      on pagamentos for select to authenticated using (cliente_id = auth.uid());
create policy pag_financeiro_criar on pagamentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and registado_por = auth.uid()
              and private.papel_em(array['admin_empresa','financeiro']));
-- Numerário no terreno: exige a permissão "receive_cash", fica pendente de reconciliação.
create policy pag_terreno_criar    on pagamentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and registado_por = auth.uid()
              and private.papel_em(array['operador_terreno'])
              and numerario_terreno and private.tem_permissao('receive_cash')
              and estado = 'pendente' and not reconciliado
              and exists (select 1 from encomendas en where en.id = encomenda_id));
create policy pag_financeiro_editar on pagamentos for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa());

-- ---------- 14. Manifestos e declarações de carga ---------------------
create policy manif_ver            on manifestos for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem','financeiro']));
create policy manif_gerir          on manifestos for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']))
  with check (empresa_id = private.minha_empresa());
create policy manif_enc_ver        on manifesto_encomendas for select to authenticated
  using (exists (select 1 from manifestos m where m.id = manifesto_id and m.empresa_id = private.minha_empresa())
         and private.papel_em(array['admin_empresa','operador','armazem','financeiro']));
create policy manif_enc_gerir      on manifesto_encomendas for all to authenticated
  using (private.papel_em(array['admin_empresa','operador','armazem'])
         and exists (select 1 from manifestos m where m.id = manifesto_id and m.empresa_id = private.minha_empresa()))
  with check (private.papel_em(array['admin_empresa','operador','armazem'])
         and exists (select 1 from manifestos m where m.id = manifesto_id and m.empresa_id = private.minha_empresa()));
create policy decl_ver             on declaracoes_carga for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem','financeiro']));
create policy decl_gerir           on declaracoes_carga for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']))
  with check (empresa_id = private.minha_empresa());

-- ---------- 15. Terreno -----------------------------------------------
create policy terreno_ver          on trabalhos_terreno for select to authenticated
  using (empresa_id = private.minha_empresa()
         and (private.meu_papel() <> 'operador_terreno' or operador_id = auth.uid()));
create policy terreno_gerir        on trabalhos_terreno for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador']))
  with check (empresa_id = private.minha_empresa());
create policy terreno_atribuido    on trabalhos_terreno for update to authenticated
  using (empresa_id = private.minha_empresa() and operador_id = auth.uid())
  with check (empresa_id = private.minha_empresa() and operador_id = auth.uid());

-- ---------- 16. Suporte, notificações, auditoria ----------------------
create policy tickets_ver          on tickets for select to authenticated
  using (cliente_id = auth.uid() or (empresa_id is not null and empresa_id = private.minha_empresa()));
create policy tickets_cliente_criar on tickets for insert to authenticated
  with check (cliente_id = auth.uid() and criado_por = auth.uid() and origem in ('cliente','reclamacao'));
create policy tickets_empresa_criar on tickets for insert to authenticated
  with check (empresa_id = private.minha_empresa() and criado_por = auth.uid() and origem in ('prestador','terreno'));
create policy tickets_empresa_editar on tickets for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador']))
  with check (empresa_id = private.minha_empresa());

create policy ticket_msg_ver       on ticket_mensagens for select to authenticated using (private.ve_ticket(ticket_id));
create policy ticket_msg_criar     on ticket_mensagens for insert to authenticated
  with check (autor_id = auth.uid() and private.ve_ticket(ticket_id));

create policy notif_ver            on notificacoes for select to authenticated
  using (user_id = auth.uid()
         or (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])));
create policy notif_marcar_lida    on notificacoes for update to authenticated
  using (user_id = auth.uid()
         or (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])))
  with check (user_id = auth.uid()
         or (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])));

create policy auditoria_empresa    on auditoria for select to authenticated
  using (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa']));

-- ---------- 17. Regras da plataforma visíveis ao prestador ------------
create policy comissoes_empresa    on regras_comissao for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
create policy conformidade_ver     on regras_conformidade for select to authenticated
  using (private.minha_empresa() is not null and (empresa_id is null or empresa_id = private.minha_empresa()));
create policy faturas_empresa      on faturas_plataforma for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));

-- ---------- 18. Armazenamento privado de documentos -------------------
-- Convenção de caminho: <empresa_id>/... (prestador) ou <cliente_id>/... (cliente).
-- A leitura reaproveita a RLS da tabela "documentos". Requer o schema "storage" do Supabase.
insert into storage.buckets (id, name, public) values ('documentos', 'documentos', false)
  on conflict (id) do nothing;

create policy storage_documentos_ler on storage.objects for select to authenticated
  using (bucket_id = 'documentos'
         and exists (select 1 from public.documentos d where d.storage_path = storage.objects.name));
create policy storage_documentos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos'
              and (storage.foldername(name))[1] in (coalesce(private.minha_empresa()::text, ''), auth.uid()::text));
-- Sem políticas de UPDATE/DELETE: os ficheiros não se substituem em silêncio (nova versão = novo ficheiro).
