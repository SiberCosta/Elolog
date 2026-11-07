/* Elolog — aviso no ecrã quando chega um email (v86).
   O email-1.js verifica as caixas a cada 30 s e lança «elolog:email-novo». Aqui mostra-se um cartão com remetente e assunto
   (e, se a página estiver em segundo plano e o utilizador tiver autorizado, um aviso do sistema). */
(function(){"use strict";
const E=()=>window.__elologEmail,esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const curto=(t,n)=>{t=String(t||"").trim();return t.length>n?t.slice(0,n-1)+"…":t};
let pilha=null;const vistos=new Set();

function cartao(m){if(!pilha){pilha=document.createElement("div");pilha.className="em-avisos";pilha.setAttribute("aria-live","polite");document.body.appendChild(pilha)}
  const d=document.createElement("div");d.className="em-aviso";d.setAttribute("role","status");
  d.innerHTML=`<span class="em-aviso-ic" aria-hidden="true">✉</span><div class="em-aviso-txt"><strong>Novo email${m.caixa?` · ${esc(curto(m.caixa,28))}`:""}</strong>
    ${m.de?`<span>${esc(curto(m.de,48))}</span>`:""}<em>${esc(curto(m.assunto||"(sem assunto)",70))}</em></div>
    <div class="em-aviso-acoes"><button type="button" class="btn-primary" data-abrir>Abrir</button><button type="button" class="em-aviso-x" aria-label="Fechar aviso" data-fechar>×</button></div>`;
  const fechar=()=>{d.classList.add("sair");setTimeout(()=>d.remove(),250)};
  d.querySelector("[data-fechar]").onclick=fechar;d.querySelector("[data-abrir]").onclick=()=>{fechar();window.elologEmail?.abrir()};
  pilha.prepend(d);while(pilha.children.length>3)pilha.lastChild.remove();setTimeout(fechar,15e3);
  try{navigator.vibrate?.(120)}catch(_){}}

function sistema(m){if(document.visibilityState==="visible"||typeof Notification==="undefined"||Notification.permission!=="granted")return;
  try{const n=new Notification("Novo email — Elolog",{body:`${curto(m.de,60)}\n${curto(m.assunto||"(sem assunto)",90)}`,tag:"elolog-email-"+(m.uid||""),icon:"../partilhado/imagens/icon-192.png"});
    n.onclick=()=>{window.focus();window.elologEmail?.abrir();n.close()}}catch(_){}}

async function avisar(ev){const caixas=(ev.detail?.caixas||[]).slice(0,3);
  for(const c of caixas){let m={caixa:c.email,assunto:`${c.novas} por ler`};
    try{const r=await E()?.chamar("listar",{caixa:c.id,pasta:"entrada",pagina:0}),nova=(r?.mensagens||[]).find(x=>!x.lida);
      if(nova){const chave=c.id+":"+nova.uid;if(vistos.has(chave))continue;vistos.add(chave);m={caixa:c.email,de:nova.de,assunto:nova.assunto,uid:nova.uid}}}catch(_){}
    cartao(m);sistema(m)}}
document.addEventListener("elolog:email-novo",avisar);

// Pede autorização para avisos do sistema quando o utilizador abre o email (tem de ser num toque do utilizador).
const pedir=()=>{try{if(typeof Notification!=="undefined"&&Notification.permission==="default")Notification.requestPermission()}catch(_){}};
document.addEventListener("click",e=>{if(e.target.closest?.('button[onclick^="elologEmail.abrir"]'))pedir()},true);
})();
