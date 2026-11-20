/* Elolog v2 — tema da área interna: claro, escuro ou igual ao sistema. A escolha fica neste navegador (só aspeto, nunca dados). Carregar no <head>, antes das folhas de estilo. */
(function(){
  const CHAVE="elolog_tema",TEMAS=["claro","escuro","sistema"],NOMES={claro:"Claro",escuro:"Escuro",sistema:"Sistema"};
  const ICO={claro:'<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4"/>',escuro:'<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',sistema:'<rect x="3" y="4.5" width="18" height="12" rx="1.5"/><path d="M9 20h6M12 16.5V20"/>'};
  const ler=()=>{try{const t=localStorage.getItem(CHAVE);return TEMAS.includes(t)?t:"claro"}catch(e){return "claro"}};
  const aplicar=t=>{document.documentElement.setAttribute("data-tema",t);const b=document.getElementById("eloTemaBotao");if(b){b.querySelector("span").textContent=NOMES[t];const g=b.querySelector("svg");if(g)g.innerHTML=ICO[t];b.setAttribute("aria-label","Tema: "+NOMES[t]+". Mudar tema")}};
  aplicar(ler());
  /* proposta de estilo «Carta náutica»: ?estilo=carta liga, ?estilo=v2 desliga (fica guardado neste navegador) */
  try{const q=new URLSearchParams(location.search).get("estilo");if(q==="carta")localStorage.setItem("elolog_estilo","carta");else if(q==="v2")localStorage.removeItem("elolog_estilo");
    if(localStorage.getItem("elolog_estilo")==="carta")document.documentElement.setAttribute("data-estilo","carta")}catch(e){}
  function botao(){
    if(document.getElementById("eloTemaBotao"))return;
    const barra=document.querySelector("#app .topbar");if(!barra)return;
    const b=document.createElement("button");b.type="button";b.id="eloTemaBotao";b.className="elo-tema-botao";
    b.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"></svg><span></span>';b.title="Mudar tema (claro, escuro ou igual ao sistema)";
    b.addEventListener("click",()=>{const t=TEMAS[(TEMAS.indexOf(ler())+1)%TEMAS.length];try{localStorage.setItem(CHAVE,t)}catch(e){}aplicar(t)});
    const antes=barra.querySelector(".notification-center")||null;barra.insertBefore(b,antes);aplicar(ler());
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",botao);else botao();
  window.ELOLogTema={aplicar,ler};
})();
