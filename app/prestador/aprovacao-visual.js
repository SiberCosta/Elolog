/* Elolog — «Aprovar pedidos» mais claro (v155). Sem mudar as regras nem os botões existentes, cada pedido mostra:
   valor e estado no topo; dados agrupados (pessoas, carga); uma lista «Antes de aprovar» com o que falta;
   ações separadas — consultar à esquerda, decidir (Rejeitar / Aprovar) à direita. */
(function(){"use strict";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const eur=v=>Number(v)>0?Number(v).toLocaleString("pt-PT",{style:"currency",currency:"EUR"}):"";
function dados(card){const m={};card.querySelectorAll(".provider-work-data>span").forEach(s=>{const k=s.querySelector("small")?.textContent.trim(),v=s.querySelector("strong")?.textContent.trim();if(k)m[k]={v,el:s}});return m}
function melhorar(card){if(card.dataset.ap2)return;card.dataset.ap2="1";card.classList.add("ap2");
  const cod=card.querySelector(".work-code")?.textContent.trim()||"",op=(typeof operations!=="undefined"?operations:[]).find(o=>String(o.id)===cod)||{};
  const d=dados(card),falta=v=>!v||v==="—"||/^—|, —$/.test(v);
  /* topo: valor ao lado do estado; linha «Simulação: —» só quando há número */
  const p=card.querySelector(".provider-work-main p");if(p){const sim=op.simulationId&&op.simulationId!==cod?op.simulationId:"";p.textContent=sim?`Pedido do cliente: simulação ${sim}`:(op.createdByRole?"Encomenda criada pela empresa":"");if(!p.textContent)p.remove()}
  const est=card.querySelector(".provider-work-main .work-status");const valor=eur(op.estimatedPrice);
  if(est&&valor){const b=document.createElement("div");b.className="ap2-topo";est.replaceWith(b);b.appendChild(est);b.insertAdjacentHTML("afterbegin",`<strong class="ap2-valor">${esc(valor)}</strong>`)}
  /* grupos */
  const grade=card.querySelector(".provider-work-data");if(grade){grade.classList.add("ap2-grade");
    const grupo=(t,ks)=>{const g=document.createElement("div");g.className="ap2-grupo";g.innerHTML=`<h5>${t}</h5>`;ks.forEach(k=>{if(d[k])g.appendChild(d[k].el)});return g.children.length>1?g:null};
    const gs=[grupo("Pessoas e moradas",["Remetente","Destinatário","Morada de recolha"]),grupo("Carga",["Carga","Peso / volume","Documentos"])].filter(Boolean);
    grade.innerHTML="";gs.forEach(g=>grade.appendChild(g));
    /* lista «Antes de aprovar» */
    const itens=[["Destinatário indicado",!falta(d["Destinatário"]?.v)],["Carga descrita",!falta(d["Carga"]?.v)],["Documentos anexados",!/^0\b/.test(d["Documentos"]?.v||"0")],
      ["Pagamento",/pago/i.test(d["Pagamento"]?.v||"")?true:null,d["Pagamento"]?.v],["Conformidade",/conforme|verificad|ok/i.test(d["Conformidade"]?.v||"")&&!/por verificar/i.test(d["Conformidade"]?.v||"")?true:null,d["Conformidade"]?.v]];
    const lista=document.createElement("div");lista.className="ap2-grupo ap2-verificar";
    lista.innerHTML=`<h5>Antes de aprovar</h5><ul>${itens.map(([t,okv,v])=>`<li class="${okv===true?"ok":okv===false?"falta":"aviso"}"><span aria-hidden="true"></span>${esc(t)}${v&&okv!==true?`: <b>${esc(v)}</b>`:""}${okv===false?" <b>em falta</b>":""}</li>`).join("")}</ul>`;
    grade.appendChild(lista)}
  /* ações: consultar | decidir */
  const ac=card.querySelector(".provider-work-actions");if(ac&&!ac.querySelector(".ap2-decidir")){const dec=document.createElement("div");dec.className="ap2-decidir";
    [...ac.querySelectorAll(':scope>button')].filter(b=>/approve'|reject'/.test(b.getAttribute("onclick")||"")).sort(b=>/reject/.test(b.getAttribute("onclick"))?-1:1).forEach(b=>dec.appendChild(b));
    const con=document.createElement("div");con.className="ap2-consultar";[...ac.children].forEach(c=>con.appendChild(c));ac.append(con,dec);ac.classList.add("ap2-acoes")}}
/* botões acrescentados depois por outros módulos (Ficha, Ocorrências) vão para o lado «consultar» */
function arrumar(card){const ac=card.querySelector(".ap2-acoes"),con=ac?.querySelector(".ap2-consultar");if(!con)return;[...ac.children].forEach(c=>{if(!c.classList.contains("ap2-consultar")&&!c.classList.contains("ap2-decidir"))con.appendChild(c)})}
function tudo(){document.querySelectorAll("#providerAprovacaoList .provider-work-card").forEach(c=>{melhorar(c);arrumar(c)})}
let t=0;new MutationObserver(()=>{cancelAnimationFrame(t);t=requestAnimationFrame(tudo)}).observe(document.documentElement,{childList:true,subtree:true});
})();
