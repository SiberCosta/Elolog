// Edge Function «validar-documento» (v123): validação pública dos documentos do Centro Documental pelo QR.
//   POST {c}  → página site/validar.html?c=… (qualquer pessoa com o código impresso no documento).
// Devolve só o que não é confidencial: tipo, número, versão, estado, data, referência da encomenda e empresa emissora (sem nomes, moradas,
// contactos nem valores). Limite: 60 pedidos por hora por IP. O código tem 96 bits aleatórios: não se adivinha.
// Deploy: supabase functions deploy validar-documento --no-verify-jwt
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { limitar, seguro } from '../_shared/seguranca.ts';

const env = (k: string) => Deno.env.get(k) ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const CODIGO = /^[0-9a-f]{24}$/;

Deno.serve(seguro('validar-documento', async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const lido = await lerJson(req, 500);
  if (!lido.ok) return lido.resp;
  const c = String(((lido.valor ?? {}) as Record<string, unknown>).c ?? '').trim().toLowerCase();
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'sem-ip';
  if (!(await limitar(admin, 'validar-doc:' + ip.slice(0, 60), 60, 60))) return erro(429, 'limite', 'Demasiadas validações seguidas. Tente daqui a pouco.');
  if (!CODIGO.test(c)) return resposta(200, { encontrado: false });
  const { data, error } = await admin.rpc('servico_validar_documento', { p_codigo: c });
  if (error) { console.error('validar-documento: falha', error.code); return erro(500, 'validar', 'Não conseguimos validar agora. Tente outra vez daqui a pouco.'); }
  return resposta(200, data ?? { encontrado: false });
}, { admin }));
