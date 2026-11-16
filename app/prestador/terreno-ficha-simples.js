/* Elolog — ficha do serviço para o operador no terreno, simplificada (v158).
   Mostra só o essencial (quem, onde, quando, viatura, notas) com «Ligar» e «Navegar» à mão, os 3 passos do serviço
   (A caminho · No local · Registado) e UM botão principal com o próximo passo:
   Iniciar rota → Cheguei ao local → Registar recolha/entrega (comprovativo com volumes, fotografias e assinatura).
   Se já houver outra rota a decorrer, não deixa iniciar esta e leva à rota em curso. Só com servidor. */
(function(){"use strict";
const D=()=>window.elologTerrenoDados,esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const noServidor=()=>{const u=typeof currentUser!=="undefined"?currentUser:null;return u?.role==="prestador"&&u?.providerCompany?.server===true};
const CHEGOU=id=>"elolog_chegou_"+id,chegou=id=>{try{return sessionStorage.getItem(CHEGOU(id))==="1"}catch(_){return false}};
window.elologMarcarChegada=id=>{try{sessionStorage.setItem(CHEGOU(id),"1")}catch(_){}};
function quando(v){if(!v)return"Sem hora marcada";const d=new Date(v);if(isNaN(d))return"Sem hora marcada";const h=d.toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"}),
  dia=new Date(d);dia.setHours(0,0,0,0);const hoje=new Date();hoje.setHours(0,0,0,0);const n=Math.round((dia-hoje)/864e5);
  return(n===0?"Hoje":n===1?"Amanhã":n===-1?"Ontem":d.toLocaleDateString("pt-PT",{weekday:"short",day:"2-digit",month:"2-digit"}))+" às "+h}
async function abrir(id){const job=(getFieldJobs()||[]).find(j=>String(j.id)===String(id));if(!job)return window.showPlatformNotice?.("Serviço não encontrado.","warning");
  const rec=job.type!=="Entrega",o=typeof fieldJobOperation==="function"?fieldJobOperation(job):null;
  let t=null,rota=null;try{[t,rota]=await Promise.all([D()?.servicos?.().then(l=>l.find(x=>String(x.id)===String(id))).catch(()=>null),D()?.rotaAtiva?.()])}catch(_){}
  const p=t?D().pessoa(t):{},nome=p.nome||o?.client||"Cliente",tel=p.telefone||(rec?o?.senderPhone:o?.recipientPhone)||"",
    morada=(t&&D().morada(t))||(rec?o?.pickupAddress||o?.origin:o?.deliveryAddress||o?.destination)||"",cod=t?.encomenda?.codigo||job.operationId||"";
  const ativo=rota&&String(rota.trabalho_id)===String(id)||D()?.estado?.().trabalho?.id===id,outra=rota&&String(rota.trabalho_id)!==String(id)?rota:null,cheg=chegou(id);
  const passo=cheg?3:ativo?2:1,acao=rec?"recolha":"entrega";
  const principal=outra?`<div class="tf-bloqueio"><b>Está a decorrer outra rota</b><span>Termine a ${outra.tipo==="entrega"?"entrega":"recolha"}${outra.codigo?" da encomenda "+esc(outra.codigo):""} antes de iniciar esta.</span>
      <button type="button" class="tf-principal" onclick="openFieldTask('${esc(outra.trabalho_id)}')">Abrir a rota em curso</button></div>`
    :passo===1?`<button type="button" class="tf-principal" data-tf="start">Iniciar rota</button>`
    :passo===2?`<button type="button" class="tf-principal" data-tf="arrive">Cheguei ao local</button>`
    :`<button type="button" class="tf-principal" data-tf="complete">Registar ${acao}</button>`;
  openPlatformRecordDrawer(`${rec?"Recolha":"Entrega"} ${cod}`,`Serviço ${job.code||""}`.trim(),`<div class="tf" data-id="${esc(id)}">
    <ol class="tf-passos" aria-label="Passos do serviço">${["A caminho","No local","Registado"].map((x,i)=>`<li class="${i+1<passo?"feito":i+1===passo?"atual":""}">${x}</li>`).join("")}</ol>
    <section class="tf-quem"><strong>${esc(nome)}</strong><div class="tf-atalhos">${tel?`<a class="tf-atalho" href="tel:${esc(String(tel).replace(/[^\d+]/g,""))}">Ligar</a>`:""}
      ${morada?`<a class="tf-atalho" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(morada)}">Navegar</a>`:""}</div></section>
    <dl class="tf-dados"><div><dt>Onde</dt><dd>${esc(morada||"Morada por indicar")}</dd></div><div><dt>Quando</dt><dd>${esc(quando(job.scheduledAt))}</dd></div>
      ${job.vehicle?`<div><dt>Viatura</dt><dd>${esc(job.vehicle)}</dd></div>`:""}${t?.encomenda?.quantidade?`<div><dt>Volumes</dt><dd>${esc(t.encomenda.quantidade)}</dd></div>`:""}
      ${job.instructions?`<div class="tf-notas"><dt>Notas</dt><dd>${esc(job.instructions)}</dd></div>`:""}</dl>
    <div class="tf-acoes">${principal}<button type="button" class="tf-secundaria" data-tf="incident">Comunicar um problema</button></div></div>`);
  const dw=document.getElementById("platformRecordDrawer");dw?.classList.add("fullscreen-analysis");
  dw?.querySelector(".tf")?.addEventListener("click",async ev=>{const b=ev.target.closest("[data-tf]");if(!b)return;const a=b.dataset.tf;b.disabled=true;const txt=b.textContent;
    if(a==="start")b.textContent="A obter a localização…";
    try{await Promise.resolve(window.fieldJobAction(id,a))}finally{b.disabled=false;b.textContent=txt}
    if(a==="start"&&document.getElementById("platformRecordDrawer")?.classList.contains("open"))abrir(id)})}
window.addEventListener("load",()=>setTimeout(()=>{const f=window.openFieldTask;if(typeof f!=="function"||f.__simples)return;
  const g=function(id){if(!noServidor())return f.apply(this,arguments);abrir(id)};Object.assign(g,f);g.__simples=true;window.openFieldTask=g},80));
})();
