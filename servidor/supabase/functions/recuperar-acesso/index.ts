// Edge Function «recuperar-acesso»: recuperar palavras-passe esquecidas, sem passar pelos emails padrão do Supabase.
// Sem sessão:  pedir {email} → email com ligação (?repor=…) e código de 6 dígitos (contas de cliente, funcionários e equipa Elolog)
//              empresa_pedir {nome, nif} → código para o email oficial da empresa · empresa_confirmar {id | nome+nif, codigo, senha}
// Com sessão:  alterada → email «a sua palavra-passe foi alterada».
// A resposta a «pedir» é sempre a mesma, exista ou não a conta (não revela quem está registado).
// Segredos usados: BREVO_API_KEY, EMAIL_REMETENTE, EMAIL_NOME (opcional), SITE_URL (opcional, por omissão https://www.elolog.pt).
// Deploy: supabase functions deploy recuperar-acesso --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { type Email, emailAlterada, emailEmpresa, emailRecuperacao } from './modelo.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const SITE = (env('SITE_URL') || 'https://www.elolog.pt').replace(/\/(app|site)\/.*$/, '').replace(/\/+$/, '');
const APP = SITE + '/app/area-cliente.html';
const EMAIL = /^[^\s@<>"]{1,64}@[^\s@<>"]+\.[a-z]{2,}$/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const txt = (v: unknown, max = 200) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const JANELA = 600_000;

async function hmacHex(msg: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(env('SUPABASE_SERVICE_ROLE_KEY')), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(msg))), (b) => b.toString(16).padStart(2, '0')).join('');
}
/** Código da empresa: depende do id, da «impressão» do segredo atual (deixa de valer quando muda) e da janela de 10 min. */
async function codigoEmpresa(id: string, impressao: string, janela: number): Promise<string> {
  return String(parseInt((await hmacHex(`empresa|${id}|${impressao}|${janela}`)).slice(0, 8), 16) % 1_000_000).padStart(6, '0');
}
async function limite(chave: string, max: number, min: number): Promise<boolean> {
  const { data } = await admin.rpc('servico_limite', { p_chave: chave, p_max: max, p_janela_min: min });
  return data !== false;
}
async function enviar(para: string, e: Email, etiqueta: string): Promise<boolean> {
  if (!env('BREVO_API_KEY') || !env('EMAIL_REMETENTE')) { console.error('recuperar-acesso: Brevo não configurado'); return false; }
  const r = await fetch('https://api.brevo.com/v3/smtp/email', { method: 'POST', signal: AbortSignal.timeout(10_000),
    headers: { 'api-key': env('BREVO_API_KEY'), 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: { name: env('EMAIL_NOME') || 'Elolog', email: env('EMAIL_REMETENTE') }, to: [{ email: para }],
      subject: e.assunto, htmlContent: e.html, textContent: e.texto, tags: ['elolog', etiqueta] }) }).catch(() => null);
  if (!r?.ok) console.error('recuperar-acesso: envio recusado', r?.status ?? 'rede');
  return !!r?.ok;
}
const senhaFraca = (s: string) => s.length < 8 || s.length > 72 || !/[a-zA-Z]/.test(s) || !/\d/.test(s);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const lido = await lerJson(req, 5_000);
  if (!lido.ok) return lido.resp;
  const c = (lido.valor ?? {}) as Record<string, unknown>, acao = txt(c.acao, 30);
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'sem-ip';
  const hash = async (v: string) => (await hmacHex('limite|' + v)).slice(0, 32);
  try {
    if (acao === 'pedir') {
      const email = txt(c.email, 254).toLowerCase();
      if (!EMAIL.test(email)) return erro(400, 'email', 'Indique um endereço de email válido.');
      if (!(await limite('rec-ip:' + (await hash(ip)), 20, 60)) || !(await limite('rec:' + (await hash(email)), 3, 15)))
        return erro(429, 'limite', 'Já pediu várias recuperações. Aguarde 15 minutos e verifique a caixa de entrada e o spam.');
      const { data, error } = await admin.auth.admin.generateLink({ type: 'recovery', email });
      const p = data?.properties as { hashed_token?: string; email_otp?: string } | undefined;
      if (!error && p?.hashed_token && p.email_otp) await enviar(email, emailRecuperacao(SITE, `${APP}?repor=${encodeURIComponent(p.hashed_token)}`, p.email_otp), 'recuperacao');
      return resposta(200, { ok: true });   // igual exista ou não a conta
    }
    if (acao === 'alterada') {
      const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
      const { data: u } = jwt ? await admin.auth.getUser(jwt) : { data: null };
      if (!u?.user?.email) return erro(401, 'sessao', 'Sessão inválida.');
      if (await limite('rec-alt:' + u.user.id, 5, 60))
        await enviar(u.user.email, emailAlterada(SITE, new Date().toLocaleString('pt-PT', { timeZone: 'Europe/Lisbon' })), 'senha-alterada');
      return resposta(200, { ok: true });
    }
    if (acao === 'empresa_pedir' || acao === 'empresa_confirmar') {
      const id = UUID.test(txt(c.id, 40)) ? txt(c.id, 40) : null, nome = txt(c.nome, 200), nif = txt(c.nif, 30);
      if (!id && (!nome || !nif)) return erro(400, 'dados', 'Indique o nome da empresa e o NIF.');
      const chave = await hash(id ?? `${nome.toLowerCase()}|${nif}`);
      const { data: e } = await admin.rpc('servico_empresa_reposicao', { p_nome: nome || null, p_nif: nif || null, p_id: id });
      const emp = e as { id: string; nome: string; email: string; estado: string; impressao: string } | null;
      const janela = Math.floor(Date.now() / JANELA);
      if (acao === 'empresa_pedir') {
        if (!(await limite('rece-ip:' + (await hash(ip)), 20, 60)) || !(await limite('rece:' + chave, 3, 15)))
          return erro(429, 'limite', 'Já pediu várias recuperações. Aguarde 15 minutos.');
        if (emp && emp.estado === 'aprovada' && EMAIL.test(emp.email)) {
          const cod = await codigoEmpresa(emp.id, emp.impressao, janela);
          await enviar(emp.email, emailEmpresa(SITE, emp.nome, `${APP}?acesso=prestador&repor-empresa=${emp.id}.${cod}`, cod), 'senha-empresa');
        }
        return resposta(200, { ok: true });
      }
      if (!(await limite('recec:' + chave, 8, 15))) return erro(429, 'limite', 'Demasiadas tentativas. Peça um código novo daqui a 15 minutos.');
      const codigo = txt(c.codigo, 10), senha = typeof c.senha === 'string' ? c.senha : '';
      if (senhaFraca(senha)) return erro(400, 'senha', 'A palavra-passe da empresa deve ter 8 a 72 caracteres, com letras e números.');
      let valido = false;
      if (emp && emp.estado === 'aprovada' && /^\d{6}$/.test(codigo))
        for (const j of [janela, janela - 1, janela - 2]) if ((await codigoEmpresa(emp.id, emp.impressao, j)) === codigo) valido = true;
      if (!valido || !emp) return erro(400, 'codigo', 'Código errado ou expirado. Peça um novo.');
      const { error } = await admin.rpc('servico_empresa_definir_senha', { p_id: emp.id, p_senha: senha });
      if (error) return erro(400, 'regra', error.message);
      return resposta(200, { ok: true, empresa: emp.nome });
    }
    return erro(400, 'acao', 'Ação desconhecida.');
  } catch (e) {
    console.error('recuperar-acesso:', e instanceof Error ? e.message.slice(0, 200) : '');
    return erro(500, 'interno', 'Erro interno. Tente novamente.');
  }
});
