/* Elolog — um título por página (v160).
   A barra de topo já diz onde o utilizador está («Pagamentos»). Quando o primeiro cartão da página repete o mesmo título
   («Pagamentos» › «Pagamentos»), esse título repetido sai da vista mas continua a existir para leitores de ecrã
   (classe .titulo-na-barra). A etiqueta curta por cima dele («ATENDIMENTO») sai também. A descrição fica.
   Não se aplica quando o título da barra está escondido (administração) nem no site público. Não altera dados nem ações. */
(function(){"use strict";
const PARAS=new Set(["a","ao","aos","as","o","os","da","das","de","do","dos","e","em","na","no","nas","nos","para","por","seu","sua","seus","suas"]);
const chave=s=>String(s||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-z0-9 ]+/g," ").split(/\s+/)
  .filter(p=>p&&!PARAS.has(p)&&!/^\d+$/.test(p)).sort().join(" ");
const visivel=e=>!!(e&&e.offsetParent!==null&&e.getBoundingClientRect().width>2);

function limpar(){document.querySelectorAll(".titulo-na-barra,.cab-sem-titulo,.sem-fio-topo").forEach(e=>e.classList.remove("titulo-na-barra","cab-sem-titulo","sem-fio-topo"))}
/* v162: sem o cabeçalho, a linha separadora da primeira linha da lista ficava sozinha no topo do cartão */
function fioTopo(card){if(!card)return;const cs=getComputedStyle(card),topo=card.getBoundingClientRect().top+parseFloat(cs.borderTopWidth)+parseFloat(cs.paddingTop);
  const e=[...card.querySelectorAll("*")].find(x=>{if(!visivel(x))return false;const r=x.getBoundingClientRect();return r.height>2&&Math.abs(r.top-topo)<3&&(()=>{const s=getComputedStyle(x);
    return parseFloat(s.borderTopWidth)>=1&&s.borderTopStyle!=="none"&&!parseFloat(s.borderLeftWidth)&&!parseFloat(s.borderRightWidth)})()});if(e)e.classList.add("sem-fio-topo")}

function aplicar(){
  const barra=document.getElementById("pageTitle");limpar();
  if(!barra||!visivel(barra))return;
  const alvo=chave(barra.textContent);if(!alvo)return;
  const pagina=[...document.querySelectorAll(".main .page,.content>section,.content>.page")].find(visivel);if(!pagina)return;
  const titulos=[...pagina.querySelectorAll("h2,h3")].filter(visivel);
  /* só os títulos que dizem exatamente o mesmo; o primeiro é sempre o do cabeçalho do cartão */
  titulos.filter(h=>chave(h.textContent)===alvo).forEach(h=>{h.classList.add("titulo-na-barra");
    const e=h.previousElementSibling;if(e&&/^(SMALL|SPAN|P|EM|B)$/.test(e.tagName)&&e.textContent.trim().length<=24&&!e.querySelector("button,a,input"))e.classList.add("titulo-na-barra");
    /* o cabeçalho do cartão que ficou sem nada visível sai todo (sem deixar a linha de separação vazia); se ainda tem a descrição, perde a linha */
    let el=h;for(let n=0;n<3;n++){const cab=el.parentElement;if(!cab||cab===pagina||/(^|\s)(card|page)(\s|$)/.test(cab.className))break;
      const resto=[...cab.children].filter(c=>!c.classList.contains("titulo-na-barra")&&visivel(c)&&(c.textContent.trim()||c.querySelector("button,input,select,img,svg")));
      cab.classList.add(resto.length?"cab-sem-titulo":"titulo-na-barra");el=cab}
    fioTopo(h.closest(".card"))});
}

let t,obs=[];const agendar=()=>{clearTimeout(t);t=setTimeout(()=>{aplicar();obs.forEach(o=>o.takeRecords())},120)};
function ligar(){const barra=document.getElementById("pageTitle");if(!barra){setTimeout(ligar,500);return}
  const o1=new MutationObserver(agendar);o1.observe(barra,{childList:true,characterData:true,subtree:true});
  const raiz=document.querySelector(".main")||document.body;
  /* ignora as mudanças feitas por este módulo (só a classe .titulo-na-barra) */
  const o2=new MutationObserver(rs=>{if(rs.some(r=>!(r.type==="attributes"&&r.attributeName==="class"&&/titulo-na-barra|cab-sem-titulo|sem-fio-topo/.test(r.target.className+" "+(r.oldValue||"")))))agendar()});
  o2.observe(raiz,{childList:true,subtree:true,attributes:true,attributeOldValue:true,attributeFilter:["class","hidden","style"]});obs=[o1,o2];
  addEventListener("resize",agendar);agendar()}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
window.elologTitulos={aplicar,chave};
})();
