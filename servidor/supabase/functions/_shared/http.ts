// Utilitários HTTP partilhados pelas Edge Functions. Só usa APIs web padrão (Request/Response).

export const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

export function resposta(estado: number, corpo: unknown): Response {
  return new Response(JSON.stringify(corpo), {
    status: estado,
    headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

export function erro(estado: number, codigo: string, mensagem: string): Response {
  return resposta(estado, { ok: false, erro: { codigo, mensagem } });
}

export function preflight(): Response {
  return new Response(null, { status: 204, headers: CORS });
}

/** Lê o corpo JSON com limite de tamanho. Devolve a Response de erro já pronta se algo falhar. */
export async function lerJson(req: Request, maxBytes = 20_000): Promise<{ ok: true; valor: unknown } | { ok: false; resp: Response }> {
  const declarado = Number(req.headers.get('content-length') ?? '0');
  if (declarado > maxBytes) return { ok: false, resp: erro(413, 'corpo_grande', 'O pedido é demasiado grande.') };
  let texto = '';
  try {
    texto = await req.text();
  } catch {
    return { ok: false, resp: erro(400, 'corpo_invalido', 'Não foi possível ler o pedido.') };
  }
  if (texto.length > maxBytes) return { ok: false, resp: erro(413, 'corpo_grande', 'O pedido é demasiado grande.') };
  try {
    return { ok: true, valor: JSON.parse(texto) };
  } catch {
    return { ok: false, resp: erro(400, 'json_invalido', 'O pedido não é um JSON válido.') };
  }
}
