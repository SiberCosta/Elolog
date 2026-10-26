// Segredo das tarefas agendadas: vem de CRON_SECRET (se definido) ou do cofre da base de dados (servico_segredo_cron).
// Fica em memória 10 minutos para não ler o cofre a cada pedido.
import { igualConstante } from './comparar.ts';

type Rpc = { rpc: (nome: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }> };
let guardado = '', lidoEm = 0;

export async function segredoCron(admin: Rpc): Promise<string> {
  const env = (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get('CRON_SECRET') ?? '';
  if (env) return env;
  if (guardado && Date.now() - lidoEm < 600_000) return guardado;
  const { data, error } = await admin.rpc('servico_segredo_cron');
  if (error || typeof data !== 'string') return '';
  guardado = data; lidoEm = Date.now();
  return guardado;
}

/** true se o pedido traz o cabeçalho x-cron-secret certo. */
export async function pedidoAgendado(req: Request, admin: Rpc): Promise<boolean> {
  const esperado = await segredoCron(admin);
  const recebido = req.headers.get('x-cron-secret') ?? '';
  return !!esperado && !!recebido && (await igualConstante(recebido, esperado));
}
