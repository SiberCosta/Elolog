/** Compara dois textos sem revelar, pelo tempo, em que posição diferem. */
export async function igualConstante(a: string, b: string): Promise<boolean> {
  const h = async (v: string) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(v)));
  const [x, y] = await Promise.all([h(a), h(b)]);
  let dif = 0;
  for (let i = 0; i < x.length; i++) dif |= x[i] ^ y[i];
  return dif === 0;
}
