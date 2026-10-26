// Edge Function: equipa da plataforma Elolog (funcionários que gerem o portal).
// Ações: criar {nome,email,papel,senha} · alterar {alvo,ativo?,papel?} · senha {alvo,senha}.
// Só um administrador da plataforma (papel «admin», ativo, sessão com 2.º fator) pode gerir a equipa.
// Deploy: supabase functions deploy gerir-equipa --no-verify-jwt (o token é validado no código).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';

const texto = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
const normalizarEmail = (v: unknown) => texto(v).toLowerCase();
const emailValido = (s: string) => s.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
const ehUuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
function validarSenha(s: unknown): string | null {
  if (typeof s !== 'string' || s.length < 10 || new TextEncoder().encode(s).length > 72 || !/[a-z]/.test(s) || !/[A-Z]/.test(s) || !/\d/.test(s))
    return 'A palavra-passe deve ter 10 a 72 caracteres, com maiúscula, minúscula e número.';
  return null;
}

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } });
const PAPEIS = ['admin', 'operador', 'apoio'];

/** Nível de autenticação (aal1/aal2) lido do token já validado por auth.getUser. */
function nivel(jwt: string): string {
  try { return JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).aal ?? ''; } catch { return ''; }
}
const negocio = (e: { code?: string; message: string }) =>
  e.code === 'P0001' ? erro(400, 'regra', e.message) : (console.error('gerir-equipa: bd', e.code), erro(500, 'interno', 'Erro interno. Tente novamente.'));

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: u, error: eu } = jwt ? await admin.auth.getUser(jwt) : { data: null, error: true };
  if (eu || !u?.user) return erro(401, 'sessao', 'Sessão inválida. Entre de novo.');
  if (nivel(jwt) !== 'aal2') return erro(403, 'mfa', 'Confirme o segundo fator de autenticação antes de gerir a equipa.');
  const autor = u.user.id;
  const { data: pode } = await admin.rpc('servico_equipa_pode_gerir', { p_user: autor });
  if (pode !== true) return erro(403, 'permissao', 'Só um administrador da plataforma pode gerir a equipa.');
  const { data: dentro } = await admin.rpc('servico_limite', { p_chave: 'equipa:' + autor, p_max: 30, p_janela_min: 10 });
  if (dentro === false) return erro(429, 'limite', 'Demasiados pedidos. Aguarde alguns minutos.');

  const lido = await lerJson(req);
  if (!lido.ok) return lido.resp;
  const c = (lido.valor ?? {}) as Record<string, unknown>;
  const acao = texto(c.acao);

  if (acao === 'criar') {
    const nome = texto(c.nome), email = normalizarEmail(c.email), papel = texto(c.papel);
    if (nome.length < 2 || nome.length > 120) return erro(400, 'nome', 'Indique o nome do funcionário.');
    if (!emailValido(email)) return erro(400, 'email', 'Indique um email válido.');
    if (!PAPEIS.includes(papel)) return erro(400, 'papel', 'Escolha a função.');
    const fraca = validarSenha(c.senha);
    if (fraca) return erro(400, 'senha', fraca);
    const { data: novo, error } = await admin.auth.admin.createUser({ email, password: c.senha as string, email_confirm: true, user_metadata: { nome, equipa_elolog: true } });
    if (error || !novo.user) {
      if (error?.code === 'email_exists' || error?.code === 'user_already_exists') return erro(409, 'existe', 'Já existe uma conta com este email.');
      console.error('gerir-equipa: createUser', error?.code, error?.status);
      return erro(400, 'criar', 'Não foi possível criar a conta. Verifique o email e a palavra-passe.');
    }
    const { data, error: e2 } = await admin.rpc('servico_equipa_criar', { p_user: novo.user.id, p_nome: nome, p_email: email, p_papel: papel, p_autor: autor });
    if (e2) { await admin.auth.admin.deleteUser(novo.user.id); return negocio(e2); }
    return resposta(200, { ok: true, funcionario: data });
  }
  if (!ehUuid(c.alvo)) return erro(400, 'alvo', 'Funcionário inválido.');
  if (acao === 'alterar') {
    const papel = c.papel == null ? null : texto(c.papel), ativo = typeof c.ativo === 'boolean' ? c.ativo : null;
    if (papel !== null && !PAPEIS.includes(papel)) return erro(400, 'papel', 'Função inválida.');
    const { data, error } = await admin.rpc('servico_equipa_alterar', { p_alvo: c.alvo, p_ativo: ativo, p_papel: papel, p_autor: autor });
    if (error) return negocio(error);
    if (ativo !== null) {
      await admin.auth.admin.updateUserById(c.alvo as string, { ban_duration: ativo ? 'none' : '876000h' });
      if (!ativo) await admin.rpc('servico_encerrar_sessoes', { p_alvo: c.alvo });
    }
    return resposta(200, { ok: true, funcionario: data });
  }
  if (acao === 'senha') {
    const fraca = validarSenha(c.senha);
    if (fraca) return erro(400, 'senha', fraca);
    if (c.alvo === autor) return erro(400, 'regra', 'Altere a sua própria palavra-passe no perfil.');
    const { data: alvoOk } = await admin.from('administradores_plataforma').select('user_id').eq('user_id', c.alvo as string).maybeSingle();
    if (!alvoOk) return erro(404, 'alvo', 'Funcionário inexistente.');
    const { error } = await admin.auth.admin.updateUserById(c.alvo as string, { password: c.senha as string });
    if (error) return erro(400, 'senha', 'Não foi possível alterar a palavra-passe.');
    await admin.rpc('servico_auditar', { p_empresa: null, p_user: autor, p_acao: 'repor_senha_equipa', p_entidade_id: c.alvo, p_depois: {} });
    return resposta(200, { ok: true });
  }
  return erro(400, 'acao', 'Ação desconhecida.');
});
