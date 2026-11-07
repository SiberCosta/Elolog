// Edge Function «verificar-ficheiro»: confirma pelo CONTEÚDO que um ficheiro enviado é do tipo declarado.
// Até ser verificado, só quem o enviou o vê (políticas da migração 00151). Se não passar, o ficheiro é apagado
// do armazenamento e a recusa fica na auditoria. Qualquer falha = ficheiro fica bloqueado (fail closed).
// Deploy: supabase functions deploy verificar-ficheiro --no-verify-jwt (o token é validado no código).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { limitar, registarBloqueio, seguro } from '../_shared/seguranca.ts';
import { verificarFicheiro } from '../_shared/ficheiros.ts';
const ehUuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } });

async function tratar(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return preflight();
  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: u, error: eu } = jwt ? await admin.auth.getUser(jwt) : { data: null, error: true };
  if (eu || !u?.user) return erro(401, 'sessao', 'Sessão inválida. Entre de novo.');
  const user = u.user.id;
  if (!(await limitar(admin, 'verif:' + user, 60, 10))) return erro(429, 'limite', 'Demasiados ficheiros seguidos. Aguarde alguns minutos.');

  const corpo = await lerJson(req, 2_000);
  if (!corpo.ok) return corpo.resp;
  const id = (corpo.valor as { documento_id?: unknown })?.documento_id;
  if (!ehUuid(id)) return erro(400, 'pedido', 'Pedido inválido.');

  const { data: doc, error: ed } = await admin.from('documentos')
    .select('id, storage_path, mime, tamanho_bytes, enviado_por, verificado').eq('id', id).maybeSingle();
  if (ed) throw ed;
  if (!doc || doc.enviado_por !== user) return erro(403, 'acesso', 'Sem autorização para este ficheiro.');
  if (doc.verificado) return resposta(200, { ok: true, verificado: true });

  const { data: blob, error: eb } = await admin.storage.from('documentos').download(doc.storage_path);
  if (eb || !blob) throw eb ?? new Error('ficheiro indisponível');
  const inicio = new Uint8Array(await blob.slice(0, 16).arrayBuffer());
  const motivo = blob.size !== Number(doc.tamanho_bytes) ? 'o tamanho não corresponde ao declarado'
    : verificarFicheiro(doc.storage_path, String(doc.mime ?? ''), blob.size, inicio);

  if (motivo) {
    await admin.storage.from('documentos').remove([doc.storage_path]);
    const { error } = await admin.rpc('servico_documento_verificado', { p_id: id, p_ok: false, p_motivo: motivo });
    if (error) throw error;
    await registarBloqueio(admin, 'verificar-ficheiro', 'ficheiro recusado: ' + motivo, user);
    return erro(422, 'ficheiro_recusado', 'O ficheiro foi recusado: ' + motivo + '.');
  }
  const { error } = await admin.rpc('servico_documento_verificado', { p_id: id, p_ok: true, p_motivo: 'conteúdo confere com ' + doc.mime });
  if (error) throw error;
  return resposta(200, { ok: true, verificado: true });
}

Deno.serve(seguro('verificar-ficheiro', tratar, { metodos: ['POST'], maxBytes: 2_000, admin }));
