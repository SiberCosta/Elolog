// Leitura das mensagens AIS do aisstream.io (gratuito). Funções puras, testadas sem rede.

export interface Posicao { mmsi: string; nome?: string; imo?: string; latitude?: number; longitude?: number; velocidade_nos?: number;
  rumo?: number; destino?: string; eta?: string | null; posicao_em?: string }

/** ETA do AIS (mês, dia, hora, minuto, sem ano) → ISO no próximo ano em que essa data ainda não passou. */
export function etaIso(e: { Month?: number; Day?: number; Hour?: number; Minute?: number } | undefined, agora = new Date()): string | null {
  if (!e || !e.Month || !e.Day || e.Month > 12 || e.Day > 31) return null;
  const h = (e.Hour ?? 24) < 24 ? e.Hour ?? 0 : 0, m = (e.Minute ?? 60) < 60 ? e.Minute ?? 0 : 0;
  let d = new Date(Date.UTC(agora.getUTCFullYear(), e.Month - 1, e.Day, h, m));
  if (d.getTime() < agora.getTime() - 30 * 864e5) d = new Date(Date.UTC(agora.getUTCFullYear() + 1, e.Month - 1, e.Day, h, m));
  return d.toISOString();
}

const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : undefined);
const txt = (v: unknown) => (typeof v === 'string' ? v.replace(/@+/g, '').trim() || undefined : undefined);

/** Junta uma mensagem do aisstream ao estado acumulado por MMSI. Ignora o que não reconhece. */
export function juntar(estado: Map<string, Posicao>, bruto: unknown, agora = new Date()): void {
  const msg = bruto as { MessageType?: string; MetaData?: Record<string, unknown>; Message?: Record<string, Record<string, unknown>> };
  const md = msg?.MetaData ?? {};
  const mmsi = String(md.MMSI ?? md.mmsi ?? '');
  if (!/^\d{9}$/.test(mmsi)) return;
  const p: Posicao = estado.get(mmsi) ?? { mmsi };
  p.nome = txt(md.ShipName) ?? p.nome;
  const tipo = msg.MessageType ?? '';
  const corpo = msg.Message?.[tipo] ?? {};
  if (tipo === 'PositionReport' || tipo === 'StandardClassBPositionReport' || tipo === 'ExtendedClassBPositionReport') {
    const lat = num(corpo.Latitude) ?? num(md.latitude), lon = num(corpo.Longitude) ?? num(md.longitude);
    if (lat !== undefined && lon !== undefined && Math.abs(lat) <= 90 && Math.abs(lon) <= 180) {
      p.latitude = lat; p.longitude = lon;
      p.velocidade_nos = num(corpo.Sog); p.rumo = num(corpo.Cog);
      const t = Date.parse(String(md.time_utc ?? '').replace(' +0000 UTC', 'Z').replace(' ', 'T'));
      p.posicao_em = Number.isFinite(t) ? new Date(t).toISOString() : agora.toISOString();
    }
  } else if (tipo === 'ShipStaticData') {
    p.nome = txt(corpo.Name) ?? p.nome;
    p.destino = txt(corpo.Destination) ?? p.destino;
    p.imo = corpo.ImoNumber ? String(corpo.ImoNumber) : p.imo;
    p.eta = etaIso(corpo.Eta as { Month?: number; Day?: number; Hour?: number; Minute?: number }, agora) ?? p.eta;
  } else return;
  estado.set(mmsi, p);
}

/** Pedido de subscrição do aisstream para uma lista de MMSI. */
export function subscricao(chave: string, mmsis: string[]) {
  return { APIKey: chave, BoundingBoxes: [[[-90, -180], [90, 180]]], FiltersShipMMSI: mmsis.slice(0, 50),
    FilterMessageTypes: ['PositionReport', 'StandardClassBPositionReport', 'ShipStaticData'] };
}
