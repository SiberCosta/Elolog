/* Elolog — duas páginas do prestador (v137):
   1) «Auditoria» (Gestão, só administrador): quem fez o quê e quando na empresa — sessões, códigos de segurança, criação e alteração
      de registos, funcionários, tarifas. Com servidor lê a tabela «auditoria» (o servidor só mostra a empresa do administrador);
      na demonstração junta o histórico das encomendas, da equipa de terreno e da automação deste navegador. Filtros e exportação CSV.
   2) «Pedidos concluídos» (Propostas): os pedidos e propostas que já se tornaram encomenda, com o estado atual da encomenda. */
(function(){"use strict";
const P=()=>window.elologProducao,on=()=>!!P()?.online?.(),esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const quando=v=>{const d=new Date(v);return isNaN(d)?"—":d.toLocaleString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit"})};
const eur=v=>v==null||v===""?"—":Number(v).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const pagina=(id,t,b)=>window.elologPaginaPropria?.(id,t,b);

/* ---------------- Auditoria ---------------- */
const ACAO={abrir_sessao_empresa:"Entrou na área da empresa",abrir_sessao_funcionario:"Iniciou sessão",bloqueio_seguranca:"Bloqueio de segurança",codigo_email_enviado:"Código enviado por email",
  codigo_email_usado:"Usou o código do email",codigo_reserva_errado:"Código de reserva errado",codigo_reserva_gerado:"Gerou códigos de reserva",codigo_reserva_usado:"Usou um código de reserva",
  confirmar_pagamento_subscricao:"Pagamento da subscrição confirmado",criar_funcionario:"Criou um funcionário",registo_prestador:"Registo da empresa",aprovar_empresa:"Empresa aprovada",
  tarifa_aprovar:"Tarifa aprovada",insert:"Criou",update:"Alterou",delete:"Apagou"};
const ENT={encomendas:"encomenda",simulacoes:"pedido",propostas:"proposta",pagamentos:"pagamento",funcionarios:"funcionário",tarifas:"tarifa",documentos:"documento",armazens:"armazém",
  trabalhos_terreno:"serviço de terreno",manifestos:"manifesto",faturas:"fatura",tickets:"pedido de apoio",clientes:"cliente",empresas:"empresa",veiculos:"viatura"};
const GRUPO=r=>/sessao|codigo|bloqueio/.test(r.acao)?"seg":/funcionario/.test(r.acao)||r.entidade==="funcionarios"?"eq":/pagament|fatura|tarifa|subscric/.test(r.acao+" "+r.entidade)?"fin":/encomend|simulac|propost|manifest|terreno|document/.test(r.entidade||"")?"op":"outro";
const GRUPOS=[["","Tudo"],["op","Operações"],["fin","Financeiro"],["eq","Equipa"],["seg","Acessos e segurança"]];
let estado={dias:30,grupo:"",q:"",linhas:[],nomes:{},erro:""};
function alteracoes(r){const a=r.antes||{},d=r.depois||{};const ks=[...new Set([...Object.keys(a),...Object.keys(d)])].filter(k=>!/^(updated_at|created_at|id)$/.test(k)&&JSON.stringify(a[k])!==JSON.stringify(d[k])).slice(0,12);
  return ks.map(k=>`<li><b>${esc(k.replace(/_/g," "))}</b>: ${esc(a[k]==null?"—":typeof a[k]==="object"?JSON.stringify(a[k]).slice(0,80):a[k])} → ${esc(d[k]==null?"—":typeof d[k]==="object"?JSON.stringify(d[k]).slice(0,80):d[k])}</li>`).join("")}
async function lerServidor(){const sb=await P().sb();const desde=new Date(Date.now()-estado.dias*864e5).toISOString();
  const{data,error}=await sb.from("auditoria").select("id,user_id,papel,acao,entidade,entidade_id,antes,depois,motivo,created_at").gte("created_at",desde).order("created_at",{ascending:false}).limit(500);if(error)throw error;
  const{data:fs}=await sb.from("funcionarios").select("id,nome");estado.nomes=Object.fromEntries((fs||[]).map(f=>[f.id,f.nome]));return data||[]}
function lerLocal(){const l=[],desde=Date.now()-estado.dias*864e5,quem=x=>x||"—";
  (typeof operations!=="undefined"?providerCompanyOperations():[]).forEach(o=>{(o.history||[]).forEach(h=>l.push({created_at:h.dateTime||h.datetime,acao:"update",entidade:"encomendas",entidade_id:o.id,quem:quem(h.employee),motivo:`${h.previous||""} → ${h.status||h.next||""}${h.observation?". "+h.observation:""}`}));
    try{getProviderOrderHistory(o.id).forEach(h=>l.push({created_at:h.datetime,acao:"update",entidade:"encomendas",entidade_id:o.id,quem:quem(h.employee),motivo:`${h.previous||""} → ${h.next||""}${h.note?". "+h.note:""}`}))}catch(_){}});
  try{getFieldJobs().forEach(j=>(j.history||[]).forEach(h=>l.push({created_at:h.at,acao:"update",entidade:"trabalhos_terreno",entidade_id:j.code||j.id,quem:quem(h.by),motivo:h.action})))}catch(_){}
  try{JSON.parse(localStorage.getItem("elolog_automation_log")||"[]").forEach(a=>l.push({created_at:a.at,acao:"update",entidade:"encomendas",entidade_id:"",quem:"Automação Elolog",motivo:`${a.title}. ${a.detail||""}`}))}catch(_){}
  return l.filter(r=>{const t=Date.parse(r.created_at);return!isNaN(t)&&t>=desde}).sort((a,b)=>Date.parse(b.created_at)-Date.parse(a.created_at)).slice(0,500)}
function filtradas(){const q=estado.q.toLowerCase();return estado.linhas.filter(r=>(!estado.grupo||GRUPO(r)===estado.grupo)&&(!q||[r.motivo,r.entidade_id,ACAO[r.acao]||r.acao,ENT[r.entidade]||r.entidade,r.quem||estado.nomes[r.user_id]].some(v=>String(v||"").toLowerCase().includes(q))))}
function desenharAud(){const s=document.getElementById("provAuditoria");if(!s)return;const l=filtradas();
  s.innerHTML=`<div class="card ac-pag"><div class="ac-topo"><div><h2>Auditoria</h2><p>Quem fez o quê e quando na empresa.${on()?"":" <b>Demonstração:</b> histórico guardado neste navegador."}</p></div>
    <button type="button" class="btn-secondary" data-ac="csv"${l.length?"":" disabled"}>Exportar CSV</button></div>
    <div class="ac-filtros"><label>Período<select data-ac="dias">${[[7,"7 dias"],[30,"30 dias"],[90,"90 dias"],[365,"12 meses"]].map(([v,t])=>`<option value="${v}"${v===estado.dias?" selected":""}>${t}</option>`).join("")}</select></label>
      <label>Tipo<select data-ac="grupo">${GRUPOS.map(([v,t])=>`<option value="${v}"${v===estado.grupo?" selected":""}>${t}</option>`).join("")}</select></label>
      <label class="ac-q">Pesquisar<input type="search" data-ac="q" value="${esc(estado.q)}" placeholder="Código, pessoa ou ação"></label></div>
    ${estado.erro?`<p class="campo-erro">${esc(estado.erro)}</p>`:""}<p class="ac-conta">${l.length} ${l.length===1?"registo":"registos"}</p>
    ${l.length?`<div class="pf-tabela"><table><thead><tr><th scope="col">Quando</th><th scope="col">Quem</th><th scope="col">O quê</th><th scope="col">Registo</th><th scope="col">Detalhe</th></tr></thead><tbody>${l.slice(0,300).map(r=>{const det=alteracoes(r);
      return`<tr><td>${quando(r.created_at)}</td><td>${esc(r.quem||estado.nomes[r.user_id]||(r.papel?r.papel.replace(/_/g," "):"Sistema"))}</td><td><span class="pf-pill">${esc(ACAO[r.acao]||r.acao)}</span></td><td>${esc(ENT[r.entidade]||r.entidade||"—")}${r.entidade_id?` <small>${esc(String(r.entidade_id).slice(0,24))}</small>`:""}</td>
        <td>${esc(r.motivo||"")}${det?`<details><summary>Ver alterações</summary><ul class="ac-alt">${det}</ul></details>`:""}</td></tr>`}).join("")}</tbody></table></div>`:'<p class="pf-vazio">Sem registos neste período.</p>'}</div>`}
async function carregar(){estado.erro="";try{estado.linhas=on()?await lerServidor():lerLocal()}catch(e){estado.linhas=[];estado.erro="Não conseguimos ler a auditoria agora: "+String(e?.message||e)}desenharAud()}
function csv(){const l=filtradas(),c=v=>`"${String(v??"").replace(/"/g,'""')}"`,linhas=[["Quando","Quem","Ação","Registo","Código","Detalhe"].map(c).join(";"),
  ...l.map(r=>[quando(r.created_at),r.quem||estado.nomes[r.user_id]||r.papel||"Sistema",ACAO[r.acao]||r.acao,ENT[r.entidade]||r.entidade,r.entidade_id,r.motivo].map(c).join(";"))];
  const a=document.createElement("a");a.href=URL.createObjectURL(new Blob(["﻿"+linhas.join("\n")],{type:"text/csv;charset=utf-8"}));a.download=`auditoria-${new Date().toISOString().slice(0,10)}.csv`;document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},5000)}
function abrirAuditoria(b){try{if(typeof providerFunction==="function"&&providerFunction()!=="admin")return showPlatformNotice?.("A auditoria só está disponível para o administrador da empresa.","warning")}catch(_){}
  const s=pagina("provAuditoria","Auditoria",b);if(!s)return;if(!s.dataset.ligado){s.dataset.ligado=1;
    s.addEventListener("change",e=>{const k=e.target.dataset.ac;if(k==="dias"){estado.dias=+e.target.value;carregar()}else if(k==="grupo"){estado.grupo=e.target.value;desenharAud()}});
    s.addEventListener("input",e=>{if(e.target.dataset.ac==="q"){estado.q=e.target.value;const pos=e.target.selectionStart;desenharAud();const i=s.querySelector('[data-ac="q"]');i?.focus();try{i.setSelectionRange(pos,pos)}catch(_){}}});
    s.addEventListener("click",e=>{if(e.target.closest('[data-ac="csv"]'))csv()})}
  s.innerHTML='<div class="card"><p role="status">A carregar…</p></div>';carregar()}

/* ---------------- Pedidos concluídos ---------------- */
async function concluidosServidor(){const sb=await P().sb();
  const{data,error}=await sb.from("encomendas").select("id,codigo,estado,origem,destino,cliente_nome,preco_total,created_at,simulacao_id,proposta_id").or("simulacao_id.not.is.null,proposta_id.not.is.null").order("created_at",{ascending:false}).limit(200);if(error)throw error;
  const ids=[...new Set((data||[]).map(x=>x.simulacao_id).filter(Boolean))];let sims={};if(ids.length){const{data:s}=await sb.from("simulacoes").select("id,codigo,created_at").in("id",ids);sims=Object.fromEntries((s||[]).map(x=>[x.id,x]))}
  const ESTADO={aprovacao:"Aprovação",agendamento:"Agendamento",recolha:"Recolha",armazenamento:"Armazém",expedicao:"Expedição",em_transito:"Em trânsito",destino:"No destino",disponivel:"Disponível",entregue:"Entregue",cancelada:"Cancelada"};
  return(data||[]).map(e=>({pedido:sims[e.simulacao_id]?.codigo||"—",pedidoEm:sims[e.simulacao_id]?.created_at,encomenda:e.codigo,cliente:e.cliente_nome,rota:`${e.origem||"—"} → ${e.destino||"—"}`,valor:e.preco_total,em:e.created_at,estado:ESTADO[e.estado]||e.estado}))}
function concluidosLocal(){const ops=typeof operations!=="undefined"?providerCompanyOperations():[],sims=typeof getClientSimulations==="function"?getClientSimulations():[];const l=[];
  sims.filter(s=>s.shipmentId||/envio criado|convertid|conclu/i.test(String(s.status||""))).forEach(s=>{const o=ops.find(x=>String(x.id)===String(s.shipmentId))||ops.find(x=>String(x.simulationId)===String(s.registro));
    l.push({pedido:s.registro,pedidoEm:s.createdAt||s.sentToProviderAt,encomenda:o?.id||s.shipmentId||"—",cliente:s.client||o?.client,rota:`${s.origin||"—"} → ${s.destination||"—"}`,valor:s.estimatedPrice??o?.estimatedPrice,em:s.reviewedAt||o?.createdAt,estado:o?.status||o?.stage||"Encomenda criada"})});
  ops.filter(o=>o.simulationId&&!l.some(x=>String(x.encomenda)===String(o.id))&&sims.some(s=>String(s.registro)===String(o.simulationId))).forEach(o=>l.push({pedido:o.simulationId,encomenda:o.id,cliente:o.client,rota:`${o.origin||"—"} → ${o.destination||"—"}`,valor:o.estimatedPrice,em:o.createdAt,estado:o.status||o.stage}));
  return l.sort((a,b)=>Date.parse(b.em||0)-Date.parse(a.em||0))}
async function abrirConcluidos(b){const s=pagina("provConcluidos","Pedidos concluídos",b);if(!s)return;s.innerHTML='<div class="card"><p role="status">A carregar…</p></div>';let l=[],erro="";
  try{l=on()?await concluidosServidor():concluidosLocal()}catch(e){erro=String(e?.message||e)}
  const abrirEnc=c=>window.elologFicha?.abrir?`elologFicha.abrir('${esc(c)}')`:`showProviderPage('providerOrder');setTimeout(()=>{const i=operations.findIndex(x=>x.id==='${esc(c)}');if(i>=0)openProviderOrderDetail(i)},80)`;
  s.innerHTML=`<div class="card ac-pag"><div class="ac-topo"><div><h2>Pedidos concluídos</h2><p>Pedidos e propostas que já se tornaram encomenda.${on()?"":" <b>Demonstração:</b> dados deste navegador."}</p></div></div>
    ${erro?`<p class="campo-erro">Não conseguimos ler os pedidos concluídos: ${esc(erro)}</p>`:""}
    ${l.length?`<p class="ac-conta">${l.length} ${l.length===1?"pedido concluído":"pedidos concluídos"}</p><div class="ac-lista">${l.map(x=>`<article class="ac-cartao"><div><span class="ac-cod">${esc(x.pedido)} → ${esc(x.encomenda)}</span><h4>${esc(x.rota)}</h4>
      <p>${esc(x.cliente||"Cliente")}, ${eur(x.valor)}, encomenda criada ${quando(x.em)}</p></div><div class="ac-lado"><span class="pf-pill">${esc(x.estado||"—")}</span><button type="button" class="btn-secondary" onclick="${abrirEnc(x.encomenda)}">Abrir encomenda</button></div></article>`).join("")}</div>`
      :'<p class="pf-vazio">Ainda não há pedidos concluídos. Quando um cliente aceitar uma proposta e a encomenda for criada, aparece aqui.</p>'}</div>`}

window.elologAuditoriaPrestador={abrir:abrirAuditoria,carregar,lerLocal};
window.elologPropostasConcluidas={abrir:abrirConcluidos,local:concluidosLocal};
})();
