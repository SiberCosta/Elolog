/* Elolog — encomendas criadas pelo prestador (v128).
   1) A tarifa de recolha conta por quilómetro: valor × km até ao armazém mais próximo, com o preço mínimo da tarifa como piso
      (a mesma regra do motor do servidor). Sem morada de recolha não há km e a recolha fica a 0 € até ser indicada.
   2) Com servidor, a encomenda criada em «Simular e criar encomenda» é gravada no servidor (criar_encomenda_prestador):
      entra em «Aprovar pedidos» e aparece a todos os funcionários da empresa. As encomendas antigas que ficaram só neste
      navegador são enviadas uma vez ao entrar (o código local evita duplicados). */
(function(){"use strict";
const P=()=>window.elologProducao,eur=(n,m)=>Number(n||0).toLocaleString("pt-PT",{style:"currency",currency:m||"EUR"});
const kmAtual=()=>{const i=document.getElementById("providerDirectDistance");return Math.max(0,Number(i?.value||0))};
const temMorada=()=>String(providerDirectValue("providerDirectPickupAddress")||"").trim().length>0;
const num=v=>{const n=Number(String(v??"").replace(",","."));return Number.isFinite(n)?n:0};

/* 1) recolha por km */
function taxaRecolha(){const t=typeof providerDirectPickupTariff==="function"?providerDirectPickupTariff():null;if(!t)return 0;
  if(!temMorada())return 0;const km=kmAtual(),valor=num(t.value),minimo=num(t.minimumPrice);return Math.round(Math.max(minimo,valor*km)*100)/100}
function detalhe(){const t=typeof providerDirectPickupTariff==="function"?providerDirectPickupTariff():null;if(!t)return"";
  if(!temMorada())return"Indique a morada de recolha para calcular os quilómetros.";
  const km=kmAtual(),valor=num(t.value),minimo=num(t.minimumPrice),bruto=valor*km;
  const conta=`${eur(valor,t.currency)}/km × ${km.toLocaleString("pt-PT",{maximumFractionDigits:1})} km = ${eur(bruto,t.currency)}`;
  return bruto<minimo?`${conta}; aplica-se o mínimo da tarifa: ${eur(minimo,t.currency)}.`:conta+"."}
function ligarRecolha(){window.providerDirectPickupFee=taxaRecolha;
  const u=window.updateProviderDirectPickupStatus;if(typeof u!=="function"||u.__km)return;
  const novo=function(){const r=u.apply(this,arguments);const st=document.getElementById("providerDirectPickupPricingStatus");
    if(st&&providerDirectValue("providerDirectPickup")==="yes"){st.querySelector(".rec-km")?.remove();const txt=detalhe();
      if(txt){const s=document.createElement("span");s.className="rec-km";s.style.cssText="display:block;margin-top:4px;font-weight:600";s.textContent="Recolha por km: "+txt;st.appendChild(s)}}return r};
  novo.__km=1;Object.keys(u).forEach(k=>{if(k!=="__km")novo[k]=u[k]});window.updateProviderDirectPickupStatus=novo}

/* 2) gravar no servidor */
function paraServidor(o,extra){const v=Array.isArray(o.volumes)?o.volumes:[];
  return{id_local:String(o.id),cliente_nome:o.client||o.senderName||"",cliente_nif:o.clientNif||"",origem:o.origin||"",destino:o.destination||"",tipo_carga:o.cargo||"",
    descricao:o.goods||"",quantidade:num(o.quantity)||null,peso_kg:num(o.weight)||null,volume_m3:num(o.volume)||null,
    volumes:v.slice(0,200).map(x=>({descricao:x.description||x.descricao||"",quantidade:num(x.quantity),peso:num(x.weight),comprimento:num(x.length),largura:num(x.width),altura:num(x.height),valor:num(x.lineValue)})),
    remetente:{nome:o.senderName||o.client||"",telefone:o.senderPhone||"",email:o.senderEmail||"",morada:o.senderAddress||""},
    destinatario:{nome:o.recipientName||"",telefone:o.recipientPhone||"",email:o.recipientEmail||"",nif:o.recipientNif||"",morada:o.deliveryAddress||""},
    recolha:o.pickupRequested!==false,morada_recolha:o.pickupRequested===false?"":(o.pickupAddress||""),data_prevista:o.date||null,
    valor_declarado:num(o.declaredPrice)||null,observacoes:o.notes||"",preco_total:num(o.estimatedPrice),
    km_recolha:o.pickupRequested===false?null:num(o.distance),recolha_valor:extra?.recolha??o.pickupFee??null,recolha_tarifa:extra?.tarifa??o.pickupTariff??null,carga_valor:extra?.carga??o.cargoValue??null}}
const erroTexto=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
async function enviar(o,extra){if(!o||o.servidor?.id||!P()?.online?.())return null;
  const sb=await P().sb();const{data,error}=await sb.rpc("criar_encomenda_prestador",{p:paraServidor(o,extra)});if(error)throw error;
  o.servidor={id:data.id,codigo:data.codigo};if(extra){o.pickupFee=extra.recolha;o.pickupTariff=extra.tarifa;o.cargoValue=extra.carga}
  if(typeof saveAll==="function")saveAll();return data}
/* v136: fotografias de anomalias e documentos anexos seguem para o armazenamento do servidor, ligados à encomenda (só funcionários da empresa os veem) */
function ficheiro(x){const m=/^data:([^;,]+)?(;base64)?,(.*)$/s.exec(String(x?.data||""));if(!m)return null;const bin=m[2]?atob(m[3]):decodeURIComponent(m[3]),u=new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return new File([u],x.name||"anexo",{type:x.type||m[1]||"application/octet-stream"})}
async function anexos(o){if(!o?.servidor?.codigo||!P()?.enviarDocumento)return 0;const lista=[...(o.anomalyPhotos||[]),...(o.extraDocuments||[])].filter(x=>x&&x.data&&!x.noServidor);let n=0,falhou=0;
  for(const x of lista){try{const f=ficheiro(x);if(!f)continue;await P().enviarDocumento(f,{encomenda:o.servidor.codigo,categoria:"operacional",visibilidade:"interna"});x.noServidor=true;n++}catch(e){falhou++;console.warn("Anexo não enviado:",x.name,erroTexto(e))}}
  if(n&&typeof saveAll==="function")saveAll();if(falhou)avisar(`${falhou} anexo(s) da encomenda ${o.servidor.codigo} ficaram só neste navegador. Tentamos outra vez quando voltar a entrar.`,"warning");return n}
function avisar(txt,tipo){if(typeof showPlatformNotice==="function")showPlatformNotice(txt,tipo);else console.warn(txt)}
function depois(o,extra){if(!o||!P()?.online?.())return;
  enviar(o,extra).then(async d=>{if(!d)return;avisar(`Encomenda ${d.codigo} gravada no servidor: já aparece a todos os funcionários em «Aprovar pedidos».`,"success");window.elologAtualizarCotacoes?.();const n=await anexos(o);if(n)avisar(`${n} anexo(s) guardado(s) no servidor com a encomenda ${d.codigo}.`,"success")})
    .catch(e=>avisar(`A encomenda ${o.id} ficou só neste navegador: ${erroTexto(e)} Volte a entrar para tentar outra vez.`,"warning"))}
function envolver(nome){const f=window[nome];if(typeof f!=="function"||f.__servidor)return;
  const novo=function(){const antes=operations[0],t=typeof providerDirectPickupTariff==="function"?providerDirectPickupTariff():null,d=providerDirectSimulationData;
    const extra=d?{recolha:d.pickup?taxaRecolha():0,tarifa:t?.name||null,carga:num(d.cargoValue)}:null;
    const r=f.apply(this,arguments);const o=operations[0];if(o&&o!==antes)depois(o,extra);return r};
  novo.__servidor=1;window[nome]=novo}

/* encomendas antigas desta empresa que ficaram só no navegador */
let recuperado=false;
async function recuperar(){if(recuperado||!P()?.online?.()||typeof operations==="undefined")return;
  const emp=await P().minhaEmpresa?.().catch(()=>null);if(!emp?.empresa_id||!["admin_empresa","operador","operador_terreno"].includes(emp.papel))return;recuperado=true;
  const nome=typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"";
  const locais=operations.filter(o=>o&&!o.servidor?.id&&o.createdByRole&&/aprova/i.test(String(o.status||o.stage||""))&&(!nome||!o.provider||o.provider===nome)).slice(0,30);
  let ok=0;for(const o of locais){try{if(await enviar(o))ok++}catch(e){console.warn("Encomenda local não enviada:",o.id,erroTexto(e))}}
  for(const o of operations.filter(x=>x?.servidor?.codigo&&[...(x.anomalyPhotos||[]),...(x.extraDocuments||[])].some(y=>y?.data&&!y.noServidor)).slice(0,10)){try{await anexos(o)}catch(_){}}
  if(ok){avisar(`${ok} encomenda(s) que estavam só neste navegador foram gravadas no servidor e já aparecem aos colegas.`,"success");window.elologAtualizarCotacoes?.()}}

function arrancar(){ligarRecolha();envolver("createProviderDirectOrder");envolver("createOrderFromReviewedSimulation")}
arrancar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arrancar);
window.addEventListener("load",()=>{arrancar();setTimeout(()=>recuperar().catch(()=>{}),4000)});
setInterval(()=>{if(!recuperado)recuperar().catch(()=>{})},60000);
window.elologEncomendasServidor={taxaRecolha,detalhe,paraServidor,enviar,recuperar,anexos};
})();
