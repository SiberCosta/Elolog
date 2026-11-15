/* Elolog — novidades em destaque (v153).
   Uma encomenda, pedido, pagamento ou pedido de apoio que aparece pela primeira vez, ou que muda de estado, fica com
   outra cor e a etiqueta «Novo» até a pessoa o ver (4 segundos no ecrã ou um clique). Quando chega algo novo com a página
   aberta, o sino abana, o título do separador mostra «(n)» e aparece um aviso. Guarda o que já foi visto neste aparelho. */
(function(){"use strict";
const LINHAS=".ca-linha,.pw-linha,.provider-work-card,.client-order-card,.provider-order-result-card,.admin-record-row,.ap-linha,.ac-cartao,.client-payment-item,.provider-payment-card,.field-job-row,.field-service-card,.client-history-row,.provider-complaint-row,.pf-tabela tbody tr";
const CODIGO=/(ELO_[A-Z0-9]+-\d{3,}|SUP-\d+|PAY-\d+|EL-\d{4}-\d+|REC-\d+|ENT-\d+)(?!\d)/;
const ESTADO=[".pf-pill",".work-status",".finance-status","[class*='status-pill']","[class*='-status']",".ck-selo"];
let vistos=null,paginas=new Set(),novosNaoVistos=new Set(),espera=null,tituloBase=document.title;
const quem=()=>{try{const u=typeof currentUser!=="undefined"?currentUser:null;return u?(u.role||"")+":"+(u.email||u.name||""):""}catch(e){return""}};
const chave=()=>"elolog_vistos_"+quem();
function carregar(){const q=quem();if(!q){vistos=null;return false}if(vistos&&vistos.__q===q)return true;
  let l=null;try{l=JSON.parse(localStorage.getItem(chave())||"null")}catch(e){}vistos=new Set(l?.k||[]);paginas=new Set(l?.p||[]);vistos.__q=q;return true}
function gravar(){try{localStorage.setItem(chave(),JSON.stringify({k:[...vistos].slice(-800),p:[...paginas]}))}catch(e){}}
function chaveDe(el){const t=el.textContent||"",m=t.match(CODIGO);if(!m)return null;let e=null;for(const q of ESTADO){e=el.querySelector(q);if(e)break}return m[1]+"|"+(e?e.textContent.replace(/\s+/g," ").trim().slice(0,40):"")}
const olhar=("IntersectionObserver" in window)?new IntersectionObserver(es=>es.forEach(e=>{const el=e.target;
  if(e.isIntersecting){el.__t=setTimeout(()=>marcarVisto(el),4000)}else clearTimeout(el.__t)}),{threshold:.6}):null;
function marcarVisto(el){const k=el.dataset.ecNovo;if(!k)return;vistos.add(k);novosNaoVistos.delete(k);gravar();titulo();
  document.querySelectorAll(".ec-novo").forEach(x=>{if(x.dataset.ecNovo===k){x.classList.add("ec-novo-visto");olhar?.unobserve(x)}})}
function titulo(){const n=novosNaoVistos.size;document.title=(n?`(${n}) `:"")+tituloBase.replace(/^\(\d+\)\s*/,"")}
function avisar(lista){const sino=document.getElementById("notificationBell");if(sino){sino.classList.remove("ec-sino-novo");void sino.offsetWidth;sino.classList.add("ec-sino-novo");setTimeout(()=>sino.classList.remove("ec-sino-novo"),6000)}
  const cod=lista[0].split("|")[0],est=lista[0].split("|")[1];
  window.showPlatformNotice?.(lista.length>1?`Tem ${lista.length} novidades. A primeira: ${cod}${est?" ("+est+")":""}.`:`Novidade: ${cod}${est?", "+est:""}.`,"info")}
/* a primeira vez que uma página é vista neste aparelho, o que lá está conta como já visto (só o que chega depois é «Novo») */
const pagina=el=>el.closest(".page")?.id||"geral";let iniciadas=new Map(),mudou=false;
function analisar(){if(!carregar())return;const novas=[],agora=Date.now();
  document.querySelectorAll(LINHAS).forEach(el=>{if(!el.offsetParent)return;const k=chaveDe(el);if(!k)return;const pg=pagina(el);
    if(!paginas.has(pg)){if(!iniciadas.has(pg))iniciadas.set(pg,agora);if(agora-iniciadas.get(pg)<2500){vistos.add(k);mudou=true;return}paginas.add(pg);mudou=true}
    if(!vistos.has(k)){el.classList.add("ec-novo");el.dataset.ecNovo=k;if(!novosNaoVistos.has(k)){novosNaoVistos.add(k);novas.push(k)}olhar?.observe(el);
      if(!el.querySelector(".ec-novo-etiqueta")){const alvo=el.matches("tr")?el.querySelector("td"):el;alvo?.insertAdjacentHTML("afterbegin",'<span class="ec-novo-etiqueta">Novo</span>')}
      if(!el.__clique){el.__clique=true;el.addEventListener("click",()=>marcarVisto(el),{capture:true})}}});
  iniciadas.forEach((t,pg)=>{if(agora-t>=2500&&!paginas.has(pg)){paginas.add(pg);mudou=true}});if(mudou){mudou=false;gravar()}
  titulo();if(novas.length&&document.visibilityState==="visible"&&window.__elologNovidadesProntas)avisar(novas)}
function agendar(){if(espera)return;espera=setTimeout(()=>{espera=null;analisar()},400)}
new MutationObserver(agendar).observe(document.documentElement,{childList:true,subtree:true});
window.addEventListener("elolog:mudanca",agendar);
/* só avisa do que chega depois de a página estar aberta há 3 s (o resto fica só destacado) */
setTimeout(()=>{window.__elologNovidadesProntas=true},3000);
window.elologNovidades={analisar,limpar:()=>{try{localStorage.removeItem(chave())}catch(e){}vistos=null}};
})();
