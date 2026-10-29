/* Elolog — espaço de ficheiros do plano (medido no servidor: função espaco_ficheiros / espaco_empresas, migração 00144).
   Prestador: o quadro «Plano contratado» mostra o espaço real usado. Equipa Elolog: tabela por empresa em «Planos e subscrições»,
   com o valor acordado dos contratos personalizados. Em modo demo nada muda. */
(function(){"use strict";
const S=()=>window.ELOLogServidor,ativo=()=>!!(S()&&S().ativo&&S().ativo());
const gb=b=>(Number(b||0)/1073741824).toLocaleString("pt-PT",{maximumFractionDigits:b<1073741824?2:1})+" GB";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const barra=p=>`<span class="espaco-barra" aria-hidden="true"><i style="width:${Math.min(100,p)}%;background:${p>=100?"#b42318":p>=80?"#b54708":"#236186"}"></i></span>`;
async function rpc(nome,args){const sb=await S().cliente(),{data,error}=await sb.rpc(nome,args||{});if(error)throw error;return data}
let ultimo=null;
async function atualizar(){if(!ativo())return;try{ultimo=await rpc("espaco_ficheiros")}catch(_){return}pintarPrestador()}
function pintarPrestador(){const box=document.getElementById("providerSubscriptionContent");if(!box||!ultimo||ultimo.tipo!=="empresa")return;
const cel=[...box.querySelectorAll(".admin-module-grid>div")].find(d=>/Armazenamento/i.test(d.querySelector("small")?.textContent||""));if(!cel)return;
const p=ultimo.percentagem;cel.querySelector("strong").innerHTML=`${gb(ultimo.usado)} / ${gb(ultimo.limite)} ${barra(p)}${p>=80?`<small class="espaco-aviso">${p>=100?"Esgotado: novos documentos bloqueados":"Quase cheio ("+p+" %)"}</small>`:""}`}
const orig=window.renderProviderSubscription;
if(typeof orig==="function")window.renderProviderSubscription=function(){const r=orig.apply(this,arguments);if(ativo()){pintarPrestador();atualizar()}return r};

/* ---- Equipa Elolog ---- */
let lidoEm=0;
async function pintarAdmin(forcar){const pag=document.getElementById("adminPlans");if(!pag||currentUser?.role!=="admin"||!ativo())return;
if(!forcar&&document.getElementById("adminEspaco")&&Date.now()-lidoEm<60000)return;lidoEm=Date.now();
let card=document.getElementById("adminEspaco");if(!card){card=document.createElement("div");card.id="adminEspaco";card.className="card";pag.appendChild(card)}
card.innerHTML='<div class="admin-section-heading"><div><h3>Espaço de ficheiros por empresa</h3><p>Medido no servidor. Ao chegar ao limite do plano, a empresa deixa de poder juntar documentos.</p></div></div><p>A carregar…</p>';
let lista=[];try{lista=await rpc("espaco_empresas")||[]}catch(e){card.lastElementChild.textContent="Não foi possível ler o espaço das empresas.";return}
card.lastElementChild.outerHTML=lista.length?`<div class="table-wrapper"><table><thead><tr><th>Empresa</th><th>Plano</th><th>Usado</th><th>Limite</th><th>Valor acordado (GB)</th></tr></thead><tbody>${lista.map(e=>{const p=Math.floor(100*e.usado/Math.max(e.limite,1));
return`<tr><td>${esc(e.nome)}</td><td>${esc(e.plano||"—")}</td><td>${gb(e.usado)} ${barra(p)}</td><td>${gb(e.limite)}</td><td><input type="number" min="0.1" step="0.1" value="${e.acordado_gb??""}" placeholder="do plano" data-espaco="${esc(e.empresa_id)}" aria-label="Valor acordado para ${esc(e.nome)}" style="width:110px"> <button type="button" class="btn-secondary" data-gravar="${esc(e.empresa_id)}">Guardar</button></td></tr>`}).join("")}</tbody></table></div>`:"<p>Ainda não há empresas aprovadas.</p>";
card.querySelectorAll("[data-gravar]").forEach(b=>b.onclick=async()=>{const v=card.querySelector(`[data-espaco="${b.dataset.gravar}"]`).value.trim();
try{await rpc("espaco_definir_acordado",{p_empresa:b.dataset.gravar,p_gb:v===""?null:Number(v.replace(",","."))});window.showPlatformNotice?.("Espaço acordado guardado.","success");pintarAdmin(true)}catch(e){window.showPlatformNotice?.(e.message||"Não foi possível guardar.","error")}})}
const origA=window.renderAdminPlatformPages;let aPintar=0;
if(typeof origA==="function")window.renderAdminPlatformPages=function(){const r=origA.apply(this,arguments);clearTimeout(aPintar);aPintar=setTimeout(pintarAdmin,200);return r};
window.elologEspaco={atualizar,pintarAdmin,gb};
})();
