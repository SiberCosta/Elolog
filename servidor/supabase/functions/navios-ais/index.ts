// Edge Function «navios-ais»: posição, velocidade, destino e ETA reais dos navios seguidos pelas empresas.
// Fonte: aisstream.io (gratuito; criar conta e chave em https://aisstream.io). Chamada pelo agendador a cada 30 minutos.
// Deploy: supabase functions deploy navios-ais --no-verify-jwt      Segredo: AISSTREAM_API_KEY
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { juntar, subscricao, type Posicao } from './ais.ts';
import { classificar, subscricaoRota, type NavioRota } from './rota.ts';
import { pedidoAgendado } from '../_shared/cofre.ts';
import { erro, resposta } from '../_shared/http.ts';
import { seguro } from '../_shared/seguranca.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } });
const ESCUTA_MS = 40_000;

function escutar(chave: string, mmsis: string[], estado: Map<string, Posicao>): Promise<Map<string, Posicao>> {
  const novos = new Set<string>();
  return new Promise((fim) => {
    const ws = new WebSocket('wss://stream.aisstream.io/v0/stream');
    const parar = () => { try { ws.close(); } catch { /* já fechado */ } fim(estado); };
    const relogio = setTimeout(parar, ESCUTA_MS);
    ws.onopen = () => ws.send(JSON.stringify(subscricao(chave, mmsis)));
    ws.onmessage = async (ev) => {
      try {
        const t = typeof ev.data === 'string' ? ev.data : await new Response(ev.data).text();
        const m = JSON.parse(t); juntar(estado, m); novos.add(String(m?.MetaData?.MMSI ?? ''));
        if (mmsis.every((x) => novos.has(x))) { clearTimeout(relogio); parar(); }
      } catch { /* mensagem ilegível: ignorar */ }
    };
    ws.onerror = () => { clearTimeout(relogio); parar(); };
    ws.onclose = () => { clearTimeout(relogio); fim(estado); };
  });
}

/** v89: escuta o corredor Portugal ⇄ São Tomé e devolve os navios de carga com destino declarado na rota. */
function escutarRota(chave: string): Promise<Map<string, NavioRota>> {
  const achados = new Map<string, NavioRota>();
  return new Promise((fim) => {
    const ws = new WebSocket('wss://stream.aisstream.io/v0/stream');
    const parar = () => { try { ws.close(); } catch { /* já fechado */ } fim(achados); };
    const relogio = setTimeout(parar, ESCUTA_MS);
    ws.onopen = () => ws.send(JSON.stringify(subscricaoRota(chave)));
    ws.onmessage = async (ev) => {
      try {
        const n = classificar(JSON.parse(typeof ev.data === 'string' ? ev.data : await new Response(ev.data).text()));
        if (n) achados.set(n.mmsi, n);
      } catch { /* mensagem ilegível: ignorar */ }
    };
    ws.onerror = () => { clearTimeout(relogio); parar(); };
    ws.onclose = () => { clearTimeout(relogio); fim(achados); };
  });
}

async function seguidos(chave: string): Promise<{ seguidos: number; atualizados: number }> {
  const { data, error } = await admin.rpc('servico_navios_seguidos');
  if (error) throw error;
  const mmsis = ((data ?? []) as { mmsi: string }[]).map((r) => r.mmsi);
  if (!mmsis.length) return { seguidos: 0, atualizados: 0 };
  // Parte do que já se sabe, para uma mensagem só de posição não apagar o destino e a ETA guardados.
  const { data: antes } = await admin.from('navios_posicoes').select('mmsi,nome,imo,latitude,longitude,velocidade_nos,rumo,destino,eta,posicao_em').in('mmsi', mmsis);
  const estado = new Map<string, Posicao>(((antes ?? []) as Posicao[]).map((p) => [p.mmsi, p]));
  const lido = await escutar(chave, mmsis, estado);
  const linhas = [...lido.values()].map((p) => ({ ...p, atualizado_em: new Date().toISOString() }));
  if (linhas.length) {
    const { error: e2 } = await admin.from('navios_posicoes').upsert(linhas, { onConflict: 'mmsi' });
    if (e2) throw e2;
  }
  return { seguidos: mmsis.length, atualizados: linhas.length };
}

async function rota(chave: string): Promise<number> {
  const linhas = [...(await escutarRota(chave)).values()].map((n) => ({ ...n, atualizado_em: new Date().toISOString() }));
  if (linhas.length) {
    const { error } = await admin.from('navios_rota').upsert(linhas, { onConflict: 'mmsi' });
    if (error) throw error;
  }
  return linhas.length;
}

Deno.serve(seguro('navios-ais', async (req: Request) => {
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  if (!(await pedidoAgendado(req, admin))) return erro(401, 'nao_autorizado', 'Não autorizado.');
  const chave = Deno.env.get('AISSTREAM_API_KEY') ?? '';
  if (chave.length < 20) return erro(503, 'nao_configurado', 'AISSTREAM_API_KEY ainda não está definido.');
  try {
    const [s, r] = await Promise.all([seguidos(chave), rota(chave)]);   // as duas escutas correm em paralelo (cerca de 40 s)
    return resposta(200, { ok: true, ...s, na_rota: r });
  } catch (e) {
    console.error('navios-ais: erro', e instanceof Error ? e.message : e);
    return erro(500, 'interno', 'Erro interno.');
  }
}, { admin }));
