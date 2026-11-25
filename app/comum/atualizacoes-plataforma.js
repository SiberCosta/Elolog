/* Elolog — atualizações da plataforma (v172, migração 00205).
   Avisos e novidades que a administração publica em Site público com «Onde mostrar: Plataforma» (ou Site e plataforma)
   aparecem no topo da área de cliente/prestador, com a cor e o fundo escolhidos. Cada pessoa pode fechar um aviso;
   fica fechado neste aparelho. Os alertas vermelhos não se podem fechar enquanto estiverem ativos. Sem servidor, nada aparece. */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const seguro=l=>/^(https:\/\/(www\.)?elolog\.pt(\/|$)|\/|#|\.\.\/)/.test(String(l||""));
const CHAVE="elolog_atualizacoes_fechadas";
const fechadas=()=>{try{return JSON.parse(localStorage.getItem(CHAVE)||"[]")}catch(_){return[]}};
const fechar=id=>{try{localStorage.setItem(CHAVE,JSON.stringify([...fechadas(),id].slice(-80)))}catch(_){}};
/* cor do texto que se lê sobre o fundo escolhido */
const claro=hex=>{const m=/^#?([0-9a-f]{6})$/i.exec(hex||"");if(!m)return true;const n=parseInt(m[1],16),r=n>>16,g=n>>8&255,b=n&255;return(.299*r+.587*g+.114*b)>160};
let lista=[];

function desenhar(){const main=document.querySelector(".main");if(!main)return;let box=$("platAtualizacoes");
  const vis=lista.filter(a=>a.cor==="vermelho"||!fechadas().includes(a.id));
  if(!vis.length){box?.remove();return}
  if(!box){box=document.createElement("div");box.id="platAtualizacoes";box.className="pa-caixa";const top=main.querySelector(".topbar");if(top)top.after(box);else main.prepend(box)}
  box.innerHTML=vis.slice(0,3).map(a=>{const est=a.fundo?` style="--pa-fundo:${esc(a.fundo)};--pa-texto:${claro(a.fundo)?"#13293D":"#fff"}"`:"";
    return`<div class="pa-item pa-c-${esc(a.cor||"normal")}${a.fundo?" pa-com-fundo":""}" role="${a.cor==="vermelho"?"alert":"status"}"${est}>
      <span class="pa-etiqueta">${a.cor==="vermelho"?"Alerta":a.tipo==="novidade"?"Novidade":"Aviso"}</span>
      <p><strong>${esc(a.titulo)}</strong>${a.texto?` ${esc(a.texto)}`:""}${a.ligacao&&seguro(a.ligacao)?` <a href="${esc(a.ligacao)}">Saber mais</a>`:""}</p>
      ${a.cor==="vermelho"?"":`<button type="button" class="pa-fechar" data-pa-fechar="${esc(a.id)}" aria-label="Fechar aviso">×</button>`}</div>`}).join("")}
async function carregar(){if(!S()?.ativo?.()||typeof currentUser==="undefined"||!currentUser)return;
  try{const sb=await S().cliente();const{data,error}=await sb.rpc("plataforma_avisos");if(error)throw error;lista=Array.isArray(data)?data:[];desenhar()}catch(_){/* sem atualizações: a página continua igual */}}
document.addEventListener("click",e=>{const b=e.target.closest("[data-pa-fechar]");if(!b)return;fechar(b.dataset.paFechar);desenhar()});
const ini=window.startApp;if(typeof ini==="function")window.startApp=async function(){const r=await ini.apply(this,arguments);setTimeout(carregar,1200);return r};
setTimeout(carregar,2500);setInterval(carregar,10*60*1000);
window.elologAtualizacoes={carregar};
})();
