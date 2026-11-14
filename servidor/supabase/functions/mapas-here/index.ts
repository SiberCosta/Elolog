// Edge Function «mapas-here» (v132): rotas de camião com trânsito e localização de moradas pelo HERE, sem a chave sair do servidor.
//   POST {acao:'rota', de:{lat,lon}, para:{lat,lon}}        → {km, min, min_sem_transito, linha:[[lon,lat]…], fonte:'here'}
//   POST {acao:'matriz', de:{lat,lon}, para:[{lat,lon}…≤10]} → {km:[…], fonte:'here'}  (uma rota por destino)
//   POST {acao:'morada', q:'texto'}                          → {lat, lon, fonte:'here'} ou {encontrado:false}
// Só para utilizadores com sessão iniciada. Limites: 300 pedidos/hora por utilizador e um teto MENSAL (por omissão 90 % da quota
// gratuita: 4500 rotas e 27000 moradas; mudar com os segredos HERE_LIMITE_ROTAS / HERE_LIMITE_MORADAS). Acima do teto devolve 429
// e a aplicação usa os serviços gratuitos (Valhalla, GeoAPI.pt, Photon). Segredo obrigatório: HERE_API_KEY.
// Deploy: supabase functions deploy mapas-here
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { limitar, seguro } from '../_shared/seguranca.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
type P = { lat: number; lon: number };
const ponto = (v: unknown): P | null => { const o = (v ?? {}) as Record<string, unknown>; const lat = Number(o.lat), lon = Number(o.lon);
  return Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 ? { lat, lon } : null; };
const um = (n: number) => Math.round(n * 10) / 10;

// «flexible polyline» do HERE → [[lon,lat]…]
const TAB = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
function descodificar(s: string): number[][] {
  let i = 0; const ler = () => { let r = 0, mult = 1, c; do { c = TAB.indexOf(s[i++]); if (c < 0) throw new Error('polyline'); r += (c & 31) * mult; mult *= 32; } while (c & 32); return r; };
  const z = (u: number) => (u % 2 ? -(u + 1) / 2 : u / 2);
  ler(); const h = ler(); const prec = 10 ** (h & 15), terceira = Math.floor(h / 16) & 7; let lat = 0, lon = 0; const l: number[][] = [];
  while (i < s.length) { lat += z(ler()); lon += z(ler()); if (terceira) ler(); l.push([lon / prec, lat / prec]); }
  return l;
}
async function here(url: string) {
  const c = new AbortController(), t = setTimeout(() => c.abort(), 9000);
  try { const r = await fetch(url + '&apiKey=' + encodeURIComponent(env('HERE_API_KEY')), { signal: c.signal }); if (!r.ok) { console.error('mapas-here: HERE', r.status); return null; } return await r.json(); }
  catch { return null; } finally { clearTimeout(t); }
}
const conta = async (tipo: 'rota' | 'morada', n = 1) => { const max = Number(env(tipo === 'rota' ? 'HERE_LIMITE_ROTAS' : 'HERE_LIMITE_MORADAS')) || (tipo === 'rota' ? 4500 : 27000);
  for (let k = 0; k < n; k++) { const { data, error } = await admin.rpc('servico_here_contar', { p_tipo: tipo, p_max: max }); if (error || data !== true) return false; } return true; };
async function rota(de: P, para: P, comLinha: boolean) {
  const j = await here(`https://router.hereapi.com/v8/routes?transportMode=truck&origin=${de.lat},${de.lon}&destination=${para.lat},${para.lon}&return=summary${comLinha ? ',polyline' : ''}`);
  const sec = j?.routes?.[0]?.sections; if (!Array.isArray(sec) || !sec.length) return null;
  const s = sec.reduce((a: { l: number; d: number; b: number }, x: { summary?: { length?: number; duration?: number; baseDuration?: number } }) =>
    ({ l: a.l + (x.summary?.length ?? 0), d: a.d + (x.summary?.duration ?? 0), b: a.b + (x.summary?.baseDuration ?? x.summary?.duration ?? 0) }), { l: 0, d: 0, b: 0 });
  let linha: number[][] = []; if (comLinha) try { linha = sec.flatMap((x: { polyline?: string }) => x.polyline ? descodificar(x.polyline) : []); } catch { linha = []; }
  return { km: um(s.l / 1000), min: Math.round(s.d / 6) / 10, min_sem_transito: Math.round(s.b / 6) / 10, linha, fonte: 'here' };
}

Deno.serve(seguro('mapas-here', async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: u } = jwt ? await admin.auth.getUser(jwt) : { data: null };
  if (!u?.user) return erro(401, 'sessao', 'Inicie sessão para usar os mapas HERE.');
  if (!(await limitar(admin, 'here:' + u.user.id, 300, 60))) return erro(429, 'limite', 'Demasiados pedidos de mapa seguidos.');
  const lido = await lerJson(req, 4000); if (!lido.ok) return lido.resp;
  const b = (lido.valor ?? {}) as Record<string, unknown>;
  if (b.acao === 'morada') {
    const q = String(b.q ?? '').replace(/\s+/g, ' ').trim().slice(0, 300); if (q.length < 3) return resposta(200, { encontrado: false });
    if (!(await conta('morada'))) return erro(429, 'quota', 'Quota mensal do HERE atingida.');
    const pt = /\b\d{4}-\d{3}\b/.test(q) && !/s[aã]o tom[eé]|angola|brasil|cabo verde|mo[cç]ambique|espanha|fran[cç]a/i.test(q);
    const j = await here(`https://geocode.search.hereapi.com/v1/geocode?lang=pt-PT&limit=1&q=${encodeURIComponent(q)}${pt ? '&in=countryCode:PRT' : ''}`);
    const p = j?.items?.[0]?.position; return resposta(200, p ? { lat: p.lat, lon: p.lng, fonte: 'here' } : { encontrado: false });
  }
  const de = ponto(b.de); if (!de) return erro(400, 'pontos', 'Pontos inválidos.');
  if (b.acao === 'rota') { const para = ponto(b.para); if (!para) return erro(400, 'pontos', 'Pontos inválidos.');
    if (!(await conta('rota'))) return erro(429, 'quota', 'Quota mensal do HERE atingida.');
    const r = await rota(de, para, true); return r ? resposta(200, r) : erro(502, 'here', 'Rota indisponível.'); }
  if (b.acao === 'matriz') { const l = (Array.isArray(b.para) ? b.para : []).slice(0, 10).map(ponto); if (!l.length || l.some((x) => !x)) return erro(400, 'pontos', 'Pontos inválidos.');
    if (!(await conta('rota', l.length))) return erro(429, 'quota', 'Quota mensal do HERE atingida.');
    const rs = await Promise.all(l.map((p) => rota(de, p as P, false))); return resposta(200, { km: rs.map((r) => r?.km ?? null), fonte: 'here' }); }
  return erro(400, 'acao', 'Ação desconhecida.');
}, { admin, segredos: ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'HERE_API_KEY'], metodos: ['POST'] }));
