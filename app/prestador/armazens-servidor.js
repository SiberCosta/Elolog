/* Elolog — armazéns do prestador e distância da recolha (v116).
   1) Ao guardar as Configurações, localiza cada armazém (coordenadas) e, com servidor, grava-os na tabela «armazens»
      (guardar_armazens): é daí que o simulador do cliente mede a distância. Mostra quais não foram encontrados.
   2) Na simulação direta, a distância ao armazém mais próximo passa a ser por estrada (comum/distancia.js). */
(function(){"use strict";
const P=()=>window.elologProducao,D=()=>window.elologDistancia,esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const chave=()=>"elolog_provider_settings_"+(currentProviderCompanyName()||"default");
const ler=()=>{try{return JSON.parse(localStorage.getItem(chave())||"{}")}catch(_){return{}}};

async function localizar(){const s=ler(),l=Array.isArray(s.warehouses)?s.warehouses:[],fb=document.getElementById("providerSettingsFeedback");if(!l.length)return;
  const info=t=>{if(fb)fb.insertAdjacentHTML("beforeend",t)};const falhou=[];
  for(const w of l){if(w.lat!=null&&w.geoMorada===w.address)continue;try{const c=await obterCoordenadas(w.address);w.lat=c.lat;w.lon=c.lon;w.geoMorada=w.address}catch(_){delete w.lat;delete w.lon;falhou.push(w.name)}}
  localStorage.setItem(chave(),JSON.stringify({...s,warehouses:l}));D()?.limparCache?.();
  let gravado="";if(P()?.online?.()){try{const sb=await P().sb();const{error}=await sb.rpc("guardar_armazens",{p_armazens:l.map(w=>({nome:w.name,morada:w.address,lat:w.lat??null,lon:w.lon??null}))});
      if(error)throw error;gravado=" Guardados no servidor: o simulador dos clientes mede a distância a partir deles."}catch(e){gravado=` Não foi possível gravar no servidor: ${esc(String(e.message||e).replace(/^.*?ERROR:\s*/,""))}`}}
  info(falhou.length?`<div class="sim-warning" role="status">Não encontrámos no mapa: ${esc(falhou.join(", "))}. Corrija a morada (rua, número, código postal e localidade).${gravado}</div>`
    :`<div class="sim-success" role="status">${l.length} armazém(ns) localizado(s) no mapa.${gravado}</div>`)}

function ligar(){const guardar=window.saveProviderSettings;if(typeof guardar==="function"&&!guardar.__armazens){const novo=function(){const r=guardar.apply(this,arguments);setTimeout(localizar,400);return r};novo.__armazens=1;window.saveProviderSettings=novo}}

/* simulação direta: armazém mais próximo por estrada */
let pedido=0;
window.updateProviderDirectNearestWarehouse=async function(){const pickup=providerDirectValue("providerDirectPickup")==="yes",morada=providerDirectValue("providerDirectPickupAddress"),
  input=document.getElementById("providerDirectDistance"),status=document.getElementById("providerDirectPickupPricingStatus"),ws=getProviderWarehouses();
  const limpar=()=>{if(input){input.value="0";delete input.dataset.warehouseId;delete input.dataset.warehouseName}updateProviderDirectPickupStatus();updateProviderDirectTotals()};
  if(!pickup||!morada||!ws.length)return limpar();const id=++pedido;if(status){status.textContent="A medir a distância por estrada até ao armazém mais próximo…";status.className="provider-pickup-pricing-status"}
  try{const a=await obterCoordenadas(morada);if(id!==pedido)return;const pts=[];for(const w of ws){let c=w.lat!=null?{lat:+w.lat,lon:+w.lon}:null;if(!c){try{c=await obterCoordenadas(w.address)}catch(_){}}if(c)pts.push({w,...c})}
    if(id!==pedido)return;if(!pts.length)throw new Error("armazéns");const kms=D()?await D().estradaVarios(a,pts):pts.map(()=>null);if(id!==pedido)return;
    const lista=pts.map((p,i)=>({w:p.w,km:kms[i]!=null?kms[i]:Math.round(D()?D().linha(a,p)*13:calcularDistanciaKm(a,p)*10)/10,aprox:kms[i]==null})).sort((x,y)=>x.km-y.km),m=lista[0];
    input.value=String(m.km);input.dataset.warehouseId=m.w.id;input.dataset.warehouseName=`${m.w.name} (${m.km.toLocaleString("pt-PT")} km ${m.aprox?"aproximados":"por estrada"})`;
    updateProviderDirectPickupStatus();updateProviderDirectTotals()}
  catch(e){if(id!==pedido)return;limpar();if(status){status.textContent=/armaz/.test(e.message)?"Não encontrámos os armazéns no mapa. Corrija as moradas em Configurações.":"Não encontrámos a morada de recolha. Experimente só o código postal e a localidade.";status.className="provider-pickup-pricing-status is-warning"}}};

if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
window.elologArmazens={localizar};
})();
