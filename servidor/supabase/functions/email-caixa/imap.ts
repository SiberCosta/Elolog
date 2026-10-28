// Cliente IMAP mínimo (RFC 3501) sobre uma ligação TLS já aberta. Sem dependências; testado em Node com um servidor simulado.
export interface Ligacao { ler(): Promise<Uint8Array | null>; escrever(d: Uint8Array): Promise<void>; fechar(): void }
export type No = string | Uint8Array | null | No[];
export class ErroImap extends Error { constructor(m: string, public codigo = 'imap') { super(m); } }

const LIMITE = 30 * 1024 * 1024;
const asc = (s: string) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 255);
const str = (b: Uint8Array) => new TextDecoder().decode(b);
/** Texto IMAP entre aspas (só ASCII imprimível; os outros vão em literal). */
export const aspas = (s: string) => '"' + s.replace(/[\\"]/g, '\\$&') + '"';

/** Analisa uma resposta (com literais embutidos) em átomos, textos, literais (bytes), NIL e listas. */
export function analisar(b: Uint8Array): No[] {
  let i = 0;
  const lista = (fim: number): No[] => {
    const r: No[] = [];
    while (i < b.length) {
      const c = b[i];
      if (c === 32 || c === 13 || c === 10) { i++; continue; }
      if (c === fim) { i++; return r; }
      if (c === 40) { i++; r.push(lista(41)); continue; }
      if (c === 34) { let s = ''; i++; while (i < b.length && b[i] !== 34) { if (b[i] === 92) i++; s += String.fromCharCode(b[i++]); } i++; r.push(str(asc(s))); continue; }
      if (c === 123) { const f = b.indexOf(125, i); const n = parseInt(str(b.subarray(i + 1, f)), 10); i = f + 1;
        if (b[i] === 13) i++; if (b[i] === 10) i++; r.push(b.slice(i, i + n)); i += n; continue; }
      let s = '', prof = 0;
      while (i < b.length) { const x = b[i]; if (x === 91) prof++; if (x === 93) prof--;
        if (prof <= 0 && (x === 32 || x === 40 || x === 41 || x === 13 || x === 10)) break; s += String.fromCharCode(x); i++; }
      r.push(s.toUpperCase() === 'NIL' ? null : s);
    }
    return r;
  };
  return lista(-1);
}

export class Imap {
  private mem = new Uint8Array(65536); private tam = 0; private n = 0; private lidos = 0;
  private get buf() { return this.mem.subarray(0, this.tam); }
  private consumir(k: number) { this.mem.copyWithin(0, k, this.tam); this.tam -= k; }
  constructor(private l: Ligacao) {}

  private async encher() {
    const d = await this.l.ler(); if (!d) throw new ErroImap('O servidor de email fechou a ligação.');
    this.lidos += d.length; if (this.lidos > LIMITE) throw new ErroImap('Resposta demasiado grande.');
    if (this.tam + d.length > this.mem.length) { const nb = new Uint8Array(Math.max(this.mem.length * 2, this.tam + d.length)); nb.set(this.buf); this.mem = nb; }
    this.mem.set(d, this.tam); this.tam += d.length;
  }
  /** Uma linha lógica (com os literais {n} incluídos), sem o CRLF final. */
  private async linha(): Promise<Uint8Array> {
    let p = 0;
    for (;;) {
      let f = this.buf.indexOf(10, p);
      while (f < 0) { await this.encher(); f = this.buf.indexOf(10, p); }
      const m = str(this.buf.subarray(p, f)).match(/\{(\d+)\+?\}\r?$/);
      if (!m) { const r = this.buf.slice(0, f > 0 && this.buf[f - 1] === 13 ? f - 1 : f); this.consumir(f + 1); return r; }
      const fimLit = f + 1 + Number(m[1]);
      while (this.buf.length < fimLit) await this.encher();
      p = fimLit;
    }
  }
  async saudacao() { const l = str(await this.linha()); if (!/^\* (OK|PREAUTH)/i.test(l)) throw new ErroImap('Servidor IMAP indisponível.'); }

  /** Envia um comando (literais em `lit` substituem os marcadores {L}) e devolve as linhas não marcadas. */
  async comando(cmd: string, lit: Uint8Array[] = []): Promise<No[][]> {
    const tag = 'E' + (++this.n), partes = cmd.split('{L}'), r: No[][] = [];
    await this.l.escrever(asc(tag + ' ' + partes[0] + (lit.length ? `{${lit[0].length}}` : '') + '\r\n'));
    let k = 0;
    for (;;) {
      const b = await this.linha(), t = str(b.subarray(0, 200));
      if (t.startsWith('+') && k < lit.length) {
        const resto = partes[k + 1] + (k + 1 < lit.length ? `{${lit[k + 1].length}}` : '');
        const env = new Uint8Array(lit[k].length + resto.length + 2); env.set(lit[k]); env.set(asc(resto + '\r\n'), lit[k].length);
        await this.l.escrever(env); k++; continue;
      }
      if (t.startsWith(tag + ' ')) {
        if (/^\S+ OK/i.test(t)) return r;
        const msg = t.replace(/^\S+ \S+ (\[[^\]]*\] )?/, '');
        throw new ErroImap(msg || 'Comando recusado.', cmd.startsWith('LOGIN') ? 'login' : 'imap');
      }
      if (t.startsWith('*')) r.push(analisar(b).slice(1));
    }
  }

  async entrar(u: string, s: string) {
    if (/[\x00-\x1f\x7f]/.test(u + s)) throw new ErroImap('Utilizador ou palavra-passe inválidos.', 'login');
    const ascii = /^[\x20-\x7e]*$/.test(s);
    await this.comando(`LOGIN ${aspas(u)} ` + (ascii ? aspas(s) : '{L}'), ascii ? [] : [new TextEncoder().encode(s)]);
  }
  /** Pastas com atributos especiais (\Sent, \Trash...). */
  async pastas(): Promise<{ nome: string; flags: string[] }[]> {
    return (await this.comando('LIST "" "*"')).filter((x) => String(x[0]).toUpperCase() === 'LIST')
      .map((x) => ({ flags: ((x[1] as string[]) ?? []).map(String), nome: x[3] instanceof Uint8Array ? str(x[3]) : String(x[3] ?? '') }));
  }
  async selecionar(p: string, so = false): Promise<number> {
    const r = await this.comando(`${so ? 'EXAMINE' : 'SELECT'} ${aspas(p)}`);
    return Number(r.find((x) => String(x[1]).toUpperCase() === 'EXISTS')?.[0] ?? 0);
  }
  async pesquisar(texto = ''): Promise<number[]> {
    const r = texto ? await this.comando('UID SEARCH CHARSET UTF-8 TEXT {L}', [new TextEncoder().encode(texto)]) : await this.comando('UID SEARCH ALL');
    return r.filter((x) => String(x[0]).toUpperCase() === 'SEARCH').flatMap((x) => x.slice(1).map(Number)).filter((n) => n > 0);
  }
  /** FETCH por UIDs → [{UID, FLAGS, ..., corpo}] com as chaves em maiúsculas. */
  async buscar(uids: number[], itens: string): Promise<Record<string, No>[]> {
    if (!uids.length) return [];
    const r = await this.comando(`UID FETCH ${uids.join(',')} (${itens})`);
    return r.filter((x) => String(x[1]).toUpperCase() === 'FETCH' && Array.isArray(x[2])).map((x) => {
      const l = x[2] as No[], o: Record<string, No> = {};
      for (let i = 0; i + 1 < l.length; i += 2) o[String(l[i]).toUpperCase().replace(/^BODY\[.*$/, 'CORPO')] = l[i + 1];
      return o;
    });
  }
  /** Número de mensagens por ler numa pasta (STATUS ... (UNSEEN)). */
  async naoLidas(p = 'INBOX'): Promise<number> {
    const x = (await this.comando(`STATUS ${aspas(p)} (UNSEEN)`)).find((l) => String(l[0]).toUpperCase() === 'STATUS');
    const l = (x?.[2] ?? []) as No[], i = l.findIndex((v) => String(v).toUpperCase() === 'UNSEEN');
    return i >= 0 ? Number(l[i + 1]) || 0 : 0;
  }
  marcar(uid: number, flag: string, por: boolean) { return this.comando(`UID STORE ${uid} ${por ? '+' : '-'}FLAGS.SILENT (${flag})`); }
  async mover(uid: number, para: string) {
    try { await this.comando(`UID MOVE ${uid} ${aspas(para)}`); }
    catch { await this.comando(`UID COPY ${uid} ${aspas(para)}`); await this.marcar(uid, '\\Deleted', true); await this.comando('EXPUNGE'); }
  }
  acrescentar(pasta: string, msg: Uint8Array) { return this.comando(`APPEND ${aspas(pasta)} (\\Seen) {L}`, [msg]); }
  async sair() { try { await this.comando('LOGOUT'); } catch { /* ignorar */ } this.l.fechar(); }
}
