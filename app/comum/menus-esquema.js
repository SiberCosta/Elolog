/* Elolog — menus do cliente e da administração organizados como no quadro «estrutura do Elolog» (v133).
   Cliente: Início · Nova simulação · Criar encomenda · Encomendas · Encomendas diretas · Pagamentos · Documentos · Apoio e perfil.
   Administração: Centro de comando · Prestadores · Subscrições · Operações · Conformidade e segurança · Apoio e reclamações ·
   Relatórios e definições · Configurações. Só muda nomes, ordem e agrupamento: os botões continuam a abrir as mesmas páginas,
   e o que não estava no desenho (por exemplo Email e Chat da equipa) fica onde estava. Corre depois dos módulos que acrescentam entradas. */
(function(){"use strict";
const $=id=>document.getElementById(id);
const SVG=d=>`<svg class="mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
const ICONE={com:'<path d="M4 5h16v11H8l-4 4z"/><path d="M8 9h8M8 12h5"/>',criar:'<path d="M12 5v14M5 12h14"/><rect x="3" y="3" width="18" height="18" rx="3"/>',pagar:'<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18M7 15h3"/>',
  doc:'<path d="M7 3h7l4 4v14H7z"/><path d="M14 3v4h4M10 12h5M10 16h5"/>',conf:'<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'};
/* troca o texto visível de um botão sem mexer no ícone */
function rotulo(b,novo){if(!b)return;const alvo=b.querySelector(".mi-l")||b;const t=[...alvo.childNodes].reverse().find(n=>n.nodeType===3&&n.textContent.trim());
  if(t){if(t.textContent.trim()!==novo)t.textContent=novo}else if(!alvo.querySelector("svg,i"))alvo.textContent=novo}
const porTexto=(raiz,txt)=>raiz?[...raiz.querySelectorAll("button")].find(b=>b.textContent.replace(/[⌄⌃]/g,"").trim()===txt):null;
const porAcao=(raiz,re)=>raiz?[...raiz.querySelectorAll("button")].find(b=>re.test(b.getAttribute("onclick")||"")):null;

/* ---------- cliente ---------- */
function cliente(){if(typeof currentUser==="undefined"||currentUser?.role!=="cliente")return;const nav=document.querySelector("#sidebar .menu");if(!nav)return;
  let criar=$("menuCriarEncomenda");
  if(!criar){criar=document.createElement("button");criar.type="button";criar.id="menuCriarEncomenda";criar.innerHTML=SVG(ICONE.criar)+"Criar encomenda";
    criar.setAttribute("onclick","window.elologCriarEncomenda?elologCriarEncomenda.abrir(this):showPage('clientSimulation',this)");nav.appendChild(criar)}
  /* Pagamentos passa a ser uma entrada própria; o grupo fica só com Documentos e Centro documental */
  const pag=$("menuPayments");if(pag&&pag.parentElement?.id==="clientFinanceSubmenu"){pag.classList.add("menu-esq-topo");if(!pag.querySelector("svg"))pag.insertAdjacentHTML("afterbegin",SVG(ICONE.pagar));nav.appendChild(pag)}
  const fin=$("menuFinance");if(fin)rotulo(fin,"Documentos");
  const ordem={menuDashboard:1,menuSimulation:2,menuCriarEncomenda:3,menuOrders:4,clientOrdersSubmenu:5,menuDirectOrders:6,menuPayments:7,menuFinance:8,clientFinanceSubmenu:9,menuHelp:10,clientHelpSubmenu:11};
  Object.entries(ordem).forEach(([id,n])=>{const e=$(id);if(e)e.style.order=String(n)});
  [criar,pag].forEach(b=>{if(b)b.style.display="block"})}

/* ---------- administração ---------- */
function admin(){const m=$("adminMenuStructure");if(!m||typeof currentUser==="undefined"||currentUser?.role!=="admin")return;
  const grupo=id=>$(id)?.closest(".provider-menu-group")?.querySelector(".provider-menu-main");
  rotulo(grupo("adminGrpFin"),"Subscrições");rotulo(grupo("adminGrpOp"),"Operações");
  rotulo(porTexto($("adminGrpPrest"),"Prestadores ativos"),"Ativos");rotulo(porTexto($("adminGrpFin"),"Planos e subscrições"),"Planos");
  const op=$("adminGrpOp");if(op){rotulo(porAcao(op,/elologPedidoContacto/),"Criar encomenda");rotulo(op.querySelector("#adminMenuTerreno"),"Acompanhamento");
    [porAcao(op,/adminOperations/),porAcao(op,/adminClients/),porAcao(op,/elologPedidoContacto/),porAcao(op,/elologEncDiretasGestao/),op.querySelector("#adminMenuTerreno")].forEach(b=>{if(b)op.appendChild(b)})}
  rotulo(porTexto($("adminGrpSis"),"Auditoria de prestador"),"Auditoria do prestador");
  /* Configurações passa a entrada própria, a seguir a «Relatórios e definições» */
  const sis=$("adminGrpSis"),cfg=porAcao(sis,/adminSettings/);
  if(cfg){cfg.className="provider-menu-main";cfg.innerHTML=`<span class="mi-l">${SVG(ICONE.conf)}Configurações</span>`;sis.closest(".provider-menu-group").after(cfg)}
  /* v135: «Relatórios»; Operações antes de Subscrições; Apoio, Email e Chat juntos em «Comunicação» */
  rotulo(grupo("adminGrpSis"),"Relatórios");
  const gOp=$("adminGrpOp")?.closest(".provider-menu-group"),gFin=$("adminGrpFin")?.closest(".provider-menu-group");if(gOp&&gFin&&gOp.compareDocumentPosition(gFin)&Node.DOCUMENT_POSITION_PRECEDING)gFin.before(gOp);
  if(!$("adminGrpCom")){const soltos=[porAcao(m,/showAdminPage\('adminSupport'/),porAcao(m,/elologEmail\.abrir/),porAcao(m,/elologChat\.abrir/)].filter(b=>b&&!b.closest(".provider-submenu"));
    if(soltos.length>1){const g=document.createElement("div");g.className="provider-menu-group";
      g.innerHTML=`<button type="button" class="provider-menu-main" aria-expanded="false" onclick="toggleAdminGroup('adminGrpCom',this)"><span class="mi-l">${SVG(ICONE.com)}Comunicação</span><span>⌄</span></button><div id="adminGrpCom" class="provider-submenu"></div>`;
      soltos[0].before(g);const sub=g.querySelector("#adminGrpCom");
      soltos.forEach(b=>{const t=b.textContent.replace(/\s+/g," ").trim();b.className="";b.textContent=t;sub.appendChild(b)})}}}

function aplicar(){try{cliente()}catch(e){console.warn("menu do cliente",e)}try{admin()}catch(e){console.warn("menu da administração",e)}}
const conf=window.configureRole;if(typeof conf==="function"&&!conf.__esq){const n=function(){const r=conf.apply(this,arguments);aplicar();setTimeout(aplicar,0);setTimeout(aplicar,900);return r};n.__esq=1;window.configureRole=n}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",aplicar);else aplicar();
window.addEventListener("load",()=>setTimeout(aplicar,300));
window.elologMenusEsquema={aplicar};
})();
