/* Elolog — atualizar sem mexer o ecrã (v154).
   Quando os dados chegam (tempo real, outro separador, servidor), os ecrãs redesenham as listas. Isto guarda onde a pessoa
   estava (posição da página, listas com barra própria, campo com o cursor) e repõe-no a cada redesenho durante uns
   segundos — a não ser que a própria pessoa mexa (rodar, tocar, teclar), e aí deixa-a em paz. */
(function(){"use strict";
let ate=0,estado=null,obs=null,pedido=0;
function raizes(){return[...document.querySelectorAll(".page.active,#platformRecordDrawer,.provider-drawer.open,.pm-janela,.modal.show,#sidebar")]}
function guardar(){const listas=[];raizes().forEach(r=>{if(r.scrollTop>0)listas.push([r,r.scrollTop]);r.querySelectorAll("*").forEach(e=>{if(e.scrollTop>0)listas.push([e,e.scrollTop,cam(e)])})});
  const a=document.activeElement,campo=a&&a!==document.body&&a.id?{id:a.id,ini:a.selectionStart,fim:a.selectionEnd}:null;
  estado={x:window.scrollX,y:window.scrollY,listas,campo,principal:document.querySelector(".main-content,main")?.scrollTop||0}}
/* caminho simples para reencontrar uma lista redesenhada (id ou classe + posição) */
function cam(e){if(e.id)return"#"+CSS.escape(e.id);const c=[...e.classList].map(x=>"."+CSS.escape(x)).join("");if(!c)return null;const t=document.querySelectorAll(c);return t.length===1?c:null}
function repor(){if(!estado||Date.now()>ate)return parar();
  if(Math.abs(window.scrollY-estado.y)>2)window.scrollTo({left:estado.x,top:estado.y,behavior:"instant"});
  const m=document.querySelector(".main-content,main");if(m&&estado.principal&&Math.abs(m.scrollTop-estado.principal)>2)m.scrollTo({top:estado.principal,behavior:"instant"});
  estado.listas.forEach(([e,t,c])=>{let el=e;if(!el.isConnected&&c)el=document.querySelector(c);if(el&&Math.abs(el.scrollTop-t)>2)el.scrollTo({top:t,behavior:"instant"})});
  const f=estado.campo;if(f&&document.activeElement?.id!==f.id){const el=document.getElementById(f.id);if(el){try{el.focus({preventScroll:true});if(f.ini!=null)el.setSelectionRange(f.ini,f.fim)}catch(_){}}}}
function agendar(){cancelAnimationFrame(pedido);pedido=requestAnimationFrame(repor)}
function parar(){obs?.disconnect();obs=null;estado=null}
function proteger(ms){guardar();ate=Date.now()+(ms||3000);if(!obs){obs=new MutationObserver(agendar);obs.observe(document.body,{childList:true,subtree:true})}}
["wheel","touchstart","mousedown"].forEach(ev=>window.addEventListener(ev,e=>{if(estado&&e.isTrusted)parar()},{passive:true,capture:true}));
/* algo que faça deslizar a página sozinho (foco, «scrollIntoView») durante a proteção também é desfeito */
window.addEventListener("scroll",()=>{if(estado)agendar()},{passive:true,capture:true});
window.elologSemSaltos={proteger,parar};
})();
