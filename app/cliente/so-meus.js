/* Elolog — o cliente só vê o que é dele (v154).
   No mesmo aparelho podem ficar guardados dados de outras contas (por exemplo, testes como prestador). Numa sessão real
   de cliente, as encomendas que não vieram do servidor para esta conta e os pagamentos delas saem da vista — não são
   apagados: voltam ao guardar e ao sair. Assim, painel, menu, encomendas e pagamentos mostram só os dados do cliente. */
(function(){"use strict";
const S=()=>window.ELOLogServidor;let guardadasOps=[],guardadosPag=[];
const u=()=>typeof currentUser!=="undefined"?currentUser:null;
const real=()=>u()?.role==="cliente"&&u()?.authenticatedBy!=="local-demo"&&!!S()?.ativo?.();
/** a encomenda pertence ao cliente com sessão? */
window.elologDoCliente=function(o){if(!o)return false;if(real())return o.servidor===true;const c=u();return !o.client||o.client===c?.name||o.clientEmail===c?.email};
function filtrar(){if(!real()||typeof operations==="undefined"||typeof payments==="undefined")return;
  const fora=operations.filter(o=>!window.elologDoCliente(o));if(fora.length){guardadasOps.push(...fora);for(const o of fora)operations.splice(operations.indexOf(o),1)}
  const meus=new Set(operations.map(o=>String(o.id))),pf=payments.filter(p=>!meus.has(String(p.operationId)));
  if(pf.length){guardadosPag.push(...pf);for(const p of pf)payments.splice(payments.indexOf(p),1)}}
function repor(){if(typeof operations==="undefined")return;const jo=new Set(operations),jp=new Set(payments);
  guardadasOps.forEach(o=>{if(!jo.has(o)&&!operations.some(x=>x.id===o.id&&x.client===o.client))operations.push(o)});
  guardadosPag.forEach(p=>{if(!jp.has(p)&&!payments.some(x=>x.id===p.id))payments.push(p)});guardadasOps=[];guardadosPag=[]}
window.addEventListener("load",()=>{
  const sa=window.saveAll;if(typeof sa==="function"){const g=function(){if(!guardadasOps.length&&!guardadosPag.length)return sa.apply(this,arguments);repor();try{return sa.apply(this,arguments)}finally{filtrar()}};Object.assign(g,sa);window.saveAll=g}
  ["renderClientDashboard","renderClientTracking","renderPayments","renderClientPayments"].forEach(n=>{const f=window[n];if(typeof f!=="function")return;const g=function(){filtrar();return f.apply(this,arguments)};Object.assign(g,f);window[n]=g});
  const sa2=window.startApp;if(typeof sa2==="function"){const g=async function(){const r=await sa2.apply(this,arguments);filtrar();return r};Object.assign(g,sa2);window.startApp=g}
  const lo=window.logout;if(typeof lo==="function"){const g=function(){repor();return lo.apply(this,arguments)};Object.assign(g,lo);window.logout=g}
  setTimeout(filtrar,1200)});
window.addEventListener("storage",()=>setTimeout(filtrar,50));
window.elologSoMeus={filtrar,repor};
})();
