/* Elolog — efeitos discretos nos cartões dos painéis (v185).
   Inspirados nos padrões CountUp e FadeContent da biblioteca React Bits, mas escritos de raiz em JavaScript simples:
   a aplicação não usa React, por isso não há dependências novas nem código copiado.
   · Números dos indicadores contam até ao valor quando aparecem ou mudam (0,6 s). Se o valor não mudou, não anima:
     os painéis redesenham-se a cada 30 s e não podem ficar sempre a mexer.
   · Os blocos do painel entram com um pequeno deslize, só na primeira vez que aparecem em cada visita.
   · Nada disto acontece com «reduzir movimento» ligado no sistema. Tabelas, formulários, encomendas, financeiro,
     armazém e documentos ficam de fora de propósito. */
(function(){"use strict";
const calmo=()=>matchMedia("(prefers-reduced-motion: reduce)").matches;
const NUM=".pw-kpi strong,.ck-txt strong,.pv-kpi strong,[data-contar]";
const vistos=new Map(),entrou=new Set();
/* «900,00 €», «1 234», «94,8 %» → {n, casas, antes, depois}; null se não for um número simples */
function ler(t){const m=String(t).trim().match(/^([^\d\p{L}-]*)(-?[\d \u00a0\u202f.]*\d(?:,\d+)?)(.*)$/u);if(!m)return null;
  const limpo=m[2].replace(/[ \u00a0\u202f.]/g,"").replace(",","."),n=Number(limpo);if(!isFinite(n))return null;
  return{n,casas:(m[2].split(",")[1]||"").length,antes:m[1],depois:m[3]}}
const fmt=(v,c)=>v.toLocaleString("pt-PT",{minimumFractionDigits:c,maximumFractionDigits:c});
function contar(el){const txt=el.textContent,l=ler(txt);if(!l)return;
  const chave=(el.closest("[id]")?.id||"")+"|"+(el.parentElement?.querySelector("small")?.textContent||el.previousElementSibling?.textContent||"");
  const ant=vistos.get(chave);vistos.set(chave,l.n);
  if(ant===l.n||calmo()||l.n===0&&ant===undefined)return;
  const de=ant??0,t0=performance.now(),dur=600;el.setAttribute("aria-label",txt.trim());
  const passo=t=>{const k=Math.min(1,(t-t0)/dur),e=1-Math.pow(1-k,3);el.textContent=l.antes+fmt(de+(l.n-de)*e,l.casas)+l.depois;
    if(k<1&&el.isConnected)requestAnimationFrame(passo);else{el.textContent=txt;el.removeAttribute("aria-label")}};
  requestAnimationFrame(passo)}
function entrar(bloco){const id=bloco.id;if(!id||entrou.has(id))return;entrou.add(id);if(calmo())return;
  const i=[...bloco.parentElement.children].indexOf(bloco);bloco.style.setProperty("--ce-atraso",Math.min(i,6)*45+"ms");bloco.classList.add("ce-entrar");
  bloco.addEventListener("animationend",()=>bloco.classList.remove("ce-entrar"),{once:true})}
function varrer(raiz){if(!raiz||!raiz.querySelectorAll)return;
  raiz.querySelectorAll(".pw-grelha>.pw").forEach(entrar);
  raiz.querySelectorAll(NUM).forEach(el=>{if(!el.closest("table,form"))contar(el)})}
const obs=new MutationObserver(l=>{const alvos=new Set();for(const m of l)for(const n of m.addedNodes)if(n.nodeType===1)alvos.add(n.closest?.(".page")||n);
  alvos.forEach(a=>{if(a.closest?.(".page")?.classList.contains("active")!==false)varrer(a)})});
function arrancar(){obs.observe(document.body,{childList:true,subtree:true});varrer(document.querySelector(".page.active"))}
/* mudar de ecrã volta a mostrar a entrada dos blocos desse ecrã na próxima visita */
document.addEventListener("click",e=>{if(e.target.closest("#sidebar"))setTimeout(()=>varrer(document.querySelector(".page.active")),60)});
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arrancar);else arrancar();
window.elologEfeitosCartoes={ler,varrer};
})();
