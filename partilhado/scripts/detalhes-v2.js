/* Elolog v2 — pormenores de apresentação (só o que se vê; dados, valores de campos e contagens ficam iguais):
   1) o contador do sino esconde-se quando é 0;
   2) datas no formato português dd/mm/aaaa onde o texto mostrava aaaa-mm-dd (não toca em campos, código nem atributos);
   3) a barra superior mostra o nome da entrada do menu aberta quando o título ficava no genérico «Painel». */
(function(){"use strict";
  function sino(){const c=document.getElementById("notificationCount");if(!c)return false;const z=()=>{const t=(c.textContent||"").trim();c.classList.toggle("zero",t===""||t==="0")};z();new MutationObserver(z).observe(c,{childList:true,characterData:true,subtree:true});return true}

  const ISO=/\b(20\d{2})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])\b(?![-\d])/g;
  const FORA="input,textarea,select,option,script,style,code,pre,[contenteditable],.elo-assistant";
  function datas(raiz){
    if(!raiz||raiz.nodeType!==1||raiz.closest(FORA))return;
    const w=document.createTreeWalker(raiz,NodeFilter.SHOW_TEXT,{acceptNode:n=>ISO.test(n.nodeValue)&&!n.parentElement.closest(FORA)?(ISO.lastIndex=0,NodeFilter.FILTER_ACCEPT):(ISO.lastIndex=0,NodeFilter.FILTER_REJECT)});
    const L=[];while(w.nextNode())L.push(w.currentNode);
    L.forEach(n=>{const v=n.nodeValue.replace(ISO,(_,a,m,d)=>`${d}/${m}/${a}`);if(v!==n.nodeValue)n.nodeValue=v});
  }

  let ultimo="";
  const rotulo=b=>(b.textContent||"").replace(/\s+/g," ").trim().replace(/\s+\d+$/,"");
  function titulo(){const t=document.getElementById("pageTitle");if(!t)return;if((t.textContent||"").trim()==="Painel"&&ultimo&&!/^(painel|início|inicio|dashboard|centro de comando)$/i.test(ultimo))t.textContent=ultimo}

  function iniciar(){
    if(!sino()){const o=new MutationObserver(()=>{if(sino())o.disconnect()});o.observe(document.body,{childList:true,subtree:true})}
    const app=document.getElementById("app")||document.body;datas(app.querySelector(".content")||app);
    let fila=new Set(),t=0;
    new MutationObserver(m=>{m.forEach(x=>{if(x.type==="characterData")fila.add(x.target.parentElement);else x.addedNodes.forEach(n=>fila.add(n.nodeType===3?n.parentElement:n))});clearTimeout(t);t=setTimeout(()=>{const f=[...fila];fila=new Set();f.forEach(e=>e&&e.isConnected&&e.closest&&e.closest("#app .content")&&datas(e))},60)}).observe(app,{childList:true,subtree:true,characterData:true});
    const sb=document.getElementById("sidebar");
    if(sb)sb.addEventListener("click",e=>{const b=e.target.closest("nav.menu button");if(!b||b.matches(".provider-menu-main,.client-group,.menu-personalizar"))return;ultimo=rotulo(b);setTimeout(titulo,80);setTimeout(titulo,400)});
    const pt=document.getElementById("pageTitle");if(pt)new MutationObserver(()=>titulo()).observe(pt,{childList:true,characterData:true,subtree:true});
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
})();
