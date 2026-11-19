/* Elolog v2 — tema da área interna: claro, escuro ou igual ao sistema. A escolha fica neste navegador (só aspeto, nunca dados). Carregar no <head>, antes das folhas de estilo. */
(function(){
  const CHAVE="elolog_tema",TEMAS=["claro","escuro","sistema"],NOMES={claro:"Claro",escuro:"Escuro",sistema:"Sistema"};
  const ler=()=>{try{const t=localStorage.getItem(CHAVE);return TEMAS.includes(t)?t:"claro"}catch(e){return "claro"}};
  const aplicar=t=>{document.documentElement.setAttribute("data-tema",t);const b=document.getElementById("eloTemaBotao");if(b){b.querySelector("span").textContent=NOMES[t];b.setAttribute("aria-label","Tema: "+NOMES[t]+". Mudar tema")}};
  aplicar(ler());
  function botao(){
    if(document.getElementById("eloTemaBotao"))return;
    const barra=document.querySelector("#app .topbar");if(!barra)return;
    const b=document.createElement("button");b.type="button";b.id="eloTemaBotao";b.className="elo-tema-botao";
    b.innerHTML='<i class="ic ic-settings" aria-hidden="true"></i><span></span>';
    b.addEventListener("click",()=>{const t=TEMAS[(TEMAS.indexOf(ler())+1)%TEMAS.length];try{localStorage.setItem(CHAVE,t)}catch(e){}aplicar(t)});
    const antes=barra.querySelector(".notification-center")||null;barra.insertBefore(b,antes);aplicar(ler());
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",botao);else botao();
  window.ELOLogTema={aplicar,ler};
})();
