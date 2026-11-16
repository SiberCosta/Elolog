/* Elolog — «Programar recolhas» só com o que falta agendar (v156).
   Uma encomenda está «por agendar» quando ainda não tem recolha com responsável. Assim que a recolha é agendada
   (operador escolhido), sai desta lista e do contador do menu e passa a acompanhar-se em «Recolhas». */
(function(){"use strict";
const norm=v=>String(v||"").normalize("NFD").replace(/[̀-ͯ]/g,"").toLowerCase();
function servicoAtivo(o){let l=[];try{l=typeof getFieldJobs==="function"?getFieldJobs():[]}catch(_){}
  return l.some(j=>String(j.operationId)===String(o.id)&&j.type!=="Entrega"&&j.operatorId&&!/conclu|cancel/i.test(j.status||""))}
window.elologPorAgendar=function(o){const s=norm(o?.status||o?.stage);if(!s.includes("recol")&&!s.includes("agend"))return false;
  if(/cancel|rejeit|anulad/.test(s))return false;return !servicoAtivo(o)};
function limpar(){const box=document.getElementById("providerRecolhaList");if(!box)return;let ficaram=0;
  box.querySelectorAll(".admin-record-row").forEach(row=>{const id=row.querySelector("strong")?.textContent?.trim(),o=(typeof operations!=="undefined"?operations:[]).find(x=>String(x.id)===id);
    if(o&&!window.elologPorAgendar(o))row.remove();else ficaram++});
  if(!ficaram&&!box.querySelector(".provider-order-empty,.pf-vazio"))box.insertAdjacentHTML("beforeend",`<div class="provider-order-empty">Todas as recolhas já estão agendadas. Acompanhe-as em «Recolhas».<div style="margin-top:12px"><button type="button" class="btn-secondary" onclick="showProviderFieldPage('pickups')">Abrir «Recolhas»</button></div></div>`)}
window.addEventListener("load",()=>{const f=window.renderProviderExtendedPages;if(typeof f!=="function"||f.__porAgendar)return;
  const g=function(page){const r=f.apply(this,arguments);if(page==="providerRecolha")limpar();return r};Object.assign(g,f);g.__porAgendar=true;window.renderProviderExtendedPages=g;
  setTimeout(()=>{try{window.elologNavegacao?.atualizar?.()}catch(_){}},800)});
})();
