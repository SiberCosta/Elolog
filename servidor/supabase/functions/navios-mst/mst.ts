// MyShipTracking (API paga por créditos) — navios em São Tomé e Príncipe. Funções puras, testáveis sem rede.
// Docs: https://api.myshiptracking.com/docs  ·  autenticação: cabeçalho x-api-key  ·  porto: São Tomé = port_id 5867 (UN/LOCODE na MST: STPCP).
// Custos (1 execução): chegadas previstas 1 crédito/navio · navios no porto 10 créditos · saídas (7 dias) 5 créditos/dia com saídas.

export const BASE = 'https://api.myshiptracking.com/api/v2';
export const PORTO = 5867;   // confirmado em /port/search «Sao Tome» (o código STTMS não existe na MyShipTracking)

export type Estado = 'a_caminho' | 'no_porto' | 'partiu';
export interface NavioSTP { mmsi: string; nome?: string; imo?: string; estado: Estado; sentido: 'PT-STP' | 'STP-PT'; destino: string;
  eta: string | null; evento_em: string | null; tipo_txt?: string; bandeira?: string; gt?: number; fonte: 'myshiptracking'; visto_em: string }

/** Os três pedidos de cada execução (caminho + parâmetros). */
export function pedidos(porto: string | number = PORTO): { chave: Estado; url: string }[] {
  const id: Record<string, string> = typeof porto === 'number' ? { port_id: String(porto) } : { unloco: porto };
  const q = (p: string, o: Record<string, string>) => `${BASE}${p}?${new URLSearchParams({ ...id, ...o })}`;
  return [
    { chave: 'partiu', url: q('/port/calls', { type: '2', days: '7' }) },
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

/** Junta os resultados: o mesmo navio fica com o estado mais recente (partiu < a caminho < no porto). */
export function juntar(listas: NavioSTP[][]): NavioSTP[] {
  const m = new Map<string, NavioSTP>();
  for (const l of listas) for (const x of l) m.set(x.mmsi, x);
  return [...m.values()];
}
