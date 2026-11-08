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

/* v121: os armazéns da empresa vêm do servidor (tabela «armazens»), para qualquer funcionário e em qualquer navegador.
   Se o servidor ainda não os tem mas este navegador tem, e o utilizador pode gerir armazéns, envia-os (corrige gravações antigas). */
let doServidorEm=0;
async function carregarDoServidor(forcar){if(!P()?.online?.()||(!forcar&&Date.now()-doServidorEm<120000))return false;doServidorEm=Date.now();
  try{const emp=await P().minhaEmpresa();if(!emp?.empresa_id)return false;const sb=await P().sb();
    const{data,error}=await sb.from("armazens").select("id,nome,morada,latitude,longitude").eq("empresa_id",emp.empresa_id).eq("ativo",true).order("nome");if(error)return false;
    if(!data?.length){const locais=ler().warehouses;if(Array.isArray(locais)&&locais.some(w=>w?.address)&&["admin_empresa","armazem"].includes(emp.papel))localizar();return false}
    const s=ler();s.warehouses=data.map(a=>a.latitude!=null?{id:a.id,name:a.nome,address:a.morada,lat:+a.latitude,lon:+a.longitude,geoMorada:a.morada}:{id:a.id,name:a.nome,address:a.morada});
    localStorage.setItem(chave(),JSON.stringify(s));D()?.limparCache?.();return true}catch(_){return false}}

/* simulação direta: armazém mais próximo por estrada; sem armazéns, mede até à origem do envio (e diz isso) */
let pedido=0;
window.updateProviderDirectNearestWarehouse=async function(){const pickup=providerDirectValue("providerDirectPickup")==="yes",morada=providerDirectValue("providerDirectPickupAddress"),
  input=document.getElementById("providerDirectDistance"),status=document.getElementById("providerDirectPickupPricingStatus");let ws=getProviderWarehouses();
  const limpar=()=>{if(input){input.value="0";delete input.dataset.warehouseId;delete input.dataset.warehouseName;delete input.dataset.semArmazem}updateProviderDirectPickupStatus();updateProviderDirectTotals()};
  if(!pickup||!morada)return limpar();const id=++pedido;if(status){status.textContent="A medir a distância por estrada…";status.className="provider-pickup-pricing-status"}
  if(!ws.length&&await carregarDoServidor(true)){if(id!==pedido)return;ws=getProviderWarehouses()}
  try{const a=await obterCoordenadas(morada);if(id!==pedido)return;
    if(!ws.length){const origem=providerDirectValue("providerDirectOrigin");if(!origem)return limpar();const b=await obterCoordenadas(origem);if(id!==pedido)return;
      const e=D()?await D().estrada(a,b):{km:Math.round(calcularDistanciaKm(a,b)*13)/10,metodo:"aproximada"};if(id!==pedido)return;
      input.value=String(e.km);delete input.dataset.warehouseId;input.dataset.semArmazem="1";input.dataset.warehouseName=`${origem}, ${e.km.toLocaleString("pt-PT")} km ${e.metodo==="estrada"?"por estrada":"aproximados"}`;
      updateProviderDirectPickupStatus();updateProviderDirectTotals();return}
    const pts=[];for(const w of ws){let c=w.lat!=null?{lat:+w.lat,lon:+w.lon}:null;if(!c){try{c=await obterCoordenadas(w.address)}catch(_){}}if(c)pts.push({w,...c})}
    if(id!==pedido)return;if(!pts.length)throw new Error("armazéns");const kms=D()?await D().estradaVarios(a,pts):pts.map(()=>null);if(id!==pedido)return;
    const lista=pts.map((p,i)=>({w:p.w,km:kms[i]!=null?kms[i]:Math.round(D()?D().linha(a,p)*13:calcularDistanciaKm(a,p)*10)/10,aprox:kms[i]==null})).sort((x,y)=>x.km-y.km),m=lista[0];
    input.value=String(m.km);delete input.dataset.semArmazem;input.dataset.warehouseId=m.w.id;input.dataset.warehouseName=`${m.w.name} (${m.km.toLocaleString("pt-PT")} km ${m.aprox?"aproximados":"por estrada"})`;
    updateProviderDirectPickupStatus();updateProviderDirectTotals()}
  catch(e){if(id!==pedido)return;limpar();if(status){status.textContent=/armaz/.test(e.message)?"Não encontrámos os armazéns no mapa. Corrija as moradas em Configurações.":"Não encontrámos a morada de recolha. Experimente só o código postal e a localidade.";status.className="provider-pickup-pricing-status is-warning"}}};

/* Configurações: mostrar os armazéns guardados no servidor, mesmo noutro navegador */
function ligarConfig(){const r=window.renderProviderSettings;if(typeof r!=="function"||r.__armazens)return;const novo=function(){const x=r.apply(this,arguments);carregarDoServidor(true).then(ok=>{if(ok&&document.getElementById("providerWarehouseRows"))r.apply(this,arguments)});return x};novo.__armazens=1;window.renderProviderSettings=novo}

/* Configurações: botão «Validar morada» em cada armazém — localiza no mapa, mostra onde ficou e guarda as coordenadas */
async function validar(row){const btn=row.querySelector(".arm-validar"),est=row.querySelector(".arm-estado"),morada=row.querySelector(".provider-warehouse-address")?.value.trim();
  const dizer=(t,c)=>{est.className="arm-estado"+(c?" "+c:"");est.innerHTML=t};delete row.dataset.lat;delete row.dataset.lon;
  if(!morada){dizer("Escreva a morada completa: rua, número, código postal e localidade.","erro");row.querySelector(".provider-warehouse-address")?.focus();return}
  btn.disabled=true;dizer("A procurar a morada no mapa…");
  try{const c=await obterCoordenadas(morada);row.dataset.lat=c.lat;row.dataset.lon=c.lon;
    dizer(`Morada encontrada no mapa (${(+c.lat).toFixed(5)}, ${(+c.lon).toFixed(5)}). <a href="https://www.openstreetmap.org/?mlat=${c.lat}&mlon=${c.lon}#map=16/${c.lat}/${c.lon}" target="_blank" rel="noopener noreferrer">Confirmar no mapa</a>. Carregue em «Guardar configurações» para a usar nas simulações.`,"ok")}
  catch(_){dizer("Não encontrámos esta morada. Escreva a rua, o número, o código postal e a localidade (ex.: Rua Dom Francisco de Melo e Noronha 15, 2810-221 Almada).","erro")}
  finally{btn.disabled=false}}
function enriquecer(row,data){if(!row||row.querySelector(".arm-validar"))return;const b=document.createElement("button");b.type="button";b.className="btn-secondary arm-validar";b.textContent="Validar morada";b.onclick=()=>validar(row);
  const apagar=row.querySelector(".btn-danger");row.insertBefore(b,apagar);const est=document.createElement("p");est.className="arm-estado";est.setAttribute("role","status");
  est.textContent=data?.lat!=null&&data.geoMorada===data.address?"Morada validada no mapa.":data?.address?"Morada por validar.":"Escreva a morada e carregue em «Validar morada».";if(data?.lat!=null&&data.geoMorada===data.address)est.classList.add("ok");row.appendChild(est);
  row.querySelector(".provider-warehouse-address")?.addEventListener("input",()=>{delete row.dataset.lat;delete row.dataset.lon;est.className="arm-estado";est.textContent="Morada alterada: carregue em «Validar morada»."})}
function ligarLinhas(){const a=window.addProviderWarehouseRow;if(typeof a!=="function"||a.__armazens)return;const novo=function(data={}){const r=a.apply(this,arguments);enriquecer(document.querySelector("#providerWarehouseRows .provider-warehouse-row:last-child"),data);return r};novo.__armazens=1;window.addProviderWarehouseRow=novo}

function iniciar(){ligar();ligarConfig();ligarLinhas();document.addEventListener("input",e=>{if(e.target?.id==="providerDirectOrigin"&&!getProviderWarehouses().length&&typeof scheduleProviderDirectNearestWarehouse==="function")scheduleProviderDirectNearestWarehouse()})}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
window.elologArmazens={localizar,carregarDoServidor};
})();
