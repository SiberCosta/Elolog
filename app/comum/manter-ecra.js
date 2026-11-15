/* Elolog — ao atualizar a página, volta ao mesmo ecrã (v153).
   Guarda no separador do navegador (sessionStorage) o último ecrã aberto por cada pessoa e reabre-o depois de entrar.
   Cobre páginas da área de cliente e do prestador, separadores de propostas, financeiro e equipa de terreno. */
(function(){"use strict";
const CHAVE="elolog_pagina";let aRestaurar=false,arranque=true;const INICIO=Date.now();
const quem=()=>{try{const u=typeof currentUser!=="undefined"?currentUser:null;return u?(u.role||"")+":"+(u.email||u.name||""):""}catch(e){return""}};
function guardar(fn,arg){if(aRestaurar||arranque)return;const q=quem();if(!q)return;try{sessionStorage.setItem(CHAVE,JSON.stringify({q,fn,arg,t:Date.now()}))}catch(e){}}
const FUNCOES=["showPage","showProviderPage","showProviderProposalTab","showProviderFinanceTab","showProviderFieldPage"];
function embrulhar(){FUNCOES.forEach(n=>{const f=window[n];if(typeof f!=="function"||f.__manter)return;
  const g=function(a){const r=f.apply(this,arguments);if(typeof a==="string"&&a)guardar(n,a);return r};Object.assign(g,f);g.__manter=true;window[n]=g})}
function restaurar(antes){let d=null;try{d=JSON.parse(sessionStorage.getItem(CHAVE)||"null")}catch(e){}
  if(!d||d.q!==quem()||(antes&&d.t>=antes)||!FUNCOES.includes(d.fn)||typeof window[d.fn]!=="function")return;
  /* páginas: só se existir no ecrã; dashboards já abrem por omissão */
  if((d.fn==="showPage"||d.fn==="showProviderPage")&&(!document.getElementById(d.arg)||d.arg==="dashboard"))return;
  aRestaurar=true;try{if(d.fn==="showProviderFieldPage"&&typeof window.showProviderPage==="function")window.showProviderPage("providerFieldTeam");window[d.fn](d.arg)}catch(e){console.warn("Não foi possível reabrir o último ecrã.",e)}finally{aRestaurar=false}}
window.elologManterEcra={guardar,restaurar,esquecer:()=>{try{sessionStorage.removeItem(CHAVE)}catch(e){}}};
function ligar(){embrulhar();const s=window.startApp;if(typeof s==="function"&&!s.__manter){const g=async function(){arranque=true;const t0=Date.now();let r;try{r=await s.apply(this,arguments)}finally{embrulhar();setTimeout(()=>{restaurar(t0);arranque=false},350)}return r};g.__manter=true;window.startApp=g}
  const sair=window.logout;if(typeof sair==="function"&&!sair.__manter){const g=function(){window.elologManterEcra.esquecer();return sair.apply(this,arguments)};g.__manter=true;window.logout=g}}
/* liga depois de todos os módulos (que também embrulham estas funções) e reabre se a sessão já estava aberta */
const ativa=()=>document.querySelector(".page.active")?.id||"";
/* só reabre o que ficou guardado ANTES desta carga (se a pessoa já mudou de ecrã, não interfere) */
function talvezRestaurar(){let d=null;try{d=JSON.parse(sessionStorage.getItem(CHAVE)||"null")}catch(e){}if(!d||!quem()||d.t>=INICIO)return;
  if((d.fn==="showPage"||d.fn==="showProviderPage")&&ativa()===d.arg)return;restaurar()}
window.addEventListener("load",()=>{ligar();setTimeout(()=>{embrulhar();talvezRestaurar()},900);setTimeout(()=>{talvezRestaurar();arranque=false},2600)});
})();
