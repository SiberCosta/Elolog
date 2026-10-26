// Testes das funções de produção (pagamentos ifthenpay, aviso, AIS). Sem rede: a API e a base de dados são simuladas.
import { tratar, type DepsPag, type Pedido } from '../pagamentos/handler.ts';
import { criarIfthenpay, dataIso, estadoPedidoMbway } from '../pagamentos/ifthenpay.ts';
import { avisar } from '../pagamentos-aviso/aviso.ts';
import { etaIso, juntar, subscricao, type Posicao } from '../navios-ais/ais.ts';

let falhas = 0;
const ok = (c: unknown, m: string) => { console.log((c ? '✔ ' : '✘ ') + m); if (!c) falhas++; };
const post = (corpo: unknown, h: Record<string, string> = {}) =>
  new Request('https://x/functions/v1/pagamentos', { method: 'POST', headers: { 'content-type': 'application/json', ...h }, body: JSON.stringify(corpo) });
const ID = '11111111-2222-4333-8444-555555555555';

// ---------- ifthenpay: pedidos HTTP certos e leitura das respostas
const chamadas: { url: string; corpo?: unknown }[] = [];
const falso = (resp: Record<string, unknown>) => (async (url: string, init?: RequestInit) => {
  chamadas.push({ url, corpo: init?.body ? JSON.parse(String(init.body)) : undefined });
  return new Response(JSON.stringify(resp));
}) as (u: string, i?: RequestInit) => Promise<Response>;
const api1 = criarIfthenpay(() => undefined, falso({ Status: '0', Entity: '12345', Reference: '123456789', Amount: '10.00', ExpiryDate: '28-10-2026', RequestId: 'r1' }));
const mb = await api1.multibanco({ chave: 'ABC-123456', orderId: 'ELX', valor: 10, descricao: 'Encomenda', sandbox: true, dias: 3 });
ok(mb.ok && mb.entidade === '12345' && mb.referencia === '123456789' && mb.expira === '2026-10-28T23:59:59Z', 'Multibanco: referência e prazo lidos');
ok(chamadas[0].url.endsWith('/multibanco/reference/sandbox') && (chamadas[0].corpo as { amount: string }).amount === '10.00', 'Multibanco: sandbox e valor com ponto decimal');
const api2 = criarIfthenpay(() => undefined, falso({ Status: '000', RequestId: 'rq9', Message: 'Pending' }));
const w = await api2.mbway({ chave: 'MBW-123456', orderId: 'ELY', valor: 5.5, telemovel: '912345678', descricao: 'x' });
ok(w.ok && w.requestId === 'rq9' && (chamadas[1].corpo as { mobileNumber: string }).mobileNumber === '351#912345678', 'MB WAY: número no formato 351#9…');
ok(estadoPedidoMbway('000') === 'pago' && estadoPedidoMbway('020') === 'recusado' && estadoPedidoMbway('101') === 'expirado' && estadoPedidoMbway('123') === null, 'estados MB WAY traduzidos');
ok(dataIso('2026-11-02') === '2026-11-02T23:59:59Z' && dataIso('') === null, 'datas de validade');

// ---------- função «pagamentos»
const registo: string[] = [];
const pedido: Pedido = { id: ID, order_id: 'EL1234567890AB', metodo: 'multibanco', valor: 120, estado: 'pendente' };
const deps = (extra: Partial<DepsPag> = {}): DepsPag => ({
  agendado: async (r) => r.headers.get('x-cron-secret') === 'segredo',
  autenticar: async (j) => (j === 'bom' ? 'cliente-1' : null),
  limite: async () => true,
  preparar: async (_c, enc, met) => (enc === 'PAGA' ? { erro: 'Esta encomenda já está paga.' } : { reutilizar: false, pedido: { ...pedido, metodo: met }, chave: 'K-123456', sandbox: true, descricao: 'Encomenda ' + enc }),
  atualizar: async (id, e, d) => { registo.push(`atualizar ${e ?? '-'} ${JSON.stringify(d)}`); },
  confirmar: async (o, v, origem) => { registo.push(`confirmar ${o} ${v} ${origem}`); return 'pago'; },
  pendentesMbway: async () => [{ id: ID, order_id: 'ELW', request_id: 'rq', valor: 9, chave: 'K' }],
  lerPedido: async () => null,
  api: api1, ...extra,
});
let r = await tratar(post({ acao: 'pedir', encomenda: 'TR-1', metodo: 'multibanco' }), deps());
ok(r.status === 401, 'sem sessão: recusado');
r = await tratar(post({ acao: 'pedir', encomenda: 'TR-1', metodo: 'multibanco' }, { authorization: 'Bearer bom' }), deps());
let j = await r.json();
ok(r.status === 200 && j.pedido.referencia === '123456789' && j.pedido.entidade === '12345', 'cliente recebe entidade e referência');
ok(registo.some((x) => x.includes('"referencia":"123456789"')), 'referência guardada no pedido');
ok(!JSON.stringify(j).includes('K-123456'), 'a chave da empresa nunca vai para o cliente');
r = await tratar(post({ acao: 'pedir', encomenda: 'TR-1', metodo: 'mbway', telemovel: '812' }, { authorization: 'Bearer bom' }), deps());
ok(r.status === 400, 'MB WAY com telemóvel inválido recusado');
r = await tratar(post({ acao: 'pedir', encomenda: 'PAGA', metodo: 'multibanco' }, { authorization: 'Bearer bom' }), deps());
j = await r.json();
ok(r.status === 409 && j.erro.mensagem.includes('já está paga'), 'encomenda já paga: mensagem do servidor');
r = await tratar(post({ acao: 'pedir', encomenda: 'TR-1', metodo: 'multibanco' }, { authorization: 'Bearer bom' }), deps({ api: criarIfthenpay(() => undefined, falso({ Status: '5', Message: 'erro' })) }));
ok(r.status === 502 && registo.some((x) => x.startsWith('atualizar erro')), 'falha da ifthenpay: pedido marcado com erro, mensagem simples');
r = await tratar(post({ acao: 'verificar' }), deps());
ok(r.status === 401, 'verificação sem segredo recusada');
r = await tratar(post({ acao: 'verificar' }, { 'x-cron-secret': 'segredo' }), deps({ api: criarIfthenpay(() => undefined, falso({ Status: '000' })) }));
j = await r.json();
ok(j.pagos === 1 && registo.some((x) => x === 'confirmar ELW 9 verificacao'), 'verificação periódica confirma MB WAY pago');
r = await tratar(new Request('https://x', { method: 'GET' }), deps());
ok(r.status === 405, 'GET recusado');

// ---------- aviso da ifthenpay
const conf = async (o: string, k: string, v: number) => (k !== 'antiphishing-123' ? 'chave_invalida' : v !== 120 ? 'valor_diferente' : 'pago');
ok((await avisar(new URL('https://x/?key=antiphishing-123&orderId=EL1234567890AB&amount=120.00'), conf)).status === 200, 'aviso válido: 200');
ok((await avisar(new URL('https://x/?key=errada&orderId=EL1234567890AB&amount=120'), conf)).status === 403, 'aviso com chave errada: 403');
ok((await avisar(new URL('https://x/?key=antiphishing-123&orderId=EL1234567890AB&amount=1'), conf)).status === 400, 'aviso com valor diferente: recusado');
ok((await avisar(new URL('https://x/?key=a&orderId=<x>&amount=1'), conf)).status === 400, 'aviso com dados estranhos: recusado');

// ---------- AIS
const est = new Map<string, Posicao>();
juntar(est, { MessageType: 'PositionReport', MetaData: { MMSI: 255806000, ShipName: 'SAO TOME@@', latitude: 38.7, longitude: -9.1, time_utc: '2026-10-25 18:00:00.0 +0000 UTC' },
  Message: { PositionReport: { Latitude: 38.69, Longitude: -9.14, Sog: 12.3, Cog: 190 } } });
juntar(est, { MessageType: 'ShipStaticData', MetaData: { MMSI: 255806000 }, Message: { ShipStaticData: { Name: 'SAO TOME', Destination: 'STP SAO TOME', ImoNumber: 9123456, Eta: { Month: 11, Day: 3, Hour: 8, Minute: 0 } } } });
juntar(est, { MessageType: 'PositionReport', MetaData: { MMSI: 'abc' } });
const n = est.get('255806000');
ok(n?.latitude === 38.69 && n?.velocidade_nos === 12.3 && n?.nome === 'SAO TOME' && n?.destino === 'STP SAO TOME' && est.size === 1, 'AIS: posição e dados de viagem juntos por MMSI');
ok(etaIso({ Month: 11, Day: 3, Hour: 8, Minute: 0 }, new Date('2026-10-25T00:00:00Z')) === '2026-11-03T08:00:00.000Z', 'ETA no próprio ano');
ok(etaIso({ Month: 1, Day: 5, Hour: 24, Minute: 60 }, new Date('2026-12-20T00:00:00Z')) === '2027-01-05T00:00:00.000Z' && etaIso({ Month: 0, Day: 0 }) === null, 'ETA passa de ano; ETA vazia ignorada');
ok(subscricao('k', ['255806000']).FiltersShipMMSI[0] === '255806000', 'subscrição filtra pelos navios seguidos');

console.log(falhas ? `\n${falhas} FALHA(S)` : '\nTodos os testes passaram.');
if (falhas) (globalThis as { process?: { exit(c: number): void } }).process?.exit(1);
