/* Elolog — «Mais ações» nunca fica escondido (v155). O menu abre por cima de tudo (posição fixa no ecrã), alinhado à
   direita do botão; se não houver espaço por baixo, abre para cima. Fecha ao clicar fora, com Esc ou ao deslizar. */
(function(){"use strict";
function posicionar(d){const m=d.querySelector(':scope>div[role="menu"]'),s=d.querySelector("summary");if(!m||!s)return;
  const r=s.getBoundingClientRect(),st=(k,v)=>m.style.setProperty(k,v,"important");st("position","fixed");st("right","auto");st("bottom","auto");st("z-index","2147482000");st("visibility","hidden");st("top","0px");st("left","0px");st("margin","0");st("transform","none");
  const w=m.offsetWidth,h=m.offsetHeight,baixo=innerHeight-r.bottom-8,cima=r.top-8;
  const top=(h<=baixo||baixo>=cima)?r.bottom+6:Math.max(8,r.top-6-h),left=Math.min(Math.max(8,r.right-w),innerWidth-w-8);
  st("top",top+"px");st("left",left+"px");st("max-height",Math.max(160,(top>r.top?baixo:cima)-6)+"px");st("overflow-y","auto");st("visibility","visible")}
function fecharOutros(atual){document.querySelectorAll("details.pr-mais[open],details.acoes-mais[open]").forEach(d=>{if(d!==atual)d.removeAttribute("open")})}
document.addEventListener("toggle",e=>{const d=e.target;if(!(d instanceof HTMLDetailsElement)||!(d.classList.contains("pr-mais")||d.classList.contains("acoes-mais")))return;if(d.open){fecharOutros(d);posicionar(d)}},true);
document.addEventListener("click",e=>{if(!e.target.closest?.("details.pr-mais,details.acoes-mais"))fecharOutros(null);else if(e.target.closest('div[role="menu"] button'))setTimeout(()=>fecharOutros(null),0)},true);
document.addEventListener("keydown",e=>{if(e.key==="Escape")fecharOutros(null)});
window.addEventListener("scroll",e=>{if(e.target?.closest?.('details.pr-mais div[role="menu"],details.acoes-mais div[role="menu"]'))return;fecharOutros(null)},{capture:true,passive:true});
window.addEventListener("resize",()=>fecharOutros(null));
})();
