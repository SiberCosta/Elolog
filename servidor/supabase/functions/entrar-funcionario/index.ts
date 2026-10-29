// Edge Function «entrar-funcionario»: um funcionário do prestador entra com NIF da empresa + n.º de funcionário + palavra-passe pessoal.
// Não pede a palavra-passe da empresa (essa fica só para o administrador da empresa). O email nunca chega ao navegador antes do login.
// Resposta: { ok, session:{access_token, refresh_token}, funcionario:{nome,email,papel,empresa_id,empresa_nome} } — o navegador faz setSession.
// Deploy: supabase functions deploy entrar-funcionario --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const opc = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), opc);
const txt = (v: unknown, max = 60) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const ERRADO = 'NIF, número de funcionário ou palavra-passe incorretos.';

async function hash(v: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(v + '|' + env('SUPABASE_SERVICE_ROLE_KEY').slice(-16)));
  return Array.from(new Uint8Array(d).slice(0, 16), (b) => b.toString(16).padStart(2, '0')).join('');
}
async function limite(chave: string, max: number, min: number): Promise<boolean> {
  const { data } = await admin.rpc('servico_limite', { p_chave: chave, p_max: max, p_janela_min: min });
  return data !== false;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const lido = await lerJson(req, 2_000);
  if (!lido.ok) return lido.resp;
  const c = (lido.valor ?? {}) as Record<string, unknown>;
  const nif = txt(c.nif, 20).replace(/\s/g, ''), numero = txt(c.numero, 20), senha = typeof c.senha === 'string' ? c.senha : '';
  if (!/^\d{9}$/.test(nif) || !numero || !senha || senha.length > 72) return erro(400, 'dados', 'Indique o NIF da empresa, o número de funcionário e a palavra-passe.');
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'sem-ip';
  if (!(await limite('entfunc-ip:' + (await hash(ip)), 30, 15)) || !(await limite('entfunc:' + (await hash(nif + '|' + numero.toUpperCase())), 8, 15)))
    return erro(429, 'limite', 'Demasiadas tentativas. Aguarde 15 minutos ou peça ajuda ao administrador da empresa.');
  try {
    const { data } = await admin.rpc('servico_funcionario_por_numero', { p_nif: nif, p_numero: numero });
    const f = (Array.isArray(data) ? data[0] : data) as { user_id: string; email: string; nome: string; papel: string; ativo: boolean; empresa_id: string; empresa_nome: string; empresa_aprovada: boolean } | undefined;
    if (!f) return erro(401, 'credenciais', ERRADO);
    const anon = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), opc);
    const { data: s, error } = await anon.auth.signInWithPassword({ email: f.email, password: senha });
    if (error || !s.session) return erro(401, 'credenciais', ERRADO);
    // Só depois de provada a palavra-passe se explica porque não pode entrar por aqui (e a sessão criada é terminada).
    const recusa = f.papel === 'admin_empresa' ? 'O administrador da empresa entra em «Sou administrador da empresa», com a palavra-passe da empresa.'
      : !f.ativo ? 'Esta conta de funcionário está desativada. Contacte o administrador da empresa.' : !f.empresa_aprovada ? 'A empresa ainda não está aprovada pela Elolog.' : '';
    if (recusa) { await anon.auth.signOut().catch(() => null); return erro(403, f.papel === 'admin_empresa' ? 'admin' : 'recusado', recusa); }
    const { error: e2 } = await admin.rpc('servico_abrir_sessao_funcionario', { p_user: f.user_id });
    if (e2) return erro(403, 'sessao', e2.message);
    return resposta(200, { ok: true, session: { access_token: s.session.access_token, refresh_token: s.session.refresh_token },
      funcionario: { nome: f.nome, email: f.email, papel: f.papel, empresa_id: f.empresa_id, empresa_nome: f.empresa_nome } });
  } catch (x) {
    console.error('entrar-funcionario:', x instanceof Error ? x.message.slice(0, 200) : '');
    return erro(500, 'interno', 'Erro interno. Tente novamente.');
  }
});
