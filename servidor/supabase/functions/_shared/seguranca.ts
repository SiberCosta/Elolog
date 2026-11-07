// Regras de segurança obrigatórias das Edge Functions (documentacao/REGRAS_SEGURANCA.md).
// Tudo falha em modo FECHADO: se uma verificação não puder ser feita, a operação não é executada.
import { erro } from './http.ts';

type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }> };
type Tratador = (req: Request) => Response | Promise<Response>;

/** Limite de pedidos. Só devolve true se o serviço de limites confirmar; erro ou resposta estranha = bloqueado. */
export async function limitar(admin: Rpc, chave: string, max: number, janelaMin: number): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc('servico_limite', { p_chave: chave, p_max: max, p_janela_min: janelaMin });
    return !error && data === true;
  } catch {
    return false;
  }
}

/** Regista um bloqueio de segurança na auditoria. Nunca lança erro (o bloqueio acontece na mesma). */
export async function registarBloqueio(admin: Rpc | null, funcao: string, motivo: string, user?: string | null): Promise<void> {
  if (!admin) return;
  try {
    await admin.rpc('servico_registar_bloqueio', { p_funcao: funcao, p_motivo: motivo.slice(0, 300), p_user: user ?? null });
  } catch { /* o registo é o melhor possível; o pedido já foi recusado */ }
}

/** Nível da sessão de um token JÁ validado (auth.getUser): 'aal2' com o código do telemóvel OU com o código de reserva
 *  usado nesta sessão (migração 00152). Qualquer falha = 'aal1' (fail closed). */
export async function nivelSessao(admin: Rpc, jwt: string): Promise<string> {
  try {
    const p = JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    if (p.aal === 'aal2') return 'aal2';
    if (typeof p.sub !== 'string' || typeof p.session_id !== 'string') return 'aal1';
    const { data, error } = await admin.rpc('servico_sessao_reforcada', { p_user: p.sub, p_session: p.session_id });
    return !error && data === true ? 'aal2' : 'aal1';
  } catch {
    return 'aal1';
  }
}

export interface OpcoesSeguro {
  /** Segredos obrigatórios. Se faltar algum, a função não executa nada (serviço indisponível). */
  segredos?: string[];
  /** Métodos aceites (OPTIONS é sempre aceite para o navegador). */
  metodos?: string[];
  /** Tamanho máximo do pedido em bytes (padrão 1 MB). */
  maxBytes?: number;
  admin?: Rpc | null;
}

/** Envolve o tratador de uma Edge Function com as verificações comuns e captura qualquer falha (fail closed). */
export function seguro(nome: string, tratador: Tratador, o: OpcoesSeguro = {}): Tratador {
  const maxBytes = o.maxBytes ?? 1_000_000;
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'OPTIONS') {
      if (o.metodos && !o.metodos.includes(req.method)) return erro(405, 'metodo', 'Método não permitido.');
      const faltam = (o.segredos ?? ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']).filter((k) => !(Deno.env.get(k) ?? '').trim());
      if (faltam.length) {
        console.error(`${nome}: segredos em falta (${faltam.join(', ')}) — operação bloqueada`);
        return erro(503, 'servico_indisponivel', 'Serviço temporariamente indisponível. Tente mais tarde.');
      }
      if (Number(req.headers.get('content-length') ?? '0') > maxBytes) {
        await registarBloqueio(o.admin ?? null, nome, 'pedido acima do tamanho máximo');
        return erro(413, 'corpo_grande', 'O pedido é demasiado grande.');
      }
    }
    try {
      const r = await tratador(req);
      if (r.status === 403 || r.status === 429) await registarBloqueio(o.admin ?? null, nome, `recusado (${r.status})`);
      return r;
    } catch (e) {
      console.error(`${nome}: falha — operação não executada`, e instanceof Error ? e.message : e);
      await registarBloqueio(o.admin ?? null, nome, 'falha interna: operação não executada');
      return erro(503, 'falha_seguranca', 'Não foi possível concluir a operação em segurança. Tente mais tarde.');
    }
  };
}

// ---------------------------------------------------------------- assistente ELO (respostas automáticas)
const CONTROLO = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁦-⁩]/g;

/** R1: nenhuma entrada chega ao assistente sem validação. Texto curto, sem caracteres de controlo nem invisíveis. */
export function entradaAssistente(v: unknown, max = 1000): { ok: true; texto: string } | { ok: false; motivo: string } {
  if (v === null || v === undefined) return { ok: true, texto: '' };
  if (typeof v !== 'string') return { ok: false, motivo: 'tipo' };
  const t = v.replace(CONTROLO, '').replace(/\s+/g, ' ').trim();
  if (t.length > max) return { ok: false, motivo: 'comprimento' };
  return { ok: true, texto: t };
}

/** R6: nenhuma resposta automática é confiável sem verificação. Só ligações para elolog.pt e tamanho limitado. */
export function saidaAssistente(t: string, alternativa: string): string {
  if (typeof t !== 'string' || !t.trim() || t.length > 4000) return alternativa;
  const links = t.match(/https?:\/\/[^\s)]+/gi) ?? [];
  if (links.some((l) => !/^https:\/\/(www\.)?elolog\.pt(\/|$)/i.test(l))) return alternativa;
  if (/<\s*\/?\s*(script|iframe|img|a)\b/i.test(t)) return alternativa;
  return t;
}
