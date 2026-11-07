// MyShipTracking (API paga por créditos) — navios em São Tomé e Príncipe. Funções puras, testáveis sem rede.
// Docs: https://api.myshiptracking.com/docs  ·  autenticação: cabeçalho x-api-key  ·  porto: São Tomé = port_id 5867 (UN/LOCODE na MST: STPCP).
// Custos (1 execução por dia): chegadas previstas 1/navio · no porto 10 · saídas (20 dias) 5 por dia com saídas · zonas 3/navio.

export const BASE = 'https://api.myshiptracking.com/api/v2';
export const PORTO = 5867;   // confirmado em /port/search «Sao Tome» (o código STTMS não existe na MyShipTracking)

export type Estado = 'a_caminho' | 'no_porto' | 'partiu';
export interface NavioSTP { mmsi: string; nome?: string; imo?: string; estado: Estado; sentido: 'PT-STP' | 'STP-PT'; destino: string;
  eta: string | null; evento_em: string | null; tipo_txt?: string; bandeira?: string; gt?: number; fonte: 'myshiptracking'; visto_em: string;
  local?: string; latitude?: number; longitude?: number }

/** Os três pedidos de cada execução (caminho + parâmetros). */
export function pedidos(porto: string | number = PORTO): { chave: Estado; url: string }[] {
  const id: Record<string, string> = typeof porto === 'number' ? { port_id: String(porto) } : { unloco: porto };
  const q = (p: string, o: Record<string, string>) => `${BASE}${p}?${new URLSearchParams({ ...id, ...o })}`;
  return [
    { chave: 'partiu', url: q('/port/calls', { type: '2', days: '20' }) },   // 20 dias: limite das chaves de teste
    { chave: 'a_caminho', url: q('/port/estimate', {}) },
    { chave: 'no_porto', url: q('/port/inport', {}) },
  ];
}

const s = (v: unknown, max = 80) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : undefined);
const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && /^\d+$/.test(v) ? Number(v) : undefined);
const data = (v: unknown) => { const t = typeof v === 'string' ? Date.parse(/[zZ]|[+-]\d\d:?\d\d$/.test(v) ? v : v.replace(' ', 'T') + 'Z') : NaN; return Number.isFinite(t) ? new Date(t).toISOString() : null; };

/** Converte a resposta da API em navios. Respostas de erro ou registos sem MMSI válido são ignorados. */
export function converter(estado: Estado, corpo: unknown, agora = new Date()): NavioSTP[] {
  const c = corpo as { status?: string; data?: unknown };
  if (!c || c.status === 'error' || !Array.isArray(c.data)) return [];
  const out: NavioSTP[] = [];
  for (const r of c.data as Record<string, unknown>[]) {
    const mmsi = String(r?.mmsi ?? '');
    if (!/^\d{9}$/.test(mmsi)) continue;
    if (estado === 'partiu' && r.event && !/depart/i.test(String(r.event))) continue;
    const imo = n(r.imo);
    out.push({ mmsi, nome: s(r.vessel_name ?? r.name), imo: imo && imo > 999999 ? String(imo).slice(0, 7) : undefined, estado,
      sentido: estado === 'partiu' ? 'STP-PT' : 'PT-STP', destino: estado === 'partiu' ? 'Saída de São Tomé' : 'São Tomé',
      eta: estado === 'a_caminho' ? data(r.eta_utc) : null, evento_em: estado === 'partiu' ? data(r.time_utc) : estado === 'no_porto' ? data(r.arrived) : null,
      tipo_txt: s(r.vessel_type, 40), bandeira: s(r.flag, 40), gt: n(r.gt), fonte: 'myshiptracking', visto_em: agora.toISOString() });
  }
  return out;
}

// ---------------------------------------------------------------- v93: navios por zona (destino declarado no AIS)
// Zonas pequenas nos portos portugueses e à volta de São Tomé (AIS terrestre). Resposta «extended»: 3 créditos por navio.
export interface Zona { nome: string; stp: boolean; minlat: number; maxlat: number; minlon: number; maxlon: number }
export const ZONAS: Zona[] = [
  { nome: 'Lisboa', stp: false, minlat: 38.60, maxlat: 38.76, minlon: -9.42, maxlon: -8.95 },
  { nome: 'Leixões', stp: false, minlat: 41.13, maxlat: 41.23, minlon: -8.78, maxlon: -8.66 },
  { nome: 'Setúbal', stp: false, minlat: 38.42, maxlat: 38.54, minlon: -8.98, maxlon: -8.78 },
  { nome: 'Sines', stp: false, minlat: 37.88, maxlat: 37.99, minlon: -8.94, maxlon: -8.83 },
  { nome: 'São Tomé', stp: true, minlat: -0.25, maxlat: 0.70, minlon: 6.30, maxlon: 6.95 },
];
export const DESTINO_STP = /\bS(?:T|AO|\.)?\.?\s*TOM[EÉ]|S\.\s*TOM|STTMS|ST\s*TMS|STPCP|NEVES|PRINCIPE|\bSTP\b/i;

export function pedidoZona(z: Zona): string {
  return `${BASE}/vessel/zone?${new URLSearchParams({ minlat: String(z.minlat), maxlat: String(z.maxlat), minlon: String(z.minlon),
    maxlon: String(z.maxlon), minutesBack: '360', response: 'extended' })}`;
}

/** Navios de uma zona: em Portugal só os que declaram destino São Tomé (a caminho); em São Tomé, os que declaram
 *  outro destino (a partir, com o destino declarado). */
export function converterZona(z: Zona, corpo: unknown, agora = new Date()): NavioSTP[] {
  const c = corpo as { status?: string; data?: unknown };
  if (!c || c.status === 'error' || !Array.isArray(c.data)) return [];
  const out: NavioSTP[] = [];
  for (const r of c.data as Record<string, unknown>[]) {
    const mmsi = String(r?.mmsi ?? ''), destino = s(r.destination, 40) ?? '';
    if (!/^\d{9}$/.test(mmsi) || !destino) continue;
    const paraStp = DESTINO_STP.test(destino);
    if (z.stp === paraStp) continue;                       // em PT: só destino STP · em STP: só destino diferente de STP
    const imo = n(r.imo), lat = n(r.lat) ?? Number(r.lat), lng = n(r.lng) ?? Number(r.lng);
    out.push({ mmsi, nome: s(r.vessel_name ?? r.name), imo: imo && imo > 999999 ? String(imo).slice(0, 7) : undefined,
      estado: paraStp ? 'a_caminho' : 'partiu', sentido: paraStp ? 'PT-STP' : 'STP-PT', destino,
      eta: data(r.eta), evento_em: paraStp ? null : agora.toISOString(), tipo_txt: s(r.vessel_type, 40), bandeira: s(r.flag, 40), gt: n(r.gt),
      fonte: 'myshiptracking', visto_em: agora.toISOString(), local: z.nome,
      latitude: Number.isFinite(lat) ? lat : undefined, longitude: Number.isFinite(lng) ? lng : undefined });
  }
  return out;
}

const PESO: Record<Estado, number> = { partiu: 1, a_caminho: 2, no_porto: 3 };
/** Junta os resultados de todas as fontes por navio. Fica o estado mais «atual» (no porto > a caminho > partiu);
 *  com o mesmo estado, completa os campos em falta (ex.: destino da zona + hora real de saída das escalas). */
export function juntar(listas: NavioSTP[][]): NavioSTP[] {
  const m = new Map<string, NavioSTP>();
  for (const l of listas) for (const x of l) {
    const a = m.get(x.mmsi);
    if (!a || PESO[x.estado] > PESO[a.estado]) { m.set(x.mmsi, a ? { ...completar(x, a) } : x); continue; }
    if (PESO[x.estado] === PESO[a.estado]) m.set(x.mmsi, completar(a, x));
    else m.set(x.mmsi, completar(a, x, ['nome', 'imo', 'tipo_txt', 'bandeira', 'gt']));
  }
  return [...m.values()];
}
/** Preenche em «base» os campos vazios com os de «extra» (sem substituir o que já existe). */
function completar(base: NavioSTP, extra: NavioSTP, campos?: (keyof NavioSTP)[]): NavioSTP {
  const r = { ...base } as Record<string, unknown>, e = extra as unknown as Record<string, unknown>;
  for (const k of campos ?? (Object.keys(e) as (keyof NavioSTP)[])) if ((r[k] === undefined || r[k] === null || (k === 'destino' && /^(São Tomé|Saída de São Tomé)$/.test(String(r[k])))) && e[k] != null) r[k] = e[k];
  return r as unknown as NavioSTP;
}
