/* Elolog — estado da encomenda no detalhe do prestador (v141).
   1) Encomenda cancelada, rejeitada, anulada ou já entregue fica fechada: o quadro «Alterar estado» dá lugar a um aviso com
      o motivo, quem fechou e quando. Confirmar uma alteração numa encomenda fechada é recusado também aqui (o servidor já recusa).
   2) Encomendas gravadas no servidor mudam de estado no servidor (transitar_encomenda), e não só neste navegador: a lista
      de estados mostra apenas os passos permitidos a partir do estado atual, e cancelar obriga a indicar o motivo.
   3) O histórico das alterações destas encomendas vem do servidor (encomenda_historico), com a observação de cada passo. */
(function(){"use strict";
const P=()=>window.elologProducao,$=id=>document.getElementById(id);
const esc=v=>typeof escapeHtml==="function"?escapeHtml(v):String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const FECHADA=/cancel|rejeit|anulad/i,CONCLUIDA=/levantad|entregue/i;
const NOME={aprovacao:"Aprovação",agendamento:"Recolha por atribuir",recolha:"Recolha",armazenamento:"Armazém",expedicao:"Expedição",em_transito:"Em trânsito",
  destino:"No destino",disponivel:"Disponível",entregue:"Entregue",cancelada:"Cancelada"};
const CODIGO={};Object.entries(NOME).forEach(([k,v])=>CODIGO[v.toLowerCase()]=k);
Object.assign(CODIGO,{"agendamento":"agendamento","armazenamento":"armazenamento","destino":"destino","levantado":"entregue","levantada":"entregue","em transito":"em_transito"});
/* passos permitidos (iguais a encomenda_transicoes no servidor, que continua a ser quem decide) */
const SEGUINTES={aprovacao:["agendamento","armazenamento","cancelada"],agendamento:["recolha","cancelada"],recolha:["armazenamento","agendamento","cancelada"],
  armazenamento:["expedicao","cancelada"],expedicao:["em_transito"],em_transito:["destino"],destino:["disponivel","entregue"],disponivel:["entregue"]};
const estadoDe=o=>String(o?.status||o?.stage||"");
const codigoDe=o=>CODIGO[estadoDe(o).toLowerCase()]||"";
const fechada=o=>FECHADA.test(estadoDe(o))||CONCLUIDA.test(estadoDe(o));
const dataHora=v=>{const d=new Date(v);return isNaN(d)?String(v||"—"):d.toLocaleString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit"})};
const aviso=(t,tipo)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,tipo):alert(t);
const erroTexto=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");

/* motivo guardado neste navegador (para encomendas que só existem aqui) */
function motivoLocal(o){const h=typeof getProviderOrderHistory==="function"?getProviderOrderHistory(o.id):[];
  const fecho=[...h].reverse().find(x=>FECHADA.test(String(x.next||""))||CONCLUIDA.test(String(x.next||"")));
  return{nota:fecho?.note||o.cancelReason||o.rejectionReason||o.decisionNote||o.lastStatusChange?.note||"",quem:fecho?.employee||o.lastStatusChange?.employee||"",quando:fecho?.datetime||""}}

async function historicoServidor(o){if(!o?.servidor?.id||!P()?.online?.())return null;
  try{const sb=await P().sb();const{data,error}=await sb.from("encomenda_historico").select("de,para,nota,responsavel,created_at,motivo_excecao")
    .eq("encomenda_id",o.servidor.id).order("created_at",{ascending:true});if(error)throw error;return data||[]}
  catch(e){console.warn("Histórico da encomenda:",erroTexto(e));return null}}

function quadroFechado(o,m){const cancel=FECHADA.test(estadoDe(o));
  return`<div class="oe-fechada ${cancel?"oe-cancelada":"oe-concluida"}" role="status">
    <div class="oe-fechada-topo"><span class="oe-selo">${cancel?"Encomenda cancelada":"Encomenda concluída"}</span>
      <p>${cancel?"Uma encomenda cancelada não pode mudar de estado. Para retomar o serviço, crie uma nova encomenda.":"A encomenda foi entregue. O estado já não pode ser alterado."}</p></div>
    <dl class="oe-fechada-dados"><div><dt>Motivo</dt><dd>${m.nota?esc(m.nota):"Sem motivo registado"}</dd></div>
      <div><dt>Registado por</dt><dd>${esc(m.quem||"—")}</dd></div><div><dt>Data e hora</dt><dd>${esc(m.quando||"—")}</dd></div></dl></div>`}

function tabela(linhas){if(!linhas.length)return'<div class="provider-order-empty">Ainda não existem alterações registadas para esta encomenda.</div>';
  return`<div class="oe-tabela"><table><thead><tr><th>Data e hora</th><th>Responsável</th><th>Estado anterior</th><th>Novo estado</th><th>Observação</th></tr></thead><tbody>${
    linhas.slice().reverse().map(h=>`<tr${FECHADA.test(NOME[h.para]||h.para||"")?' class="oe-linha-fecho"':""}><td>${esc(dataHora(h.created_at))}</td><td>${esc(h.responsavel||"—")}</td><td>${esc(h.de?NOME[h.de]||h.de:"Criação")}</td><td><b>${esc(NOME[h.para]||h.para)}</b></td><td>${esc(h.nota||h.motivo_excecao||"—")}</td></tr>`).join("")}</tbody></table></div>`}

/* lista de estados: só os passos que o servidor aceita a partir do atual */
function opcoesServidor(o){const sel=$("providerNewStatus");if(!sel)return;const atual=codigoDe(o),prox=SEGUINTES[atual]||[];const reag=c=>atual==="recolha"&&c==="agendamento";
  if(!prox.length){sel.innerHTML=`<option value="">Sem passos disponíveis</option>`;sel.disabled=true;return}
  sel.innerHTML=`<option value="">Escolher o próximo estado…</option>`+prox.map(c=>`<option value="${c}">${reag(c)?"Reagendar a recolha (indique o motivo)":NOME[c]+(c==="cancelada"?" (indique o motivo)":"")}</option>`).join("");
  sel.dataset.servidor="1";const nota=$("providerStatusNote");
  sel.onchange=()=>{if(nota)nota.placeholder=sel.value==="cancelada"?"Motivo do cancelamento (obrigatório). O cliente vê esta observação.":reag(sel.value)?"Porque falhou a recolha e o que fica combinado (obrigatório). O cliente vê esta observação.":"Indique o motivo ou detalhe da alteração…"}}

async function completar(index){const o=operations[index],detail=$("providerOrderDetail");if(!o||!detail||detail.hidden)return;
  const caixa=detail.querySelector(".provider-order-change"),hist=detail.querySelector(".provider-order-history");
  if(fechada(o)&&caixa)caixa.innerHTML=quadroFechado(o,motivoLocal(o));
  else if(o.servidor?.id)opcoesServidor(o);
  const t=hist?.querySelector("table");if(t&&!t.closest(".oe-tabela")){const w=document.createElement("div");w.className="oe-tabela";t.before(w);w.appendChild(t);
    t.querySelectorAll("tbody tr").forEach(tr=>{if(FECHADA.test(tr.cells[3]?.textContent||""))tr.classList.add("oe-linha-fecho")})}
  const linhas=await historicoServidor(o);if(!linhas||operations[index]!==o||$("providerOrderDetail")!==detail)return;
  if(hist)hist.innerHTML=`<h4>Histórico das alterações</h4>${tabela(linhas)}`;
  if(fechada(o)&&caixa){const f=[...linhas].reverse().find(h=>h.para==="cancelada"||h.para==="entregue");
    if(f)caixa.innerHTML=quadroFechado(o,{nota:f.nota||f.motivo_excecao||"",quem:f.responsavel||"",quando:dataHora(f.created_at)})}}

async function mudarNoServidor(index){const o=operations[index],sel=$("providerNewStatus"),nota=$("providerStatusNote"),para=sel?.value,txt=nota?.value.trim()||"",estadoAtual=codigoDe(o);
  if(!para){aviso("Escolha o próximo estado da encomenda.","warning");sel?.focus();return}
  if(para==="agendamento"&&String(estadoAtual??"")==="recolha"&&txt.length<5){aviso("Indique porque falhou a recolha e o que fica combinado. O cliente vê esta observação.","warning");nota?.focus();return}
  if(para==="cancelada"&&txt.length<5){aviso("Indique o motivo do cancelamento. O cliente vê esta observação.","warning");nota?.focus();return}
  const botao=$("providerOrderDetail")?.querySelector(".provider-order-change-grid button");if(botao){botao.disabled=true;botao.textContent="A gravar…"}
  try{const sb=await P().sb();const{error}=await sb.rpc("transitar_encomenda",{p_encomenda:o.servidor.id,p_para:para,p_nota:txt||null});if(error)throw error;
    const antes=estadoDe(o);o.status=o.stage=NOME[para];o.updatedAt=new Date().toISOString();o.lastStatusChange={datetime:dataHora(new Date()),employee:currentUser?.name||"",previous:antes,next:NOME[para],note:txt};
    if(typeof saveAll==="function")saveAll();aviso(`Estado da encomenda ${o.id} alterado para «${NOME[para]}».`,"success");
    ["renderProviderOrderList","renderProviderDashboardForCompany","renderClientTracking"].forEach(f=>{try{window[f]?.()}catch(_){}});
    window.openProviderOrderDetail(index)}
  catch(e){aviso(`O servidor não aceitou a alteração: ${erroTexto(e)}`,"error");if(botao){botao.disabled=false;botao.textContent="Confirmar alteração"}}}

function ligar(){const abrir=window.openProviderOrderDetail,conf=window.confirmProviderOrderStatus;
  if(typeof abrir==="function"&&!abrir.__estado){const n=function(index){const r=abrir.apply(this,arguments);completar(index).catch(e=>console.warn(e));return r};n.__estado=1;window.openProviderOrderDetail=n}
  if(typeof conf==="function"&&!conf.__estado){const n=function(index){const o=operations[index];
      if(o&&fechada(o)){aviso(FECHADA.test(estadoDe(o))?"Esta encomenda está cancelada: o estado já não pode ser alterado.":"Esta encomenda já foi entregue: o estado já não pode ser alterado.","warning");return}
      if(o?.servidor?.id&&P()?.online?.()){if(typeof requireProviderPermission==="function"&&!requireProviderPermission("change_status"))return;return mudarNoServidor(index)}
      return conf.apply(this,arguments)};n.__estado=1;window.confirmProviderOrderStatus=n}}
ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);
window.addEventListener("load",()=>setTimeout(ligar,300));
window.elologEstadoEncomenda={fechada,motivoLocal,historicoServidor,NOME,SEGUINTES};
})();
