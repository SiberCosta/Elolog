/* Elolog — botão «voltar» dentro da plataforma (v86).
   Cada opção aberta no menu fica no histórico do navegador. O «voltar» do telemóvel/navegador regressa à opção anterior
   em vez de sair para a página principal. No início (primeira opção) pede um segundo toque para sair. */
(function(){"use strict";
const FUNCOES=["showPage","showProviderPage","showAdminPage","showProviderFieldPage"];
let profundidade=0,restaurar=false,ultimoToque=0,atual=null;
const aviso=m=>{try{typeof showPlatformNotice==="function"?showPlatformNotice(m,"info"):window.elologProducao?.aviso(m,"info")}catch(_){}};
const botao=p=>document.querySelector(`#sidebar [onclick*="'${p}'"]`)||document.querySelector(`[onclick*="'${p}'"]`);
const dentro=()=>{try{return!!currentUser&&!!document.getElementById("app")?.classList.contains("app-visible")}catch(_){return false}};

function registar(fn,pagina){if(restaurar||profundidade>1||!dentro()||typeof pagina!=="string")return;
  const novo={fn,pagina};if(atual&&atual.fn===novo.fn&&atual.pagina===novo.pagina)return;
  if(!history.state?.elo)history.replaceState({elo:{guarda:true}},"");                // base: o «voltar» a partir daqui pede confirmação
  history.pushState({elo:novo},"");
  atual=novo}

FUNCOES.forEach(nome=>{const orig=window[nome];if(typeof orig!=="function")return;
  window[nome]=function(pagina){profundidade++;try{return orig.apply(this,arguments)}finally{registar(nome,pagina);profundidade--}}});

function abrir(e){const f=window[e.fn];if(typeof f!=="function")return;restaurar=true;try{f(e.pagina,botao(e.pagina))}catch(_){}finally{restaurar=false}atual=e}

window.addEventListener("popstate",ev=>{const e=ev.state?.elo;if(!dentro())return;
  const menu=document.getElementById("sidebar");                                   // 1.º: fecha o menu aberto
  if(menu?.classList.contains("open")&&window.innerWidth<=900){window.closeSidebar?.();if(e?.guarda&&atual)history.pushState({elo:atual},"");return}
  if(e&&!e.guarda){abrir(e);return}
  if(e?.guarda){const inicio={fn:"showPage",pagina:"dashboard"};
    if(atual&&atual.pagina!=="dashboard"){abrir(inicio);history.pushState({elo:inicio},"");return}   // primeiro volta ao início
    const agora=Date.now();if(agora-ultimoToque<2500){history.back();return}                         // no início: 2 toques para sair
    ultimoToque=agora;history.pushState({elo:atual||inicio},"");aviso("Toque outra vez em «voltar» para sair da plataforma.")}});
})();
