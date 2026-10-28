// Edge Function «email-caixa»: painel de email da plataforma (ler e responder) por IMAP (993) e SMTP (465), ambos com TLS.
// Ações: caixas · gravar · remover · listar · ler · anexo · enviar · marcar · apagar.
// Acesso: administrador da plataforma (caixas da Elolog, com 2.º fator) e administrador do prestador (caixas da empresa).
// A palavra-passe da caixa fica no cofre da base de dados (servico_email_*) e nunca é devolvida ao navegador.
// Deploy: supabase functions deploy email-caixa --no-verify-jwt (o token é validado no código).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { ErroImap, Imap, type Ligacao } from './imap.ts';
import { enviarSmtp, ErroSmtp } from './smtp.ts';
import { analisar, construir, enderecos, palavras, separar } from './mime.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false, autoRefreshToken: false } });
type Cred = { elolog: boolean; email: string; nome: string; imap_host: string; imap_porta: number; smtp_host: string; smtp_porta: number; utilizador: string; senha: string };
const txt = (v: unknown, max = 300) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const ehUuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const HOST = /^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/;
const EMAIL = /^[^\s@<>"]{1,64}@[a-z0-9.-]+\.[a-z]{2,}$/i;
const ID_MSG = /^<[^<>\s]{3,250}>$/;
const PASTAS = ['entrada', 'enviados', 'lixo'];
const b64 = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192)); return btoa(s); };
const quando = (d?: string) => { const t = d ? Date.parse(d.replace(/\s*\([^)]*\)\s*$/, '')) : NaN; return Number.isNaN(t) ? null : new Date(t).toISOString(); };
function nivel(jwt: string): string { try { return JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).aal ?? ''; } catch { return ''; } }

async function abrir(host: string, porta: number): Promise<Ligacao> {
  if (!HOST.test(host) || ![993, 465].includes(porta)) throw new ErroImap('Servidor de email inválido.', 'servidor');
  let c: Deno.TlsConn;
  try { c = await Deno.connectTls({ hostname: host, port: porta }); } catch { throw new ErroImap(`Não foi possível ligar a ${host}:${porta}. Confirme o nome do servidor.`, 'servidor'); }
  const b = new Uint8Array(65536);
  return { ler: async () => { const n = await c.read(b); return n === null ? null : b.slice(0, n); },
    escrever: async (d) => { let o = 0; while (o < d.length) o += await c.write(d.subarray(o)); },
    fechar: () => { try { c.close(); } catch { /* já fechada */ } } };
}
async function comPrazo<T>(l: Ligacao, p: Promise<T>, ms = 25_000): Promise<T> {
  let t = 0;
  try { return await Promise.race([p, new Promise<never>((_, r) => { t = setTimeout(() => { l.fechar(); r(new ErroImap('O servidor de email não respondeu a tempo.', 'tempo')); }, ms); })]); }
  finally { clearTimeout(t); l.fechar(); }
}
async function comImap<T>(c: Cred, fn: (i: Imap) => Promise<T>): Promise<T> {
  const l = await abrir(c.imap_host, c.imap_porta), i = new Imap(l);
  return comPrazo(l, (async () => { await i.saudacao(); await i.entrar(c.utilizador, c.senha); const r = await fn(i); await i.sair(); return r; })());
}
async function smtp(c: Cred, para: string[], mensagem: string) {
  const l = await abrir(c.smtp_host, c.smtp_porta);
  await comPrazo(l, enviarSmtp(l, { utilizador: c.utilizador, senha: c.senha, de: c.email, para, mensagem, ehlo: c.email.split('@')[1] }));
}
async function pasta(i: Imap, qual: string): Promise<string> {
  if (qual === 'entrada') return 'INBOX';
  const ps = await i.pastas(), flag = qual === 'enviados' ? '\\SENT' : '\\TRASH';
  const re = qual === 'enviados' ? /(^|[./])(sent|enviad|itens enviados)/i : /(^|[./])(trash|lixo|deleted|eliminad|reciclagem)/i;
  const p = ps.find((x) => x.flags.some((f) => f.toUpperCase() === flag)) ?? ps.find((x) => re.test(x.nome));
  if (!p) throw new ErroImap(qual === 'enviados' ? 'Não encontrei a pasta de enviados.' : 'Não encontrei a pasta do lixo.', 'pasta');
  return p.nome;
}
async function mensagem(i: Imap, uid: number) {
  const [m] = await i.buscar([uid], 'UID RFC822.SIZE');
  if (!m) throw new ErroImap('A mensagem já não existe.', 'pasta');
  if (Number(m['RFC822.SIZE'] ?? 0) > 12 * 1024 * 1024) throw new ErroImap('Mensagem demasiado grande para abrir aqui (mais de 12 MB). Abra-a no webmail.', 'pasta');
  const [c] = await i.buscar([uid], 'UID BODY.PEEK[]');
  return analisar(c?.CORPO instanceof Uint8Array ? c.CORPO : new Uint8Array(0));
}
function falha(e: unknown): Response {
  if (e instanceof ErroImap || e instanceof ErroSmtp) {
    if (e.codigo === 'login') return erro(400, 'login', 'O servidor de email recusou o utilizador ou a palavra-passe. ' + e.message);
    return erro(e.codigo === 'tempo' ? 504 : 400, e.codigo, e.message);
  }
  const pg = e as { code?: string; message?: string };
  if (pg?.code === 'P0001') return erro(400, 'regra', pg.message ?? 'Pedido recusado.');
  console.error('email-caixa:', pg?.code ?? '', e instanceof Error ? e.message.slice(0, 200) : '');
  return erro(500, 'interno', 'Erro interno. Tente novamente.');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: u, error: eu } = jwt ? await admin.auth.getUser(jwt) : { data: null, error: true };
  if (eu || !u?.user) return erro(401, 'sessao', 'Sessão inválida. Entre de novo.');
  const user = u.user.id, mfa = nivel(jwt) === 'aal2';
  const { data: ac } = await admin.rpc('servico_email_acesso', { p_user: user });
  const acesso = (ac ?? {}) as { plataforma?: boolean; empresa?: string | null };
  if (!acesso.empresa && !acesso.plataforma) return erro(403, 'permissao', 'O email só está disponível para administradores.');
  if (!acesso.empresa && !mfa) return erro(403, 'mfa', 'Confirme o segundo fator de autenticação para abrir o email da Elolog.');
  const { data: dentro } = await admin.rpc('servico_limite', { p_chave: 'email:' + user, p_max: 300, p_janela_min: 10 });
  if (dentro === false) return erro(429, 'limite', 'Demasiados pedidos. Aguarde alguns minutos.');
  const lido = await lerJson(req, 200_000);
  if (!lido.ok) return lido.resp;
  const c = (lido.valor ?? {}) as Record<string, unknown>, acao = txt(c.acao, 20);

  try {
    if (acao === 'caixas') {
      const { data, error } = await admin.rpc('servico_email_caixas', { p_user: user }); if (error) throw error;
      return resposta(200, { ok: true, caixas: ((data ?? []) as { elolog: boolean }[]).filter((x) => mfa || !x.elolog), elolog: !!acesso.plataforma && mfa, empresa: !!acesso.empresa });
    }
    if (c.caixa != null && !ehUuid(c.caixa)) return erro(400, 'caixa', 'Caixa de email inválida.');
    const credenciais = async (id: unknown): Promise<Cred> => {
      const { data, error } = await admin.rpc('servico_email_credenciais', { p_user: user, p_caixa: id }); if (error) throw error;
      const cr = data as Cred; if (cr.elolog && !mfa) throw new ErroImap('Confirme o segundo fator de autenticação.', 'mfa'); return cr;
    };
    if (acao === 'gravar') {
      const d = { email: txt(c.email, 254).toLowerCase(), nome: txt(c.nome, 80), imap_host: txt(c.imap_host, 253).toLowerCase(), smtp_host: txt(c.smtp_host, 253).toLowerCase(),
        utilizador: txt(c.utilizador, 254), ambito: acesso.plataforma && mfa && c.ambito !== 'empresa' ? 'elolog' : 'empresa' };
      if (!EMAIL.test(d.email)) return erro(400, 'email', 'Indique um endereço de email válido.');
      if (!HOST.test(d.imap_host) || !HOST.test(d.smtp_host)) return erro(400, 'servidor', 'Indique os servidores IMAP e SMTP (ex.: imap.exemplo.pt).');
      const senha = typeof c.senha === 'string' && c.senha ? c.senha.slice(0, 200) : null;
      const antiga = c.caixa ? await credenciais(c.caixa) : null;
      if (!senha && !antiga) return erro(400, 'senha', 'Indique a palavra-passe da caixa.');
      const teste: Cred = { elolog: false, ...d, imap_porta: 993, smtp_porta: 465, utilizador: d.utilizador || d.email, senha: senha ?? antiga!.senha };
      await comImap(teste, async (i) => { await i.selecionar('INBOX', true); });
      const l = await abrir(teste.smtp_host, 465); await comPrazo(l, enviarSmtp(l, { utilizador: teste.utilizador, senha: teste.senha, de: d.email, para: [], mensagem: '', ehlo: d.email.split('@')[1] }));
      const { data, error } = await admin.rpc('servico_email_gravar', { p_user: user, p_id: c.caixa ?? null, p_dados: { ...d, utilizador: teste.utilizador }, p_senha: senha });
      if (error) throw error;
      return resposta(200, { ok: true, caixa: data });
    }
    if (acao === 'remover') {
      await credenciais(c.caixa);
      const { error } = await admin.rpc('servico_email_remover', { p_user: user, p_caixa: c.caixa }); if (error) throw error;
      return resposta(200, { ok: true });
    }
    const cr = await credenciais(c.caixa), qual = PASTAS.includes(String(c.pasta)) ? String(c.pasta) : 'entrada';
    const uid = Number(c.uid);
    if (['ler', 'anexo', 'marcar', 'apagar'].includes(acao) && !(Number.isInteger(uid) && uid > 0)) return erro(400, 'uid', 'Mensagem inválida.');
    if (acao === 'listar') {
      const pagina = Math.max(0, Math.min(400, Number(c.pagina) || 0)), procura = txt(c.pesquisa, 100);
      return resposta(200, { ok: true, ...(await comImap(cr, async (i) => {
        await i.selecionar(await pasta(i, qual), true);
        const uids = (await i.pesquisar(procura)).sort((a, b) => b - a);
        const linhas = await i.buscar(uids.slice(pagina * 25, pagina * 25 + 25), 'UID FLAGS RFC822.SIZE BODY.PEEK[HEADER.FIELDS (FROM TO SUBJECT DATE CONTENT-TYPE)]');
        const mensagens = linhas.map((o) => {
          const cab = separar(o.CORPO instanceof Uint8Array ? o.CORPO : new Uint8Array(0)).cab, f = ((o.FLAGS ?? []) as string[]).map((x) => String(x).toUpperCase());
          return { uid: Number(o.UID), de: palavras(cab.from ?? ''), para: palavras(cab.to ?? ''), assunto: palavras(cab.subject ?? ''), data: quando(cab.date),
            lida: f.includes('\\SEEN'), respondida: f.includes('\\ANSWERED'), anexos: /multipart\/mixed/i.test(cab['content-type'] ?? ''), tamanho: Number(o['RFC822.SIZE'] ?? 0) };
        }).sort((a, b) => b.uid - a.uid);
        return { total: uids.length, pagina, mensagens };
      })) });
    }
    if (acao === 'ler' || acao === 'anexo') {
      return await comImap(cr, async (i) => {
        await i.selecionar(await pasta(i, qual), acao === 'anexo');
        const m = await mensagem(i, uid);
        if (acao === 'anexo') {
          const a = m.anexos[Number(c.indice)]; if (!a) return erro(404, 'anexo', 'Anexo inexistente.');
          return resposta(200, { ok: true, nome: a.nome, tipo: a.tipo, base64: b64(a.dados) });
        }
        await i.marcar(uid, '\\Seen', true);
        const h = m.cabecalhos;
        return resposta(200, { ok: true, mensagem: { uid, de: h.from ?? '', para: h.to ?? '', cc: h.cc ?? '', responder_a: h['reply-to'] ?? '', assunto: h.subject ?? '', data: quando(h.date),
          message_id: h['message-id'] ?? '', referencias: h.references ?? '', texto: m.texto.slice(0, 300_000), html: m.html.slice(0, 800_000),
          anexos: m.anexos.map((a, k) => ({ indice: k, nome: a.nome, tipo: a.tipo, tamanho: a.tamanho })) } });
      });
    }
    if (acao === 'marcar' || acao === 'apagar') {
      await comImap(cr, async (i) => {
        const p = await pasta(i, qual); await i.selecionar(p);
        if (acao === 'marcar') await i.marcar(uid, '\\Seen', c.lida !== false);
        else if (qual === 'lixo') { await i.marcar(uid, '\\Deleted', true); await i.comando('EXPUNGE'); }
        else await i.mover(uid, await pasta(i, 'lixo'));
      });
      return resposta(200, { ok: true });
    }
    if (acao === 'enviar') {
      const { data: ok } = await admin.rpc('servico_limite', { p_chave: 'email-envio:' + user, p_max: 40, p_janela_min: 10 });
      if (ok === false) return erro(429, 'limite', 'Limite de envios atingido. Aguarde alguns minutos.');
      const para = enderecos(txt(c.para, 2000)).map((x) => x.email), cc = enderecos(txt(c.cc, 2000)).map((x) => x.email);
      if (!para.length || [...para, ...cc].some((e) => !EMAIL.test(e)) || para.length + cc.length > 20) return erro(400, 'para', 'Indique destinatários válidos (máximo 20).');
      const assunto = txt(c.assunto, 300), texto = typeof c.texto === 'string' ? c.texto.slice(0, 100_000) : '';
      if (!assunto || !texto.trim()) return erro(400, 'texto', 'Escreva o assunto e a mensagem.');
      const emResposta = ID_MSG.test(txt(c.em_resposta, 260)) ? txt(c.em_resposta, 260) : undefined;
      const referencias = (txt(c.referencias, 2000).match(/<[^<>\s]{3,250}>/g) ?? []).slice(-10).join(' ');
      const msg = construir({ de: cr.email, nome: cr.nome, para, cc, assunto, texto, emResposta, referencias, dominio: cr.email.split('@')[1] });
      await smtp(cr, [...new Set([...para, ...cc])], msg);
      let guardada = true;
      try { await comImap(cr, async (i) => {
        await i.acrescentar(await pasta(i, 'enviados'), Uint8Array.from(msg, (x) => x.charCodeAt(0)));
        if (emResposta && Number(c.uid) > 0) { await i.selecionar(await pasta(i, qual)); await i.marcar(Number(c.uid), '\\Answered', true); }
      }); } catch { guardada = false; }
      return resposta(200, { ok: true, guardada });
    }
    return erro(400, 'acao', 'Ação desconhecida.');
  } catch (e) { return falha(e); }
});
