// Cliente da API ifthenpay (Multibanco com referência dinâmica e MB WAY). Só corre no servidor.
// Endereços por omissão conforme a documentação da ifthenpay; podem ser trocados por variáveis de ambiente
// (IFTHENPAY_MB_URL, IFTHENPAY_MB_SANDBOX_URL, IFTHENPAY_MBWAY_URL, IFTHENPAY_MBWAY_ESTADO_URL) se a ifthenpay os mudar.

export interface RespMb { ok: boolean; entidade?: string; referencia?: string; expira?: string | null; requestId?: string; mensagem: string }
export interface RespMbway { ok: boolean; requestId?: string; estado: string; mensagem: string }
export interface Ifthenpay {
  multibanco(a: { chave: string; orderId: string; valor: number; descricao: string; sandbox: boolean; dias: number }): Promise<RespMb>;
  mbway(a: { chave: string; orderId: string; valor: number; telemovel: string; descricao: string }): Promise<RespMbway>;
  estadoMbway(a: { chave: string; requestId: string }): Promise<RespMbway>;
}

type Env = (k: string) => string | undefined;
type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

/** «dd-mm-aaaa» ou «aaaa-mm-dd» → ISO; null se não vier data. */
export function dataIso(v: unknown): string | null {
  const s = String(v ?? '').trim();
  let m = s.match(/^(\d{2})-(\d{2})-(\d{4})/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}T23:59:59Z`;
  m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? `${m[1]}-${m[2]}-${m[3]}T23:59:59Z` : null;
}

export function criarIfthenpay(env: Env, f: Fetch = fetch): Ifthenpay {
  const url = (k: string, omissao: string) => env(k) || omissao;
  const pedir = async (u: string, init?: RequestInit) => {
    const r = await f(u, { ...init, signal: AbortSignal.timeout(15_000) });
    const texto = await r.text();
    try { return { status: r.status, json: JSON.parse(texto) as Record<string, unknown> }; } catch { return { status: r.status, json: {} as Record<string, unknown> }; }
  };
  const post = (u: string, corpo: unknown) => pedir(u, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) });
  return {
    async multibanco(a) {
      const u = a.sandbox ? url('IFTHENPAY_MB_SANDBOX_URL', 'https://api.ifthenpay.com/multibanco/reference/sandbox')
                          : url('IFTHENPAY_MB_URL', 'https://api.ifthenpay.com/multibanco/reference/init');
      const { json } = await post(u, { mbKey: a.chave, orderId: a.orderId, amount: a.valor.toFixed(2), description: a.descricao.slice(0, 200), expiryDays: a.dias });
      const ok = String(json.Status ?? '') === '0' && !!json.Reference;
      return { ok, entidade: String(json.Entity ?? ''), referencia: String(json.Reference ?? ''), expira: dataIso(json.ExpiryDate),
        requestId: String(json.RequestId ?? ''), mensagem: String(json.Message ?? (ok ? 'Referência criada' : 'Sem resposta da ifthenpay')) };
    },
    async mbway(a) {
      const { json } = await post(url('IFTHENPAY_MBWAY_URL', 'https://api.ifthenpay.com/spg/payment/mbway'),
        { mbWayKey: a.chave, orderId: a.orderId, amount: a.valor.toFixed(2), mobileNumber: '351#' + a.telemovel, description: a.descricao.slice(0, 100) });
      const estado = String(json.Status ?? '');
      return { ok: estado === '000', requestId: String(json.RequestId ?? ''), estado, mensagem: String(json.Message ?? '') };
    },
    async estadoMbway(a) {
      const base = url('IFTHENPAY_MBWAY_ESTADO_URL', 'https://api.ifthenpay.com/spg/payment/mbway/status');
      const { json } = await pedir(`${base}?mbWayKey=${encodeURIComponent(a.chave)}&requestId=${encodeURIComponent(a.requestId)}`);
      const estado = String(json.Status ?? '');
      return { ok: estado === '000', requestId: a.requestId, estado, mensagem: String(json.Message ?? '') };
    },
  };
}

/** Estado MB WAY da ifthenpay → estado do pedido na Elolog (null = continua à espera). */
export function estadoPedidoMbway(codigo: string): 'pago' | 'recusado' | 'expirado' | null {
  if (codigo === '000') return 'pago';
  if (codigo === '020' || codigo === '122') return 'recusado';
  if (codigo === '101') return 'expirado';
  return null;
}
