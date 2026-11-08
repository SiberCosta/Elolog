// Edge Function «seguimento» (v109): emails de seguimento das simulações (com consentimento) e de boas-vindas depois de aprovar.
//   processar  → só o agendador (x-cron-secret, tarefa elolog-seguimento, de hora a hora): envia o que está na hora.
//   sair {t}   → página site/seguimento.html (ligação «Deixar de receber» dos emails): qualquer pessoa com o token.
// Segredos usados: BREVO_API_KEY, EMAIL_REMETENTE, EMAIL_NOME (opcional), SITE_URL (opcional, por omissão https://www.elolog.pt).
// Opcionais: SEGUIMENTO_LOTE (por omissão 20 por hora), SEGUIMENTO_ATIVO=false (pausa sem perder nada).
// Deploy: supabase functions deploy seguimento --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { pedidoAgendado } from '../_shared/cofre.ts';
import { limitar, seguro } from '../_shared/seguranca.ts';
import { type Dados, type Email, emailSeguimento } from './modelo.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const SITE = (env('SITE_URL') || 'https://elolog.pt').replace(/\/(app|site)\/.*$/, '').replace(/\/+$/, '').replace('://www.elolog.pt', '://elolog.pt');   // www.elolog.pt não tem certificado válido
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOTE = Math.min(100, Math.max(1, Number.parseInt(env('SEGUIMENTO_LOTE'), 10) || 20));

type Envio = 'ok' | 'repetir' | 'parar';
async function enviar(para: string, e: Email, sair: string | null, etiqueta: string): Promise<Envio> {
  const headers: Record<string, string> = sair ? { 'List-Unsubscribe': `<${sair}>` } : {};
  const r = await fetch('https://api.brevo.com/v3/smtp/email', { method: 'POST', signal: AbortSignal.timeout(10_000),
    headers: { 'api-key': env('BREVO_API_KEY'), 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: { name: env('EMAIL_NOME') || 'Elolog', email: env('EMAIL_REMETENTE') }, to: [{ email: para }],
      subject: e.assunto, htmlContent: e.html, textContent: e.texto, headers, tags: ['elolog', etiqueta] }) }).catch(() => null);
  if (r?.ok) { await r.body?.cancel().catch(() => {}); return 'ok'; }
  const corpo = r ? (await r.text().catch(() => '')).replace(/[^\s@]+@[^\s@]+/g, '[email]').slice(0, 200) : '';
  console.error('seguimento: envio recusado', etiqueta, r?.status ?? 'rede', corpo);   // sem o endereço
  return r && [401, 403, 429].includes(r.status) ? 'parar' : 'repetir';
}

interface Pendente extends Dados { simulacao_id: string; email: string; token: string; estado_simulacao: string }

async function processar(): Promise<Response> {
  if ((env('SEGUIMENTO_ATIVO') || 'true').toLowerCase() === 'false') return resposta(200, { ok: true, pausado: true });
  if (!env('BREVO_API_KEY') || !env('EMAIL_REMETENTE')) { console.error('seguimento: Brevo não configurado'); return resposta(200, { ok: false, motivo: 'sem_fornecedor' }); }
  const { data, error } = await admin.rpc('servico_seguimento_pendentes', { p_limite: LOTE });
  if (error) { console.error('seguimento: não foi possível ler os pendentes', error.code); return erro(500, 'pendentes', 'Falha ao ler os pendentes.'); }
  const lista = (data ?? []) as Pendente[];
  let enviados = 0, saltados = 0, falhas = 0;
  for (const p of lista) {
    // nutrição numa simulação que entretanto foi aprovada ou cancelada: não escreve (a regra da base de dados já a tirou do fluxo)
    if (p.fluxo === 'nutricao' && ['convertida', 'cancelada'].includes(p.estado_simulacao)) {
      await admin.rpc('servico_seguimento_marcar', { p_simulacao: p.simulacao_id, p_ok: false, p_saltar: true }); saltados++; continue;
    }
    const sair = p.fluxo === 'nutricao' ? `${SITE}/site/seguimento.html?t=${p.token}` : null;
    const email = emailSeguimento(SITE, { ...p, propostas: Number(p.propostas) || 0, nome: p.nome || '', codigo: p.codigo || '' }, sair ?? '');
    const r = await enviar(p.email, email, sair, `seguimento-${p.fluxo}-${p.passo}`);
    await admin.rpc('servico_seguimento_marcar', { p_simulacao: p.simulacao_id, p_ok: r === 'ok', p_erro: r === 'ok' ? null : 'envio recusado' });
    if (r === 'ok') enviados++; else falhas++;
    if (r === 'parar') break;   // chave recusada ou limite do fornecedor: o resto fica reservado e volta na próxima hora
  }
  console.log('seguimento: lote', { pendentes: lista.length, enviados, saltados, falhas });
  return resposta(200, { ok: true, enviados, saltados, falhas });
}

Deno.serve(seguro('seguimento', async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const lido = await lerJson(req, 2_000);
  if (!lido.ok) return lido.resp;
  const c = (lido.valor ?? {}) as Record<string, unknown>;
  if (c.acao === 'processar') {
    if (!(await pedidoAgendado(req, admin))) return erro(403, 'proibido', 'Só o agendador pode pedir isto.');
    return processar();
  }
  if (c.acao === 'sair') {
    const t = typeof c.t === 'string' ? c.t.trim() : '';
    const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'sem-ip';
    if (!(await limitar(admin, 'seg-sair:' + ip.slice(0, 60), 20, 60))) return erro(429, 'limite', 'Demasiados pedidos. Tente daqui a pouco.');
    if (!UUID.test(t)) return erro(400, 'ligacao', 'Esta ligação não está completa. Abra-a de novo a partir do email.');
    const { error } = await admin.rpc('servico_seguimento_sair', { p_token: t });
    if (error) return erro(500, 'sair', 'Não conseguimos registar o pedido. Tente outra vez daqui a pouco.');
    return resposta(200, { ok: true });   // mesma resposta se o token já tinha saído: não revela nada
  }
  return erro(400, 'acao', 'Ação desconhecida.');
}, { admin }));
