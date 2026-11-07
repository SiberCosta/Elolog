// Testes da ligação MyShipTracking (v92). Correr: node --experimental-strip-types mst.test.mts
import { converter, converterZona, juntar, pedidoZona, pedidos, ZONAS } from '../navios-mst/mst.ts';
let falhas = 0;
const ok = (c: unknown, m: string) => { console.log((c ? '✔ ' : '✘ ') + m); if (!c) falhas++; };
const p = pedidos();
ok(p.length === 3 && p.every((x) => x.url.startsWith('https://api.myshiptracking.com/api/v2/') && x.url.includes('port_id=5867')), 'três pedidos ao porto de São Tomé (5867)');
ok(p[0].url.includes('type=2') && p[0].url.includes('days=20'), 'saídas dos últimos 20 dias');
const est = converter('a_caminho', { status: 'success', data: [{ mmsi: 636012345, imo: 9123456, vessel_name: 'CARGO UM', vessel_type: 'Cargo', flag: 'LR', gt: 9000, eta_utc: '2026-11-20 08:00:00' }, { mmsi: 12, vessel_name: 'X' }] });
ok(est.length === 1 && est[0].estado === 'a_caminho' && est[0].eta === '2026-11-20T08:00:00.000Z' && est[0].imo === '9123456' && est[0].sentido === 'PT-STP', 'chegadas previstas convertidas (MMSI inválido ignorado)');
const inp = converter('no_porto', { status: 'success', data: [{ mmsi: 636012345, name: 'CARGO UM', arrived: '2026-11-06T10:00:00Z' }] });
ok(inp[0].estado === 'no_porto' && inp[0].evento_em === '2026-11-06T10:00:00.000Z' && inp[0].nome === 'CARGO UM', 'navio no porto convertido');
const par = converter('partiu', { status: 'success', data: [{ mmsi: 311000001, vessel_name: 'SAIU', event: 'Departure', time_utc: '2026-11-05 18:30:00' }, { mmsi: 311000002, event: 'Arrival' }] });
ok(par.length === 1 && par[0].sentido === 'STP-PT' && par[0].evento_em === '2026-11-05T18:30:00.000Z', 'saídas convertidas (chegadas ignoradas)');
ok(converter('a_caminho', { status: 'error', code: 'ERR_NO_CREDITS' }).length === 0 && converter('a_caminho', null).length === 0, 'erros e respostas vazias ignorados');
ok(juntar([par, est, inp]).length === 2 && juntar([par, est, inp]).find((x) => x.mmsi === '636012345')?.estado === 'no_porto', 'o mesmo navio fica com o estado mais recente');
const lis = ZONAS[0], stp = ZONAS.find((z) => z.stp)!;
ok(pedidoZona(lis).includes('/vessel/zone?') && pedidoZona(lis).includes('response=extended'), 'pedido por zona com dados de viagem');
const zpt = converterZona(lis, { status: 'success', data: [{ mmsi: 255000001, vessel_name: 'PARA STP', destination: 'ST TMS', eta: '2026-11-25T06:00:00Z', lat: 38.7, lng: -9.1 },
  { mmsi: 255000002, vessel_name: 'PARA ROTERDAO', destination: 'NLRTM' }, { mmsi: 255000003, vessel_name: 'SAO TOME', destination: 'STTMS' }] });
ok(zpt.length === 2 && zpt.every((x) => x.estado === 'a_caminho' && x.local === 'Lisboa') && zpt[0].eta === '2026-11-25T06:00:00.000Z', 'em Lisboa: só os navios com destino São Tomé (ST TMS / STTMS)');
const zst = converterZona(stp, { status: 'success', data: [{ mmsi: 636000009, vessel_name: 'SAI PARA LISBOA', destination: 'LISBON' }, { mmsi: 636000010, destination: 'ST TOME' }] });
ok(zst.length === 1 && zst[0].estado === 'partiu' && zst[0].destino === 'LISBON', 'em São Tomé: navios a sair com o destino declarado');
const j = juntar([[{ ...par[0], mmsi: '636000009' }], zst]);
ok(j.length === 1 && j[0].destino === 'LISBON' && j[0].evento_em === par[0].evento_em, 'saída: junta a hora real da escala com o destino declarado');
console.log(falhas ? `\n${falhas} FALHA(S)` : '\nTodos os testes passaram.');
if (falhas) (globalThis as any).process.exit(1);
