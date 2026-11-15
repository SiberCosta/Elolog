// Edge Function «copia-dados» (v140): entrega ao Worker do Cloudflare a cópia dos dados, já comprimida e CIFRADA.
//   POST com o cabeçalho x-copia-token (= segredo COPIA_TOKEN)  →  ficheiro binário «.elolog-copia»
// Formato: "ELOC1" (5 bytes) + sal (16) + iv (12) + AES-256-GCM( gzip( JSON de servico_exportar_dados() ) ).
// A chave vem do segredo COPIA_SENHA (PBKDF2-SHA-256, 210 000 iterações). Sem a senha, a cópia não se lê — nem no Cloudflare.
// Segredos: COPIA_TOKEN e COPIA_SENHA (16+ caracteres). Limite: 12 pedidos por hora.
// Deploy: supabase functions deploy copia-dados --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, preflight } from '../_shared/http.ts';
import { limitar, seguro } from '../_shared/seguranca.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const enc = new TextEncoder();

function igual(a: string, b: string): boolean {   // comparação em tempo constante
  const x = enc.encode(a), y = enc.encode(b); let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}
async function gzip(dados: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await new Response(new Blob([dados]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer());
}
async function cifrar(dados: Uint8Array, senha: string): Promise<Uint8Array> {
  const sal = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12));
  const base = await crypto.subtle.importKey('raw', enc.encode(senha), 'PBKDF2', false, ['deriveKey']);
  const chave = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt: sal, iterations: 210000, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
  const c = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, chave, dados));
  const out = new Uint8Array(5 + 16 + 12 + c.length); out.set(enc.encode('ELOC1'), 0); out.set(sal, 5); out.set(iv, 21); out.set(c, 33); return out;
}

Deno.serve(seguro('copia-dados', async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  const token = req.headers.get('x-copia-token') ?? '';
  if (!token || !igual(token, env('COPIA_TOKEN'))) return erro(403, 'token', 'Acesso recusado.');
  if (!(await limitar(admin, 'copia-dados', 12, 60))) return erro(429, 'limite', 'Demasiadas cópias seguidas.');
  if (env('COPIA_SENHA').length < 16) return erro(503, 'senha', 'Defina o segredo COPIA_SENHA com 16 ou mais caracteres.');
  const { data, error } = await admin.rpc('servico_exportar_dados');
  if (error) { console.error('copia-dados: exportação falhou', error.code); return erro(500, 'exportar', 'A exportação falhou.'); }
  const corpo = await cifrar(await gzip(enc.encode(JSON.stringify(data))), env('COPIA_SENHA'));
  return new Response(corpo, { status: 200, headers: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(corpo.length), 'Cache-Control': 'no-store',
    'X-Elolog-Registos': String((data as { registos?: number })?.registos ?? 0) } });
}, { admin, segredos: ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'COPIA_TOKEN', 'COPIA_SENHA'], metodos: ['POST'], maxBytes: 1000 }));
