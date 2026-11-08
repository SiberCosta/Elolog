/* Elolog — som das notificações (v116).
   Toca um aviso curto sempre que o número de notificações por ler aumenta (cliente, prestador, operadores e administração).
   O som é gerado no navegador (Web Audio), sem ficheiros nem serviços externos. Liga/desliga no painel de notificações,
   guardado por utilizador neste navegador. Os navegadores só deixam tocar depois do primeiro clique ou toque na página. */
(function(){"use strict";
const CHAVE="elolog_som_notificacoes";let ctx=null,ultimo=null,ultimoSom=0;
const ligado=()=>{try{return localStorage.getItem(CHAVE)!=="0"}catch(_){return true}};
function audio(){if(!ctx){const A=window.AudioContext||window.webkitAudioContext;if(!A)return null;ctx=new A()}if(ctx.state==="suspended")ctx.resume().catch(()=>{});return ctx}

/** dois toques suaves (como um «ding-dong» curto); não toca mais de uma vez a cada 1,5 s */
function tocar(forcar){if(!forcar&&(!ligado()||Date.now()-ultimoSom<1500))return;const a=audio();if(!a)return;ultimoSom=Date.now();
  [[880,0],[1320,.16]].forEach(([f,t])=>{const o=a.createOscillator(),g=a.createGain(),i=a.currentTime+t;o.type="sine";o.frequency.value=f;
    g.gain.setValueAtTime(0.0001,i);g.gain.exponentialRampToValueAtTime(0.25,i+.02);g.gain.exponentialRampToValueAtTime(0.0001,i+.45);o.connect(g).connect(a.destination);o.start(i);o.stop(i+.5)});
  try{navigator.vibrate?.(120)}catch(_){}}

/* contador do sino: quando sobe, há notificação nova */
function contar(){const el=document.getElementById("notificationCount");if(!el)return null;return el.hidden?0:Number(String(el.textContent).replace(/\D/g,""))||0}
function verificar(){const n=contar();if(n==null)return;if(ultimo!=null&&n>ultimo)tocar();ultimo=n}
function vigiar(){const el=document.getElementById("notificationCount");if(!el)return;ultimo=contar();
  new MutationObserver(verificar).observe(el,{childList:true,characterData:true,subtree:true,attributes:true,attributeFilter:["hidden"]})}

/* botão no painel de notificações */
function botao(){const cab=document.querySelector("#notificationPanel .notification-panel-head");if(!cab||cab.querySelector(".som-notif"))return;
  const b=document.createElement("button");b.type="button";b.className="som-notif";const pinta=()=>{b.textContent=ligado()?"Som ligado":"Som desligado";b.setAttribute("aria-pressed",String(ligado()));
    b.title=ligado()?"Desligar o som das notificações":"Ligar o som das notificações"};pinta();
  b.addEventListener("click",e=>{e.stopPropagation();try{localStorage.setItem(CHAVE,ligado()?"0":"1")}catch(_){}pinta();if(ligado())tocar(true)});
  const marcar=cab.querySelector("button");marcar?marcar.before(b):cab.appendChild(b)}

/* desbloquear o áudio no primeiro gesto (regra dos navegadores) */
["pointerdown","keydown","touchstart"].forEach(ev=>document.addEventListener(ev,()=>audio(),{once:true,passive:true}));
document.addEventListener("DOMContentLoaded",()=>{vigiar();botao()});if(document.readyState!=="loading"){vigiar();botao()}
/* o cabeçalho e o contador podem ser redesenhados depois de entrar: volta a ligar o botão e confere o contador a cada 2 s */
document.addEventListener("click",e=>{if(e.target.closest?.("#notificationBell"))setTimeout(botao,0)});
setInterval(()=>{botao();verificar()},2000);
window.elologSomNotificacoes={tocar:()=>tocar(true),ligado,verificar};
})();
