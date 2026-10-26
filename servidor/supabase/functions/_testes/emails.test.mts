import { renderizar, limparAssunto, ligacao, escaparHtml, type ItemEmail } from '../_shared/emails.ts';
import { criarBrevo } from '../enviar-emails/brevo.ts';
import { tratar, igualConstante, type DepsEmails } from '../enviar-emails/handler.ts';

let falhas = 0;
const ok = (c: unknown, m: string) => { console.log((c ? '✔ ' : '✘ ') + m); if (!c) falhas++; };
const APP = 'https://exemplo.pt/Area%20de%20Cliente/Area%20de%20Cliente.html';
const item = (o: Partial<ItemEmail> = {}): ItemEmail => ({ id: 'i1', destinatario: 'a@b.pt', destino: 'empresa', tipo: 'empresa_recusada', titulo: 'O pedido de registo da empresa foi recusado', corpo: 'Documentação em falta.', ...o });

// ============================================================ modelos
{
  const e = renderizar(item({ corpo: '<script>alert(1)</script> & "aspas"' }), APP);
  ok(!e.html.includes('<script>') && e.html.includes('&lt;script&gt;') && e.html.includes('&amp;') && e.html.includes('&quot;aspas&quot;'), 'modelo: o motivo escrito por uma pessoa é escapado no HTML (sem <script>)');
  ok(e.texto.includes('<script>alert(1)</script>'), 'modelo: a versão em texto simples mantém o texto tal como foi escrito');
  const t = renderizar(item({ titulo: 'Olá\r\nBcc: vitima@x.pt\nSubject: outro' }), APP);
  ok(!/[\r\n]/.test(t.assunto) && t.assunto.startsWith('[Elolog] '), 'modelo: o assunto fica numa só linha (sem injeção de cabeçalhos) e com prefixo [Elolog]');
  ok(limparAssunto('x'.repeat(400)).length <= 150, 'modelo: assunto limitado a 150 caracteres');
  ok(renderizar(item({ tipo: 'estado_encomenda', titulo: 'A sua encomenda TR-1 mudou de estado', corpo: 'em_transito', destino: 'utilizador' }), APP).texto.includes('Novo estado: Em trânsito'), 'modelo: o estado da encomenda aparece em português ("Em trânsito")');
  ok(renderizar(item({ tipo: 'estado_encomenda', corpo: 'estado_novo_desconhecido' }), APP).texto.includes('estado_novo_desconhecido'), 'modelo: estado desconhecido não rebenta');
  ok(renderizar(item({ tipo: 'tipo_inventado', titulo: 'Título próprio' }), APP).texto.includes('Título próprio'), 'modelo: tipo sem modelo usa o título da notificação');
  ok(renderizar(item({ corpo: 'x'.repeat(2000) }), APP).texto.length < 1200, 'modelo: o texto livre é cortado a 500 caracteres');
  ok(renderizar(item({ tipo: 'pagamento_confirmado', corpo: null }), APP).texto.includes('Confirmámos o pagamento'), 'modelo: sem corpo não mostra "Nota:" vazia');
  const adm = ligacao(APP, 'plataforma'), emp = ligacao(APP, 'empresa');
  ok(adm?.includes('acesso=administracao') && !emp?.includes('acesso='), 'ligação: a administração abre o acesso administrativo, os outros não');
  ok(ligacao('javascript:alert(1)', 'empresa') === null && ligacao('', 'empresa') === null && ligacao('ftp://x.pt', 'empresa') === null, 'ligação: só http(s) é aceite (javascript: e vazio não geram botão)');
  ok(!renderizar(item(), 'javascript:alert(1)').html.includes('href='), 'modelo: sem endereço válido não há botão');
  ok(renderizar(item({ tipo: 'empresa_aprovada', corpo: null }), APP).texto.includes('Se não reconhece esta mensagem, ignore-a'), 'modelo: rodapé avisa quem recebe sem reconhecer (abuso)');
  ok(escaparHtml(`<>&"'`) === '&lt;&gt;&amp;&quot;&#39;', 'escaparHtml cobre < > & " \'');
}

// ============================================================ adaptador Brevo
const CFG = { chave: 'xkeysib-SEGREDO-123', remetenteEmail: 'avisos@exemplo.pt', remetenteNome: 'Elolog' };
const pronto = renderizar(item(), APP);
const falso = (estado: number, corpo: unknown = {}) => {
  const chamadas: { url: string; init: RequestInit }[] = [];
  const f = (async (url: string, init: RequestInit) => { chamadas.push({ url, init }); return new Response(JSON.stringify(corpo), { status: estado, headers: { 'content-type': 'application/json' } }); }) as unknown as typeof fetch;
  return { f, chamadas };
}
{
  const { f, chamadas } = falso(201, { messageId: '<msg-1@brevo>' });
  const r = await criarBrevo(CFG, f)('dest@x.pt', pronto, 'empresa_recusada');
  const c = chamadas[0], corpo = JSON.parse(String(c.init.body));
  ok(r.tipo === 'ok' && r.id === '<msg-1@brevo>', 'brevo: 201 → enviado, guarda o identificador');
  ok(c.url === 'https://api.brevo.com/v3/smtp/email' && (c.init.headers as Record<string, string>)['api-key'] === CFG.chave, 'brevo: endereço da API e cabeçalho api-key');
  ok(corpo.to.length === 1 && corpo.to[0].email === 'dest@x.pt' && corpo.sender.email === CFG.remetenteEmail && corpo.subject === pronto.assunto && !!corpo.htmlContent && !!corpo.textContent, 'brevo: um só destinatário, remetente configurado, assunto, HTML e texto');
  ok(!JSON.stringify(corpo).includes(CFG.chave), 'brevo: a chave API nunca vai no corpo do e-mail');
}
{
  const classe = async (estado: number, corpo: unknown) => (await criarBrevo(CFG, falso(estado, corpo).f)('d@x.pt', pronto, 't')).tipo;
  ok(await classe(429, { message: 'Too many requests' }) === 'limite', 'brevo: 429 → limite (parar o lote)');
  ok(await classe(401, { code: 'unauthorized' }) === 'configuracao' && await classe(403, {}) === 'configuracao', 'brevo: 401/403 → configuração (parar, sem gastar tentativas)');
  ok(await classe(400, { code: 'invalid_parameter', message: 'Sender is not valid' }) === 'configuracao', 'brevo: 400 por remetente não validado → configuração (não se perdem e-mails)');
  ok(await classe(400, { code: 'invalid_parameter', message: 'Invalid email address' }) === 'falhou', 'brevo: 400 por endereço inválido → falha definitiva');
  ok(await classe(503, {}) === 'repetir' && await classe(500, {}) === 'repetir', 'brevo: 5xx → repetir mais tarde');
  const echo = await criarBrevo(CFG, falso(400, { message: `invalid key ${CFG.chave} for request` }).f)('d@x.pt', pronto, 't');
  ok(echo.tipo === 'falhou' && !echo.erro.includes(CFG.chave) && echo.erro.includes('***'), 'brevo: se o fornecedor repetir a chave numa mensagem de erro, é ocultada');
  const rede = await criarBrevo(CFG, (async () => { throw new TypeError(`fetch failed ${CFG.chave}`); }) as unknown as typeof fetch)('d@x.pt', pronto, 't');
  ok(rede.tipo === 'repetir' && !rede.erro.includes(CFG.chave), 'brevo: falha de rede → repetir, sem detalhes internos');
  const lento = (async (_u: string, init: RequestInit) => new Promise<Response>((_res, rej) => { init.signal?.addEventListener('abort', () => rej(Object.assign(new Error('abort'), { name: 'AbortError' }))); })) as unknown as typeof fetch;
  const t = await criarBrevo(CFG, lento, 30)('d@x.pt', pronto, 't');
  ok(t.tipo === 'repetir' && /Tempo esgotado/.test(t.erro), 'brevo: pedido que não responde é cortado ao fim do tempo limite');
}

// ============================================================ função enviar-emails
const SEGREDO = 'segredo-cron-muito-longo-123456';
const itens = (n: number): ItemEmail[] => Array.from({ length: n }, (_, i) => item({ id: 'e' + i, destinatario: `u${i}@x.pt` }));
function deps(sobre: Partial<DepsEmails> = {}, fila: ItemEmail[] = itens(3), respostas: ((i: number) => ReturnType<DepsEmails['enviar']>) | null = null) {
  const log: string[] = []; const marcas: Record<string, string> = {}; let n = 0; let pediu = -1;
  const d: DepsEmails = {
    segredo: SEGREDO, ativo: true, fornecedorConfigurado: true, appUrl: APP, limiteDiario: 250, lote: 20,
    async enviadosHoje() { log.push('hoje'); return 0; },
    async reservar(max) { pediu = max; log.push('reservar'); return fila.slice(0, max); },
    async marcar(id, r) { marcas[id] = r; log.push(`marcar:${id}:${r}`); },
    async enviar(para, email) { log.push('enviar:' + para); const i = n++; return respostas ? respostas(i) : { tipo: 'ok', id: 'm' + i }; },
    ...sobre,
  };
  return { d, log, marcas, pediu: () => pediu };
}
const pedido = (corpo: unknown = {}, h: Record<string, string> = { 'x-cron-secret': SEGREDO }, metodo = 'POST') =>
  new Request('http://localhost/enviar-emails', { method: metodo, headers: { 'content-type': 'application/json', ...h }, body: metodo === 'GET' ? undefined : JSON.stringify(corpo) });

ok(await igualConstante('abc', 'abc') && !(await igualConstante('abc', 'abd')) && !(await igualConstante('abc', 'abcd')) && !(await igualConstante('', 'x')), 'segredo: comparação exata (iguais, diferentes, tamanhos diferentes)');
{
  const { d, log } = deps();
  ok((await tratar(pedido({}, {}, 'GET'), d)).status === 405, 'enviar-emails: GET → 405');
  const sem = await tratar(pedido({}, {}), d);
  ok(sem.status === 401 && !log.includes('reservar'), 'enviar-emails: sem segredo → 401 e nada é reservado');
  const mau = await tratar(pedido({}, { 'x-cron-secret': 'segredo-cron-muito-longo-123457' }), d);
  const txt = await mau.text();
  ok(mau.status === 401 && !txt.includes(SEGREDO) && !log.includes('reservar'), 'enviar-emails: segredo errado (mesmo tamanho) → 401 sem revelar o segredo');
  const d0 = deps({ segredo: '' });
  ok((await tratar(pedido({}, { 'x-cron-secret': '' }), d0.d)).status === 503, 'enviar-emails: sem CRON_SECRET configurado a função recusa tudo (nunca fica aberta)');
}
{
  const a = deps({ ativo: false }); const ra = await tratar(pedido(), a.d);
  ok(ra.status === 200 && (await ra.json()).ativo === false && !a.log.includes('reservar'), 'enviar-emails: EMAIL_ATIVO=false → pausa (nada reservado, a fila acumula)');
  const b = deps({ fornecedorConfigurado: false }); const rb = await tratar(pedido(), b.d);
  ok(rb.status === 503 && !b.log.includes('reservar'), 'enviar-emails: Brevo não configurado → 503 e a fila fica intacta');
}
{
  const { d, log, marcas } = deps();
  const r = await tratar(pedido(), d); const j = await r.json();
  ok(r.status === 200 && j.enviados === 3 && j.falhados === 0 && Object.values(marcas).every(x => x === 'enviado'), 'enviar-emails: lote de 3 → 3 enviados e marcados');
  ok(log.filter(x => x.startsWith('enviar:')).join() === 'enviar:u0@x.pt,enviar:u1@x.pt,enviar:u2@x.pt', 'enviar-emails: cada e-mail vai para o seu destinatário');
}
{
  const a = deps({ limiteDiario: 250, async enviadosHoje() { return 250; } });
  const ra = await tratar(pedido(), a.d); const ja = await ra.json();
  ok(ra.status === 200 && /limite diário/.test(ja.adiado) && !a.log.includes('reservar'), 'enviar-emails: limite diário atingido → adia, não reserva nada');
  const b = deps({ limiteDiario: 250, lote: 20, async enviadosHoje() { return 245; } });
  await tratar(pedido(), b.d);
  ok(b.pediu() === 5, 'enviar-emails: perto do limite só reserva o que ainda cabe (5 de 250)');
}
{
  const { d, log, marcas } = deps({}, itens(4), i => Promise.resolve(i === 1 ? { tipo: 'limite' as const, erro: 'HTTP 429' } : { tipo: 'ok' as const, id: 'm' }));
  const j = await (await tratar(pedido(), d)).json();
  ok(marcas.e0 === 'enviado' && marcas.e1 === 'libertar' && marcas.e2 === 'libertar' && marcas.e3 === 'libertar', '429 a meio: o 1.º segue, o que bateu no limite e os restantes são LIBERTADOS (não gastam tentativa)');
  ok(log.filter(x => x.startsWith('enviar:')).length === 2 && j.interrompido && /Limite/.test(j.interrompido), '429 a meio: não insiste (só 2 pedidos ao fornecedor) e diz que interrompeu');
}
{
  const { d, marcas } = deps({}, itens(3), () => Promise.resolve({ tipo: 'configuracao' as const, erro: 'HTTP 401' }));
  const j = await (await tratar(pedido(), d)).json();
  ok(Object.values(marcas).every(x => x === 'libertar') && j.enviados === 0 && /Configuração/.test(j.interrompido), 'chave recusada: todos libertados (nenhum e-mail se perde nem gasta tentativas) e o lote para');
}
{
  const { d, marcas, log } = deps({}, itens(5), () => Promise.resolve({ tipo: 'repetir' as const, erro: 'HTTP 503' }));
  const j = await (await tratar(pedido(), d)).json();
  ok(marcas.e0 === 'repetir' && marcas.e1 === 'repetir' && marcas.e2 === 'repetir' && marcas.e3 === 'libertar' && marcas.e4 === 'libertar', '3 falhas temporárias seguidas: as 3 vão para repetir e o resto é libertado');
  ok(log.filter(x => x.startsWith('enviar:')).length === 3 && /Falhas temporárias/.test(j.interrompido), '3 falhas temporárias seguidas: o lote para (não martela um fornecedor em baixo)');
}
{
  const { d, marcas } = deps({}, itens(3), i => Promise.resolve(i === 0 ? { tipo: 'falhou' as const, erro: 'HTTP 400 Invalid email' } : { tipo: 'ok' as const, id: 'm' }));
  const j = await (await tratar(pedido(), d)).json();
  ok(marcas.e0 === 'falhou' && marcas.e1 === 'enviado' && marcas.e2 === 'enviado' && j.falhados === 1, 'endereço inválido: falha definitiva só desse e-mail; os outros seguem');
}
{
  const { d, marcas } = deps({ async enviar() { throw new Error('boom com dados internos 10.0.0.5'); } });
  const r = await tratar(pedido(), d); const t = await r.text();
  ok(r.status === 200 && !t.includes('10.0.0.5') && Object.values(marcas).slice(0, 3).every(x => x === 'repetir' || x === 'libertar'), 'erro inesperado ao enviar: tratado como falha temporária, sem expor detalhes');
}
{
  const { d } = deps({ async reservar() { throw new Error('relation emails_fila does not exist'); } });
  const r = await tratar(pedido(), d); const t = await r.text();
  ok(r.status === 503 && !t.includes('emails_fila'), 'erro da base de dados: 503 genérico, sem detalhes internos');
}
{
  const { d, log } = deps();
  const r = await tratar(pedido({ teste: 'Eu@Exemplo.pt' }), d);
  ok(r.status === 200 && (await r.json()).enviado === true && log.includes('enviar:eu@exemplo.pt') && !log.includes('reservar'), 'teste: envia um e-mail de teste ao endereço indicado (normalizado) sem tocar na fila');
  ok((await tratar(pedido({ teste: 'não-é-email' }), d)).status === 400, 'teste: endereço inválido → 400');
  const f = deps({ async enviar() { return { tipo: 'configuracao' as const, erro: 'HTTP 401' }; } });
  const rf = await tratar(pedido({ teste: 'a@b.pt' }), f.d); const jf = await rf.json();
  ok(rf.status === 502 && jf.resultado === 'configuracao', 'teste: se o Brevo recusar, a resposta diz porquê (502 + resultado) para ajudar a configurar');
  ok((await tratar(pedido({ teste: 'a@b.pt' }, {}), d)).status === 401, 'teste: também exige o segredo');
}

console.log(falhas === 0 ? '\nTODOS OS TESTES DE E-MAIL PASSARAM' : `\n${falhas} FALHA(S)`);
process.exit(falhas === 0 ? 0 : 1);
