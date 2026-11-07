// Descoberta de navios REAIS na rota Portugal ⇄ São Tomé e Príncipe pelo AIS (aisstream.io, gratuito). Funções puras, testáveis sem rede.
// Escuta os dados de viagem (ShipStaticData) dos navios entre o Golfo da Guiné e Portugal e guarda os navios de carga
// cujo destino declarado é São Tomé/Neves (sentido PT-STP) ou um porto português vindo do sul (sentido STP-PT).
import { etaIso } from './ais.ts';

export interface NavioRota { mmsi: string; nome?: string; imo?: string; tipo?: number; destino: string; eta: string | null;
  sentido: 'PT-STP' | 'STP-PT'; latitude?: number; longitude?: number; visto_em: string }

// Corredor: do Golfo da Guiné (2° S) até ao norte de Portugal (43° N), de 26° W a 10° E. [lat, lon]
export const CORREDOR = [[-2, -26], [43, 10]];
const STP = /\bS(?:T|AO|\.)?\.?\s*TOM[EÉ]|S\.\s*TOM|STTMS|ST\s*TMS|NEVES|PRINCIPE|\bSTP\b/i;
const PT = /LISBO|LISBON|PTLIS|LEIX|PTLEI|SETUBAL|PTSET|\bSINES\b|PTSIE|AVEIRO|PTAVE|FIGUEIRA|PORTUGAL|OPORTO|\bPTOPO\b/i;

/** Pedido de subscrição: só dados de viagem, no corredor. */
export function subscricaoRota(chave: string) {
  return { APIKey: chave, BoundingBoxes: [CORREDOR], FilterMessageTypes: ['ShipStaticData'] };
}

const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : undefined);
const txt = (v: unknown) => (typeof v === 'string' ? v.replace(/@+/g, ' ').replace(/\s+/g, ' ').trim() : '');

/** Classifica uma mensagem: devolve o navio se estiver na rota, ou null. Só carga (70–79), petroleiros (80–89) ou tipo desconhecido. */
export function classificar(bruto: unknown, agora = new Date()): NavioRota | null {
  const m = bruto as { MessageType?: string; MetaData?: Record<string, unknown>; Message?: Record<string, Record<string, unknown>> };
  if (m?.MessageType !== 'ShipStaticData') return null;
  const md = m.MetaData ?? {}, c = m.Message?.ShipStaticData ?? {};
  const mmsi = String(md.MMSI ?? c.UserID ?? '');
  if (!/^\d{9}$/.test(mmsi)) return null;
  const destino = txt(c.Destination).slice(0, 40);
  const tipo = num(c.Type);
  if (!destino || (tipo !== undefined && tipo !== 0 && (tipo < 70 || tipo > 89))) return null;
  const lat = num(md.latitude), lon = num(md.longitude);
  let sentido: NavioRota['sentido'] | null = null;
  if (STP.test(destino)) sentido = 'PT-STP';
  else if (PT.test(destino) && (lat === undefined || lat < 30)) sentido = 'STP-PT';   // a caminho de Portugal, ainda a sul
  if (!sentido) return null;
  const imo = c.ImoNumber && Number(c.ImoNumber) > 999999 ? String(c.ImoNumber).slice(0, 7) : undefined;
  return { mmsi, nome: txt(c.Name || md.ShipName).slice(0, 80) || undefined, imo, tipo, destino, sentido,
    eta: etaIso(c.Eta as { Month?: number; Day?: number; Hour?: number; Minute?: number }, agora),
    latitude: lat, longitude: lon, visto_em: agora.toISOString() };
}
