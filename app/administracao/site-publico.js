/* Elolog — «Site público» na administração (v169, migração 00202).
   A administração decide o que o site mostra: saídas previstas (as que os prestadores publicam no calendário), prestadores
   verificados (todos automaticamente ou só os escolhidos, com texto de destaque), novidades e avisos. Com o automático ligado,
   saídas novas e empresas aprovadas aparecem sozinhas nas novidades; aqui só se esconde o que não se quer mostrar.
   O site e o ELO leem o resultado pela função pública site_conteudo (sem NIF, emails, moradas nem preços). */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const dia=v=>v?new Date(String(v).length===10?v+"T12:00":v).toLocaleDateString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric"}):"—";
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k||"info"):alert(t);
const ESTADO={planeada:"Planeada",aberta:"Aberta a carga",lotada:"Lotada",atrasada:"Atrasada",partiu:"Partiu",chegou:"Chegou",cancelada:"Cancelada"};
const ABAS=[["saidas","Saídas previstas"],["prestadores","Prestadores"],["novidades","Novidades e avisos"],["auto","Automatização"]];
let aba="saidas",d=null;

function pagina(){if($("adminSite"))return;const ref=$("adminSettings");if(!ref)return;
  const s=document.createElement("section");s.id="adminSite";s.className="page admin-platform-page";s.innerHTML='<div class="card sp-pagina"><div id="adminSiteContent"></div></div>';ref.before(s)}
function botao(){if($("adminSiteBtn"))return;const cfg=document.querySelector('#sidebar [onclick*="showAdminPage(\'adminSettings\'"]');if(!cfg)return;
  const b=document.createElement("button");b.type="button";b.id="adminSiteBtn";b.className=cfg.className||"provider-menu-main";b.setAttribute("onclick","showAdminPage('adminSite',this)");
  b.innerHTML='<span class="mi-l"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/></svg>Site público</span>';cfg.before(b)}

async function ler(){const sb=await S().cliente(),hoje=new Date().toISOString().slice(0,10);
  const[a,b,c,e,f]=await Promise.all([sb.from("site_definicoes").select("chave,valor"),
    sb.from("viagens_maritimas").select("id,navio,viagem,porto_origem,porto_destino,partida,chegada,fecho_carga,estado,publicada,empresa_id").gte("partida",hoje).order("partida").limit(200),
    sb.from("empresas").select("id,nome,nome_comercial,cidade").eq("estado","aprovada").order("nome"),sb.from("site_publicacoes").select("*").order("created_at",{ascending:false}).limit(200),sb.rpc("site_conteudo")]);
  for(const r of[a,b,c,e])if(r.error)throw r.error;
  const def={};(a.data||[]).forEach(x=>def[x.chave]=x.valor||{});d={def,viagens:b.data||[],empresas:(c.data||[]).map(x=>({id:x.id,nome:x.nome_comercial||x.nome,cidade:x.cidade})),pubs:e.data||[],site:f.data||{}}}
async function guardarDef(chave,muda){const v={...(d.def[chave]||{}),...muda};const sb=await S().cliente();
  const{error}=await sb.from("site_definicoes").upsert({chave,valor:v,updated_at:new Date().toISOString()});if(error)throw error;d.def[chave]=v}
const lig=(id,on,txt)=>`<label class="sp-lig"><input type="checkbox" id="${id}" ${on?"checked":""}> ${esc(txt)}</label>`;
const maximo=(id,v,op)=>`<label class="sp-max">Quantos mostrar <select id="${id}">${op.map(n=>`<option ${+v===n?"selected":""}>${n}</option>`).join("")}</select></label>`;
const nomeEmp=id=>d.empresas.find(e=>e.id===id)?.nome||"Prestador";

function vSaidas(){const s=d.def.saidas||{},oc=s.ocultas||[];
  return`<div class="sp-barra">${lig("spSaidasMostrar",s.mostrar!==false,"Mostrar «Próximas saídas» no site")}${maximo("spSaidasMax",s.max||6,[3,4,6,8,12])}</div>
  <p class="sp-nota">Aparecem sozinhas as saídas que os prestadores publicam no calendário marítimo. Desligue as que não quer mostrar.</p>
  ${d.viagens.length?`<div class="sp-lista">${d.viagens.map(v=>`<div class="sp-linha"><div><strong>${dia(v.partida)} · ${esc(v.porto_origem)} → ${esc(v.porto_destino)}</strong>
    <small>${esc(v.navio)}${v.viagem?` · viagem ${esc(v.viagem)}`:""} · ${esc(nomeEmp(v.empresa_id))} · ${esc(ESTADO[v.estado]||v.estado)}${v.fecho_carga?` · fecho de carga ${dia(v.fecho_carga)}`:""}</small></div>
    ${v.publicada?lig("",!oc.includes(v.id),"No site").replace('id=""',`data-saida="${v.id}"`):`<span class="sp-pill">Não publicada pelo prestador</span>`}</div>`).join("")}</div>`
   :`<div class="sp-vazio">Ainda não há saídas previstas. Quando um prestador publicar uma viagem no calendário marítimo, aparece aqui e no site.</div>`}`}
function vPrest(){const p=d.def.prestadores||{},oc=p.ocultos||[],esc2=p.escolhidos||[],auto=p.auto!==false;
  const txt=id=>d.pubs.find(x=>x.tipo==="destaque"&&x.empresa_id===id&&x.ativo)?.texto||"";
  return`<div class="sp-barra">${lig("spPrestMostrar",p.mostrar!==false,"Mostrar «Prestadores verificados» no site")}${maximo("spPrestMax",p.max||8,[4,6,8,12,24])}</div>
  <div class="sp-barra"><label class="sp-lig"><input type="radio" name="spModo" value="auto" ${auto?"checked":""}> Todos os aprovados (automático)</label>
    <label class="sp-lig"><input type="radio" name="spModo" value="escolha" ${auto?"":"checked"}> Só os escolhidos</label></div>
  ${d.empresas.length?`<div class="sp-lista">${d.empresas.map(e=>{const on=auto?!oc.includes(e.id):esc2.includes(e.id);
    return`<div class="sp-linha sp-prest"><div><strong>${esc(e.nome)}</strong><small>${esc(e.cidade||"")}</small>
      <input class="sp-destaque" data-destaque="${e.id}" maxlength="200" placeholder="Texto de destaque (opcional), ex.: Especialistas em São Tomé" value="${esc(txt(e.id))}"></div>
      ${lig("",on,"No site").replace('id=""',`data-prest="${e.id}"`)}</div>`}).join("")}</div>`:`<div class="sp-vazio">Ainda não há prestadores aprovados com subscrição ativa.</div>`}`}
function vNov(){const ps=d.pubs.filter(x=>x.tipo!=="destaque");
  return`<form id="spForm" class="sp-form"><div class="sp-grelha">
    <label>Tipo<select id="spTipo"><option value="novidade">Novidade (no feed do site)</option><option value="aviso">Aviso (faixa no topo do site)</option></select></label>
    <label>Prestador (opcional)<select id="spEmp"><option value="">—</option>${d.empresas.map(e=>`<option value="${e.id}">${esc(e.nome)}</option>`).join("")}</select></label>
    <label class="sp-largo">Título<input id="spTitulo" required minlength="3" maxlength="120" placeholder="Ex.: Nova rota para Cabo Verde"></label>
    <label class="sp-largo">Texto<textarea id="spTexto" maxlength="600" rows="3" placeholder="O que muda para quem envia (curto)."></textarea></label>
    <label>Ligação (opcional)<input id="spLig" placeholder="/site/simulador.html"></label>
    <label>Mostrar de<input id="spIni" type="date"></label><label>até<input id="spFim" type="date"></label></div>
    <button type="submit" class="btn-secondary">Publicar no site</button></form>
  ${ps.length?`<div class="sp-lista">${ps.map(x=>`<div class="sp-linha"><div><strong>${x.tipo==="aviso"?"Aviso · ":""}${esc(x.titulo)}</strong>
    <small>${esc(x.texto||"")}${x.inicio||x.fim?` · ${x.inicio?dia(x.inicio):"já"} a ${x.fim?dia(x.fim):"sem fim"}`:""}</small></div>
    <span class="sp-acoes">${lig("",x.ativo,"Ativo").replace('id=""',`data-pub="${x.id}"`)}<button type="button" class="btn-secondary" data-apagar="${x.id}">Apagar</button></span></div>`).join("")}</div>`
   :`<div class="sp-vazio">Ainda não publicou novidades nem avisos.</div>`}`}
function vAuto(){const f=d.def.feed||{},s=d.site||{};
  return`<div class="sp-barra">${lig("spFeedMostrar",f.mostrar!==false,"Mostrar «Novidades» no site")}${maximo("spFeedMax",f.max||6,[3,4,6,8,12])}</div>
  ${lig("spFaixa",f.faixa!==false,"Faixa a correr no topo do site (avisos, saídas e novidades)")}
  ${lig("spFeedAuto",f.auto!==false,"Novidades automáticas: empresas aprovadas (90 dias) e saídas novas (30 dias)")}
  <p class="sp-nota">O ELO usa a mesma informação: quando alguém pergunta pelo próximo barco, responde com as saídas publicadas aqui.</p>
  <h4 class="sp-sub">O site mostra agora</h4><ul class="sp-resumo"><li>${(s.saidas||[]).length} saídas previstas</li><li>${(s.prestadores||[]).length} prestadores</li>
    <li>${(s.feed||[]).length} novidades</li><li>${(s.avisos||[]).length} avisos</li></ul><a class="btn-secondary" href="../site/inicio.html" target="_blank" rel="noopener">Ver o site</a>`}

function desenhar(){const box=$("adminSiteContent");if(!box)return;
  const cab=`<header class="sp-cab"><div><h3>Site público</h3><p>O que o site e o ELO mostram: saídas, prestadores, novidades e avisos.</p></div></header>
    <nav class="sp-abas" role="tablist">${ABAS.map(([k,t])=>`<button type="button" role="tab" aria-selected="${aba===k}" class="${aba===k?"on":""}" data-aba="${k}">${t}</button>`).join("")}</nav>`;
  if(!S()?.ativo?.())return box.innerHTML=cab+`<div class="sp-vazio">Disponível com o servidor ligado (fora do modo de demonstração).</div>`;
  if(!d)return box.innerHTML=cab+`<div class="sp-vazio">A carregar…</div>`;
  box.innerHTML=cab+`<div class="sp-corpo">${{saidas:vSaidas,prestadores:vPrest,novidades:vNov,auto:vAuto}[aba]()}</div>`}
async function recarregar(){try{await ler()}catch(e){d=null;const box=$("adminSiteContent");if(box)box.innerHTML=`<div class="sp-vazio">Não foi possível ler o conteúdo do site: ${esc(S()?.mensagem?.(e)||e.message)}</div>`;return}desenhar()}
async function acao(fn,ok){try{await fn();if(ok)aviso(ok,"success");await recarregar()}catch(e){aviso(S()?.mensagem?.(e)||e.message,"error")}}

document.addEventListener("click",e=>{const box=$("adminSiteContent");if(!box||!box.contains(e.target))return;
  const a=e.target.closest("[data-aba]");if(a){aba=a.dataset.aba;return desenhar()}
  const ap=e.target.closest("[data-apagar]");if(ap&&confirm("Apagar esta publicação do site?"))acao(async()=>{const{error}=await(await S().cliente()).from("site_publicacoes").delete().eq("id",ap.dataset.apagar);if(error)throw error},"Publicação apagada.")});
document.addEventListener("change",e=>{const box=$("adminSiteContent"),t=e.target;if(!box||!box.contains(t))return;const lista=(k,c,id,on)=>{const l=(d.def[k]?.[c]||[]).filter(x=>x!==id);if(on)l.push(id);return l};
  if(t.id==="spSaidasMostrar")return acao(()=>guardarDef("saidas",{mostrar:t.checked}),"Guardado.");
  if(t.id==="spSaidasMax")return acao(()=>guardarDef("saidas",{max:+t.value}),"Guardado.");
  if(t.dataset.saida)return acao(()=>guardarDef("saidas",{ocultas:lista("saidas","ocultas",t.dataset.saida,!t.checked)}),t.checked?"A saída volta a aparecer no site.":"A saída deixou de aparecer no site.");
  if(t.id==="spPrestMostrar")return acao(()=>guardarDef("prestadores",{mostrar:t.checked}),"Guardado.");
  if(t.id==="spPrestMax")return acao(()=>guardarDef("prestadores",{max:+t.value}),"Guardado.");
  if(t.name==="spModo")return acao(()=>guardarDef("prestadores",{auto:t.value==="auto"}),"Guardado.");
  if(t.dataset.prest){const auto=(d.def.prestadores||{}).auto!==false;return acao(()=>guardarDef("prestadores",auto?{ocultos:lista("prestadores","ocultos",t.dataset.prest,!t.checked)}:{escolhidos:lista("prestadores","escolhidos",t.dataset.prest,t.checked)}),"Guardado.")}
  if(t.dataset.destaque!==undefined){const id=t.dataset.destaque,v=t.value.trim(),ant=d.pubs.find(x=>x.tipo==="destaque"&&x.empresa_id===id);
    return acao(async()=>{const sb=await S().cliente();const r=ant?(v?await sb.from("site_publicacoes").update({texto:v,ativo:true,updated_at:new Date().toISOString()}).eq("id",ant.id):await sb.from("site_publicacoes").delete().eq("id",ant.id))
      :v?await sb.from("site_publicacoes").insert({tipo:"destaque",titulo:"Destaque",texto:v,empresa_id:id}):{error:null};if(r.error)throw r.error},"Destaque guardado.")}
  if(t.dataset.pub)return acao(async()=>{const{error}=await(await S().cliente()).from("site_publicacoes").update({ativo:t.checked,updated_at:new Date().toISOString()}).eq("id",t.dataset.pub);if(error)throw error},t.checked?"Publicação ativa.":"Publicação escondida.");
  if(t.id==="spFeedMostrar")return acao(()=>guardarDef("feed",{mostrar:t.checked}),"Guardado.");
  if(t.id==="spFeedMax")return acao(()=>guardarDef("feed",{max:+t.value}),"Guardado.");
  if(t.id==="spFaixa")return acao(()=>guardarDef("feed",{faixa:t.checked}),t.checked?"A faixa aparece no site.":"A faixa deixou de aparecer.");
  if(t.id==="spFeedAuto")return acao(()=>guardarDef("feed",{auto:t.checked}),"Guardado.")});
document.addEventListener("submit",e=>{if(e.target.id!=="spForm")return;e.preventDefault();const v=id=>$(id).value.trim();
  const lig=v("spLig");if(lig&&!/^(https:\/\/(www\.)?elolog\.pt(\/|$)|\/|#|\.\.\/)/.test(lig))return aviso("A ligação tem de ser do site Elolog (ex.: /site/simulador.html).","warning");
  acao(async()=>{const{error}=await(await S().cliente()).from("site_publicacoes").insert({tipo:v("spTipo"),titulo:v("spTitulo"),texto:v("spTexto")||null,empresa_id:v("spEmp")||null,
    ligacao:lig||null,inicio:v("spIni")||null,fim:v("spFim")||null});if(error)throw error},"Publicado no site.")});

const orig=window.showAdminPage;if(typeof orig==="function")window.showAdminPage=showAdminPage=function(page){const r=orig.apply(this,arguments);
  if(page==="adminSite"){const t=$("pageTitle");if(t)t.textContent="Site público";desenhar();recarregar()}return r};
function ligar(){if(typeof currentUser==="undefined"||currentUser?.role!=="admin")return;pagina();botao()}
const ini=window.startApp;if(typeof ini==="function")window.startApp=async function(){const r=await ini.apply(this,arguments);setTimeout(ligar,600);setTimeout(ligar,2000);return r};
setTimeout(ligar,1500);window.elologSitePublico={recarregar,abrir:()=>showAdminPage("adminSite")};
})();
