/* Elolog — Centro de comando no telemóvel (v86).
   Em ecrãs estreitos junta no topo um painel visual: resumo do dia com o fluxo das operações numa barra de cores,
   atalhos grandes para as tarefas mais usadas e as últimas operações em cartões. A tabela larga e o fluxo em grelha
   ficam escondidos no telemóvel (continuam no computador). Os dados são os mesmos do painel (administracao/painel.js). */
(function(){"use strict";
const telemovel=window.matchMedia("(max-width: 760px)");
const I=()=>window.__ELOLOG_INTERNO?.["painel@administracao"]||{};
const ETAPAS=[["aprovacao","Aprovação","#7c8da0"],["agendamento","Agendamento","#5aa6d6"],["recolha","Recolha","#e0951a"],["armazenamento","Armazém","#8a63c7"],
  ["expedicao","Expedição","#1F5F8B"],["em_transito","Em trânsito","#13293D"],["destino","No destino","#1F7A5C"]];
const ATALHOS=[["file","Inscrições","showAdminPage('adminProviderRequests')","inscricoes"],["truck","Operações","showAdminPage('adminOperations')",""],
  ["wallet","Faturação","showAdminPage('adminBilling')",""],["headset","Apoio","showAdminPage('adminSupport')","apoio"],
  ["clipboard","Auditoria","abrirAuditoria()",""],["users","Clientes","showAdminPage('adminClients')",""],
  ["plus","Pedido por contacto","elologPedidoContacto()",""],["mail","Email","elologEmail.abrir()",""]];
const esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const atras=d=>{const m=Math.max(0,Math.round((Date.now()-new Date(d))/6e4));return m<1?"agora":m<60?`há ${m} min`:m<1440?`há ${Math.round(m/60)} h`:`há ${Math.round(m/1440)} d`};
const cor=e=>/tr[âa]nsito/i.test(e)?"azl":/armaz/i.test(e)?"rox":/recolha/i.test(e)?"amb":"ver";

function icone(n){return n==="plus"?'<b class="cm-glifo" aria-hidden="true">+</b>':n==="mail"?'<b class="cm-glifo" aria-hidden="true">✉</b>':`<i class="ic ic-${n}" aria-hidden="true"></i>`}

function painel(d){const{num,eur}=I(),n=v=>num?num(v):String(v),e=d.encomendas||{},pl=d.pipeline||{},p=d.prestadores||{},s=d.subscricoes||{},a=d.apoio||{};
  const total=ETAPAS.reduce((t,[k])=>t+(pl[k]||0),0)||0;
  const barra=total?ETAPAS.filter(([k])=>pl[k]).map(([k,nome,c])=>`<i style="flex:${pl[k]};background:${c}" title="${esc(nome)}: ${pl[k]}"></i>`).join(""):'<i style="flex:1;background:#dfe7ee"></i>';
  const legenda=ETAPAS.map(([k,nome,c])=>`<button type="button" class="cm-etapa${pl[k]?"":" zero"}" onclick="showAdminPage('adminOperations')"><span style="background:${c}"></span>${esc(nome)}<b>${n(pl[k]||0)}</b></button>`).join("");
  const espera=(p.pendentes||0)+(s.pagamentos_por_confirmar||0)+(e.paradas_mais_7d||0),urg=Math.min(3,[s.pagamentos_por_confirmar>0,p.pendentes_mais_48h>0,e.paradas_mais_7d>0,a.escalados>0].filter(Boolean).length);
  const marca={inscricoes:p.pendentes||0,apoio:(a.abertos||0)};const nome=String(window.currentUser?.name||(typeof currentUser!=="undefined"?currentUser?.name:"")||"").split(" ")[0];
  const hoje=new Date().toLocaleDateString("pt-PT",{weekday:"long",day:"numeric",month:"long"});const hojeT=hoje.charAt(0).toUpperCase()+hoje.slice(1);
  const ops=(d.operacoes_recentes||[]).slice(0,5).map(o=>`<li><button type="button" onclick="showAdminPage('adminOperations')"><span class="cm-ref">${esc(o.ref)}</span>
    <span class="cm-rota">${esc(o.origem)} <i aria-hidden="true">→</i> ${esc(o.destino)}</span><span class="work-status ct-est ${cor(o.estado)}">${esc(o.estado)}</span>
    <small>${esc(o.cliente)} · ${esc(atras(o.quando))}</small></button></li>`).join("");
  return`<div class="cm-painel" aria-label="Resumo do centro de comando">
  <section class="cm-hero"><p class="cm-ola">Olá${nome?", "+esc(nome):""} <span>· ${esc(hojeT)}</span></p>
    <div class="cm-grande"><strong>${n(e.em_curso||0)}</strong><span>operações em curso<br><b>${eur?eur(e.valor_em_curso||0):""}</b></span></div>
    <div class="cm-barra" role="img" aria-label="Operações por etapa">${barra}</div><div class="cm-etapas">${legenda}</div></section>
  <div class="cm-estado">
    <button type="button" class="cm-pill ${espera?"amb":"ok"}" onclick="document.getElementById('pw-alertas')?.scrollIntoView({behavior:'smooth'})">${espera?`<b>${n(espera)}</b> a aguardar ação`:"✓ Tudo em ordem"}</button>
    ${urg?`<button type="button" class="cm-pill verm" onclick="document.getElementById('pw-alertas')?.scrollIntoView({behavior:'smooth'})"><b>${n(urg)}</b> ${urg===1?"assunto urgente":"assuntos urgentes"}</button>`:""}
    <button type="button" class="cm-pill" onclick="showAdminPage('adminBilling')"><b>${eur?eur(s.mrr||0):""}</b> / mês</button></div>
  <nav class="cm-atalhos" aria-label="Atalhos">${ATALHOS.map(([ic,t,acao,m])=>`<button type="button" onclick="${acao}"><span class="cm-ic">${icone(ic)}${marca[m]?`<em>${marca[m]>99?"99+":marca[m]}</em>`:""}</span>${esc(t)}</button>`).join("")}</nav>
  ${ops?`<section class="cm-ops"><div class="cm-tit"><h4>Últimas operações</h4><button type="button" onclick="showAdminPage('adminOperations')">Ver todas →</button></div><ul>${ops}</ul></section>`:""}</div>`}

function aplicar(){const alvo=document.getElementById("adminDashboardProviders"),sec=alvo?.querySelector(".pa-centro");
  document.body.classList.toggle("cm-movel",telemovel.matches);if(!sec)return;sec.querySelector(".cm-painel")?.remove();
  if(!telemovel.matches)return;const d=I().painelDados?.()||window.__ELOLOG_INTERNO?.painelDados?.();if(!d)return;
  const cab=sec.querySelector(".pa-cabecalho");(cab||sec.firstChild)?.insertAdjacentHTML?.(cab?"afterend":"beforebegin",painel(d))}

function ligar(){const alvo=document.getElementById("adminDashboardProviders");if(!alvo)return setTimeout(ligar,500);
  new MutationObserver(aplicar).observe(alvo,{childList:true});aplicar()}
telemovel.addEventListener?.("change",aplicar);
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
})();
