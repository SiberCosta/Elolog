/* Elolog — conteúdo do site gerido pela administração (v169, migração 00202; faixa a correr v170, 00203; cores e calendário v171, 00204; fundo e classificações v172, 00205).
   Lê site_conteudo (função pública: só dados que podem ser públicos) e mostra, se houver: aviso no topo, «Próximas saídas»,
   «Prestadores verificados» e «Novidades». Secção sem conteúdo não aparece. Sem servidor, nada muda na página. */
(function(){"use strict";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const data=v=>{const d=new Date(String(v||"").length===10?v+"T12:00":v);return isNaN(d)?null:d};
const curta=v=>{const d=data(v);return d?d.toLocaleDateString("pt-PT",{day:"numeric",month:"short"}).replace(".",""):""};
const longa=v=>{const d=data(v);return d?d.toLocaleDateString("pt-PT",{day:"numeric",month:"long",year:"numeric"}):""};
const ESTADO={aberta:"Aberta a carga",lotada:"Lotada",atrasada:"Atrasada",planeada:"Prevista"};
const iniciais=n=>String(n||"?").split(/\s+/).filter(w=>w.length>2||/^[A-Z]/.test(w)).slice(0,2).map(w=>w[0]).join("").toUpperCase()||"E";
const claro=hex=>{const m=/^#?([0-9a-f]{6})$/i.exec(hex||"");if(!m)return true;const n=parseInt(m[1],16);return(.299*(n>>16)+.587*(n>>8&255)+.114*(n&255))>160};
const fundo=f=>/^#[0-9a-f]{6}$/i.test(f||"")?` style="--sc-fundo:${f};--sc-texto:${claro(f)?"#13293D":"#fff"}"`:"";
const NIVEL={recomendado:"Recomendado Elolog",ouro:"Ouro",prata:"Prata",bronze:"Bronze"};
const seguro=l=>/^(https:\/\/(www\.)?elolog\.pt(\/|$)|\/|#|\.\.\/)/.test(String(l||""));
async function pedir(){const c=window.ELOLOG_SERVIDOR||{},url=String(c.supabaseUrl||"").replace(/\/$/,""),k=c.supabaseAnonKey||"";
  if(!/^https:\/\//.test(url)||k.length<20)return null;
  const r=await fetch(url+"/rest/v1/rpc/site_conteudo",{method:"POST",headers:{"Content-Type":"application/json",apikey:k,Authorization:"Bearer "+k},body:"{}"});
  if(!r.ok)throw new Error("servidor");return r.json()}
const secao=(id,eyebrow,titulo,corpo,extra="")=>`<section id="${id}" class="sc-secao"><div class="section-shell"><header class="sc-cab"><span class="sc-eyebrow">${eyebrow}</span><h2>${titulo}</h2>${extra}</header>${corpo}</div></section>`;
function saidas(l){if(!l?.length)return"";
  return secao("saidas","Calendário","Próximas saídas",`<div class="sc-saidas">${l.map(s=>`<article class="sc-saida"><div class="sc-data"><b>${esc(curta(s.partida))}</b><small>partida</small></div>
    <div class="sc-saida-corpo"><strong>${esc(s.origem)} → ${esc(s.destino)}</strong><span>${esc([s.navio,s.viagem,s.prestador].filter(Boolean).join(" · "))}</span>
    <small>${s.fecho_carga?`Fecho de carga a ${esc(longa(s.fecho_carga))}`:""}${s.chegada?`${s.fecho_carga?" · ":""}Chegada prevista a ${esc(longa(s.chegada))}`:""}</small>
    <div class="sc-tags">${s.estado&&ESTADO[s.estado]?`<i class="sc-tag ${s.estado}">${ESTADO[s.estado]}</i>`:""}${s.grupagem?'<i class="sc-tag">Grupagem</i>':""}${s.viaturas?'<i class="sc-tag">Aceita viaturas</i>':""}</div></div></article>`).join("")}</div>
    <p class="sc-pe"><a class="sc-botao" href="simulador.html">Simular envio nesta rota</a></p>`,'<p>Datas publicadas pelos prestadores verificados. Podem mudar: a data certa fica na sua encomenda.</p>')}
function prestadores(l){if(!l?.length)return"";
  return secao("prestadores-verificados","Rede Elolog","Prestadores verificados",`<div class="sc-prest">${l.map(p=>`<article class="sc-cartao"><span class="sc-avatar${p.logo?" com-logo":""}" aria-hidden="true">${p.logo?`<img src="${esc(p.logo)}" alt="">`:esc(iniciais(p.nome))}</span>
    <div>${p.nivel&&NIVEL[p.nivel]?`<span class="sc-nivel ${esc(p.nivel)}">${NIVEL[p.nivel]}</span>`:""}<strong>${esc(p.nome)}</strong>${p.avaliacoes>0?`<span class="sc-aval" aria-label="${p.media} de 5, ${p.avaliacoes} avaliações"><i>${"★".repeat(Math.floor(p.media+.25))}${"☆".repeat(5-Math.floor(p.media+.25))}</i> ${Number(p.media).toLocaleString("pt-PT",{minimumFractionDigits:1})} · ${p.avaliacoes} ${p.avaliacoes===1?"avaliação":"avaliações"}</span>`:""}<small>${esc([p.cidade,p.pais].filter(Boolean).join(", "))}</small>${p.texto?`<p>${esc(p.texto)}</p>`:""}
    ${p.saidas>0?`<span class="sc-tag">${p.saidas} ${p.saidas===1?"saída prevista":"saídas previstas"}</span>`:""}</div></article>`).join("")}</div>`,'<p>Empresas aprovadas pela Elolog, com documentos verificados. Peça preço a todas de uma vez no simulador.</p>')}
/* v173: novidades em cartões mais próximos — quem publica (logótipo ou iniciais), há quanto tempo, frase de boas-vindas ou de saída, e o título na cor escolhida */
const ha=v=>{const d=data(v);if(!d)return"";const dias=Math.floor((Date.now()-d)/864e5);return dias<=0?"Hoje":dias===1?"Ontem":dias<7?`Há ${dias} dias`:dias<14?"Há uma semana":dias<60?`Há ${Math.floor(dias/7)} semanas`:curta(v)};
const ICONE={saida:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l2 3h14l2-3"/><path d="M5 17V11h14v6M12 4v7M8 11V7h8v4"/></svg>',
  prestador:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5M17 8v6M14 11h6"/></svg>',
  novidade:'<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 13V9l11-5v16L4 15z"/><path d="M15 9a4 4 0 0 1 0 6M7 15l1.5 5"/></svg>'};
const FRASE={saida:"Há um novo barco a sair",prestador:"Damos as boas-vindas a um novo parceiro",novidade:"Novidade"};
function feed(l,prest){if(!l?.length)return"";const logo=n=>(prest||[]).find(p=>p.nome===n)?.logo;
  return secao("novidades","Novidades","O que se passa na Elolog",`<div class="sc-novs">${l.map(f=>{const t=FRASE[f.tipo]?f.tipo:"novidade",lg=f.prestador&&logo(f.prestador);
    const quem=f.tipo==="novidade"?(f.prestador||"Equipa Elolog"):(f.prestador||"Elolog");
    const avatar=lg?`<img src="${esc(lg)}" alt="">`:f.tipo==="novidade"&&!f.prestador?'<b>E</b>':`<i class="sc-nov-ic">${ICONE[t]}</i>`;
    return`<article class="sc-nov sc-nov-${t}${f.cor?" sc-c-"+esc(f.cor):""}${f.fundo?" sc-com-fundo":""}"${fundo(f.fundo)}>
      <header><span class="sc-nov-avatar" aria-hidden="true">${avatar}</span><span class="sc-nov-quem"><strong>${esc(quem)}</strong><time datetime="${esc(String(f.data||""))}">${esc(ha(f.data))}</time></span></header>
      <span class="sc-nov-frase">${FRASE[t]}</span><h3${/^#[0-9a-f]{6}$/i.test(f.cor_titulo||"")?` style="color:${f.cor_titulo}"`:""}>${esc(f.titulo)}</h3>${f.texto?`<p>${esc(f.texto)}</p>`:""}
      ${f.ligacao&&seguro(f.ligacao)?`<a class="sc-nov-mais" href="${esc(f.ligacao)}">Saber mais <span aria-hidden="true">→</span></a>`:t==="saida"?'<a class="sc-nov-mais" href="simulador.html">Pedir preço <span aria-hidden="true">→</span></a>':t==="prestador"?'<a class="sc-nov-mais" href="#prestadores-verificados">Conhecer <span aria-hidden="true">→</span></a>':""}</article>`}).join("")}</div>`,
    '<p>Novas rotas, barcos a sair e parceiros que se juntam à rede, contados por quem trabalha com eles.</p>')}
function avisos(l){if(!l?.length)return"";
  return`<div class="sc-aviso sc-c-${esc(l[0].cor||"amarelo")}${l[0].fundo?" sc-com-fundo":""}"${fundo(l[0].fundo)} role="${l[0].cor==="vermelho"?"alert":"status"}"><button type="button" class="sc-fechar" aria-label="Fechar aviso">×</button>${l.map(a=>`<p><strong${/^#[0-9a-f]{6}$/i.test(a.cor_titulo||"")?` style="color:${a.cor_titulo}"`:""}>${esc(a.titulo)}</strong>${a.texto?` ${esc(a.texto)}`:""}${a.ligacao&&seguro(a.ligacao)?` <a href="${esc(a.ligacao)}">Saber mais</a>`:""}</p>`).join("")}</div>`}
function faixa(c){if(c.faixa===false)return"";const it=[];
  (c.avisos||[]).forEach(a=>it.push([a.cor==="vermelho"?"Alerta":"Aviso",a.titulo+(a.texto?" — "+a.texto:""),a.ligacao,a.cor||"amarelo",a.fundo]));
  (c.saidas||[]).forEach(x=>it.push(["Saída",`${x.origem} → ${x.destino} · parte a ${longa(x.partida)}${x.fecho_carga?` · fecho de carga a ${curta(x.fecho_carga)}`:""}${x.prestador?` · ${x.prestador}`:""}`,"#saidas"]));
  (c.feed||[]).filter(f=>f.tipo!=="saida").forEach(f=>it.push(["Novidade",f.titulo,f.ligacao||"#novidades",f.cor,f.fundo]));
  if(!it.length)return"";const li=it.map(([e,t,l,cor,fd])=>`<li class="${cor?"sc-c-"+esc(cor):""}${fd?" sc-com-fundo":""}"${fundo(fd)}><i>${esc(e)}</i>${l&&seguro(l)?`<a href="${esc(l)}">${esc(t)}</a>`:`<span>${esc(t)}</span>`}</li>`).join("");
  const alerta=(c.avisos||[]).some(a=>a.cor==="vermelho");
  return`<div class="sc-faixa${alerta?" alerta":""}" role="region" aria-label="Informação Elolog"><div class="sc-faixa-trilho" style="--sc-dur:${Math.max(20,it.length*9)}s"><ul>${li}</ul><ul aria-hidden="true">${li.replace(/<a /g,'<a tabindex="-1" ')}</ul></div></div>`}
function colocarFaixa(fx){document.body.insertAdjacentHTML("afterbegin",fx);const f=document.querySelector(".sc-faixa"),nav=document.querySelector(".navbar");
  const acerta=()=>{const h=f.offsetHeight;f.classList.add("fixa");if(nav)nav.style.top=h+"px";document.body.style.paddingTop=h+"px"};
  acerta();addEventListener("resize",acerta,{passive:true})}
/* v171: calendário de saídas (liga-se em Site público → Saídas e calendário). Mês a mês; os dias com partida ficam marcados e mostram as saídas desse dia. */
const ymd=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
function calendario(c){const l=c.calendario||[];if(!c.calendario_ativo||!l.length)return"";
  return secao("calendario","Calendário","Calendário de saídas",'<div class="sc-cal" data-mes="0"></div><div class="sc-cal-dia" aria-live="polite"></div>','<p>Toque num dia marcado para ver as saídas. Datas indicadas pelos prestadores; a data certa fica na sua encomenda.</p>')}
function desenharCal(box,l,mes){const hoje=new Date(),base=new Date(hoje.getFullYear(),hoje.getMonth()+mes,1),porDia={};l.forEach(x=>(porDia[String(x.partida).slice(0,10)]??=[]).push(x));
  const ult=l.length?new Date(String(l[l.length-1].partida).slice(0,10)+"T12:00"):hoje,maxMes=(ult.getFullYear()-hoje.getFullYear())*12+ult.getMonth()-hoje.getMonth();
  const vazios=(base.getDay()+6)%7,dias=new Date(base.getFullYear(),base.getMonth()+1,0).getDate(),cel=[];for(let i=0;i<vazios;i++)cel.push("<span></span>");
  for(let d=1;d<=dias;d++){const k=ymd(new Date(base.getFullYear(),base.getMonth(),d)),n=porDia[k]?.length||0;
    cel.push(n?`<button type="button" class="tem" data-dia="${k}" aria-label="${d}: ${n} ${n===1?"saída":"saídas"}">${d}<i>${n}</i></button>`:`<span class="${k===ymd(hoje)?"hoje":""}">${d}</span>`)}
  box.dataset.mes=mes;box.innerHTML=`<div class="sc-cal-cab"><button type="button" data-mes-ir="-1" ${mes<=0?"disabled":""} aria-label="Mês anterior">‹</button><strong>${(t=>t[0].toUpperCase()+t.slice(1))(base.toLocaleDateString("pt-PT",{month:"long",year:"numeric"}))}</strong><button type="button" data-mes-ir="1" ${mes>=maxMes?"disabled":""} aria-label="Mês seguinte">›</button></div>
    <div class="sc-cal-sem">${["seg","ter","qua","qui","sex","sáb","dom"].map(x=>`<span>${x}</span>`).join("")}</div><div class="sc-cal-grelha">${cel.join("")}</div>`}
function ligarCal(c){const box=document.querySelector(".sc-cal");if(!box)return;const l=c.calendario||[],out=box.nextElementSibling;
  const prim=l[0]?new Date(String(l[0].partida).slice(0,10)+"T12:00"):new Date(),h=new Date();desenharCal(box,l,Math.max(0,(prim.getFullYear()-h.getFullYear())*12+prim.getMonth()-h.getMonth()));
  box.addEventListener("click",e=>{const ir=e.target.closest("[data-mes-ir]");if(ir)return desenharCal(box,l,+box.dataset.mes+ +ir.dataset.mesIr);
    const b=e.target.closest("[data-dia]");if(!b)return;box.querySelectorAll(".tem.on").forEach(x=>x.classList.remove("on"));b.classList.add("on");
    out.innerHTML=`<h3>${esc(longa(b.dataset.dia))}</h3><ul>${l.filter(x=>String(x.partida).slice(0,10)===b.dataset.dia).map(x=>`<li><strong>${esc(x.origem)} → ${esc(x.destino)}</strong><span>${esc([x.navio,x.prestador].filter(Boolean).join(" · "))}${x.fecho_carga?` · fecho de carga a ${esc(curta(x.fecho_carga))}`:""}</span></li>`).join("")}</ul><a class="sc-botao" href="simulador.html">Simular envio</a>`})}
async function mostrar(){let c;try{c=await pedir()}catch(_){return}if(!c)return;window.elologSiteConteudo=c;
  const ref=document.getElementById("rastrear")||document.getElementById("contacto");if(!ref)return;
  const fx=faixa(c);if(fx)colocarFaixa(fx);
  const html=saidas(c.saidas)+calendario(c)+prestadores(c.prestadores)+feed(c.feed,c.prestadores);if(html){ref.insertAdjacentHTML("beforebegin",html);ligarCal(c)}
  const av=c.faixa===false?avisos(c.avisos):"";if(av){let fechado="";try{fechado=sessionStorage.getItem("elolog_aviso_fechado")||""}catch(_){}const chave=JSON.stringify(c.avisos).length+":"+(c.avisos[0]?.titulo||"");if(fechado!==chave){document.body.insertAdjacentHTML("beforeend",av);document.querySelector(".sc-aviso .sc-fechar")?.addEventListener("click",e=>{e.currentTarget.closest(".sc-aviso").remove();try{sessionStorage.setItem("elolog_aviso_fechado",chave)}catch(_){}})}}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mostrar);else mostrar();
})();
