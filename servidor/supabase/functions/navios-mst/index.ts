// Edge Function «navios-mst»: navios a caminho, no porto e que partiram de São Tomé, pela API MyShipTracking.
// Chamada pelo agendador (pg_cron, 1 vez por dia) com x-cron-secret. Guarda em navios_rota (lida pela Pesquisa marítima).
// Segredo: MYSHIPTRACKING_API_KEY (definido no Supabase → Edge Functions → Secrets). Deploy: --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { BASE, converter, converterZona, juntar, pedidoZona, pedidos, ZONAS, type NavioSTP } from './mst.ts';
import { pedidoAgendado } from '../_shared/cofre.ts';
import { erro, resposta } from '../_shared/http.ts';
import { seguro } from '../_shared/seguranca.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } });

async function pedir(url: string, chave: string): Promise<{ corpo: unknown; creditos: number; erro?: string }> {
  const r = await fetch(url, { headers: { 'x-api-key': chave, accept: 'application/json' }, signal: AbortSignal.timeout(20_000) });
  const corpo = await r.json().catch(() => null) as { code?: string; message?: string } | null;
  return { corpo, creditos: Number(r.headers.get('X-Credit-Charged') ?? 0) || 0, erro: r.ok ? undefined : `${r.status} ${corpo?.code ?? ''}`.trim() };
}

Deno.serve(seguro('navios-mst', async (req: Request) => {
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  if (!(await pedidoAgendado(req, admin))) return erro(401, 'nao_autorizado', 'Não autorizado.');
  const chave = (Deno.env.get('MYSHIPTRACKING_API_KEY') ?? '').trim();
  if (chave.length < 10) return erro(503, 'nao_configurado', 'MYSHIPTRACKING_API_KEY ainda não está definido.');
  // Diagnóstico (só pelo agendador / SQL): {"procurar":"Sao Tome"} devolve os portos encontrados (1 crédito).
  const corpo = await req.json().catch(() => ({})) as { procurar?: unknown; porto_id?: unknown; zonas?: unknown };
  if (typeof corpo.procurar === 'string' && corpo.procurar.trim().length >= 3) {
    const r = await pedir(`${BASE}/port/search?${new URLSearchParams({ name: corpo.procurar.trim().slice(0, 40) })}`, chave);
    return resposta(r.erro ? 502 : 200, { ok: !r.erro, erro: r.erro, portos: (r.corpo as { data?: unknown })?.data ?? [] });
  }
  const listas: NavioSTP[][] = [], erros: string[] = [];
  let creditos = 0;
  const portoId = Number(corpo.porto_id) > 0 ? Math.floor(Number(corpo.porto_id)) : undefined;   // teste de outro porto
  for (const p of pedidos(portoId)) {                       // em sequência: respeita o limite de pedidos por minuto
    try {
      const r = await pedir(p.url, chave);
      creditos += r.creditos;
      if (r.erro && /ERR_NOT_FOUND/.test(r.erro)) { listas.push([]); continue; }   // sem navios neste momento (não gasta créditos)
      if (r.erro) { erros.push(`${p.chave}: ${r.erro}`); if (/ERR_(INVALID_KEY|NO_KEY|NO_CREDITS)/.test(r.erro)) break; continue; }
      listas.push(converter(p.chave, r.corpo));
    } catch (e) { erros.push(`${p.chave}: ${e instanceof Error ? e.name : 'falha'}`); }
  }
  // v93: navios nos portos portugueses com destino São Tomé e navios a sair de São Tomé (com destino declarado).
  for (const z of corpo.zonas === false ? [] : ZONAS) {   // {"zonas":false} = teste sem gastar créditos nas zonas
    if (erros.some((e) => /ERR_(INVALID_KEY|NO_KEY|NO_CREDITS)/.test(e))) break;
    try {
      const r = await pedir(pedidoZona(z), chave);
      creditos += r.creditos;
      if (r.erro && /ERR_NOT_FOUND/.test(r.erro)) continue;
      if (r.erro) { erros.push(`zona ${z.nome}: ${r.erro}`); continue; }
      listas.push(converterZona(z, r.corpo));
    } catch (e) { erros.push(`zona ${z.nome}: ${e instanceof Error ? e.name : 'falha'}`); }
  }
  const linhas = juntar(listas).map((x) => ({ ...x, atualizado_em: new Date().toISOString() }));
  if (linhas.length) {
    const { error } = await admin.from('navios_rota').upsert(linhas, { onConflict: 'mmsi' });
    if (error) throw error;
  }
  if (erros.length) console.error('navios-mst:', erros.join(' · '));
  return resposta(erros.length && !linhas.length ? 502 : 200, { ok: !erros.length, navios: linhas.length, creditos, erros });
}, { admin }));
