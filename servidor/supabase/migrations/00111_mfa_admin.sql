-- =====================================================================
-- Elolog · 0011 · Verificação em dois passos (TOTP) para a administração da plataforma
-- Depende de 0001–0010.
-- Com a regra LIGADA, só é administrador quem tem a sessão no nível aal2 (palavra-passe + código da aplicação de autenticação),
-- em todas as políticas e funções de administração (todas passam por private.e_admin_plataforma()).
-- DESLIGADA por omissão: ligar só depois de a administração ter registado o autenticador no 1.º acesso (senão ninguém entra).
--   ligar:     update private.plataforma_config set valor = 'true'  where chave = 'exigir_mfa_admin';
--   desligar:  update private.plataforma_config set valor = 'false' where chave = 'exigir_mfa_admin';   (recuperação, no SQL Editor)
-- Requer o MFA TOTP ativo no Supabase (Authentication → Multi-factor). NÃO FOI EXECUTADO: testar primeiro num projeto de teste.
-- =====================================================================
create table private.plataforma_config (chave text primary key, valor text not null);
revoke all on private.plataforma_config from public, anon, authenticated;     -- a API nunca a lê nem escreve
insert into private.plataforma_config values ('exigir_mfa_admin', 'false');

create function private.mfa_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from private.plataforma_config where chave = 'exigir_mfa_admin'), 'false') <> 'true'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;
grant execute on function private.mfa_ok() to authenticated, service_role;

-- Mesmas assinaturas de 0003 e 0007 (as permissões de execução mantêm-se).
create or replace function private.e_admin_plataforma() returns boolean
language sql stable security definer set search_path = public as $$
  select private.mfa_ok() and exists (select 1 from administradores_plataforma where user_id = auth.uid())
$$;

create or replace function public.sou_admin_plataforma()
returns table (ok boolean, nome text)
language sql stable security definer set search_path = public as $$
  select true, a.nome from administradores_plataforma a where a.user_id = auth.uid() and private.mfa_ok()
$$;
