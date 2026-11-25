/* Elolog — conteúdo do site gerido pela administração (v169, migração 00202; faixa a correr v170, 00203).
   Lê site_conteudo (função pública: só dados que podem ser públicos) e mostra, se houver: aviso no topo, «Próximas saídas»,
   «Prestadores verificados» e «Novidades». Secção sem conteúdo não aparece. Sem servidor, nada muda na página. */
(function(){"use strict";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const data=v=>{const d=new Date(String(v||"").length===10?v+"T12:00":v);return isNaN(d)?null:d};
const curta=v=>{const d=data(v);return d?d.toLocaleDateString("pt-PT",{day:"numeric",month:"short"}).replace(".",""):""};
const longa=v=>{const d=data(v);return d?d.toLocaleDateString("pt-PT",{day:"numeric",month:"long",year:"numeric"}):""};
const ESTADO={aberta:"Aberta a carga",lotada:"Lotada",atrasada:"Atrasada",planeada:"Prevista"};
const iniciais=n=>String(n||"?").split(/\s+/).filter(w=>w.length>2||/^[A-Z]/.test(w)).slice(0,2).map(w=>w[0]).join("").toUpperCase()||"E";
const seguro=l=>/^(https:\/\/(www\.)?elolog\.pt(\/|$)|\/|#|\.\.\/)/.test(String(l||""));
async function pedir(){const c=window.ELOLOG_SERVIDOR||{},url=String(c.supabaseUrl||"").replace(/\/$/,""),k=c.supabaseAnonKey||"";
  if(!/^https:\/\//.test(url)||k.length<20)return null;
  const r=await fetch(url+"/rest/v1/rpc/site_conteudo",{method:"POST",headers:{"Content-Type":"application/json",apikey:k,Authorization:"Bearer "+k},body:"{}"});
  if(!r.ok)throw new Error("servidor");return r.json()}
const secao=(id,eyebrow,titulo,corpo,extra="")=>`<section id="${id}" class="sc-secao"><div class="section-shell"><header class="sc-cab"><span class="sc-eyebrow">${eyebrow}</span><h2>${titulo}</h2>${extra}</header>${corpo}</div></section>`;
function saidas(l){if(!l?.length)return"";
  return secao("saidas","Calendário","Próximas saídas",`<div class="sc-saidas">${l.map(s=>`<article class="sc-saida"><div class="sc-data"><b>${esc(curta(s.partida))}</b><small>partida</small></div>
    <div class="sc-saida-corpo"><strong>${esc(s.origem)} → ${esc(s.destino)}</strong><span>${esc(s.navio||"")}${s.viagem?` · ${esc(s.viagem)}`:""} · ${esc(s.prestador)}</span>
    <small>${s.fecho_carga?`Fecho de carga a ${esc(longa(s.fecho_carga))}`:""}${s.chegada?`${s.fecho_carga?" · ":""}Chegada prevista a ${esc(longa(s.chegada))}`:""}</small>
    <div class="sc-tags">${s.estado&&ESTADO[s.estado]?`<i class="sc-tag ${s.estado}">${ESTADO[s.estado]}</i>`:""}${s.grupagem?'<i class="sc-tag">Grupagem</i>':""}${s.viaturas?'<i class="sc-tag">Aceita viaturas</i>':""}</div></div></article>`).join("")}</div>
    <p class="sc-pe"><a class="sc-botao" href="simulador.html">Simular envio nesta rota</a></p>`,'<p>Datas publicadas pelos prestadores verificados. Podem mudar: a data certa fica na sua encomenda.</p>')}
function prestadores(l){if(!l?.length)return"";
  return secao("prestadores-verificados","Rede Elolog","Prestadores verificados",`<div class="sc-prest">${l.map(p=>`<article class="sc-cartao"><span class="sc-avatar" aria-hidden="true">${esc(iniciais(p.nome))}</span>
    <div><strong>${esc(p.nome)}</strong><small>${esc([p.cidade,p.pais].filter(Boolean).join(", "))}</small>${p.texto?`<p>${esc(p.texto)}</p>`:""}
    ${p.saidas>0?`<span class="sc-tag">${p.saidas} ${p.saidas===1?"saída prevista":"saídas previstas"}</span>`:""}</div></article>`).join("")}</div>`,'<p>Empresas aprovadas pela Elolog, com documentos verificados. Peça preço a todas de uma vez no simulador.</p>')}
function feed(l){if(!l?.length)return"";
  return secao("novidades","Novidades","O que há de novo",`<ul class="sc-feed">${l.map(f=>`<li><time>${esc(curta(f.data))}</time><div><strong>${esc(f.titulo)}</strong>${f.texto?`<p>${esc(f.texto)}</p>`:""}
    ${f.ligacao&&seguro(f.ligacao)?`<a href="${esc(f.ligacao)}">Saber mais</a>`:""}</div></li>`).join("")}</ul>`)}
function avisos(l){if(!l?.length)return"";
  return`<div class="sc-aviso" role="status"><button type="button" class="sc-fechar" aria-label="Fechar aviso">×</button>${l.map(a=>`<p><strong>${esc(a.titulo)}</strong>${a.texto?` ${esc(a.texto)}`:""}${a.ligacao&&seguro(a.ligacao)?` <a href="${esc(a.ligacao)}">Saber mais</a>`:""}</p>`).join("")}</div>`}
function faixa(c){if(c.faixa===false)return"";const it=[];
  (c.avisos||[]).forEach(a=>it.push(["Aviso",a.titulo+(a.texto?" — "+a.texto:""),a.ligacao]));
  (c.saidas||[]).forEach(x=>it.push(["Saída",`${x.origem} → ${x.destino} · parte a ${longa(x.partida)}${x.fecho_carga?` · fecho de carga a ${curta(x.fecho_carga)}`:""}${x.prestador?` · ${x.prestador}`:""}`,"#saidas"]));
  (c.feed||[]).filter(f=>f.tipo!=="saida").forEach(f=>it.push(["Novidade",f.titulo,f.ligacao||"#novidades"]));
  if(!it.length)return"";const li=it.map(([e,t,l])=>`<li><i>${esc(e)}</i>${l&&seguro(l)?`<a href="${esc(l)}">${esc(t)}</a>`:`<span>${esc(t)}</span>`}</li>`).join("");
  return`<div class="sc-faixa" role="region" aria-label="Informação Elolog"><div class="sc-faixa-trilho" style="--sc-dur:${Math.max(20,it.length*9)}s"><ul>${li}</ul><ul aria-hidden="true">${li.replace(/<a /g,'<a tabindex="-1" ')}</ul></div></div>`}
function colocarFaixa(fx){document.body.insertAdjacentHTML("afterbegin",fx);const f=document.querySelector(".sc-faixa"),nav=document.querySelector(".navbar");
  const acerta=()=>{const h=f.offsetHeight;f.classList.add("fixa");if(nav)nav.style.top=h+"px";document.body.style.paddingTop=h+"px"};
  acerta();addEventListener("resize",acerta,{passive:true})}
async function mostrar(){let c;try{c=await pedir()}catch(_){return}if(!c)return;window.elologSiteConteudo=c;
  const ref=document.getElementById("rastrear")||document.getElementById("contacto");if(!ref)return;
  const fx=faixa(c);if(fx)colocarFaixa(fx);
  const html=saidas(c.saidas)+prestadores(c.prestadores)+feed(c.feed);if(html)ref.insertAdjacentHTML("beforebegin",html);
  const av=c.faixa===false?avisos(c.avisos):"";if(av){let fechado="";try{fechado=sessionStorage.getItem("elolog_aviso_fechado")||""}catch(_){}const chave=JSON.stringify(c.avisos).length+":"+(c.avisos[0]?.titulo||"");if(fechado!==chave){document.body.insertAdjacentHTML("beforeend",av);document.querySelector(".sc-aviso .sc-fechar")?.addEventListener("click",e=>{e.currentTarget.closest(".sc-aviso").remove();try{sessionStorage.setItem("elolog_aviso_fechado",chave)}catch(_){}})}}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mostrar);else mostrar();
})();
