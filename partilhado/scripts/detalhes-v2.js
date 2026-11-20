/* Elolog v2 — pormenores de apresentação: o contador do sino esconde-se quando é 0. Não muda a contagem nem as notificações. */
(function(){"use strict";
  function ver(){const c=document.getElementById("notificationCount");if(!c)return false;const z=()=>c.classList.toggle("zero",(c.textContent||"").trim()===""||(c.textContent||"").trim()==="0");z();new MutationObserver(z).observe(c,{childList:true,characterData:true,subtree:true});return true}
  function iniciar(){if(ver())return;const o=new MutationObserver(()=>{if(ver())o.disconnect()});o.observe(document.body,{childList:true,subtree:true})}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
})();
