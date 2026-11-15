/* Elolog — comportamento comum dos cartões (v149).
   1) Cartões que abrem algo e não são botões passam a funcionar pelo teclado: foco, Enter e Espaço (role="button").
   2) Quando o valor de um indicador muda de facto (dados novos do servidor), o número tem um realce curto; ao carregar a
      página não há realce. Nada é inventado: só se compara o texto que já está no ecrã. */
(function(){"use strict";
const CLICAVEIS=".ca-linha,.cr-tile,.pd-alerta,.ec-clicavel,[data-ec-clicavel]";
const valores=new Map();let marcado=false;
function teclado(raiz){(raiz.querySelectorAll?raiz:document).querySelectorAll(CLICAVEIS).forEach(e=>{if(/^(BUTTON|A)$/.test(e.tagName)||e.__ecTecla)return;
    if(!e.getAttribute("onclick")&&!e.dataset.ecClicavel)return;e.__ecTecla=1;if(!e.hasAttribute("role"))e.setAttribute("role","button");if(!e.hasAttribute("tabindex"))e.tabIndex=0;
    e.addEventListener("keydown",ev=>{if((ev.key==="Enter"||ev.key===" ")&&ev.target===e){ev.preventDefault();e.click()}})})}
function indicadores(){document.querySelectorAll(".pw-kpi,.ec-kpi").forEach(k=>{const chave=(k.querySelector("small")?.textContent||"").trim(),v=k.querySelector("strong");if(!chave||!v)return;
    const novo=v.textContent.trim(),antes=valores.get(chave);valores.set(chave,novo);
    if(antes!==undefined&&antes!==novo){v.classList.remove("ec-mudou");void v.offsetWidth;v.classList.add("ec-mudou");setTimeout(()=>v.classList.remove("ec-mudou"),1000)}})}
function correr(){marcado=false;try{teclado(document);indicadores()}catch(e){console.warn("Cartões:",e)}}
const vigia=new MutationObserver(()=>{if(!marcado){marcado=true;requestAnimationFrame(correr)}});
function arrancar(){correr();vigia.observe(document.body,{childList:true,subtree:true,characterData:true})}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arrancar);else arrancar();
window.elologCartoes={correr};
})();
