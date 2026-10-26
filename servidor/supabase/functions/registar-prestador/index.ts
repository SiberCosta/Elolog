// Edge Function pública: registo de um prestador (empresa pendente + 1.º administrador).
// Deploy sem verificação de JWT do gateway (quem se regista ainda não tem conta):
//   supabase functions deploy registar-prestador --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { tratar, type DepsRegisto } from './handler.ts';

const URL_PROJETO = Deno.env.get('SUPABASE_URL') ?? '';
const CHAVE_ANON = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const CHAVE_SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const SITE = Deno.env.get('SITE_URL') ?? undefined;   // para onde o e-mail de confirmação reencaminha (opcional)

const opcoes = { auth: { persistSession: false, autoRefreshToken: false } };

function dependencias(): DepsRegisto {
  const admin = createClient(URL_PROJETO, CHAVE_SERVICO, opcoes);
  const anon = createClient(URL_PROJETO, CHAVE_ANON, opcoes);
  return {
    async limite(chave, max, janelaMin) {
      const { data, error } = await admin.rpc('servico_limite', { p_chave: chave, p_max: max, p_janela_min: janelaMin });
      if (error) throw error;
      return data === true;
    },
    async utilizadorExiste(email) {
      const { data, error } = await admin.rpc('servico_utilizador_existe', { p_email: email });
      if (error) throw error;
      return data === true;
    },
    async criarUtilizador(email, senha, nome) {
      // signUp (e não admin.createUser): se o projeto exigir confirmação, o Supabase envia o e-mail e o
      // administrador só consegue entrar depois de provar que é dono do endereço.
      const { data, error } = await anon.auth.signUp({ email, password: senha, options: { data: { nome }, emailRedirectTo: SITE } });
      if (error) {
        console.error('registar-prestador: signUp falhou', error.code, error.status);
        if (error.code === 'user_already_exists' || error.code === 'email_exists') return { erro: 'existe' };
        if (error.status === 422 || error.code === 'weak_password' || error.code === 'validation_failed') return { erro: 'invalido' };
        return { erro: 'falha' };
      }
      const u = data.user;
      if (!u) return { erro: 'falha' };
      // Com confirmação ativa, um e-mail já registado devolve um utilizador "falso" sem identidades.
      if (Array.isArray(u.identities) && u.identities.length === 0) return { erro: 'existe' };
      return { id: u.id, exigeConfirmacao: !data.session };
    },
    async registar(d) {
      const { data, error } = await admin.rpc('servico_registar_prestador', {
        p_user: d.userId, p_nome: d.empresaNome, p_nif: d.nif, p_email: d.empresaEmail, p_telefone: d.telefone,
        p_senha_empresa: d.senhaEmpresa, p_admin_nome: d.adminNome, p_admin_email: d.adminEmail,
        p_plano: d.plano, p_metodo: d.metodo, p_referencia: d.referencia,
      });
      if (error) {
        console.error('registar-prestador: servico_registar_prestador falhou', error.code, error.message);
        if (/nif/i.test(error.message)) return { erro: 'nif_duplicado' };   // mensagem da função ou da restrição única de empresas.nif
        if (/plano/i.test(error.message)) return { erro: 'plano' };
        return { erro: 'falha' };
      }
      return { empresaId: String(data) };
    },
    async apagarUtilizador(id) {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) throw error;
    },
  };
}

Deno.serve((req: Request) => tratar(req, dependencias()));
