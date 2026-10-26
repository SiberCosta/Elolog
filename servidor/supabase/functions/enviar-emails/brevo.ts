// Envio através da API transacional do Brevo (https://developers.brevo.com). Só usa fetch: testável com um fetch falso.
// Classificação do resultado:
//   ok            → enviado (201 com messageId)
//   repetir       → falha temporária (rede, tempo esgotado, 5xx): tenta mais tarde
//   limite        → o fornecedor pediu para abrandar (429): parar este lote
//   configuracao  → chave recusada (401/403) ou remetente não validado: parar e NÃO gastar tentativas dos e-mails
//   falhou        → pedido recusado de forma definitiva (ex.: endereço inválido)
// Os formatos exatos dos erros do Brevo não foram confirmados contra a API real: o texto é só informativo.
import type { EmailPronto } from '../_shared/emails.ts';

export type ResultadoEnvio =
  | { tipo: 'ok'; id: string }
  | { tipo: 'repetir' | 'limite' | 'configuracao' | 'falhou'; erro: string };

export interface ConfigBrevo { chave: string; remetenteEmail: string; remetenteNome: string }
export type Enviar = (para: string, email: EmailPronto, etiqueta: string) => Promise<ResultadoEnvio>;

const URL_API = 'https://api.brevo.com/v3/smtp/email';

export function criarBrevo(cfg: ConfigBrevo, fetchFn: typeof fetch = fetch, timeoutMs = 10_000): Enviar {
  return async (para, email, etiqueta) => {
    const controlo = new AbortController();
    const relogio = setTimeout(() => controlo.abort(), timeoutMs);
    try {
      const resp = await fetchFn(URL_API, {
        method: 'POST',
        headers: { 'api-key': cfg.chave, 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({
          sender: { name: cfg.remetenteNome, email: cfg.remetenteEmail },
          to: [{ email: para }],
          subject: email.assunto, htmlContent: email.html, textContent: email.texto,
          tags: ['elolog', etiqueta.slice(0, 40)],
        }),
        signal: controlo.signal,
      });
      if (resp.status === 201 || resp.status === 200) {
        const j = await resp.json().catch(() => ({}));
        return { tipo: 'ok', id: String((j as { messageId?: unknown }).messageId ?? '') };
      }
      const detalhe = await resumoErro(resp, cfg.chave);
      if (resp.status === 429) return { tipo: 'limite', erro: `HTTP 429 ${detalhe}` };
      if (resp.status === 401 || resp.status === 403) return { tipo: 'configuracao', erro: `HTTP ${resp.status} ${detalhe}` };
      if (resp.status >= 500 || resp.status === 408) return { tipo: 'repetir', erro: `HTTP ${resp.status} ${detalhe}` };
      // 400: um remetente não validado é problema de configuração (não do destinatário): não se perdem os e-mails
      if (/sender/i.test(detalhe)) return { tipo: 'configuracao', erro: `HTTP ${resp.status} ${detalhe}` };
      return { tipo: 'falhou', erro: `HTTP ${resp.status} ${detalhe}` };
    } catch (e) {
      const abortou = e instanceof Error && e.name === 'AbortError';
      return { tipo: 'repetir', erro: abortou ? 'Tempo esgotado a contactar o Brevo.' : 'Falha de rede a contactar o Brevo.' };
    } finally {
      clearTimeout(relogio);
    }
  };
}

// Resumo curto da resposta de erro. A chave API é ocultada, caso o fornecedor a repita na mensagem.
async function resumoErro(resp: Response, chave: string): Promise<string> {
  try {
    const j = (await resp.json()) as { code?: unknown; message?: unknown };
    const texto = [j.code, j.message].filter(x => typeof x === 'string').join(': ').slice(0, 200);
    return chave ? texto.split(chave).join('***') : texto;
  } catch { return ''; }
}
