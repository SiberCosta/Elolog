/* Elolog — botões (v105): onda no ponto onde o botão é tocado ou clicado. Só aspeto; não muda o que o botão faz.
   Respeita «reduzir movimento» do sistema. A onda fica dentro do botão (recorte próprio) e desaparece sozinha. */
(function(){"use strict";
const SEL=".btn-primary,.btn-secondary,.btn-success,.btn-danger,.btn-ghost,.primary-btn,.btn-search,.btn-register-profile,.sim-add-button,.employee-action,.pa-botao,.ct-btn,.btn-selecionar-prestador,.pv-btn,.pv-btn-i,.hero-btn";
const calmo=()=>window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
document.addEventListener("pointerdown",ev=>{const b=ev.target.closest?.(SEL);if(!b||b.disabled||b.getAttribute("aria-disabled")==="true"||calmo())return;
  if(getComputedStyle(b).position==="static")b.style.position="relative";
  const r=b.getBoundingClientRect(),d=Math.max(r.width,r.height)*2.2,o=document.createElement("span"),c=document.createElement("i");
  o.className="bv-onda";o.setAttribute("aria-hidden","true");c.style.cssText=`width:${d}px;height:${d}px;left:${ev.clientX-r.left-d/2}px;top:${ev.clientY-r.top-d/2}px`;
  o.appendChild(c);b.appendChild(o);setTimeout(()=>o.remove(),620)},{passive:true});
})();
