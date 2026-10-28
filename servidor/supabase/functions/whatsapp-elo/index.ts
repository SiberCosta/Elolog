// Edge Function «whatsapp-elo»: o assistente ELO a responder no WhatsApp (WhatsApp Business Cloud API da Meta).
// Endereço do aviso (Webhook) a dar à Meta: https://<projeto>.supabase.co/functions/v1/whatsapp-elo
// Segredos: WHATSAPP_TOKEN (token permanente), WHATSAPP_PHONE_ID (Phone number ID), WHATSAPP_APP_SECRET (App Secret),
//           WHATSAPP_VERIFY_TOKEN (texto inventado por si, igual ao que puser na Meta). Opcional: WHATSAPP_API_VERSION (v21.0).
// Deploy: supabase functions deploy whatsapp-elo --no-verify-jwt   (a Meta não envia token; a assinatura é validada no código)
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { interpretar, textoEstado, type Conversa, type Encomenda } from './elo.ts';
import { assinaturaValida, enviarTexto, mensagens } from './meta.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const cfg = { token: env('WHATSAPP_TOKEN'), phoneId: env('WHATSAPP_PHONE_ID'), versao: env('WHATSAPP_API_VERSION') || 'v21.0' };
const ok = () => new Response('ok', { status: 200 });

async function hash(v: string) {
  const b = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(v)));
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
}

async function tratar(de: string, nome: string, texto: string) {
  const { data: dentro } = await admin.rpc('servico_limite', { p_chave: 'wa:' + (await hash(de)), p_max: 30, p_janela_min: 10 });
  if (dentro === false) return;
  const { data: conv } = await admin.from('whatsapp_conversas').select('passo,humano_desde,dados,mensagens').eq('telefone', de).maybeSingle();
  const c: Conversa & { mensagens?: number } = conv ?? {};
  const acao = interpretar(texto, c);
  let resposta = '', passo: string | null = c.passo ?? null, dados = { ...(c.dados ?? {}) }, humano = c.humano_desde ?? null;
  if (acao.tipo === 'estado') {
    const { data, error } = await admin.rpc('servico_whatsapp_estado', { p_codigo: acao.codigo, p_telefone: de });
    resposta = error ? 'De momento não consigo consultar as encomendas. Tente daqui a pouco ou escreva *3* para falar com a equipa.' : textoEstado(data as Encomenda, acao.codigo);
    passo = null;
  } else if (acao.tipo === 'humano') {
    await admin.from('whatsapp_conversas').upsert({ telefone: de, nome, updated_at: new Date().toISOString() });
    await admin.rpc('servico_whatsapp_pedido_humano', { p_telefone: de, p_nome: nome, p_mensagem: texto });
    resposta = acao.texto; passo = 'humano'; humano = new Date().toISOString(); dados = { ...dados, avisado: false };
  } else if (acao.tipo === 'responder') {
    resposta = acao.texto; passo = acao.passo;
    if (acao.passo === 'humano') dados = { ...dados, avisado: true };
    else if (acao.passo === null) { humano = null; dados = {}; }
  }
  await admin.from('whatsapp_conversas').upsert({ telefone: de, nome: nome || null, passo, dados, humano_desde: humano,
    mensagens: (c.mensagens ?? 0) + 1, updated_at: new Date().toISOString() });
  if (resposta) await enviarTexto(cfg, de, resposta);
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  if (req.method === 'GET') {   // verificação do Webhook pela Meta
    const verifica = env('WHATSAPP_VERIFY_TOKEN');
    if (verifica && url.searchParams.get('hub.mode') === 'subscribe' && url.searchParams.get('hub.verify_token') === verifica)
      return new Response(url.searchParams.get('hub.challenge') ?? '', { status: 200 });
    return new Response('proibido', { status: 403 });
  }
  if (req.method !== 'POST') return new Response('metodo', { status: 405 });
  const corpo = await req.text();
  if (corpo.length > 200_000) return new Response('grande', { status: 413 });
  if (!(await assinaturaValida(corpo, req.headers.get('x-hub-signature-256'), env('WHATSAPP_APP_SECRET')))) return new Response('assinatura', { status: 401 });
  if (!cfg.token || !cfg.phoneId) { console.error('whatsapp-elo: WHATSAPP_TOKEN/WHATSAPP_PHONE_ID em falta'); return ok(); }
  let aviso: unknown;
  try { aviso = JSON.parse(corpo); } catch { return ok(); }
  for (const m of mensagens(aviso)) {
    try { await tratar(m.de, m.nome, m.texto); } catch (e) { console.error('whatsapp-elo: erro', e instanceof Error ? e.message : e); }
  }
  return ok();   // responder sempre 200 para a Meta não repetir o aviso
});
