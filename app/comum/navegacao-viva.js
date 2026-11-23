/* Elolog — navegação viva (v111). O mesmo menu para os três papéis, mas atento:
   - «O seu próximo passo» no topo do menu lateral: a coisa mais útil a fazer agora, com a urgência certa;
   - no prestador, cada etapa do menu mostra quantas encomendas tem (as vazias ficam discretas, nunca escondidas);
   - o papel fica marcado no <body> (data-papel) para a cor de acento do menu e dos botões.
   Só lê dados que a plataforma já tem; não altera nada. */
(function(){"use strict";
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const eu=()=>{try{return typeof currentUser!=="undefined"?currentUser:null}catch(_){return null}};
const ops=()=>{try{return typeof operations!=="undefined"&&Array.isArray(operations)?operations:[]}catch(_){return[]}};
const pags=()=>{try{return typeof payments!=="undefined"&&Array.isArray(payments)?payments:[]}catch(_){return[]}};
const F=()=>window.elologFluxo;
const dias=v=>{const d=new Date(v);return isNaN(d)?0:Math.floor((Date.now()-d)/864e5)};
const abertos=lista=>pags().filter(p=>!/pago|anulad|reembols/i.test(p.status||"")&&(!lista||lista.some(o=>String(o.id)===String(p.operationId))));
const pl=(n,um,v)=>`${n} ${n===1?um:v}`;
/* encomendas diretas à espera da administração (lidas de vez em quando, sem bloquear o menu) */
let diretas=0;async function contarDiretas(){try{const l=await window.elologED?.listar?.();if(Array.isArray(l))diretas=l.filter(x=>["pendente_validacao","em_analise_admin","validada","recusada"].includes(x.estado)).length}catch(_){}}

/* páginas de etapa do prestador e o índice da etapa (igual ao Fluxo Vivo) */
const ETAPA_PAG={providerAprovacao:2,providerRecolha:3,providerPagamentos:4,providerArmazenamento:5,providerExpedicao:6,providerTransito:7,providerDestino:8,providerDisponivel:9};
const PERM_PAG={providerAprovacao:"approve",providerPagamentos:"manage_payments",providerRecolha:"view_loads",providerArmazenamento:"view_loads",providerExpedicao:"view_loads",providerDestino:"change_status",providerDisponivel:"change_status",providerTransito:"view_loads"};
const PRIORIDADE=[[2,"esperam a sua aprovação","espera a sua aprovação","providerAprovacao"],[4,"esperam a confirmação do pagamento","espera a confirmação do pagamento","providerPagamentos"],
  [3,"esperam recolha","espera recolha","providerRecolha"],[5,"esperam entrada no armazém","espera entrada no armazém","providerArmazenamento"],[6,"estão prontas a expedir","está pronta a expedir","providerExpedicao"],
  [8,"chegaram e esperam confirmação","chegou e espera confirmação","providerDestino"],[9,"esperam ser levantadas","espera ser levantada","providerDisponivel"],[7,"estão em viagem","está em viagem","providerTransito"]];

function doPrestador(){try{return typeof providerCompanyOperations==="function"?providerCompanyOperations():ops()}catch(_){return ops()}}
function contagem(lista){const c={};if(!F())return c;lista.forEach(o=>{const i=F().indice(o);c[i]=(c[i]||0)+1});
  /* v156: «esperam recolha» = só as que ainda não têm recolha agendada */
  if(typeof window.elologPorAgendar==="function")c[3]=lista.filter(window.elologPorAgendar).length;return c}

/* o próximo passo de cada papel: {t: texto, d: detalhe, js: ação, nivel: normal|agora|urgente} */
function proximo(papel){
  /* v154: só as encomendas do próprio cliente; o quadro só aparece quando há algo a fazer (pagar ou levantar) */
  if(papel==="cliente"){const dono=o=>typeof window.elologDoCliente==="function"?window.elologDoCliente(o):true,meus=ops().filter(dono);
    const pg=abertos(meus).sort((a,b)=>new Date(a.createdAt||a.date)-new Date(b.createdAt||b.date))[0];
    if(pg){const n=dias(pg.createdAt||pg.date);return{t:n>=2?"Regularizar um pagamento":"Pagar uma encomenda",d:`${pg.operationId}${n>=2?`, pendente há ${n} dias`:""}`,js:"showPage('payments')",nivel:n>=2?"urgente":"agora"}}
    const lev=meus.find(o=>/dispon/i.test(o.status||o.stage||""));if(lev)return{t:`Levantar ${lev.id}`,d:"A encomenda está pronta a ser levantada",js:"openClientOrderSection('status')",nivel:"agora"};
    return null}
  if(papel==="prestador"){
    /* v159: cada função só vê passos que pode tratar (o operador de terreno vê os seus serviços, não aprovações) */
    const pode=pg=>{try{return typeof hasProviderPermission!=="function"||hasProviderPermission(PERM_PAG[pg]||"view_loads")}catch(_){return true}};
    if(typeof providerFunction==="function"&&providerFunction()==="field_operator"){let n=0;try{const me=fieldCurrentOperator();n=getFieldJobs().filter(j=>j.operatorId===me?.id&&!/conclu|cancel/i.test(j.status||"")).length}catch(_){}
      return n?{t:pl(n,"serviço atribuído","serviços atribuídos"),d:"Ver recolhas e entregas",js:"showProviderFieldPage('pickups')",nivel:"agora"}:{t:"Sem serviços por fazer",d:"Os novos serviços aparecem aqui",js:"showProviderFieldPage('pickups')",nivel:"calmo"}}
    const c=contagem(doPrestador());for(const [i,v,um,pg] of PRIORIDADE)if(c[i]&&pode(pg))return{t:`${c[i]} ${c[i]===1?"encomenda "+um:"encomendas "+v}`,d:"Abrir e tratar",js:`showProviderPage('${pg}')`,nivel:i===2||i===4?"agora":"normal"};
    return{t:"Tudo em dia",d:"Veja se chegaram novas simulações",js:"document.querySelector('#sidebar [onclick*=showProviderProposalTab]')?.click()",nivel:"calmo"}}
  if(papel==="admin"){/* v112: as mesmas regras do Centro de comando, do mais urgente para o menos urgente */
    const P=(()=>{try{return window.__ELOLOG_INTERNO?.painelDados?.()||null}catch(_){return null}})()||{},sub=P.subscricoes||{},pr=P.prestadores||{},ap=P.apoio||{},en=P.encomendas||{};
    let pend=0;try{pend=(typeof getProviderProfiles==="function"?getProviderProfiles():[]).filter(p=>/pending|review/i.test(p.validationStatus||"")||/pendente|avalia/i.test(p.status||"")).length}catch(_){}
    const R=[[ap.escalados,n=>n===1?"Um cliente precisa da sua ajuda":`${n} clientes precisam da sua ajuda`,"Responder aos pedidos","showAdminPage('adminSupport')","urgente"],
      [pr.pendentes_mais_48h,n=>`${pl(n,"empresa espera","empresas esperam")} resposta há mais de 2 dias`,"Rever pedidos de inscrição","showAdminPage('adminProviderRequests')","urgente"],
      [sub.pagamentos_por_confirmar,n=>n===1?"Um prestador já pagou e espera confirmação":`${n} prestadores já pagaram e esperam confirmação`,"Confirmar pagamentos agora","showAdminPage('adminProviderRequests')","agora"],
      [diretas,n=>`${pl(n,"encomenda direta espera","encomendas diretas esperam")} a sua decisão`,"Decidir sobre as encomendas","showAdminPage('adminDirectOrders')","agora"],
      [Math.max(pr.pendentes||0,pend),n=>pl(n,"empresa espera validação","empresas esperam validação"),"Rever os documentos e decidir","showAdminPage('adminProviderRequests')","agora"],
      [en.paradas_mais_7d,n=>`${pl(n,"encomenda parada","encomendas paradas")} há mais de uma semana`,"Ver o que está parado","showAdminPage('adminOperations')","normal"],
      [ap.abertos,n=>`${pl(n,"pedido de apoio","pedidos de apoio")} por responder`,"Responder aos pedidos","showAdminPage('adminSupport')","normal"]];
    const h=R.find(r=>Number(r[0])>0);if(h)return{t:h[1](Number(h[0])),d:h[2],js:h[3],nivel:h[4]};
    return{t:"Tudo em ordem",d:"Nada à espera de si agora",js:"showPage('dashboard')",nivel:"calmo"}}
  return null}

function desenhar(){const u=eu(),papel=u?.role==="admin"?"admin":u?.role==="prestador"?"prestador":u?.role==="cliente"?"cliente":"";const sb=document.getElementById("sidebar");
  document.body.dataset.papel=papel;if(!sb||!papel)return;if(papel==="admin"&&!eu()?.suporte)contarDiretas().then(()=>{});
  const p=proximo(papel);let el=sb.querySelector(".nv-proximo");if(!p){el?.remove();return}
  if(!el){el=document.createElement("button");el.type="button";el.className="nv-proximo";const ub=sb.querySelector(".user-box");(ub||sb.firstElementChild)?.after(el)}
  el.dataset.nivel=p.nivel;el.setAttribute("onclick",p.js+";if(window.innerWidth<900&&typeof toggleSidebar==='function'&&document.getElementById('sidebar')?.classList.contains('open'))toggleSidebar()");
  el.innerHTML=p.nivel==="calmo"?`<strong><i class="ic ic-check" aria-hidden="true"></i>${esc(p.t)}</strong><span>${esc(p.d)}</span>`:`<small>O seu próximo passo</small><strong>${esc(p.t)}</strong><span>${esc(p.d)}</span>`;
  if(papel==="prestador"){const c=contagem(doPrestador());Object.entries(ETAPA_PAG).forEach(([pg,i])=>sb.querySelectorAll(`button[onclick*="'${pg}'"]:not(.nv-proximo)`).forEach(b=>{
    let s=b.querySelector(".nv-conta");if(!s){s=document.createElement("span");s.className="nv-conta";b.appendChild(s)}const n=c[i]||0;s.textContent=n?String(n):"";b.classList.remove("nv-zero");
    b.setAttribute("aria-label",`${b.textContent.replace(/\d+$/,"").trim()}: ${n?pl(n,"encomenda","encomendas"):"sem encomendas"}`)}))}
  grupos(sb)}
/* v154: o total de cada submenu aparece também na opção principal (vê-se com o grupo fechado) */
function grupos(sb){sb.querySelectorAll(".provider-submenu,.client-submenu").forEach(sub=>{const cab=sub.previousElementSibling;if(!cab||cab.tagName!=="BUTTON")return;
  const tot=[...sub.querySelectorAll(".nv-conta:not(.nv-conta-grupo)")].reduce((a,e)=>a+(parseInt(e.textContent,10)||0),0);let s=cab.querySelector(".nv-conta-grupo");
  if(!tot){s?.remove();return}if(!s){s=document.createElement("span");s.className="nv-conta nv-conta-grupo";s.setAttribute("aria-hidden","true");const ch=cab.querySelector("span:last-child:not(.nv-conta)");ch?cab.insertBefore(s,ch):cab.appendChild(s)}
  s.textContent=tot>99?"99+":String(tot)})}

let t=null;const agendar=()=>{clearTimeout(t);t=setTimeout(desenhar,250)};
document.addEventListener("DOMContentLoaded",()=>{const ini=window.startApp;if(typeof ini==="function")window.startApp=function(){const r=ini.apply(this,arguments);setTimeout(desenhar,600);return r};setTimeout(desenhar,1200);setInterval(desenhar,20000);document.addEventListener("click",e=>{if(e.target.closest?.("#sidebar,.btn-primary,.btn-success"))agendar()})});
window.elologNavegacao={atualizar:desenhar,proximo};
})();
