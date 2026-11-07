/* Elolog — Encomendas diretas na administração e no prestador (v98).
   Administração: analisa o comprovativo, valida (ou não valida, com motivo para o cliente) e encaminha ao prestador escolhido pelo cliente.
   Prestador: coloca em análise, aceita ou recusa — a recusa exige motivo. A recusa volta à administração e ao cliente; ninguém além do
   cliente muda o prestador, e nada é eliminado. */
(function(){"use strict";
const D=()=>window.elologED,P=()=>window.elologProducao,esc=v=>D().esc(v);
const aviso=(t,k)=>window.showPlatformNotice?.(t,k||"info");
const papel=()=>typeof currentUser!=="undefined"?currentUser?.role:null;
const FILTROS={admin:[["acao","Por tratar",["pendente_validacao","em_analise_admin","validada","recusada"]],["prest","No prestador",["enviada_prestador","em_analise_prestador"]],
  ["fim","Concluídas",["aceite","nao_validada","cancelada"]],["todas","Todas",null]],
  prestador:[["acao","Por decidir",["enviada_prestador","em_analise_prestador"]],["fim","Decididas",["aceite","recusada"]],["todas","Todas",null]]};
let lista=[],filtro="acao";

function acoes(e){const A=(k,t,p)=>`<button type="button" class="${p?"btn-primary":"btn-secondary"}" data-ed="${k}">${t}</button>`;
  if(papel()==="admin"){const s=e.estado;return(["pendente_validacao","em_analise_admin"].includes(s)?A("rever","Analisar e validar",1):"")+(s==="validada"?A("enviar","Encaminhar ao prestador",1)+A("rever","Rever"):"")+
    (["pendente_validacao","em_analise_admin","validada"].includes(s)?A("corrigir","Corrigir dados")+A("pedir","Pedir documentos"):"")+(["recusada","nao_validada"].includes(s)&&e.cliente_email?`<a class="btn-secondary" href="mailto:${esc(e.cliente_email)}?subject=${encodeURIComponent("Encomenda direta "+e.codigo)}">Contactar cliente</a>`:"")}
  const s=e.estado;return(s==="enviada_prestador"?A("analisar","Colocar em análise"):"")+(["enviada_prestador","em_analise_prestador"].includes(s)?A("aceitar","Aceitar",1)+A("recusar","Recusar"):"")}

function recusar(e){const j=P().janela({eyebrow:"ENCOMENDA "+e.codigo,titulo:"Recusar encomenda direta"});
  j.mostrar(`<p>O motivo é obrigatório. A administração recebe a recusa e fala com o cliente; o pedido não é eliminado nem enviado a outro prestador sem o cliente.</p>
    <fieldset class="ed-motivos"><legend>Motivo *</legend>${Object.entries(D().MOTIVOS).map(([k,t])=>`<label><input type="radio" name="edMot" value="${k}"> ${esc(t)}</label>`).join("")}</fieldset>
    <div class="pc-campo"><label for="edMotTxt">Detalhe <small>(obrigatório em «Outro motivo»)</small></label><textarea id="edMotTxt" rows="2" maxlength="500"></textarea></div><p class="campo-erro" id="edErroR" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Recusar",principal:true,acao:async()=>{const tipo=document.querySelector('input[name="edMot"]:checked')?.value,txt=(document.getElementById("edMotTxt").value||"").trim(),er=document.getElementById("edErroR");
      if(!tipo){er.textContent="Escolha o motivo da recusa.";return}if(tipo==="outro"&&txt.length<5){er.textContent="Descreva o motivo da recusa.";return}
      try{await D().prestador(e.id,"recusar",tipo,txt);j.fechar();aviso("Recusa registada. A administração foi avisada.","info");desenhar()}catch(x){er.textContent=D().erro(x)}}}])}

async function executar(e,k,i){const ok=t=>{aviso(t,"success");desenhar()};
  try{if(k==="comprovativo")return await D().comprovativo(e);if(k==="anexo")return await D().comprovativo(e,+i);
    if(papel()==="admin"){const R=window.elologEDRevisao,dep=()=>desenhar();if(k==="rever")return R.rever(e,dep);if(k==="corrigir")return R.corrigir(e,dep);if(k==="pedir")return R.pedir(e,dep);
      if(k==="enviar"){await D().admin(e.id,"enviar");return ok(`Encomenda enviada a ${e.prestador}.`)}}
    else{if(k==="analisar"){await D().prestador(e.id,"analisar");return ok("Pedido colocado em análise.")}
      if(k==="aceitar"){await D().prestador(e.id,"aceitar");return ok("Encomenda aceite. O cliente e a administração foram avisados.")}
      if(k==="recusar")return recusar(e)}}catch(x){aviso(D().erro(x),"error")}}

function pagina(){const id=papel()==="admin"?"adminDirectOrders":"providerDirectOrders";let s=document.getElementById(id);if(s)return s;const base=document.getElementById("dashboard");if(!base)return null;
  s=document.createElement("section");s.id=id;s.className="page";base.parentElement.appendChild(s);
  s.addEventListener("click",ev=>{const f=ev.target.closest("[data-filtro]");if(f){filtro=f.dataset.filtro;return mostrar()}
    const b=ev.target.closest("[data-ed]");if(!b)return;const e=lista.find(x=>String(x.id)===b.closest(".ed-cartao")?.dataset.id);if(e)executar(e,b.dataset.ed,b.dataset.i)});return s}
function mostrar(){const s=pagina(),F=FILTROS[papel()==="admin"?"admin":"prestador"];if(!s)return;const f=F.find(x=>x[0]===filtro)||F[0];
  const vis=f[2]?lista.filter(e=>f[2].includes(e.estado)):lista,conta=k=>{const x=F.find(y=>y[0]===k);return x[2]?lista.filter(e=>x[2].includes(e.estado)).length:lista.length};
  s.querySelector(".ed-filtros").innerHTML=F.map(([k,t])=>`<button type="button" class="pa-periodo ${k===f[0]?"ativo":""}" data-filtro="${k}">${t} <b>${conta(k)}</b></button>`).join("");
  s.querySelector(".ed-lista").innerHTML=vis.length?vis.map(e=>D().cartao(e,acoes(e))).join(""):'<p class="ed-vazio">Sem encomendas diretas neste filtro.</p>'}
async function desenhar(){const s=pagina();if(!s)return;const adm=papel()==="admin";
  s.innerHTML=`<div class="ed-topo"><div><h2>Encomendas diretas</h2><p>${adm?"Negociadas pelo cliente com um prestador: valide o comprovativo e encaminhe ao prestador escolhido.":"Pedidos validados pela Elolog: aceite, recuse (com motivo) ou coloque em análise."}</p></div></div>
    <div class="ed-filtros" role="group" aria-label="Filtrar"></div><div class="ed-lista"><p class="ed-vazio">A carregar…</p></div>`;
  try{lista=await D().listar()}catch(e){s.querySelector(".ed-lista").innerHTML=`<p class="campo-erro">${esc(D().erro(e))}</p>`;return}mostrar()}
function abrir(btn){pagina();if(papel()==="admin")showAdminPage("adminDirectOrders",btn);else showProviderPage("providerDirectOrders",btn);desenhar()}

/* ---------- entradas no menu ---------- */
function menu(){const r=papel();if(r==="admin"){const g=document.getElementById("adminGrpOp");if(g&&!g.querySelector("[data-ed-menu]"))
    g.insertAdjacentHTML("beforeend",'<button type="button" data-ed-menu onclick="elologEncDiretasGestao.abrir(this)">Encomendas diretas</button>')}
  if(r==="prestador"){const m=document.getElementById("providerMenuStructure"),g=m?.querySelector(".provider-submenu");if(g&&!m.querySelector("[data-ed-menu]"))
    g.insertAdjacentHTML("afterbegin",'<button type="button" data-ed-menu onclick="elologEncDiretasGestao.abrir(this)">Encomendas diretas</button>')}}
const conf=window.configureRole;if(typeof conf==="function")window.configureRole=function(){const x=conf.apply(this,arguments);setTimeout(()=>{try{menu()}catch(_){}},0);return x};
const perm=window.applyProviderPermissions;if(typeof perm==="function")window.applyProviderPermissions=function(){const x=perm.apply(this,arguments);setTimeout(()=>{try{menu()}catch(_){}},0);return x};
window.elologEncDiretasGestao={abrir,desenhar,menu};
})();
