// Edge Function «webhooks» (v127): entrega os eventos da fila (eventos_saida) aos sistemas das empresas (ERP, WMS…).
//   Só o agendador a chama (x-cron-secret; tarefa elolog-webhooks, de 2 em 2 minutos e só quando há eventos pendentes).
// Cada pedido: POST JSON {id, tipo, criado_em, encomenda, dados} com os cabeçalhos
//   X-Elolog-Evento: <tipo>   X-Elolog-Assinatura: t=<segundos>,v1=<HMAC-SHA256 hex de "<t>.<corpo>" com o segredo whsec_…>
// O destino tem de ser https:// público (sem endereços internos), responder 2xx em 8 s e não redirecionar. Falhas repetem com espera crescente (até 8).
// Deploy: supabase functions deploy webhooks --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, preflight, resposta } from '../_shared/http.ts';
import { pedidoAgendado } from '../_shared/cofre.ts';
import { seguro } from '../_shared/seguranca.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const INTERNO = /^(localhost|.*\.(local|internal|lan|localhost)|127\.|10\.|192\.168\.|169\.254\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|172\.(1[6-9]|2\d|3[01])\.|0\.|\[)/i;   // IPv6 literal vem entre [ ]

interface Evento { id: number; empresa_id: string; tipo: string; encomenda_codigo: string | null; dados: unknown; criado_em: string; tentativas: number; url: string; segredo: string | null }

/** endereço aceite: https, porta 443, sem IP interno nem nomes internos */
export function destinoValido(url: string): boolean {
  try { const u = new URL(url); return u.protocol === 'https:' && (u.port === '' || u.port === '443') && !INTERNO.test(u.hostname) && !u.username && !u.password; }
  catch { return false; }
}

async function assinar(segredo: string, texto: string): Promise<string> {
  const chave = await crypto.subtle.importKey('raw', new TextEncoder().encode(segredo), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', chave, new TextEncoder().encode(texto));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function entregar(e: Evento): Promise<{ ok: boolean; erro?: string }> {
  if (!destinoValido(e.url)) return { ok: false, erro: 'endereço não permitido' };
  if (!e.segredo) return { ok: false, erro: 'falta gerar o segredo da integração' };
  const corpo = JSON.stringify({ id: e.id, tipo: e.tipo, criado_em: e.criado_em, encomenda: e.encomenda_codigo, dados: e.dados });
  const t = Math.floor(Date.now() / 1000);
  const r = await fetch(e.url, { method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(8_000),
    headers: { 'content-type': 'application/json', 'user-agent': 'Elolog-Webhooks/1', 'x-elolog-evento': e.tipo, 'x-elolog-id': String(e.id),
      'x-elolog-assinatura': `t=${t},v1=${await assinar(e.segredo, `${t}.${corpo}`)}` }, body: corpo }).catch((x) => x as Error);
  if (r instanceof Error) return { ok: false, erro: r.name === 'TimeoutError' ? 'sem resposta em 8 s' : 'sem ligação ao destino' };
  await r.body?.cancel().catch(() => {});
  return r.status >= 200 && r.status < 300 ? { ok: true } : { ok: false, erro: `HTTP ${r.status}` };
}

Deno.serve(seguro('webhooks', async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  if (!(await pedidoAgendado(req, admin))) return erro(403, 'proibido', 'Só o agendador pode pedir isto.');
  const { data, error } = await admin.rpc('servico_webhooks_pendentes', { p_limite: 25 });
  if (error) { console.error('webhooks: não foi possível ler a fila', error.code); return erro(500, 'fila', 'Falha ao ler a fila.'); }
  let enviados = 0, falhas = 0;
  for (const e of (data ?? []) as Evento[]) {
    const r = await entregar(e);
    await admin.rpc('servico_webhook_resultado', { p_id: e.id, p_ok: r.ok, p_erro: r.erro ?? null });
    if (r.ok) enviados++; else falhas++;
  }
  console.log('webhooks: lote', { enviados, falhas });
  return resposta(200, { ok: true, enviados, falhas });
}, { admin }));
