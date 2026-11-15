/* Elolog — simulação começada no site público (v148).
   Quando o cliente chega à área de cliente vindo do simulador público, abre «Nova simulação» com a rota, a carga, os volumes
   e o destinatário já preenchidos. Os dados do site só servem para isto e apagam-se logo a seguir (ou ao fim de 1 dia). */
(function(){"use strict";
const CHAVE="simulacao_site_eloLog",$=id=>document.getElementById(id);
const pronto=()=>typeof currentUser!=="undefined"&&currentUser?.role==="cliente";
function por(id,v){const e=$(id);if(!e||v==null||v==="")return;if(e.tagName==="SELECT"&&![...e.options].some(o=>o.value===v||o.text===v))return;e.value=v;e.dispatchEvent(new Event("input",{bubbles:true}));e.dispatchEvent(new Event("change",{bubbles:true}))}
function aplicar(){if(!pronto())return false;let d=null;try{d=JSON.parse(localStorage.getItem(CHAVE)||"null")}catch(_){}if(!d)return false;
  localStorage.removeItem(CHAVE);if(Date.now()-Number(d.em||0)>864e5)return false;
  if(typeof showPage==="function")showPage("clientSimulation",$("menuSimulation"));
  setTimeout(()=>{por("clientSimOrigin",d.origem);por("clientSimDestination",d.destino);por("clientSimCargo",d.carga);por("clientSimDate",d.data);
    por("clientSimPickup",d.recolha==="nao"?"nao":"sim");por("clientSimPickupLocation",d.moradaRecolha);por("clientSimDeclaredPrice",d.valorDeclarado);por("clientSimObservations",d.observacoes);
    const dest=d.destinatario||{};por("destinatario-nome",dest.nome);por("destinatario-nif",dest.nif);por("destinatario-telefone",dest.telefone);por("destinatario-email",dest.email);por("destinatario-morada",dest.morada);
    if(Array.isArray(d.volumes)&&d.volumes.length&&typeof adicionarVolumeCliente==="function"){const box=$("clientSimVolumes");if(box)box.innerHTML="";
      d.volumes.slice(0,50).forEach(v=>adicionarVolumeCliente(v.qtd||1,v.comp||0,v.larg||0,v.alt||0,String(v.descricao||"").replace(/[<>"]/g,""),v.peso||0))}
    if(typeof showPlatformNotice==="function")showPlatformNotice("Trouxemos a simulação que fez no site. Confira os dados e avance para ver os preços.","info")},150);return true}
const conf=window.configureRole;if(typeof conf==="function"&&!conf.__site){const n=function(){const r=conf.apply(this,arguments);setTimeout(aplicar,400);return r};n.__site=1;window.configureRole=n}
window.addEventListener("load",()=>setTimeout(aplicar,1500));
window.elologSimulacaoSite={aplicar};
})();
