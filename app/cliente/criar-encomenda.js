/* Elolog — «Criar encomenda» do cliente (v141).
   O botão do menu abre a mesma página da simulação, preparada para criar a encomenda: título, texto, passos e botões
   falam de encomenda e não de cotação. O fluxo é o mesmo (rota e carga → prestador → criar encomenda), por isso os
   preços continuam a vir do servidor e a encomenda é criada pelo mesmo botão. «Nova simulação» repõe os textos originais.
   O registo de encomendas negociadas fora da plataforma continua em «Encomendas diretas». */
(function(){"use strict";
const $=id=>document.getElementById(id);
const TEXTOS={
  simulacao:{titulo:"Simulação de cotação",intro:"O seu perfil será usado como remetente. Preencha os dados essenciais para obter propostas.",
    avancar:"Avançar para propostas",passos:["Rota e carga","Propostas","Criar envio","Pagamento"]},
  encomenda:{titulo:"Criar encomenda",intro:"O seu perfil será usado como remetente. Indique a rota e a carga, escolha o prestador e crie a encomenda. O prestador confirma a recolha e o preço final.",
    avancar:"Escolher prestador",passos:["Rota e carga","Prestador","Confirmar encomenda","Pagamento"]}};
let modo="simulacao";

function guardarOriginal(el){if(el&&!el.dataset.textoOriginal)el.dataset.textoOriginal=el.textContent}
function aplicar(){const pag=$("clientSimulation");if(!pag)return;const t=TEXTOS[modo];
  pag.classList.toggle("modo-criar-encomenda",modo==="encomenda");
  const h=pag.querySelector(".client-sim-card .card-title h3");if(h)h.textContent=t.titulo;
  const intro=pag.querySelector(".client-sim-intro");if(intro)intro.textContent=t.intro;
  const avancar=pag.querySelector('[onclick="runClientSimulation()"]');if(avancar){guardarOriginal(avancar);avancar.textContent=t.avancar}
  const passos=$("clientSimSteps");if(passos){passos.setAttribute("aria-label",modo==="encomenda"?"Passos da encomenda":"Passos da simulação");
    [...passos.children].forEach((li,i)=>{const b=li.querySelector("b");li.textContent="";if(b)li.appendChild(b);li.append(t.passos[i]||"")})}
  const res=pag.querySelector(".sim-result-header h4, .client-sim-summary h4");if(res){guardarOriginal(res);res.textContent=modo==="encomenda"?"Resumo da encomenda":res.dataset.textoOriginal}
  const criarBtn=pag.querySelector('#clientCreateShipment [onclick="criarEnvioCliente()"]');if(criarBtn)criarBtn.textContent=modo==="encomenda"?"Confirmar encomenda":"Criar encomenda";
  marcarMenu()}
function marcarMenu(){const criar=$("menuCriarEncomenda"),sim=$("menuSimulation");if(criar&&modo!=="encomenda")delete criar.dataset.pagina;if(!$("clientSimulation")?.classList.contains("active"))return;
  if(criar){if(modo==="encomenda")criar.dataset.pagina="clientSimulation";else delete criar.dataset.pagina}
  const [on,off]=modo==="encomenda"?[criar,sim]:[sim,criar];
  if(off){off.classList.remove("client-menu-active");off.removeAttribute("aria-current")}if(on){on.classList.add("client-menu-active");on.setAttribute("aria-current","page")}
  const tit=document.querySelector(".topbar h1,.topbar h2,#pageTitle");if(tit&&/Simula|Criar encomenda/.test(tit.textContent))tit.textContent=modo==="encomenda"?"Criar encomenda":"Simulação"}

/* abre a página em modo encomenda; se já houver uma simulação a meio, mantém-na (o cliente pode estar a continuar) */
function abrir(botao){modo="encomenda";if(typeof showPage==="function")showPage("clientSimulation",botao);aplicar();
  setTimeout(()=>{aplicar();const o=$("clientSimOrigin");if(o&&!o.value)try{o.focus({preventScroll:true})}catch(_){}},60)}

/* qualquer outra entrada na página (menu «Nova simulação», atalhos do painel) volta ao modo simulação */
function ligar(){const sp=window.showPage;if(typeof sp!=="function"||sp.__criarEnc)return;
  const novo=function(pagina){if(pagina==="clientSimulation"||pagina==="simulation"){if(!novo.__aAbrir)modo="simulacao"}
    const r=sp.apply(this,arguments);if(pagina==="clientSimulation"||pagina==="simulation")setTimeout(aplicar,0);return r};
  novo.__criarEnc=1;window.showPage=novo;
  const abrirOrig=abrir;window.elologCriarEncomenda.abrir=function(b){novo.__aAbrir=1;try{abrirOrig(b)}finally{novo.__aAbrir=0}}}

/* os passos são redesenhados por menu.js a cada mudança; só reponho o texto quando muda o modo ou o DOM do passo */
function vigiar(){const passos=$("clientSimSteps");if(!passos||passos.__vigiado)return;passos.__vigiado=1;
  new MutationObserver(()=>{const t=TEXTOS[modo];const atual=[...passos.children].map(li=>li.textContent.replace(/^\d+/,"").trim());
    if(atual.some((x,i)=>x!==t.passos[i]))aplicar()}).observe(passos,{childList:true,subtree:true,characterData:true})}

window.elologCriarEncomenda={abrir,aplicar,modo:()=>modo};
function arrancar(){ligar();vigiar()}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arrancar);else arrancar();
window.addEventListener("load",()=>setTimeout(arrancar,200));
})();
