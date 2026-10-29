// Edge Function «email-caixa»: painel de email da plataforma (ler e responder) por IMAP (993) e SMTP (465), ambos com TLS.
// Ações: caixas · contar · acessos · conceder · equipa · atribuir · atribuidos · gravar · remover · listar · ler · anexo · enviar · marcar · apagar.
// Acesso: o administrador (Elolog, com 2.º fator, ou do prestador) liga as caixas e dá acesso a funcionários da sua equipa.
// A palavra-passe da caixa fica no cofre da base de dados (servico_email_*) e nunca é devolvida ao navegador.
// Deploy: supabase functions deploy email-caixa --no-verify-jwt (o token é validado no código).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { ErroImap } from './imap.ts';
import { enviarSmtp, ErroSmtp } from './smtp.ts';
import { construir, enderecos, palavras, separar } from './mime.ts';
import { abrir, comImap, comPrazo, type Cred, HOST, mensagem, pasta, smtp } from './ligacao.ts';
import { codigoValido, novoCodigo } from './codigo.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false, autoRefreshToken: false } });
const txt = (v: unknown, max = 300) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const ehUuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const EMAIL = /^[^\s@<>"]{1,64}@[a-z0-9.-]+\.[a-z]{2,}$/i;
const ID_MSG = /^<[^<>\s]{3,250}>$/;
const PASTAS = ['entrada', 'enviados', 'lixo'];
const b64 = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192)); return btoa(s); };
const quando = (d?: string) => { const t = d ? Date.parse(d.replace(/\s*\([^)]*\)\s*$/, '')) : NaN; return Number.isNaN(t) ? null : new Date(t).toISOString(); };
function nivel(jwt: string): string { try { return JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).aal ?? ''; } catch { return ''; } }

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
  const acesso = (ac ?? {}) as { plataforma?: boolean; empresa?: string | null; delegado?: boolean };
  if (!acesso.empresa && !acesso.plataforma && !acesso.delegado) return erro(403, 'permissao', 'Ainda não tem caixas de email atribuídas. Peça acesso ao administrador.');
  if (acesso.plataforma && !acesso.empresa && !acesso.delegado && !mfa) return erro(403, 'mfa', 'Confirme o segundo fator de autenticação para abrir o email da Elolog.');
  if (acesso.empresa && !mfa) return erro(403, 'mfa', 'Confirme o código de verificação: entre de novo como administrador da empresa.');
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
    if (acao === 'acessos' || acao === 'conceder') {   // quem pode usar a caixa (só o administrador que a gere)
      if (!ehUuid(c.caixa) || (acao === 'conceder' && !ehUuid(c.alvo))) return erro(400, 'caixa', 'Pedido inválido.');
      const { data, error } = acao === 'acessos' ? await admin.rpc('servico_email_acessos', { p_user: user, p_caixa: c.caixa })
        : await admin.rpc('servico_email_conceder', { p_user: user, p_caixa: c.caixa, p_alvo: c.alvo, p_sim: c.sim === true });
      if (error) throw error; return resposta(200, { ok: true, funcionarios: data ?? null });
    }
    if (acao === 'atribuidos') {   // emails encaminhados a este funcionário para responder
      const { data, error } = await admin.rpc('servico_email_atribuidos', { p_user: user }); if (error) throw error;
      return resposta(200, { ok: true, atribuidos: data ?? [] });
    }
    if (acao === 'equipa' || acao === 'atribuir') {   // encaminhar um email a um colega da equipa da caixa
      if (!ehUuid(c.caixa) || (acao === 'atribuir' && (!ehUuid(c.alvo) || !(Number(c.uid) > 0)))) return erro(400, 'caixa', 'Pedido inválido.');
      const { data, error } = acao === 'equipa' ? await admin.rpc('servico_email_equipa', { p_user: user, p_caixa: c.caixa })
        : await admin.rpc('servico_email_atribuir', { p_user: user, p_caixa: c.caixa, p_uid: Number(c.uid), p_alvo: c.alvo, p_de: txt(c.de), p_assunto: txt(c.assunto), p_nota: txt(c.nota, 500) });
      if (error) throw error; return resposta(200, { ok: true, equipa: data ?? null });
    }
    if (acao === 'contar') {   // emails por ler na Entrada de cada caixa (contador do menu)
      const { data, error } = await admin.rpc('servico_email_caixas', { p_user: user }); if (error) throw error;
      const lista = ((data ?? []) as { id: string; email: string; elolog: boolean }[]).filter((x) => mfa || !x.elolog).slice(0, 5);
      const r = await Promise.allSettled(lista.map(async (x) => {
        const { data: cr, error: ec } = await admin.rpc('servico_email_credenciais', { p_user: user, p_caixa: x.id }); if (ec) throw ec;
        return { id: x.id, email: x.email, novas: await comImap(cr as Cred, (i) => i.naoLidas()) };
      }));
      const caixas = r.map((v, k) => (v.status === 'fulfilled' ? v.value : { id: lista[k].id, email: lista[k].email, novas: null })); return resposta(200, { ok: true, caixas, total: caixas.reduce((t, x) => t + (x.novas ?? 0), 0) });
    }
    if (c.caixa != null && !ehUuid(c.caixa)) return erro(400, 'caixa', 'Caixa de email inválida.');
    const credenciais = async (id: unknown, uid: number | null = null): Promise<Cred> => {
      const { data, error } = await admin.rpc('servico_email_credenciais2', { p_user: user, p_caixa: id, p_uid: uid }); if (error) throw error;
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
      const chave = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', codigo = txt(c.codigo, 10);
      if (!antiga || antiga.email !== d.email) {   // caixa nova (ou outro endereço): confirmar com o código enviado para essa caixa
        if (!codigo) {
          const n = await novoCodigo(chave, user, d.email);
          await smtp(teste, [d.email], construir({ de: d.email, nome: 'Elolog', para: [d.email], assunto: `Código de confirmação Elolog: ${n}`, dominio: d.email.split('@')[1],
            texto: `O seu código para ligar esta caixa de email à plataforma Elolog é:\n\n${n}\n\nÉ válido durante 10 minutos. Se não foi você, ignore esta mensagem.` }));
          return resposta(200, { ok: true, confirmar: true, email: d.email });
        }
        const { data: pode } = await admin.rpc('servico_limite', { p_chave: 'email-codigo:' + user, p_max: 8, p_janela_min: 10 }); if (pode === false) return erro(429, 'limite', 'Demasiadas tentativas. Peça um código novo daqui a 10 minutos.');
        if (!(await codigoValido(chave, user, d.email, codigo))) return erro(400, 'codigo', 'Código errado ou expirado. Confirme o email recebido ou peça outro.');
      } else { const l = await abrir(teste.smtp_host, 465); await comPrazo(l, enviarSmtp(l, { utilizador: teste.utilizador, senha: teste.senha, de: d.email, para: [], mensagem: '', ehlo: d.email.split('@')[1] })); }
      const { data, error } = await admin.rpc('servico_email_gravar', { p_user: user, p_id: c.caixa ?? null, p_dados: { ...d, utilizador: teste.utilizador }, p_senha: senha });
      if (error) throw error; return resposta(200, { ok: true, caixa: data });
    }
    if (acao === 'remover') {
      await credenciais(c.caixa);
      const { error } = await admin.rpc('servico_email_remover', { p_user: user, p_caixa: c.caixa }); if (error) throw error;
      return resposta(200, { ok: true });
    }
    const uid = Number(c.uid), qual = PASTAS.includes(String(c.pasta)) ? String(c.pasta) : 'entrada';
    const cr = await credenciais(c.caixa, Number.isInteger(uid) && uid > 0 ? uid : null);
    if (cr.restrito && (!['ler', 'anexo', 'enviar'].includes(acao) || qual !== 'entrada')) return erro(403, 'permissao', 'Só pode abrir e responder ao email que lhe foi encaminhado.');
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
        if (emResposta && uid > 0) { await i.selecionar(await pasta(i, qual)); await i.marcar(uid, '\\Answered', true); }
      }); } catch { guardada = false; }
      if (emResposta && uid > 0) await admin.rpc('servico_email_respondido', { p_user: user, p_caixa: c.caixa, p_uid: uid });
      return resposta(200, { ok: true, guardada });
    }
    return erro(400, 'acao', 'Ação desconhecida.');
  } catch (e) { return falha(e); }
});
