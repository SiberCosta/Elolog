/* Elolog — centro de comando: «Negócio» e «Simulações dos clientes» em separadores (v186).
   Eram dois blocos grandes seguidos no fim do ecrã; agora só se vê um de cada vez e o ecrã fica mais curto.
   Não muda os dados nem os blocos: só esconde o que não está escolhido. Sobrevive às atualizações automáticas
   (o painel redesenha-se sozinho) e lembra a escolha durante a visita. Teclado: setas esquerda/direita. */
(function(){"use strict";
let escolha="negocio";
const ABAS=[["negocio","Negócio"],["simulacoes","Simulações dos clientes"]];
const alvo=k=>k==="negocio"?document.querySelector("#pvPainel .pv-negocio"):document.getElementById("paSimulacoes");
function aplicar(){const barra=document.getElementById("pvAbas");if(!barra)return;
  ABAS.forEach(([k])=>{const el=alvo(k),b=barra.querySelector(`[data-pva="${k}"]`),on=k===escolha;if(el){if(!el.id)el.id="pvNegocioPainel";b?.setAttribute("aria-controls",el.id);el.hidden=!on;el.setAttribute("role","tabpanel");el.setAttribute("aria-labelledby","pvAba-"+k)}
    if(b){b.setAttribute("aria-selected",String(on));b.tabIndex=on?0:-1;b.classList.toggle("on",on)}})}
function montar(){const neg=document.querySelector("#pvPainel .pv-negocio"),sim=document.getElementById("paSimulacoes");
  if(!neg||!sim){const b=document.getElementById("pvAbas");if(b&&!neg)b.remove();if(neg)neg.hidden=false;if(sim)sim.hidden=false;return}
  let barra=document.getElementById("pvAbas");
  if(!barra||barra.nextElementSibling!==neg){barra?.remove();
    neg.insertAdjacentHTML("beforebegin",`<div id="pvAbas" class="pv-abas" role="tablist" aria-label="Negócio e simulações">${ABAS.map(([k,t])=>`<button type="button" role="tab" id="pvAba-${k}" data-pva="${k}">${t}</button>`).join("")}</div>`)}
  const n=sim.querySelectorAll(".sa-linha,.sa-item,li,tr").length,bs=document.querySelector('#pvAbas [data-pva="simulacoes"]');
  if(bs)bs.innerHTML=`Simulações dos clientes${n?` <span class="pv-abas-n">${n}</span>`:""}`;aplicar()}
document.addEventListener("click",e=>{const b=e.target.closest?.("#pvAbas [data-pva]");if(!b)return;escolha=b.dataset.pva;aplicar()});
document.addEventListener("keydown",e=>{const b=e.target.closest?.("#pvAbas [data-pva]");if(!b||!["ArrowLeft","ArrowRight"].includes(e.key))return;e.preventDefault();
  const i=ABAS.findIndex(a=>a[0]===b.dataset.pva),j=(i+(e.key==="ArrowRight"?1:ABAS.length-1))%ABAS.length;escolha=ABAS[j][0];aplicar();document.getElementById("pvAba-"+escolha)?.focus()});
let pend=false;const obs=new MutationObserver(()=>{if(pend)return;pend=true;requestAnimationFrame(()=>{pend=false;obs.disconnect();try{montar()}finally{ligar()}})});
function ligar(){const p=document.getElementById("adminDashboardProviders");if(p)obs.observe(p,{childList:true,subtree:true})}
function arrancar(){if(!document.getElementById("adminDashboardProviders"))return setTimeout(arrancar,800);montar();ligar()}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arrancar);else arrancar();
})();
