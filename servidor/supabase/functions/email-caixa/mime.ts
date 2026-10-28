// Leitura e escrita de mensagens de email (MIME, RFC 2045–2047, 2231). Sem dependências; testado em Node.
export interface Anexo { nome: string; tipo: string; tamanho: number; dados: Uint8Array }
export interface Mensagem { cabecalhos: Record<string, string>; texto: string; html: string; anexos: Anexo[] }

const lat = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192)); return s; };
export const bytes = (s: string) => { const r = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) r[i] = s.charCodeAt(i); return r; };
function texto(b: Uint8Array, charset = 'utf-8'): string {
  try { return new TextDecoder(charset.toLowerCase().replace(/^(ascii|us-ascii)$/, 'utf-8'), { fatal: false }).decode(b); }
  catch { return new TextDecoder('windows-1252').decode(b); }
}
const b64 = (s: string) => { const l = s.replace(/[^A-Za-z0-9+/]+/g, ''); try { return bytes(atob(l.slice(0, l.length - (l.length % 4 === 1 ? 1 : 0)).padEnd(Math.ceil(l.length / 4) * 4, '='))); } catch { return new Uint8Array(0); } };
const qp = (s: string, cab = false) => bytes((cab ? s.replace(/_/g, ' ') : s.replace(/=\r?\n/g, '')).replace(/=([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16))));

/** Descodifica palavras codificadas (=?utf-8?B?...?=) e cabeçalhos com bytes de 8 bits. */
export function palavras(s: string): string {
  let cru = s;
  if (/[\x80-\xff]/.test(s)) { try { cru = new TextDecoder('utf-8', { fatal: true }).decode(bytes(s)); } catch { cru = texto(bytes(s), 'windows-1252'); } }
  return cru.replace(/\?=\s+=\?/g, '?==?').replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g, (_, cs, mod, v) =>
    texto(mod.toUpperCase() === 'B' ? b64(v) : qp(v, true), cs.split('*')[0]));
}

/** Separa cabeçalhos (nomes em minúsculas, linhas dobradas unidas) do corpo. */
export function separar(b: Uint8Array): { cab: Record<string, string>; corpo: Uint8Array } {
  let fim = -1, salto = 0;
  for (let i = b.indexOf(10); i >= 0 && fim < 0; i = b.indexOf(10, i + 1)) {
    if (b[i + 1] === 10) { fim = i; salto = 2; } else if (b[i + 1] === 13 && b[i + 2] === 10) { fim = i; salto = 3; }
  }
  if (fim < 0) fim = b.length; else if (fim > 0 && b[fim - 1] === 13) { fim--; salto++; }
  const s = lat(b.subarray(0, fim));
  const cab: Record<string, string> = {};
  for (const l of s.slice(0, fim).replace(/\r?\n[ \t]+/g, ' ').split(/\r?\n/)) {
    const i = l.indexOf(':'); if (i < 1) continue;
    const k = l.slice(0, i).trim().toLowerCase(); if (!(k in cab)) cab[k] = l.slice(i + 1).trim();
  }
  return { cab, corpo: b.subarray(Math.min(b.length, fim + salto)) };
}

/** Valor principal e parâmetros de Content-Type / Content-Disposition (inclui nome*=utf-8''...). */
export function parametros(v = ''): { valor: string; p: Record<string, string> } {
  const partes = v.match(/(?:[^;"]+|"(?:\\.|[^"])*")+/g) ?? [''];
  const p: Record<string, string> = {};
  for (const x of partes.slice(1)) {
    const m = x.trim().match(/^([^=*]+)(\*\d*\*?)?=\s*"?((?:\\.|[^"])*)"?$/); if (!m) continue;
    const k = m[1].trim().toLowerCase(); let val = m[3].replace(/\\(.)/g, '$1');
    if (m[2]?.endsWith('*')) { const e = val.match(/^([^']*)'[^']*'(.*)$/); const pc = (v: string) => bytes(v.replace(/%([0-9a-f]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)))); val = e ? texto(pc(e[2]), e[1] || 'utf-8') : texto(pc(val)); } else val = palavras(val);
    p[k] = (p[k] && m[2] ? p[k] : '') + val;
  }
  return { valor: partes[0].trim().toLowerCase(), p };
}

function conteudo(corpo: Uint8Array, cte = ''): Uint8Array {
  const t = cte.toLowerCase().trim();
  return t === 'base64' ? b64(lat(corpo)) : t === 'quoted-printable' ? qp(lat(corpo)) : corpo;
}

/** Analisa uma mensagem completa: texto, HTML e anexos (até 20 níveis de partes). */
export function analisar(b: Uint8Array): Mensagem {
  const m: Mensagem = { cabecalhos: {}, texto: '', html: '', anexos: [] };
  const raiz = separar(b);
  for (const k of ['from', 'to', 'cc', 'reply-to', 'subject', 'date', 'message-id', 'references', 'in-reply-to']) if (raiz.cab[k]) m.cabecalhos[k] = palavras(raiz.cab[k]);
  const parte = (cab: Record<string, string>, corpo: Uint8Array, nivel: number) => {
    const ct = parametros(cab['content-type'] || 'text/plain'), cd = parametros(cab['content-disposition']);
    if (ct.valor.startsWith('multipart/') && ct.p.boundary && nivel < 20) {
      const s = lat(corpo), lim = '--' + ct.p.boundary; let i = s.indexOf(lim);
      while (i >= 0) {
        const ini = s.indexOf('\n', i) + 1; if (ini <= 0 || s.startsWith(lim + '--', i)) break;
        let fim = s.indexOf('\n' + lim, ini); if (fim < 0) fim = s.length;
        const sub = separar(corpo.subarray(ini, fim > 0 && s[fim - 1] === '\r' ? fim - 1 : fim));
        parte(sub.cab, sub.corpo, nivel + 1); i = fim < s.length ? fim + 1 : -1;
      }
      return;
    }
    const dados = conteudo(corpo, cab['content-transfer-encoding']);
    const nome = cd.p.filename || ct.p.name || '';
    const anexo = cd.valor === 'attachment' || (!!nome && !ct.valor.startsWith('text/')) || !/^text\/(plain|html)$/.test(ct.valor);
    if (!anexo && ct.valor === 'text/plain' && !m.texto) m.texto = texto(dados, ct.p.charset || 'utf-8');
    else if (!anexo && ct.valor === 'text/html' && !m.html) m.html = texto(dados, ct.p.charset || 'utf-8');
    else m.anexos.push({ nome: nome || (ct.valor === 'message/rfc822' ? 'mensagem.eml' : 'anexo'), tipo: ct.valor, tamanho: dados.length, dados });
  };
  parte(raiz.cab, raiz.corpo, 0);
  return m;
}

/** Lista de endereços «Nome <email>, ...» → [{nome, email}]. */
export function enderecos(s = ''): { nome: string; email: string }[] {
  return (s.match(/(?:[^,;"<]+|"(?:\\.|[^"])*"|<[^>]*>)+/g) ?? []).map((x) => {
    const a = x.match(/<([^>]+)>/)?.[1], e = a ?? x.match(/[^\s<>";,]+@[^\s<>";,]+/)?.[0] ?? '';
    return { nome: a ? x.replace(/<[^>]*>/, '').replace(/"/g, '').trim() : '', email: e.trim().toLowerCase() };
  }).filter((x) => x.email.includes('@'));
}

const cod = (s: string) => /^[\x20-\x7e]*$/.test(s) ? s : '=?UTF-8?B?' + btoa(lat(new TextEncoder().encode(s))) + '?=';
const linha76 = (s: string) => s.replace(/.{1,76}/g, '$&\r\n');
const limpo = (s: string) => s.replace(/[\r\n]+/g, ' ').trim();

/** Constrói uma mensagem de texto UTF-8 (só ASCII no resultado). */
export function construir(o: { de: string; nome?: string; para: string[]; cc?: string[]; assunto: string; texto: string;
  emResposta?: string; referencias?: string; dominio: string; agora?: Date }): string {
  const id = `<${crypto.randomUUID()}@${o.dominio}>`;
  const de = o.nome ? `"${cod(limpo(o.nome).replace(/"/g, ''))}" <${o.de}>` : `<${o.de}>`;
  const cab = [`From: ${de}`, `To: ${o.para.join(', ')}`, o.cc?.length ? `Cc: ${o.cc.join(', ')}` : '', `Subject: ${cod(limpo(o.assunto))}`,
    `Date: ${(o.agora ?? new Date()).toUTCString().replace('GMT', '+0000')}`, `Message-ID: ${id}`,
    o.emResposta ? `In-Reply-To: ${o.emResposta}` : '', o.emResposta ? `References: ${limpo(((o.referencias ?? '') + ' ' + o.emResposta).trim())}` : '',
    'MIME-Version: 1.0', 'Content-Type: text/plain; charset=utf-8', 'Content-Transfer-Encoding: base64', 'X-Mailer: Elolog'].filter(Boolean);
  return cab.join('\r\n') + '\r\n\r\n' + linha76(btoa(lat(new TextEncoder().encode(o.texto.replace(/\r?\n/g, '\r\n')))));
}
