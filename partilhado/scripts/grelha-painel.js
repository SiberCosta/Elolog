/* Elolog v2 — painéis sem buracos: numa grelha de 12 colunas, um bloco que fica sozinho numa linha incompleta
   alarga até ao fim da linha. Só aspeto (estilo em linha grid-column); os blocos, a ordem e as escolhas do utilizador ficam iguais. */
(function(){"use strict";
  const larga=()=>window.matchMedia("(min-width: 900px)").matches;
  function span(e){const m=[...e.classList].join(" ").match(/\bpw-s(\d+)\b/);return m?Math.min(12,+m[1]):12}
  function arrumar(g){
    const itens=[...g.children].filter(e=>e.classList.contains("pw")&&e.offsetParent!==null||e.classList.contains("pw")&&getComputedStyle(e).display!=="none");
    itens.forEach(e=>{if(e.dataset.alargado){e.style.gridColumn="";delete e.dataset.alargado}});
    if(!larga()||getComputedStyle(g).display!=="grid")return;
    let usado=0,ultimo=null;
    const fechar=()=>{if(ultimo&&usado>0&&usado<12){ultimo.style.gridColumn="span "+(12-usado+span(ultimo));ultimo.dataset.alargado="1"}};
    for(const e of itens){if(getComputedStyle(e).display==="none")continue;const s=span(e);
      if(usado+s>12){fechar();usado=0}
      usado+=s;ultimo=e;if(usado===12){usado=0;ultimo=null}}
    fechar();
  }
  let t=0;const tudo=()=>{clearTimeout(t);t=setTimeout(()=>document.querySelectorAll(".pw-grelha").forEach(arrumar),120)};
  function iniciar(){tudo();new MutationObserver(m=>{if(m.some(x=>[...x.addedNodes,...x.removedNodes].some(n=>n.nodeType===1&&(n.matches?.(".pw,.pw-grelha")||n.querySelector?.(".pw-grelha")))))tudo()}).observe(document.body,{childList:true,subtree:true});window.addEventListener("resize",tudo)}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
})();
