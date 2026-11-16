/* Elolog — encomendas iguais em todos os aparelhos (v129).
   1) Encomenda rejeitada ou cancelada deixa de contar como ativa: o pagamento pendente sai de «Por receber» (fica guardado
      em «elolog_pagamentos_anulados»), deixa de aparecer em pendentes e alertas, e o Fluxo mostra «Encomenda cancelada».
      Corrige também as encomendas que já tinham sido rejeitadas antes desta versão.
   2) Com servidor: rejeitar aqui também cancela a encomenda no servidor; e as encomendas da empresa que estão no servidor
      passam a aparecer no painel, nas listas e no quadro de qualquer aparelho (telemóvel incluído), com a etapa do servidor. */
(function(){"use strict";
const P=()=>window.elologProducao,FECHADA=/rejeit|cancel|anulad/i;
const ETAPA={aprovacao:"Aprovação",agendamento:"Recolha por atribuir",recolha:"Recolha",armazenamento:"Armazém",expedicao:"Expedição",em_transito:"Em trânsito",
  destino:"No destino",disponivel:"Disponível",levantada:"Levantada",entregue:"Entregue",cancelada:"Cancelada"};
const ler=k=>{try{return JSON.parse(localStorage.getItem(k)||"[]")}catch(_){return[]}};
const redesenhar=()=>{["renderProviderDashboardForCompany","renderProviderAprovacao","renderProviderPagamentos","renderProviderOrderList"].forEach(f=>{try{window[f]?.()}catch(_){}})};

/* 1) pagamentos de encomendas fechadas saem da lista ativa */
function arquivarPagamentos(){if(typeof payments==="undefined"||typeof operations==="undefined")return 0;
  const fechadas=new Set(operations.filter(o=>FECHADA.test(String(o.status||o.stage||""))).map(o=>String(o.id)));if(!fechadas.size)return 0;
  const sair=payments.filter(p=>p.status!=="Pago"&&fechadas.has(String(p.operationId)));if(!sair.length)return 0;
  const arq=ler("elolog_pagamentos_anulados");sair.forEach(p=>{arq.unshift({...p,status:"Anulado",anuladoEm:new Date().toISOString()});payments.splice(payments.indexOf(p),1)});
  try{localStorage.setItem("elolog_pagamentos_anulados",JSON.stringify(arq.slice(0,500)))}catch(_){}
  if(typeof saveAll==="function")saveAll();return sair.length}

async function cancelarNoServidor(o,nota){if(!o?.servidor?.id||!P()?.online?.())return;
  try{const sb=await P().sb();const{error}=await sb.rpc("transitar_encomenda",{p_encomenda:o.servidor.id,p_para:"cancelada",p_nota:nota||"Rejeitada pelo prestador."});if(error)throw error}
  catch(e){window.showPlatformNotice?.(`A encomenda ${o.id} foi rejeitada aqui, mas o servidor não aceitou: ${String(e?.message||e).replace(/^.*?ERROR:\s*/,"")}`,"warning")}}

function ligarDecisao(){const f=window.submitProviderApprovalDecision;if(typeof f!=="function"||f.__fecho)return;
  const novo=function(){const id=document.getElementById("providerDecisionOrderId")?.value,nota=document.getElementById("providerDecisionNote")?.value.trim();
    const r=f.apply(this,arguments);const o=typeof operations!=="undefined"?operations.find(x=>String(x.id)===String(id)):null;
    if(o&&FECHADA.test(String(o.status||""))){if(arquivarPagamentos())redesenhar();cancelarNoServidor(o,nota)}return r};
  novo.__fecho=1;window.submitProviderApprovalDecision=novo}

/* 2) encomendas do servidor em todos os aparelhos */
let aSincronizar=false;
async function sincronizar(){if(aSincronizar||!P()?.online?.()||typeof operations==="undefined")return;aSincronizar=true;
  try{const emp=await P().minhaEmpresa?.().catch(()=>null);if(!emp?.empresa_id)return;const sb=await P().sb();
    const{data,error}=await sb.from("encomendas").select("id,codigo,estado,simulacao_id,simulacoes(codigo),cliente_nome,clientes(nome),origem,destino,tipo_carga,descricao,quantidade,peso_kg,volume_m3,preco_total,data_prevista,created_at,morada_recolha,remetente,destinatario,chegada_prevista,partida_prevista,navio")
      .eq("empresa_id",emp.empresa_id).order("created_at",{ascending:false}).limit(200);if(error||!data)return;
    const empresa=typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"";let mudou=false;
    for(const r of data){const etapa=ETAPA[r.estado]||r.estado,anterior=r.simulacoes?.codigo||"";
      /* v155: a encomenda nascida de uma simulação substitui o registo da simulação (fica o número anterior guardado) */
      if(anterior){for(let i=operations.length-1;i>=0;i--){if(String(operations[i].id)===anterior){operations.splice(i,1);mudou=true}}}
      const o=operations.find(x=>x.servidor?.id===r.id||String(x.id)===String(r.codigo));
      if(o){o.servidor=o.servidor||{id:r.id,codigo:r.codigo};if(anterior&&o.simulationId!==anterior){o.simulationId=anterior;mudou=true}
        if(r.estado==="cancelada"&&!FECHADA.test(String(o.status||""))){o.status=o.stage="Cancelada";o.updatedAt=new Date().toISOString();mudou=true}
        else if((o.doServidor||o.servidor?.id===r.id)&&o.status!==etapa){o.status=o.stage=etapa;o.arrivalDate=r.chegada_prevista||o.arrivalDate;mudou=true}
        if(r.chegada_prevista&&o.arrivalDate!==r.chegada_prevista){o.arrivalDate=r.chegada_prevista;o.departureDate=r.partida_prevista;o.vessel=r.navio;mudou=true}continue}
      const rem=r.remetente||{},dest=r.destinatario||{};
      operations.push({id:r.codigo,simulationId:anterior||undefined,servidor:{id:r.id,codigo:r.codigo},doServidor:true,client:r.clientes?.nome||r.cliente_nome||rem.nome||"Cliente",origin:r.origem,destination:r.destino,
        cargo:r.tipo_carga,goods:r.descricao,quantity:r.quantidade,weight:Number(r.peso_kg||0),volume:Number(r.volume_m3||0),estimatedPrice:Number(r.preco_total||0),date:r.data_prevista,
        createdAt:r.created_at,status:etapa,stage:etapa,pickupAddress:r.morada_recolha||"",senderName:rem.nome||"",senderPhone:rem.telefone||"",recipientName:dest.nome||"",
        recipientPhone:dest.telefone||"",deliveryAddress:dest.morada||"",provider:empresa,history:[],arrivalDate:r.chegada_prevista||null,departureDate:r.partida_prevista||null,vessel:r.navio||""});mudou=true}
    if(pagamentosServidor(data,await lerPagos(sb,emp.empresa_id)))mudou=true;
    if(mudou){arquivarPagamentos();if(typeof saveAll==="function")saveAll();redesenhar()}}
  catch(e){console.warn("Sincronização das encomendas:",e)}finally{aSincronizar=false}}

/* v145: «Por receber» igual em todos os aparelhos: cada encomenda do servidor ainda aberta tem o seu pagamento pendente,
   com o valor do servidor menos o que já está pago no servidor (antes só existia no aparelho de quem criou a encomenda). */
async function lerPagos(sb,emp){try{const{data}=await sb.from("pagamentos").select("encomenda_id,valor,estado").eq("empresa_id",emp).limit(1000);
    const m=new Map();(data||[]).filter(p=>p.estado==="pago").forEach(p=>m.set(p.encomenda_id,(m.get(p.encomenda_id)||0)+Number(p.valor||0)));return m}catch(_){return new Map()}}
function pagamentosServidor(linhas,pagos){if(typeof payments==="undefined")return false;let mudou=false;
  for(const r of linhas){if(["cancelada"].includes(r.estado)||!(Number(r.preco_total)>0))continue;const o=operations.find(x=>x.servidor?.id===r.id||String(x.id)===String(r.codigo));if(!o)continue;
    const pago=pagos.get(r.id)||0,falta=Math.max(0,Math.round((Number(r.preco_total)-pago)*100)/100),meu=payments.find(p=>String(p.operationId)===String(o.id));
    if(!meu){payments.push({id:"PAY-"+r.codigo,operationId:o.id,client:o.client,provider:o.provider,amount:Number(r.preco_total),status:falta>0?"Pendente":"Pago",createdAt:r.created_at,servidor:true});mudou=true}
    else if(falta===0&&meu.status!=="Pago"){meu.status="Pago";mudou=true}}
  return mudou}
function arrancar(){ligarDecisao();if(arquivarPagamentos())redesenhar()}
arrancar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arrancar);
window.addEventListener("load",()=>{arrancar();setTimeout(()=>sincronizar(),2500)});
setInterval(()=>sincronizar(),60000);document.addEventListener("visibilitychange",()=>{if(!document.hidden)sincronizar()});
window.elologSincronizarEncomendas={sincronizar,arquivarPagamentos,cancelarNoServidor};
})();
/* v155: com servidor, os pedidos de simulação (ELO_SM-…) não são encomendas: ficam só em «Pedidos recebidos».
   Registos ELO_SM guardados neste aparelho (por exemplo, de testes como cliente) não entram nas listas da empresa. */
window.addEventListener("load",()=>{const f=window.providerCompanyOperations;if(typeof f!=="function"||f.__semSim)return;
  const g=function(){const l=f.apply(this,arguments);const u=typeof currentUser!=="undefined"?currentUser:null;
    return u?.providerCompany?.server===true&&Array.isArray(l)?l.filter(o=>!/^ELO_SM-/i.test(String(o.id||""))):l};
  Object.assign(g,f);g.__semSim=true;window.providerCompanyOperations=g;
  const v=window.providerCanSeeOperation;if(typeof v==="function"&&!v.__semSim){const h=function(o){const u=typeof currentUser!=="undefined"?currentUser:null;
    if(u?.providerCompany?.server===true&&/^ELO_SM-/i.test(String(o?.id||"")))return false;return v.apply(this,arguments)};Object.assign(h,v);h.__semSim=true;window.providerCanSeeOperation=h}});
