/* Elolog — prestador: «Corrigir simulação» de um pedido recebido (v154, migração 00197).
   Abre o simulador do prestador já preenchido com os dados do pedido. Ao confirmar, a correção é gravada no servidor
   (prestador_corrigir_simulacao): o pedido continua por responder, o cliente é avisado e tudo fica na auditoria.
   Depois, o prestador aceita (ou recusa) como antes em «Pedidos recebidos». */
(function(){"use strict";
const S=()=>window.ELOLogServidor;let emCorrecao=null;
const num=v=>{const n=Number(v);return isFinite(n)?n:0};
function paraLocal(r){const rem=r.remetente||{},des=r.destinatario||{},vols=Array.isArray(r.volumes)?r.volumes:[];
  return{registro:r.codigo,client:r.clientes?.nome||rem.nome||"Cliente",senderName:rem.nome||r.clientes?.nome||"",senderPhone:rem.telefone||r.clientes?.telefone||"",senderEmail:rem.email||r.clientes?.email||"",senderAddress:rem.morada||"",
    recipientName:des.nome||"",recipientNif:des.nif||"",recipientPhone:des.telefone||"",recipientEmail:des.email||"",deliveryAddress:des.morada||"",origin:r.origem,destination:r.destino,date:r.data_prevista||"",
    pickupRequested:!!r.recolha_na_morada,pickupAddress:r.recolha_na_morada?(r.morada_recolha||""):"Entrega no armazém",distance:num(r.recolha_distancia_km),cargo:r.tipo_carga||"",declaredPrice:num(r.valor_declarado),notes:r.observacoes||"",
    goods:r.descricao||"",quantity:num(r.quantidade)||1,weight:num(r.peso_kg),volume:num(r.volume_m3),estimatedPrice:num(r.preco_estimado),
    volumes:vols.map(v=>({description:v.descricao??v.description??"",quantity:num(v.qtd??v.quantidade??v.quantity)||1,method:"unit",unitPrice:0,weight:num(v.peso??v.weight),
      length:num(v.comprimento??v.length),width:num(v.largura??v.width),height:num(v.altura??v.height)}))}}
window.servCorrigirSimulacao=function(id){if(typeof requireProviderPermission==="function"&&!requireProviderPermission("approve"))return;
  const r=window.elologCotacao?.(id);if(!r)return window.showPlatformNotice?.("O pedido já não está disponível.","warning");
  const sim=paraLocal(r),original=window.getClientSimulations;window.getClientSimulations=()=>[sim];
  try{openSimulationCreationReview(sim.registro)}finally{window.getClientSimulations=original}
  emCorrecao={id,codigo:r.codigo};
  const h=document.querySelector("#providerDirectSimulation .card-title h3"),intro=document.querySelector("#providerDirectSimulation .client-sim-intro"),b=document.getElementById("providerDirectCreateButton"),res=document.getElementById("providerDirectSimulationResult");
  if(h)h.textContent=`Corrigir o pedido ${r.codigo}`;if(intro)intro.textContent="Corrija o que for preciso (carga, rota, datas, moradas ou preço). O cliente é avisado e o pedido continua em «Pedidos recebidos» para aceitar.";
  if(b){b.hidden=false;b.textContent="Guardar correção"}if(res)res.innerHTML=`<div class="sim-success">Pedido ${r.codigo} carregado. Calcule de novo se mudar a carga e confirme com «Guardar correção».</div>`};
async function guardar(){calculateProviderDirectSimulation();const d=providerDirectSimulationData;if(!d)return;const alvo=emCorrecao;
  const vols=(d.volumes||[]).map(v=>({descricao:v.description||v.descricao||"",quantidade:num(v.quantity),peso:num(v.weight),comprimento:num(v.length),largura:num(v.width),altura:num(v.height)}));
  const dados={origem:d.origin,destino:d.destination,tipo_carga:d.cargoType,descricao:d.goods,quantidade:num(d.quantity),peso_kg:num(d.weight),volume_m3:num(d.volume),volumes:vols,data_prevista:d.date||null,
    recolha:!!d.pickup,morada_recolha:d.pickup?(d.pickupAddress||""):"",recolha_km:num(d.distance),valor_declarado:num(d.declaredPrice)||null,observacoes:d.notes||"",preco:num(d.estimatedPrice)>0?num(d.estimatedPrice):null,
    remetente:{nome:d.senderName||"",telefone:d.senderPhone||"",email:d.senderEmail||"",morada:d.senderAddress||""},destinatario:{nome:d.recipientName||"",telefone:d.recipientPhone||"",email:d.recipientEmail||"",nif:d.recipientNif||"",morada:d.deliveryAddress||""}};
  const b=document.getElementById("providerDirectCreateButton");if(b){b.disabled=true;b.textContent="A guardar…"}
  try{const sb=await S().cliente(),{data,error}=await sb.rpc("prestador_corrigir_simulacao",{p_simulacao:alvo.id,p_dados:dados});if(error)throw error;
    emCorrecao=null;try{resetProviderDirectSimulation()}catch(_){}window.showPlatformNotice?.(`Pedido ${alvo.codigo} corrigido. O cliente foi avisado; pode agora aceitar o pedido.`,"success");
    await window.elologAtualizarCotacoes?.();if(typeof showProviderProposalTab==="function")showProviderProposalTab("new");else showProviderPage("providerCotacao")}
  catch(e){window.showPlatformNotice?.(S()?.mensagem?.(e)||"Não foi possível guardar a correção.","error")}
  finally{if(b){b.disabled=false;if(emCorrecao)b.textContent="Guardar correção"}}}
window.addEventListener("load",()=>{const f=window.createProviderDirectOrderFromLive;if(typeof f!=="function")return;
  const g=function(){if(emCorrecao)return guardar();return f.apply(this,arguments)};Object.assign(g,f);window.createProviderDirectOrderFromLive=g;
  const rs=window.resetProviderDirectSimulation;if(typeof rs==="function"){const h=function(){const r=rs.apply(this,arguments);emCorrecao=null;return r};Object.assign(h,rs);window.resetProviderDirectSimulation=h}});
})();
