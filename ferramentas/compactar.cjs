// Uso (precisa de: npm i esbuild acorn): node ferramentas/compactar.cjs <ficheiro> <js|css> <largura>
// Tira espaços a mais com o esbuild (nomes e lógica intactos) e volta a partir em linhas só em sítios seguros:
//  JS  → depois de ; , { } fora de modelos de texto (nunca dentro de strings nem antes de ` ou de texto de modelo)
//  CSS → depois de } e ; fora de strings e de parênteses
const e = require('esbuild');
const acorn = require('acorn');
const fs = require('fs');
const [f, tipo, larg] = process.argv.slice(2);
const W = +larg;
let src = fs.readFileSync(f, 'utf8');
let cab = '';
const m = src.match(/^\s*\/\*[\s\S]*?\*\//);            // descrição do ficheiro: fica no topo, tal como está
if (m) { cab = m[0].trim() + '\n'; src = src.slice(m[0].length); }
let code = e.transformSync(src, { loader: tipo, minifyWhitespace: true, legalComments: 'none', charset: 'utf8' }).code.replace(/\n+$/, '');
if (code.includes('\n')) code = code.replace(/\n/g, tipo === 'css' ? ' ' : '\n');   // o esbuild só deixa \n onde precisa (JS)

const cortes = [];                                        // posições depois das quais se pode mudar de linha
if (tipo === 'js') {
  const toks = [...acorn.tokenizer(code, { ecmaVersion: 'latest', sourceType: 'script', allowHashBang: true })];
  for (let i = 0; i < toks.length - 1; i++) {
    const t = toks[i], n = toks[i + 1], l = t.type.label;
    if (![';', ',', '{', '}'].includes(l)) continue;
    if (n.type.label === 'template' || n.type.label === '`' || n.type.label === '=>') continue;
    if (code.slice(t.end, n.start).includes('\n')) continue;
    cortes.push(t.end);
  }
} else {
  let q = null, par = 0;
  for (let i = 0; i < code.length; i++) {
    const c = code[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '"' || c === "'") { q = c; continue; }
    if (c === '(') par++; else if (c === ')') par = Math.max(0, par - 1);
    else if ((c === '}' || c === ';') && par === 0) cortes.push(i + 1);
  }
}
// junta pedaços até à largura W
let out = '', ini = 0, ult = 0;
const linhas = [];
let k = 0, comeco = 0;
for (const c of cortes) {
  if (c - comeco > W && ult > comeco) { linhas.push(code.slice(comeco, ult)); comeco = ult; }
  ult = c;
}
linhas.push(code.slice(comeco));
process.stdout.write(cab + linhas.map(s => s.replace(/^ +/, '')).join('\n') + '\n');
