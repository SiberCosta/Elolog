// Validação do aviso da ifthenpay (separada para ser testada sem Deno).
export const texto = (estado: number, corpo: string) => new Response(corpo, { status: estado, headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' } });

export async function avisar(url: URL, confirmar: (o: string, k: string, v: number) => Promise<string>): Promise<Response> {
  const q = url.searchParams;
  const orderId = (q.get('orderId') ?? q.get('orderid') ?? '').trim(), chave = q.get('key') ?? q.get('chave') ?? '';
  const valor = Number(String(q.get('amount') ?? q.get('valor') ?? '').replace(',', '.'));
  if (!/^[A-Z0-9]{3,15}$/i.test(orderId) || !chave || !Number.isFinite(valor) || valor <= 0) return texto(400, 'dados invalidos');
  const r = await confirmar(orderId, chave, valor);
  if (r === 'pago' || r === 'ja_pago') return texto(200, 'ok');
  if (r === 'chave_invalida') return texto(403, 'chave invalida');
  return texto(400, r);
}

