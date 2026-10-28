// Ligações IMAP/SMTP com TLS e prazo máximo, pastas especiais e leitura de uma mensagem completa.
import { ErroImap, Imap, type Ligacao } from './imap.ts';
import { enviarSmtp } from './smtp.ts';
import { analisar } from './mime.ts';

export type Cred = { elolog: boolean; gerir?: boolean; restrito?: boolean; email: string; nome: string; imap_host: string; imap_porta: number; smtp_host: string; smtp_porta: number; utilizador: string; senha: string };
export const HOST = /^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/;

export async function abrir(host: string, porta: number): Promise<Ligacao> {
  if (!HOST.test(host) || ![993, 465].includes(porta)) throw new ErroImap('Servidor de email inválido.', 'servidor');
  let c: Deno.TlsConn;
  try { c = await Deno.connectTls({ hostname: host, port: porta }); } catch { throw new ErroImap(`Não foi possível ligar a ${host}:${porta}. Confirme o nome do servidor.`, 'servidor'); }
  const b = new Uint8Array(65536);
  return { ler: async () => { const n = await c.read(b); return n === null ? null : b.slice(0, n); },
    escrever: async (d) => { let o = 0; while (o < d.length) o += await c.write(d.subarray(o)); },
    fechar: () => { try { c.close(); } catch { /* já fechada */ } } };
}
export async function comPrazo<T>(l: Ligacao, p: Promise<T>, ms = 25_000): Promise<T> {
  let t = 0;
  try { return await Promise.race([p, new Promise<never>((_, r) => { t = setTimeout(() => { l.fechar(); r(new ErroImap('O servidor de email não respondeu a tempo.', 'tempo')); }, ms); })]); }
  finally { clearTimeout(t); l.fechar(); }
}
export async function comImap<T>(c: Cred, fn: (i: Imap) => Promise<T>): Promise<T> {
  const l = await abrir(c.imap_host, c.imap_porta), i = new Imap(l);
  return comPrazo(l, (async () => { await i.saudacao(); await i.entrar(c.utilizador, c.senha); const r = await fn(i); await i.sair(); return r; })());
}
export async function smtp(c: Cred, para: string[], mensagem: string) {
  const l = await abrir(c.smtp_host, c.smtp_porta);
  await comPrazo(l, enviarSmtp(l, { utilizador: c.utilizador, senha: c.senha, de: c.email, para, mensagem, ehlo: c.email.split('@')[1] }));
}
export async function pasta(i: Imap, qual: string): Promise<string> {
  if (qual === 'entrada') return 'INBOX';
  const ps = await i.pastas(), flag = qual === 'enviados' ? '\\SENT' : '\\TRASH';
  const re = qual === 'enviados' ? /(^|[./])(sent|enviad|itens enviados)/i : /(^|[./])(trash|lixo|deleted|eliminad|reciclagem)/i;
  const p = ps.find((x) => x.flags.some((f) => f.toUpperCase() === flag)) ?? ps.find((x) => re.test(x.nome));
  if (!p) throw new ErroImap(qual === 'enviados' ? 'Não encontrei a pasta de enviados.' : 'Não encontrei a pasta do lixo.', 'pasta');
  return p.nome;
}
export async function mensagem(i: Imap, uid: number) {
  const [m] = await i.buscar([uid], 'UID RFC822.SIZE');
  if (!m) throw new ErroImap('A mensagem já não existe.', 'pasta');
  if (Number(m['RFC822.SIZE'] ?? 0) > 12 * 1024 * 1024) throw new ErroImap('Mensagem demasiado grande para abrir aqui (mais de 12 MB). Abra-a no webmail.', 'pasta');
  const [c] = await i.buscar([uid], 'UID BODY.PEEK[]');
  return analisar(c?.CORPO instanceof Uint8Array ? c.CORPO : new Uint8Array(0));
}
