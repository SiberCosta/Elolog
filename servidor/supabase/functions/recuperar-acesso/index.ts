// Edge Function «recuperar-acesso»: recuperar palavras-passe esquecidas, sem passar pelos emails padrão do Supabase.
// Sem sessão:  pedir {email} → email com ligação (?repor=…) e código de 6 dígitos (contas de cliente, funcionários e equipa Elolog)
//              empresa_pedir {nome, nif} → código para o email oficial da empresa · empresa_confirmar {id | nome+nif, codigo, senha}
// Com sessão:  alterada → email «a sua palavra-passe foi alterada» · codigo_entrada {canal: email|sms} → código de 6 dígitos (2.º passo do administrador da empresa)
//              canais_codigo → para onde pode ir o código (email e, se configurado, SMS para o telemóvel registado).
// SMS (opcional, cada SMS gasta créditos pagos da Brevo): SMS_REMETENTE (nome do remetente, até 11 caracteres, ex.: Elolog) + BREVO_API_KEY.
// A resposta a «pedir» é sempre a mesma, exista ou não a conta (não revela quem está registado).
// Segredos usados: BREVO_API_KEY, EMAIL_REMETENTE, EMAIL_NOME (opcional), SITE_URL (opcional, por omissão https://www.elolog.pt).
// Deploy: supabase functions deploy recuperar-acesso --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { type Email, emailAlterada, emailCodigoEntrada, emailEmpresa, emailRecuperacao } from './modelo.ts';
import { seguro } from '../_shared/seguranca.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const SITE = (env('SITE_URL') || 'https://elolog.pt').replace(/\/(app|site)\/.*$/, '').replace(/\/+$/, '').replace('://www.elolog.pt', '://elolog.pt');   // www.elolog.pt não tem certificado válido
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
  return data === true;
}
async function enviar(para: string, e: Email, etiqueta: string): Promise<boolean> {
  if (!env('BREVO_API_KEY') || !env('EMAIL_REMETENTE')) { console.error('recuperar-acesso: Brevo não configurado'); return false; }
  const r = await fetch('https://api.brevo.com/v3/smtp/email', { method: 'POST', signal: AbortSignal.timeout(10_000),
    headers: { 'api-key': env('BREVO_API_KEY'), 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: { name: env('EMAIL_NOME') || 'Elolog', email: env('EMAIL_REMETENTE') }, to: [{ email: para }],
      subject: e.assunto, htmlContent: e.html, textContent: e.texto, tags: ['elolog', etiqueta] }) }).catch(() => null);
  if (!r?.ok) {
    const corpo = r ? (await r.text().catch(() => '')).replace(/[^\s@]+@[^\s@]+/g, '[email]').slice(0, 200) : '';
    console.error('recuperar-acesso: envio recusado', etiqueta, r?.status ?? 'rede', corpo);
    return false;
  }
  const j = (await r.json().catch(() => ({}))) as { messageId?: string };
  console.log('recuperar-acesso: email aceite pelo Brevo', etiqueta, j.messageId ?? '');   // sem o endereço
  return true;
}
/** session_id do token (o token já foi validado por admin.auth.getUser). */
function sessaoDoToken(jwt: string): string {
  try {
    const b = jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return String(JSON.parse(atob(b + '==='.slice((b.length + 3) % 4))).session_id ?? '');
  } catch { return ''; }
}
/* SMS: número em formato internacional só com dígitos (9 dígitos começados por 9 → Portugal, +351) */
const telefoneIntl = (t: string | null | undefined) => { let d = String(t ?? '').replace(/\D/g, '').replace(/^00/, ''); if (/^9\d{8}$/.test(d)) d = '351' + d; return d.length >= 9 && d.length <= 15 ? d : ''; };
const smsPronto = () => !!(env('BREVO_API_KEY') && env('SMS_REMETENTE'));
const mascaraTel = (d: string) => `+${d.slice(0, d.length - 9)} ${d.slice(-9, -8)}•• ••• ${d.slice(-2)}`;
const mascaraEmail = (e: string) => { const [n, d] = e.split('@'); return `${n.slice(0, 2)}•••@${d}`; };
/** Envia o código por SMS (Brevo, SMS transacional; cada SMS gasta créditos pagos da conta Brevo). */
async function enviarSms(para: string, codigo: string): Promise<boolean> {
  const r = await fetch('https://api.brevo.com/v3/transactionalSMS/sms', { method: 'POST', signal: AbortSignal.timeout(10_000),
    headers: { 'api-key': env('BREVO_API_KEY'), 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: env('SMS_REMETENTE').slice(0, 11), recipient: para, type: 'transactional', tag: 'codigo-entrada',
      content: `Elolog: o seu código de entrada é ${codigo}. Vale 10 minutos. Não o partilhe com ninguém.` }) }).catch(() => null);
  if (!r?.ok) { console.error('recuperar-acesso: SMS recusado', r?.status ?? 'rede', r ? (await r.text().catch(() => '')).replace(/\d{6,}/g, '[n]').slice(0, 200) : ''); return false; }
  console.log('recuperar-acesso: código enviado por SMS');
  return true;
}
const senhaFraca = (s: string) => s.length < 8 || s.length > 72 || !/[a-zA-Z]/.test(s) || !/\d/.test(s);

Deno.serve(seguro('recuperar-acesso', async (req: Request) => {
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
    if (acao === 'canais_codigo' || acao === 'codigo_entrada') {
      // 2.º passo do administrador da empresa: código de 6 dígitos por email ou SMS (alternativa à aplicação de autenticação)
      const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
      const { data: u } = jwt ? await admin.auth.getUser(jwt) : { data: null };
      const sessao = jwt ? sessaoDoToken(jwt) : '';
      if (!u?.user || !UUID.test(sessao)) return erro(401, 'sessao', 'A sessão expirou. Volte a entrar.');
      const { data: f } = await admin.from('funcionarios').select('email,telefone,ativo').eq('id', u.user.id).maybeSingle();
      const tel = telefoneIntl(f?.telefone);
      if (acao === 'canais_codigo') {
        return resposta(200, { ok: true, email: f?.email ? mascaraEmail(f.email) : null, sms: tel ? mascaraTel(tel) : null, smsDisponivel: !!tel && smsPronto(),
          motivo: !smsPronto() ? 'O envio por SMS ainda não está ativo na Elolog.' : !tel ? 'Não tem telemóvel registado: peça a quem gere a equipa para o acrescentar em Funcionários e acessos.' : null });
      }
      const canal = txt(c.canal, 10) === 'sms' ? 'sms' : 'email';
      if (canal === 'sms' && (!tel || !smsPronto())) return erro(400, 'canal', tel ? 'O envio por SMS ainda não está ativo. Receba o código por email.' : 'Não tem telemóvel registado. Receba o código por email.');
      if (!(await limite('cod-ent:' + u.user.id, 4, 10)) || !(await limite('cod-ent-ip:' + (await hash(ip)), 20, 60)))
        return erro(429, 'limite', 'Já enviámos vários códigos. Aguarde 10 minutos e veja também a pasta de spam.');
      const { data, error } = await admin.rpc('servico_codigo_email_criar', { p_user: u.user.id, p_sessao: sessao });
      if (error) { console.error('recuperar-acesso: servico_codigo_email_criar falhou', error.code); return erro(500, 'interno', 'Não foi possível criar o código. Tente novamente.'); }
      const linha = (Array.isArray(data) ? data[0] : data) as { codigo?: string; email?: string; nome?: string } | undefined;
      if (!linha?.codigo || !linha.email) return erro(403, 'conta', 'Esta conta não recebe códigos de entrada.');
      if (canal === 'sms') {
        if (!(await enviarSms(tel, linha.codigo))) return erro(502, 'envio', 'Não foi possível enviar o SMS agora. Receba o código por email.');
        return resposta(200, { ok: true, canal, para: mascaraTel(tel) });
      }
      if (!(await enviar(linha.email, emailCodigoEntrada(SITE, linha.nome ?? '', linha.codigo), 'codigo-entrada')))
        return erro(502, 'envio', 'Não foi possível enviar o email agora. Tente daqui a pouco ou use a aplicação de autenticação.');
      return resposta(200, { ok: true, canal, para: mascaraEmail(linha.email) });
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
        if (!emp) console.log('recuperar-acesso: empresa não encontrada (o nome e o NIF não coincidem com o registo)');
        else if (emp.estado !== 'aprovada') console.log('recuperar-acesso: empresa ainda não aprovada', emp.estado);
        else if (!EMAIL.test(emp.email)) console.log('recuperar-acesso: empresa sem email oficial válido');
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
}, { admin }));
