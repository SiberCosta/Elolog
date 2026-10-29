// Edge Function «criar-prestador»: a equipa Elolog cria um prestador com código de acesso temporário (72 h) enviado por email.
// criar {empresa:{nome,nome_comercial,nif,email,telefone,morada,codigo_postal,cidade,pais}, admin:{nome,email}, plano, aprovada}
// reenviar {empresa_id}  — novo código (o anterior deixa de valer)        [administrador da plataforma, sessão com 2.º fator]
// concluir {senha_empresa, senha_pessoal} — primeiro acesso do administrador do prestador: troca as duas palavras-passe.
// Segredos: BREVO_API_KEY, EMAIL_REMETENTE (já existem). Deploy: supabase functions deploy criar-prestador --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { type Email, emailPrimeiroAcesso } from '../recuperar-acesso/modelo.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const SITE = (env('SITE_URL') || 'https://www.elolog.pt').replace(/\/(app|site)\/.*$/, '').replace(/\/+$/, '');
const txt = (v: unknown, max = 200) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const EMAIL = /^[^\s@<>"]{1,64}@[^\s@<>"]+\.[a-z]{2,}$/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HORAS = 72;

/** ELO-XXXX-XXXX sem letras/números ambíguos; tem sempre letras e algarismos. */
function codigo(): string {
  const A = 'ABCDEFGHJKMNPQRSTUVWXYZ', D = '23456789', T = A + D, r = crypto.getRandomValues(new Uint8Array(8));
  const c = Array.from(r, (b, i) => (i === 0 ? A : i === 1 ? D : T)[b % (i === 0 ? A.length : i === 1 ? D.length : T.length)]);
  return `ELO-${c.slice(0, 4).join('')}-${c.slice(4).join('')}`;
}
const quando = (d: Date) => d.toLocaleString('pt-PT', { timeZone: 'Europe/Lisbon', dateStyle: 'short', timeStyle: 'short' });
function nivel(jwt: string): string { try { return JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).aal ?? ''; } catch { return ''; } }
const fraca = (s: unknown, min: number) => typeof s !== 'string' || s.length < min || s.length > 72 || !/[a-zA-Z]/.test(s) || !/\d/.test(s);
async function enviar(para: string, e: Email): Promise<boolean> {
  if (!env('BREVO_API_KEY') || !env('EMAIL_REMETENTE')) return false;
  const r = await fetch('https://api.brevo.com/v3/smtp/email', { method: 'POST', signal: AbortSignal.timeout(10_000),
    headers: { 'api-key': env('BREVO_API_KEY'), 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: { name: env('EMAIL_NOME') || 'Elolog', email: env('EMAIL_REMETENTE') }, to: [{ email: para }],
      subject: e.assunto, htmlContent: e.html, textContent: e.texto, tags: ['elolog', 'primeiro-acesso'] }) }).catch(() => null);
  if (!r?.ok) console.error('criar-prestador: envio recusado', r?.status ?? 'rede');
  return !!r?.ok;
}
const regra = (e: { code?: string; message?: string } | null) => e?.code === 'P0001' ? erro(400, 'regra', e.message ?? 'Pedido recusado.') : erro(500, 'interno', 'Erro interno. Tente novamente.');

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: u } = jwt ? await admin.auth.getUser(jwt) : { data: null };
  if (!u?.user) return erro(401, 'sessao', 'Sessão inválida. Entre de novo.');
  const lido = await lerJson(req, 10_000);
  if (!lido.ok) return lido.resp;
  const c = (lido.valor ?? {}) as Record<string, unknown>, acao = txt(c.acao, 20), eu = u.user.id;
  try {
    if (acao === 'concluir') {
      const { data: t } = await admin.rpc('servico_acesso_temporario', { p_user: eu });
      const at = t as { expirado: boolean } | null;
      if (!at) return erro(400, 'regra', 'Não há nenhum primeiro acesso pendente.');
      if (at.expirado) return erro(400, 'expirado', 'O código temporário expirou. Peça um novo à Elolog.');
      if (fraca(c.senha_empresa, 8)) return erro(400, 'senha', 'A palavra-passe da empresa deve ter 8 a 72 caracteres, com letras e números.');
      if (fraca(c.senha_pessoal, 8)) return erro(400, 'senha', 'A sua palavra-passe deve ter 8 a 72 caracteres, com letras e números.');
      if (c.senha_empresa === c.senha_pessoal) return erro(400, 'senha', 'Use palavras-passe diferentes para a empresa e para a sua conta.');
      const { error: e1 } = await admin.auth.admin.updateUserById(eu, { password: c.senha_pessoal as string });
      if (e1) return erro(400, 'senha', 'A palavra-passe pessoal não foi aceite. Escolha outra.');
      const { error: e2 } = await admin.rpc('servico_concluir_primeiro_acesso', { p_user: eu, p_senha_empresa: c.senha_empresa });
      if (e2) return regra(e2);
      return resposta(200, { ok: true });
    }
    if (acao !== 'criar' && acao !== 'reenviar') return erro(400, 'acao', 'Ação desconhecida.');
    if (nivel(jwt) !== 'aal2') return erro(403, 'mfa', 'Confirme o segundo fator de autenticação antes de criar prestadores.');
    const { data: pode } = await admin.rpc('servico_equipa_pode_gerir', { p_user: eu });
    if (pode !== true) return erro(403, 'permissao', 'Só um administrador da plataforma pode criar prestadores.');
    const { data: dentro } = await admin.rpc('servico_limite', { p_chave: 'criar-prestador:' + eu, p_max: 30, p_janela_min: 60 });
    if (dentro === false) return erro(429, 'limite', 'Demasiados pedidos. Aguarde alguns minutos.');
    const cod = codigo(), expira = new Date(Date.now() + HORAS * 3600e3);

    if (acao === 'reenviar') {
      const id = txt(c.empresa_id, 40);
      if (!UUID.test(id)) return erro(400, 'dados', 'Empresa inválida.');
      const { data, error } = await admin.rpc('servico_renovar_acesso_temporario', { p_autor: eu, p_empresa: id, p_codigo: cod, p_expira: expira.toISOString() });
      if (error) return regra(error);
      const r = (Array.isArray(data) ? data[0] : data) as { user_id: string; email: string; nome: string; empresa: string; nif: string };
      const { error: e3 } = await admin.auth.admin.updateUserById(r.user_id, { password: cod });
      if (e3) return erro(500, 'interno', 'Não foi possível renovar o código. Tente novamente.');
      const enviado = await enviar(r.email, emailPrimeiroAcesso(SITE, { empresa: r.empresa, nif: r.nif, adminNome: r.nome, adminEmail: r.email, codigo: cod, expira: quando(expira) }));
      return resposta(200, { ok: true, enviado, expira_em: expira.toISOString(), ...(enviado ? {} : { codigo: cod }) });
    }

    const e = (c.empresa ?? {}) as Record<string, unknown>, a = (c.admin ?? {}) as Record<string, unknown>;
    const empresa = { nome: txt(e.nome), nome_comercial: txt(e.nome_comercial), nif: txt(e.nif, 20).replace(/\s/g, ''), email: txt(e.email, 254).toLowerCase(),
      telefone: txt(e.telefone, 40), morada: txt(e.morada), codigo_postal: txt(e.codigo_postal, 20), cidade: txt(e.cidade, 80), pais: txt(e.pais, 80) };
    const adminNome = txt(a.nome, 120), adminEmail = txt(a.email, 254).toLowerCase();
    if (empresa.nome.length < 2) return erro(400, 'dados', 'Indique o nome legal da empresa.');
    if (!/^\d{9}$/.test(empresa.nif)) return erro(400, 'dados', 'O NIF da empresa deve ter 9 algarismos.');
    if (!EMAIL.test(empresa.email)) return erro(400, 'dados', 'Indique o email da empresa.');
    if (adminNome.length < 2 || !EMAIL.test(adminEmail)) return erro(400, 'dados', 'Indique o nome e o email do administrador da empresa.');
    const { data: novo, error: eu1 } = await admin.auth.admin.createUser({ email: adminEmail, password: cod, email_confirm: true, user_metadata: { nome: adminNome } });
    if (eu1 || !novo?.user) return (eu1?.code === 'email_exists' || eu1?.code === 'user_already_exists') ? erro(409, 'existe', 'Já existe uma conta com o email do administrador.') : erro(400, 'criar', 'Não foi possível criar a conta do administrador.');
    const { data: emp, error: e4 } = await admin.rpc('servico_criar_prestador_admin', { p_autor: eu, p_user: novo.user.id, p_empresa: empresa, p_admin_nome: adminNome,
      p_admin_email: adminEmail, p_plano: txt(c.plano, 60), p_aprovada: c.aprovada !== false, p_codigo: cod, p_expira: expira.toISOString() });
    if (e4) { await admin.auth.admin.deleteUser(novo.user.id).catch(() => null); return regra(e4); }
    const enviado = await enviar(adminEmail, emailPrimeiroAcesso(SITE, { empresa: empresa.nome, nif: empresa.nif, adminNome, adminEmail, codigo: cod, expira: quando(expira) }));
    return resposta(200, { ok: true, empresa_id: emp, enviado, expira_em: expira.toISOString(), ...(enviado ? {} : { codigo: cod }) });
  } catch (x) {
    console.error('criar-prestador:', x instanceof Error ? x.message.slice(0, 200) : '');
    return erro(500, 'interno', 'Erro interno. Tente novamente.');
  }
});
