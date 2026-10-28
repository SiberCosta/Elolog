// Código de confirmação (6 dígitos) para ligar uma caixa nova: HMAC do utilizador + email + janela de 10 minutos.
// Sem tabela: o servidor recalcula o código; vale na janela atual e na anterior (10 a 20 minutos).
const JANELA = 600_000;
async function gerar(chave: string, user: string, email: string, janela: number): Promise<string> {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(chave), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new DataView(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(`email-caixa|${user}|${email.toLowerCase()}|${janela}`)));
  return String(mac.getUint32(0) % 1_000_000).padStart(6, '0');
}
export const novoCodigo = (chave: string, user: string, email: string, agora = Date.now()) => gerar(chave, user, email, Math.floor(agora / JANELA));
export async function codigoValido(chave: string, user: string, email: string, codigo: string, agora = Date.now()): Promise<boolean> {
  if (!/^\d{6}$/.test(codigo)) return false;
  const j = Math.floor(agora / JANELA);
  for (const x of [j, j - 1]) if ((await gerar(chave, user, email, x)) === codigo) return true;
  return false;
}
