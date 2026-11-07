// Testes das regras de segurança (v84): ficheiros, assistente e funcionamento em modo fechado.
// Correr: node --experimental-strip-types seguranca.test.mts
(globalThis as any).Deno = { env: { get: (k: string) => (globalThis as any).__env?.[k] } };
import { assinaturaValida, verificarFicheiro } from '../_shared/ficheiros.ts';
import { entradaAssistente, limitar, nivelSessao, saidaAssistente, seguro } from '../_shared/seguranca.ts';

let falhas = 0;
const ok = (c: unknown, m: string) => { console.log((c ? '✔ ' : '✘ ') + m); if (!c) falhas++; };
const b = (...x: number[]) => new Uint8Array([...x, ...new Array(16).fill(0)]);
const PDF = b(0x25, 0x50, 0x44, 0x46, 0x2d), PNG = b(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a), EXE = b(0x4d, 0x5a);

// ---------- ficheiros
ok(verificarFicheiro('a/1-fatura.pdf', 'application/pdf', 100, PDF) === null, 'PDF verdadeiro aceite');
ok(verificarFicheiro('a/1-fatura.pdf', 'application/pdf', 100, EXE) !== null, 'executável disfarçado de PDF recusado');
ok(verificarFicheiro('a/1-virus.exe', 'application/x-msdownload', 100, EXE) !== null, 'tipo não permitido recusado');
ok(verificarFicheiro('a/foto.pdf', 'image/png', 100, PNG) !== null, 'extensão diferente do tipo recusada');
ok(verificarFicheiro('a/foto.png', 'image/png', 21 * 1024 * 1024, PNG) !== null, 'ficheiro acima de 20 MB recusado');
ok(verificarFicheiro('a/vazio.pdf', 'application/pdf', 0, PDF) !== null, 'ficheiro vazio recusado');
ok(assinaturaValida('image/webp', b(0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50)), 'WEBP verdadeiro aceite');
ok(assinaturaValida('application/vnd.openxmlformats-officedocument.wordprocessingml.document', b(0x50, 0x4b, 3, 4)), 'DOCX verdadeiro aceite');

// ---------- assistente: entrada e saída
const e1 = entradaAssistente('  Olá\u0000‮  menu ');
ok(e1.ok && e1.texto === 'Olá menu', 'entrada limpa de caracteres de controlo e invisíveis');
ok(!entradaAssistente('x'.repeat(1001)).ok, 'entrada demasiado longa recusada');
ok(!entradaAssistente({ texto: 'oi' }).ok, 'entrada que não é texto recusada');
ok(saidaAssistente('Veja https://www.elolog.pt/site/simulador.html', 'X') !== 'X', 'resposta com ligação Elolog aceite');
ok(saidaAssistente('Clique em https://site-falso.com/pagar', 'X') === 'X', 'resposta com ligação externa substituída');
ok(saidaAssistente('<script>alert(1)</script>', 'X') === 'X', 'resposta com código substituída');

// ---------- limites: o serviço tem de confirmar; erro = bloqueado
ok(await limitar({ rpc: async () => ({ data: true, error: null }) }, 'k', 1, 1), 'dentro do limite: permitido');
ok(!(await limitar({ rpc: async () => ({ data: false, error: null }) }, 'k', 1, 1)), 'acima do limite: bloqueado');
ok(!(await limitar({ rpc: async () => ({ data: null, error: { message: 'x' } }) }, 'k', 1, 1)), 'serviço de limites com erro: bloqueado');
ok(!(await limitar({ rpc: async () => { throw new Error('rede'); } }, 'k', 1, 1)), 'serviço de limites indisponível: bloqueado');

// ---------- funções: falha = operação não executada
const req = (m = 'POST', h: Record<string, string> = {}) => new Request('https://x/f', { method: m, headers: h, body: m === 'GET' ? undefined : '{}' });
(globalThis as any).__env = {};
let r = await seguro('t', () => new Response('feito'))(req());
ok(r.status === 503, 'segredos do servidor em falta: 503 e nada é executado');
(globalThis as any).__env = { SUPABASE_URL: 'u', SUPABASE_SERVICE_ROLE_KEY: 'k' };
r = await seguro('t', () => { throw new Error('bug'); })(req());
ok(r.status === 503, 'erro inesperado: 503 (fail closed)');
r = await seguro('t', () => new Response('feito'), { maxBytes: 10 })(req('POST', { 'content-length': '5000' }));
ok(r.status === 413, 'pedido acima do tamanho: recusado');
r = await seguro('t', () => new Response('feito'), { metodos: ['POST'] })(req('GET'));
ok(r.status === 405, 'método não permitido: recusado');
r = await seguro('t', () => new Response('feito'))(req());
ok(r.status === 200 && (await r.text()) === 'feito', 'pedido válido: executado');

// ---------- v85: nível da sessão (telemóvel ou código de reserva)
const jwt = (p: object) => 'x.' + btoa(JSON.stringify(p)).replace(/=+$/, '') + '.y';
const rpcRes = (data: unknown, error: unknown = null) => ({ rpc: async () => ({ data, error }) });
ok((await nivelSessao(rpcRes(false), jwt({ aal: 'aal2', sub: 'u' }))) === 'aal2', 'telemóvel confirmado: aal2');
ok((await nivelSessao(rpcRes(true), jwt({ aal: 'aal1', sub: 'u', session_id: 's' }))) === 'aal2', 'código de reserva nesta sessão: aal2');
ok((await nivelSessao(rpcRes(false), jwt({ aal: 'aal1', sub: 'u', session_id: 's' }))) === 'aal1', 'sem código de reserva: aal1');
ok((await nivelSessao(rpcRes(null, { message: 'x' }), jwt({ aal: 'aal1', sub: 'u', session_id: 's' }))) === 'aal1', 'serviço com erro: aal1 (fail closed)');
ok((await nivelSessao({ rpc: () => { throw new Error('rede'); } }, jwt({ aal: 'aal1', sub: 'u', session_id: 's' }))) === 'aal1', 'serviço indisponível: aal1');
ok((await nivelSessao(rpcRes(true), 'lixo')) === 'aal1', 'token ilegível: aal1');

console.log(falhas ? `\n${falhas} FALHA(S)` : '\nTodos os testes passaram.');
if (falhas) (globalThis as any).process.exit(1);
