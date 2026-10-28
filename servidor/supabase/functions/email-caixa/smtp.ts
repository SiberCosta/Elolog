// Envio SMTP mínimo (RFC 5321) sobre TLS direto (porta 465), com AUTH PLAIN/LOGIN. Testado em Node com um servidor simulado.
import type { Ligacao } from './imap.ts';
export class ErroSmtp extends Error { constructor(m: string, public codigo = 'smtp') { super(m); } }

const asc = (s: string) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 255);
const b64 = (s: string) => btoa(Array.from(new TextEncoder().encode(s), (c) => String.fromCharCode(c)).join(''));

export async function enviarSmtp(l: Ligacao, o: { utilizador: string; senha: string; de: string; para: string[]; mensagem: string; ehlo: string }) {
  let buf = '';
  const resposta = async (): Promise<{ c: number; t: string }> => {
    let t = '';
    for (;;) {
      let f = buf.indexOf('\n');
      while (f < 0) { const d = await l.ler(); if (!d) throw new ErroSmtp('O servidor de envio fechou a ligação.'); buf += String.fromCharCode(...d); f = buf.indexOf('\n'); }
      const linha = buf.slice(0, f).replace(/\r$/, ''); buf = buf.slice(f + 1); t += linha + '\n';
      if (/^\d{3} /.test(linha) || /^\d{3}$/.test(linha)) return { c: Number(linha.slice(0, 3)), t };
    }
  };
  const passo = async (cmd: string | null, ok: number[], erro: string, cod = 'smtp') => {
    if (cmd !== null) await l.escrever(asc(cmd + '\r\n'));
    const r = await resposta();
    if (!ok.includes(r.c)) throw new ErroSmtp(`${erro} (${r.t.trim().split('\n').pop()?.slice(0, 160)})`, cod);
    return r;
  };
  try {
    await passo(null, [220], 'Servidor de envio indisponível');
    const e = await passo(`EHLO ${o.ehlo}`, [250], 'O servidor de envio recusou a ligação');
    if (/AUTH[ =][^\n]*PLAIN/i.test(e.t)) await passo('AUTH PLAIN ' + b64(`\0${o.utilizador}\0${o.senha}`), [235], 'Utilizador ou palavra-passe de envio errados', 'login');
    else { await passo('AUTH LOGIN', [334], 'Autenticação não suportada'); await passo(b64(o.utilizador), [334], 'Utilizador recusado', 'login');
      await passo(b64(o.senha), [235], 'Utilizador ou palavra-passe de envio errados', 'login'); }
    if (!o.para.length) { await l.escrever(asc('QUIT\r\n')).catch(() => {}); return; }   // só testar a autenticação
    await passo(`MAIL FROM:<${o.de}>`, [250], 'Remetente recusado');
    for (const p of o.para) await passo(`RCPT TO:<${p}>`, [250, 251], `Destinatário ${p} recusado`);
    await passo('DATA', [354], 'Envio recusado');
    const corpo = o.mensagem.replace(/\r?\n/g, '\r\n').replace(/^\./gm, '..');
    await passo(corpo + (corpo.endsWith('\r\n') ? '' : '\r\n') + '.', [250], 'A mensagem não foi aceite');
    await l.escrever(asc('QUIT\r\n')).catch(() => {});
  } finally { l.fechar(); }
}
