// Testes da descoberta de navios na rota Portugal ⇄ São Tomé (v89). Correr: node --experimental-strip-types rota.test.mts
import { classificar, subscricaoRota } from '../navios-ais/rota.ts';
let falhas = 0;
const ok = (c: unknown, m: string) => { console.log((c ? '✔ ' : '✘ ') + m); if (!c) falhas++; };
const msg = (destino: string, tipo = 70, lat = 38.7, mmsi = '263000001') => ({ MessageType: 'ShipStaticData', MetaData: { MMSI: mmsi, ShipName: 'NAVIO@@', latitude: lat, longitude: -9.1 },
  Message: { ShipStaticData: { Destination: destino + '@@@', Type: tipo, Name: 'NAVIO TESTE@@', ImoNumber: 9123456, Eta: { Month: 12, Day: 1, Hour: 8, Minute: 0 } } } });
const a = classificar(msg('ST TOME'));
ok(a?.sentido === 'PT-STP' && a?.nome === 'NAVIO TESTE' && a?.imo === '9123456' && !!a?.eta, 'destino São Tomé → PT-STP com nome, IMO e ETA');
ok(classificar(msg('STTMS'))?.sentido === 'PT-STP', 'código STTMS reconhecido');
ok(classificar(msg('SAO TOME'))?.sentido === 'PT-STP', '«SAO TOME» reconhecido');
ok(classificar(msg('PTLIS LISBON', 70, 0.3))?.sentido === 'STP-PT', 'a sul, com destino Lisboa → STP-PT');
ok(classificar(msg('LISBON', 70, 38.7)) === null, 'já em Portugal com destino Lisboa: fora da rota');
ok(classificar(msg('ROTTERDAM')) === null, 'outro destino: ignorado');
ok(classificar(msg('ST TOME', 30)) === null, 'pesca/recreio: ignorado');
ok(classificar(msg('ST TOME', 84))?.sentido === 'PT-STP', 'petroleiro aceite');
ok(classificar(msg('PORTO NOVO', 70, 10)) === null, 'Porto Novo (Cabo Verde) não é confundido com Portugal');
ok(classificar({ MessageType: 'PositionReport', MetaData: { MMSI: '263000001' } }) === null, 'mensagem de posição ignorada');
ok(classificar(msg('ST TOME', 70, 38, '12')) === null, 'MMSI inválido ignorado');
const s = subscricaoRota('k'.repeat(40));
ok(s.FilterMessageTypes.length === 1 && s.BoundingBoxes.length === 1, 'subscrição só de dados de viagem no corredor');
console.log(falhas ? `\n${falhas} FALHA(S)` : '\nTodos os testes passaram.');
if (falhas) (globalThis as any).process.exit(1);
