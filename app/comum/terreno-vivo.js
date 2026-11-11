/* Elolog — Terreno ao vivo (v127): «Acompanhamento ao vivo» (empresa e administração), cartão «A caminho» do cliente e entradas nos menus.
   Mostra cada serviço em curso com a chegada prevista e o estado: a tempo, atrasado (passa da hora combinada) ou sem sinal (mais de 20 min). */
(function(){"use strict";
const D=()=>window.elologTerrenoDados,esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const hora=v=>v?new Date(v).toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"}):"—";
const ha=v=>{if(!v)return"";const m=Math.max(0,Math.round((Date.now()-new Date(v))/60000));return m<1?"agora mesmo":m===1?"há 1 minuto":m<60?`há ${m} minutos`:`há ${Math.floor(m/60)} h`};
const ESTADO={a_tempo:["A tempo","ok"],atrasado:["Atrasado","atraso"],sem_sinal:["Sem sinal","sinal"]};
const mapa=s=>`https://www.openstreetmap.org/?mlat=${s.lat}&mlon=${s.lon}#map=15/${s.lat}/${s.lon}`;
let relogio=null;

async function painel(botao){const s=window.elologPaginaPropria("terrenoPainel","Acompanhamento ao vivo",botao);if(!s)return;clearInterval(relogio);
  s.innerHTML='<div class="card tv"><p role="status">A carregar…</p></div>';await desenharPainel();relogio=setInterval(()=>{if(s.classList.contains("active"))desenharPainel();else clearInterval(relogio)},30000)}
async function desenharPainel(){const s=document.getElementById("terrenoPainel");if(!s)return;let l=[],falhou=false;try{l=await D().aCaminho()}catch(_){falhou=true}
  const n=k=>l.filter(x=>x.estado===k).length;
  s.innerHTML=`<div class="card tv"><div class="tv-topo"><div><h2>Acompanhamento ao vivo</h2><p>${!D().online()?"<b>Exemplo de demonstração.</b> ":""}Serviços em curso, com a chegada prevista calculada a partir da posição do motorista. Atualiza a cada 30 segundos.</p></div></div>
    ${falhou?'<p class="tv-erro">Não conseguimos ler os serviços agora. Tentamos outra vez daqui a 30 segundos.</p>':""}
    <div class="tv-resumo"><div><b>${l.length}</b><span>em curso</span></div><div class="ok"><b>${n("a_tempo")}</b><span>a tempo</span></div><div class="atraso"><b>${n("atrasado")}</b><span>atrasados</span></div><div class="sinal"><b>${n("sem_sinal")}</b><span>sem sinal</span></div></div>
    <div class="tv-lista">${l.length?l.map(linha).join(""):'<p class="tv-vazio">Nenhum serviço em curso. Quando um motorista iniciar o percurso, aparece aqui.</p>'}</div></div>`}
function linha(x){const[t,c]=ESTADO[x.estado]||ESTADO.a_tempo;
  return`<article class="tv-cartao tv-seg-${c}"><header><span class="tv-tipo tv-${esc(x.tipo)}">${x.tipo==="recolha"?"Recolha":"Entrega"}</span><b class="tv-cod">${esc(x.codigo||"")}</b><span class="tv-estado tv-${c}">${t}</span></header>
    <div class="tv-eta"><div><span>Chegada prevista</span><b>${hora(x.eta)}</b></div>${x.previsto_ate?`<div><span>Combinado até</span><b>${hora(x.previsto_ate)}</b></div>`:""}<div><span>Distância</span><b>${x.distancia_km!=null?String(x.distancia_km).replace(".",",")+" km":"—"}</b></div></div>
    <p class="tv-morada">${esc(x.destino||"")}</p><p class="tv-nota">${x.motorista?`${esc(x.motorista)} · `:""}última posição ${ha(x.atualizado_em)}</p>
    <div class="tv-acoes"><a class="btn-secondary" href="${mapa(x)}" target="_blank" rel="noopener noreferrer">Ver no mapa</a></div></article>`}

/* ---------- cliente: «A sua entrega está a caminho» no início ---------- */
async function cartaoCliente(){if(typeof currentUser==="undefined"||currentUser?.role!=="cliente")return;const p=document.getElementById("dashboard");if(!p)return;let l=[];try{l=await D().aCaminho()}catch(_){return}
  let box=document.getElementById("tvCliente");if(!l.length){box?.remove();return}
  if(!box){box=document.createElement("section");box.id="tvCliente";box.className="tv-cliente";box.setAttribute("aria-live","polite");p.prepend(box)}
  box.innerHTML=l.map(x=>`<div><span class="tv-pulso" aria-hidden="true"></span><div><b>${x.tipo==="recolha"?"Vamos recolher a sua carga":"A sua entrega está a caminho"} · <span class="tv-cod">${esc(x.codigo)}</span></b>
    <span>${x.eta?`Chegada prevista às ${hora(x.eta)}`:"A calcular a chegada prevista"}${x.estado==="atrasado"?" (com atraso)":""}. ${x.motorista?esc(x.motorista)+", ":""}${esc(x.empresa||"")}. Atualizado ${ha(x.atualizado_em)}.</span></div>
    <a class="btn-secondary" href="${mapa(x)}" target="_blank" rel="noopener noreferrer">Ver no mapa</a></div>`).join("")}
setInterval(()=>{if(document.getElementById("dashboard")?.classList.contains("active"))cartaoCliente()},60000);

/* ---------- menus e avisos ---------- */
function menus(){const adm=document.getElementById("adminGrpOp");if(adm&&!document.getElementById("adminMenuTerreno")){const b=document.createElement("button");b.type="button";b.id="adminMenuTerreno";b.textContent="Acompanhamento ao vivo";b.onclick=()=>painel(b);adm.appendChild(b)}}
function ligar(){menus();const c=window.configureRole;if(typeof c==="function"&&!c.__tv){const n=function(){const x=c.apply(this,arguments);menus();setTimeout(cartaoCliente,800);return x};n.__tv=1;window.configureRole=n}
  const sp=window.showPage;if(typeof sp==="function"&&!sp.__tv){const n=function(pg){const x=sp.apply(this,arguments);if(pg==="dashboard")cartaoCliente();return x};n.__tv=1;window.showPage=n}}
window.addEventListener("elolog-terreno-enviado",e=>{const a=e.detail?.aviso;if(a&&typeof showPlatformNotice==="function")showPlatformNotice(a,"warning")});
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
window.elologTerreno=Object.assign(window.elologTerreno||{},{painel,cartaoCliente});
})();
