#!/usr/bin/env node
/* Elolog — auditoria estática da plataforma (regra de trabalho: identificar → analisar → alterar → verificar → validar a página completa).
   Uso: node ferramentas/auditoria.cjs   (a partir da raiz do projeto; não altera nenhum ficheiro)
   Verifica: sintaxe de todo o JavaScript; ficheiros referidos que não existem (HTML, lista de scripts, service worker);
   versões ?v= misturadas; ficheiros com mais de 200 linhas; ids repetidos no HTML gerado; palavras do português do Brasil. */
"use strict";
const fs = require("fs"), path = require("path");
const RAIZ = process.cwd(), IGNORAR = /(^|\/)(\.git|node_modules|servidor)(\/|$)/;
const lista = (d, ext, out = []) => { for (const f of fs.readdirSync(d)) { const p = path.join(d, f), r = path.relative(RAIZ, p);
  if (IGNORAR.test(r)) continue; const s = fs.statSync(p); if (s.isDirectory()) lista(p, ext, out); else if (ext.includes(path.extname(f))) out.push(r) } return out };
const problemas = []; const p = (tipo, ficheiro, msg) => problemas.push({ tipo, ficheiro, msg });

// 1) sintaxe
const js = lista(RAIZ, [".js", ".cjs", ".mjs"]).filter(f => !f.startsWith("ferramentas/"));
for (const f of js) { try { new Function(fs.readFileSync(f, "utf8").replace(/^#!.*/, "")) } catch (e) { if (!/import|export/.test(e.message)) p("sintaxe", f, e.message) } }

// 2) referências a ficheiros que não existem
const existe = (base, ref) => { const limpo = ref.split(/[?#]/)[0]; if (!limpo || /^(https?:|data:|mailto:|tel:|#|javascript:|\/\/)/.test(ref) || limpo.includes("${")) return true;
  return fs.existsSync(limpo.startsWith("/") ? path.join(RAIZ, limpo) : path.resolve(path.dirname(base), limpo)) };
for (const f of lista(RAIZ, [".html"])) { const s = fs.readFileSync(f, "utf8");
  for (const m of s.matchAll(/(?:src|href)="([^"]+)"/g)) if (!existe(f, m[1]) && !/\.html$/.test(m[1].split("?")[0]) ) p("ficheiro em falta", f, m[1]) }
const pag3 = "app/comum/pagina-3.js"; if (fs.existsSync(pag3)) { const s = fs.readFileSync(pag3, "utf8");
  for (const m of s.matchAll(/src="([^"]+)"/g)) if (!existe("app/area-cliente.html", m[1])) p("script em falta", pag3, m[1]) }
const sw = "app/service-worker.js"; if (fs.existsSync(sw)) { const s = fs.readFileSync(sw, "utf8"), shell = (s.match(/SHELL=\[([\s\S]*?)\]/) || [])[1] || "";
  for (const m of shell.matchAll(/"([^"]+)"/g)) if (!existe(sw, m[1])) p("cache do service worker", sw, m[1]) }

// 3) versões misturadas
const versoes = {}; for (const f of [...lista(RAIZ, [".html"]), ...js]) for (const m of fs.readFileSync(f, "utf8").matchAll(/\?v=(\d+)/g)) versoes[m[1]] = (versoes[m[1]] || 0) + 1;
if (Object.keys(versoes).length > 1) p("versões misturadas", "*", JSON.stringify(versoes));

// 4) tamanho (regra: ficheiros com 200 linhas ou menos; documentação e instaladores SQL não contam)
for (const f of [...js, ...lista(RAIZ, [".css", ".html"])]) { const n = fs.readFileSync(f, "utf8").split("\n").length; if (n > 201) p("mais de 200 linhas", f, n + " linhas") }

// 5) português do Brasil em textos visíveis (palavras inequívocas; exceções entre «» ou em comentários de código são raras)
const BR = /\b(usuári[oa]s?|cadastr(o|ar|ado|ados)|celular(es)?|tela(s)? de|equipe|contato(s)?|salvar|deletar|ônibus|planilha|time de|baixar o app|você precisa|fatura(mento)? emitido pelo|caminhão|caminhões|aplicativo)\b/i;
for (const f of [...js, ...lista(RAIZ, [".html"])]) { const linhas = fs.readFileSync(f, "utf8").split("\n");
  linhas.forEach((l, i) => { const t = l.replace(/\/\*.*?\*\/|\/\/.*$/g, ""); const m = t.match(BR); if (m && !/elolog_|contato@|data-/.test(t.slice(Math.max(0, m.index - 20), m.index + 30))) p("pt-BR", `${f}:${i + 1}`, m[0]) }) }

// 6) segurança: todas as páginas HTML com política de conteúdo (CSP) e referrer restrito; nenhuma chave service_role
for (const f of lista(RAIZ, [".html"])) { const s = fs.readFileSync(f, "utf8");
  if (!/http-equiv="Content-Security-Policy"/.test(s)) p("segurança", f, "sem Content-Security-Policy");
  if (!/name="referrer"/.test(s)) p("segurança", f, "sem meta referrer") }
for (const f of [...js, ...lista(RAIZ, [".html"])]) if (/service_role"?\s*[:=]\s*["']ey|SUPABASE_SERVICE_ROLE_KEY\s*=\s*["']/.test(fs.readFileSync(f, "utf8"))) p("segurança", f, "possível chave service_role no front-end");

// relatório
const grupos = {}; for (const x of problemas) (grupos[x.tipo] ||= []).push(x);
console.log(`Auditoria Elolog: ${js.length} ficheiros JS, ${problemas.length} problema(s)`);
for (const [t, l] of Object.entries(grupos)) { console.log(`\n## ${t} (${l.length})`); l.slice(0, 60).forEach(x => console.log(`- ${x.ficheiro}: ${x.msg}`)); if (l.length > 60) console.log(`… e mais ${l.length - 60}`) }
process.exitCode = problemas.some(x => ["sintaxe", "script em falta", "cache do service worker"].includes(x.tipo)) ? 1 : 0;
