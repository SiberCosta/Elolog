// Lógica da função «pagamentos», separada do arranque para ser testada sem rede.
//  · cliente (token): {acao:'pedir', encomenda, metodo:'multibanco'|'mbway', telemovel?}  e  {acao:'estado', pedido}
//  · agendador (x-cron-secret): {acao:'verificar'} — confirma pedidos MB WAY cujo aviso não chegou.
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { estadoPedidoMbway, type Ifthenpay } from './ifthenpay.ts';

export interface Pedido { id: string; order_id: string; metodo: string; valor: number; estado: string; request_id?: string | null;
  entidade?: string | null; referencia?: string | null; expira_em?: string | null }
export interface DepsPag {
  agendado(req: Request): Promise<boolean>;
  autenticar(jwt: string): Promise<string | null>;
  limite(chave: string, max: number, janelaMin: number): Promise<boolean>;
  preparar(cliente: string, encomenda: string, metodo: string, telemovel: string): Promise<{ erro: string } | { reutilizar: boolean; pedido: Pedido; chave?: string; sandbox?: boolean; descricao?: string }>;
  atualizar(id: string, estado: string | null, dados: Record<string, unknown>): Promise<void>;
  confirmar(orderId: string, valor: number, origem: string): Promise<string>;
  pendentesMbway(): Promise<{ id: string; order_id: string; request_id: string; valor: number; chave: string }[]>;
  lerPedido(cliente: string, id: string): Promise<(Pedido & { chave?: string }) | null>;
  api: Ifthenpay;
}

const publico = (p: Pedido) => ({ id: p.id, metodo: p.metodo, valor: Number(p.valor), estado: p.estado, entidade: p.entidade ?? null,
  referencia: p.referencia ?? null, expira_em: p.expira_em ?? null });

async function verificarMbway(d: DepsPag, p: { id: string; order_id: string; request_id: string; valor: number; chave: string }) {
  const r = await d.api.estadoMbway({ chave: p.chave, requestId: p.request_id });
  const novo = estadoPedidoMbway(r.estado);
  if (novo === 'pago') return d.confirmar(p.order_id, Number(p.valor), 'verificacao');
  if (novo) await d.atualizar(p.id, novo, { mensagem: r.mensagem });
  return novo ?? 'pendente';
}

export async function tratar(req: Request, d: DepsPag): Promise<Response> {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  try {
    const corpo = await lerJson(req, 4_000);
    if (!corpo.ok) return corpo.resp;
    const c = (corpo.valor ?? {}) as Record<string, unknown>;

    if (c.acao === 'verificar') {
      if (!(await d.agendado(req))) return erro(401, 'nao_autorizado', 'Não autorizado.');
      const lista = await d.pendentesMbway();
      let pagos = 0;
      for (const p of lista) if ((await verificarMbway(d, p).catch(() => 'erro')) === 'pago') pagos++;
      return resposta(200, { ok: true, verificados: lista.length, pagos });
    }

    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    const user = jwt ? await d.autenticar(jwt) : null;
    if (!user) return erro(401, 'sessao', 'Inicie sessão para pagar.');
    if (!(await d.limite('pag:' + user, 20, 10))) return erro(429, 'limite', 'Demasiados pedidos. Aguarde alguns minutos.');

    if (c.acao === 'estado') {
      const id = String(c.pedido ?? '');
      if (!/^[0-9a-f-]{36}$/.test(id)) return erro(400, 'dados_invalidos', 'Pedido inválido.');
      const p = await d.lerPedido(user, id);
      if (!p) return erro(404, 'nao_encontrado', 'Pedido não encontrado.');
      if (p.metodo === 'mbway' && p.estado === 'pendente' && p.request_id && p.chave) {
        p.estado = await verificarMbway(d, { id: p.id, order_id: p.order_id, request_id: p.request_id, valor: Number(p.valor), chave: p.chave });
        if (p.estado === 'ja_pago') p.estado = 'pago';
      }
      return resposta(200, { ok: true, pedido: publico(p) });
    }

    if (c.acao !== 'pedir') return erro(400, 'acao', 'Ação desconhecida.');
    const encomenda = String(c.encomenda ?? '').trim(), metodo = String(c.metodo ?? ''), tel = String(c.telemovel ?? '').replace(/\D/g, '').replace(/^351/, '');
    if (!/^[A-Za-z0-9-]{3,40}$/.test(encomenda) || !['multibanco', 'mbway'].includes(metodo)) return erro(400, 'dados_invalidos', 'Dados do pagamento inválidos.');
    if (metodo === 'mbway' && !/^9[1236]\d{7}$/.test(tel)) return erro(400, 'telemovel', 'Indique um telemóvel português válido (9 dígitos).');
    const prep = await d.preparar(user, encomenda, metodo, metodo === 'mbway' ? tel : '');
    if ('erro' in prep) return erro(409, 'negocio', prep.erro);
    const p = prep.pedido;
    if (prep.reutilizar) return resposta(200, { ok: true, pedido: publico(p) });
    const base = { chave: prep.chave ?? '', orderId: p.order_id, valor: Number(p.valor), descricao: prep.descricao ?? 'Elolog' };
    if (metodo === 'multibanco') {
      const r = await d.api.multibanco({ ...base, sandbox: !!prep.sandbox, dias: 3 });
      if (!r.ok) { await d.atualizar(p.id, 'erro', { mensagem: r.mensagem }); return erro(502, 'ifthenpay', 'Não foi possível gerar a referência Multibanco. Tente mais tarde.'); }
      await d.atualizar(p.id, null, { request_id: r.requestId, entidade: r.entidade, referencia: r.referencia, expira_em: r.expira });
      return resposta(200, { ok: true, pedido: publico({ ...p, entidade: r.entidade, referencia: r.referencia, expira_em: r.expira }) });
    }
    const r = await d.api.mbway({ ...base, telemovel: tel });
    if (!r.ok) { await d.atualizar(p.id, 'erro', { mensagem: r.mensagem }); return erro(502, 'ifthenpay', 'O pedido MB WAY não foi aceite. Confirme o número e tente de novo.'); }
    await d.atualizar(p.id, null, { request_id: r.requestId, mensagem: 'A aguardar confirmação na app MB WAY' });
    return resposta(200, { ok: true, pedido: publico(p), mensagem: 'Confirme o pagamento na app MB WAY nos próximos 4 minutos.' });
  } catch (e) {
    console.error('pagamentos: erro interno', e instanceof Error ? e.message : e);
    return erro(500, 'interno', 'Erro interno. Tente mais tarde.');
  }
}
