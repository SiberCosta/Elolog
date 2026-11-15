/* Elolog — confirmar pagamentos no servidor (v146).
   Com sessão real de prestador, «Confirmar pagamento» de uma encomenda do servidor grava o recebimento em «pagamentos»
   (valor, método, referência, quem registou). O servidor gera os documentos do pagamento e o valor em dívida da encomenda
   desce em todos os aparelhos e na ficha da operação. Só administradores da empresa e financeiro podem registar. */
(function(){"use strict";
const P=()=>window.elologProducao,ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="prestador"&&currentUser?.providerCompany?.server===true&&!!P()?.online?.();
const esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):console.warn(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const METODOS=["Transferência bancária","MB WAY","Referência Multibanco","Numerário","Cartão","Outro"];

async function emDivida(sb,enc){const[{data:e},{data:p}]=await Promise.all([sb.from("encomendas").select("preco_total").eq("id",enc).maybeSingle(),
    sb.from("pagamentos").select("valor,estado,tipo").eq("encomenda_id",enc)]);
  const pago=(p||[]).filter(x=>x.estado==="pago"&&x.tipo!=="reembolso").reduce((t,x)=>t+Number(x.valor||0),0);return{total:Number(e?.preco_total||0),pago,falta:Math.max(0,Number(e?.preco_total||0)-pago)}}

async function confirmar(pag,o){const sb=await P().sb(),emp=await P().minhaEmpresa(),u=await P().utilizador();
  if(!["admin_empresa","financeiro"].includes(emp?.papel))return aviso("Só o administrador da empresa ou o financeiro registam pagamentos.","warning");
  const d=await emDivida(sb,o.servidor.id);if(d.falta<=0){pag.status="Pago";window.saveAll?.();return aviso(`A encomenda ${o.id} já está paga no servidor.`,"info")}
  const j=P().janela({eyebrow:"PAGAMENTO "+o.id,titulo:"Registar recebimento"});
  j.mostrar(`<p class="ed-intro">Total ${esc(eur(d.total))}, já pago ${esc(eur(d.pago))}. Em dívida: <b>${esc(eur(d.falta))}</b>.</p><div class="pc-grelha">
    <div class="pc-campo"><label for="pgValor">Valor recebido (€) *</label><input id="pgValor" type="number" min="0.01" step="0.01" max="${d.falta}" value="${d.falta.toFixed(2)}"></div>
    <div class="pc-campo"><label for="pgMetodo">Método *</label><select id="pgMetodo">${METODOS.map(m=>`<option>${m}</option>`).join("")}</select></div>
    <div class="pc-campo ed-largo"><label for="pgRef">Referência ou comprovativo</label><input id="pgRef" maxlength="80" placeholder="Ex.: n.º da transferência"></div></div><p class="campo-erro" id="pgErro" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Registar recebimento",principal:true,acao:async()=>{const v=Math.round(Number(document.getElementById("pgValor").value)*100)/100,el=document.getElementById("pgErro");
      if(!(v>0))return el.textContent="Indique o valor recebido.";if(v>d.falta+0.005)return el.textContent=`O valor não pode passar o que está em dívida (${eur(d.falta)}).`;
      const{error}=await sb.from("pagamentos").insert({empresa_id:emp.empresa_id,encomenda_id:o.servidor.id,tipo:v<d.falta?"prestacao":"total",valor:v,estado:"pago",metodo:document.getElementById("pgMetodo").value,
        referencia:document.getElementById("pgRef").value.trim()||null,registado_por:u.id,pago_em:new Date().toISOString()});
      if(error)return el.textContent=erro(error);
      const resta=Math.round((d.falta-v)*100)/100;if(resta<=0){pag.status="Pago";pag.confirmedAt=new Date().toISOString();pag.confirmedBy=currentUser?.name||""}else pag.amountDue=resta;
      window.saveAll?.();j.fechar();["renderProviderPagamentos","renderProviderDashboardForCompany"].forEach(f=>{try{window[f]?.()}catch(_){}});
      aviso(resta<=0?`Pagamento de ${o.id} registado no servidor: encomenda paga.`:`Recebimento de ${eur(v)} registado. Falta ${eur(resta)}.`,"success")}}])}

/* v147: reembolsos (linha «reembolso» em pagamentos, com motivo) e faturas/comprovativos (documentos visíveis ao cliente) */
async function reembolsar(pag,o){const sb=await P().sb(),emp=await P().minhaEmpresa(),u=await P().utilizador();
  if(!["admin_empresa","financeiro"].includes(emp?.papel))return aviso("Só o administrador da empresa ou o financeiro registam reembolsos.","warning");
  const{data:l}=await sb.from("pagamentos").select("valor,estado,tipo").eq("encomenda_id",o.servidor.id);
  const pago=(l||[]).filter(x=>x.estado==="pago"&&x.tipo!=="reembolso").reduce((t,x)=>t+Number(x.valor||0),0),devolvido=(l||[]).filter(x=>x.tipo==="reembolso").reduce((t,x)=>t+Number(x.valor||0),0),max=Math.max(0,pago-devolvido);
  if(max<=0)return aviso(`A encomenda ${o.id} não tem valores pagos por devolver. Para anular uma dívida, cancele a encomenda na ficha.`,"info");
  const j=P().janela({eyebrow:"PAGAMENTO "+o.id,titulo:"Registar reembolso"});
  j.mostrar(`<p class="ed-intro">Pago ${esc(eur(pago))}, já devolvido ${esc(eur(devolvido))}. Pode devolver até <b>${esc(eur(max))}</b>.</p><div class="pc-grelha">
    <div class="pc-campo"><label for="rbValor">Valor a devolver (€) *</label><input id="rbValor" type="number" min="0.01" step="0.01" max="${max}" value="${max.toFixed(2)}"></div>
    <div class="pc-campo"><label for="rbMetodo">Método *</label><select id="rbMetodo">${METODOS.map(m=>`<option>${m}</option>`).join("")}</select></div>
    <div class="pc-campo ed-largo"><label for="rbMotivo">Motivo * <small>(mínimo 8 caracteres; fica no histórico)</small></label><textarea id="rbMotivo" rows="2" maxlength="300"></textarea></div>
    <div class="pc-campo ed-largo"><label for="rbRef">Referência</label><input id="rbRef" maxlength="80"></div></div><p class="campo-erro" id="rbErro" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Registar reembolso",principal:true,acao:async()=>{const v=Math.round(Number(document.getElementById("rbValor").value)*100)/100,mot=document.getElementById("rbMotivo").value.trim(),el=document.getElementById("rbErro");
      if(!(v>0)||v>max+0.005)return el.textContent=`O valor tem de estar entre 0,01 € e ${eur(max)}.`;if(mot.length<8)return el.textContent="Indique o motivo (mínimo 8 caracteres).";
      const{error}=await sb.from("pagamentos").insert({empresa_id:emp.empresa_id,encomenda_id:o.servidor.id,tipo:"reembolso",valor:v,estado:"reembolsado",metodo:document.getElementById("rbMetodo").value,
        referencia:document.getElementById("rbRef").value.trim()||null,motivo_anulacao:mot,registado_por:u.id,pago_em:new Date().toISOString()});if(error)return el.textContent=erro(error);
      pag.refundHistory=[...(pag.refundHistory||[]),{id:"REF-"+Date.now(),type:v>=max?"Reembolso integral":"Reembolso parcial",amount:v,reason:mot,at:new Date().toISOString(),by:currentUser?.name||""}];
      if(v>=pago)pag.status="Reembolsado";else pag.status="Parcialmente reembolsado";window.saveAll?.();j.fechar();try{window.renderProviderPagamentos?.()}catch(_){}
      aviso(`Reembolso de ${eur(v)} registado no servidor.`,"success")}}])}

async function documento(pag,o,input,tipo){const file=input?.files?.[0];if(!file)return;
  try{const d=await P().enviarDocumento(file,{encomenda:o.servidor.codigo,categoria:tipo==="receipt"?"comprovativo_pagamento":"fatura",visibilidade:"cliente"});
    if(tipo==="receipt"){pag.receiptFileName=file.name;pag.receiptDoc=d.storage_path}else{pag.invoiceFileName=file.name;pag.invoiceDoc=d.storage_path;pag.invoiceFile=true}
    window.saveAll?.();try{window.renderProviderPagamentos?.()}catch(_){}aviso(`${tipo==="receipt"?"Comprovativo":"Fatura"} guardado no servidor e disponível para o cliente.`,"success")}
  catch(e){aviso(erro(e),"error")}finally{if(input)input.value=""}}

function ligar(){const f=window.confirmarPagamentoPrestador;if(typeof f!=="function"||f.__srv)return;
  window.confirmarPagamentoPrestador=function(id){if(!ativo())return f.apply(this,arguments);if(typeof requireProviderPermission==="function"&&!requireProviderPermission("manage_payments"))return;
    const pag=(typeof payments!=="undefined"?payments:[]).find(x=>String(x.id)===String(id)),o=pag&&operations.find(x=>String(x.id)===String(pag.operationId));
    if(!pag||!o)return;if(!o.servidor?.id)return aviso(`A encomenda ${o.id} não está no servidor: não é possível registar o pagamento.`,"warning");
    confirmar(pag,o).catch(e=>aviso("Não foi possível registar o pagamento: "+erro(e),"error"))};window.confirmarPagamentoPrestador.__srv=1
  const rb=window.providerRefundPayment,dc=window.carregarDocumentoPagamento,bx=window.baixarDocumentoPagamento;
  const achar=id=>{const pag=(typeof payments!=="undefined"?payments:[]).find(x=>String(x.id)===String(id));return{pag,o:pag&&operations.find(x=>String(x.id)===String(pag.operationId))}};
  if(typeof rb==="function")window.providerRefundPayment=function(id){if(!ativo())return rb.apply(this,arguments);const{pag,o}=achar(id);if(!pag||!o)return;
    if(!o.servidor?.id)return aviso(`A encomenda ${o.id} não está no servidor.`,"warning");reembolsar(pag,o).catch(e=>aviso(erro(e),"error"))};
  if(typeof dc==="function")window.carregarDocumentoPagamento=function(id,input,tipo){if(!ativo())return dc.apply(this,arguments);const{pag,o}=achar(id);if(!pag||!o)return;
    if(!o.servidor?.codigo)return aviso(`A encomenda ${o.id} não está no servidor.`,"warning");documento(pag,o,input,tipo)};
  if(typeof bx==="function")window.baixarDocumentoPagamento=function(id,tipo){const{pag}=achar(id),c=tipo==="receipt"?pag?.receiptDoc:pag?.invoiceDoc;
    if(ativo()&&c)return P().abrirDocumento(c,tipo==="receipt"?pag.receiptFileName:pag.invoiceFileName).catch(e=>aviso(erro(e),"error"));return bx.apply(this,arguments)}}
ligar();window.addEventListener("load",()=>setTimeout(ligar,300));
})();
