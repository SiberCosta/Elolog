/* Elolog — Centro de comando (v103), para a administração: um só ecrã (o antigo «Indicadores e simulações» está aqui dentro).
   Dados reais pela função painel_vivo (só leitura) através da ligação Supabase existente (ELOLogServidor.cliente); atualiza a cada 30 s.
   Não muda fluxos, permissões, comissões nem planos: cada botão leva a uma página ou ação que já existe (ficha da operação, Operações,
   Faturação, Comissões…). As secções do período (negócio, rotas, prestadores, atividade) vêm de painel-vivo-seccoes.js. */
(function(){"use strict";
const I=()=>window.__ELOLOG_INTERNO?.["painel@administracao"]||{},M=()=>window.elologPVMapa;
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const eur=v=>(Number(v)||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR",minimumFractionDigits:0,maximumFractionDigits:Math.abs(Number(v)||0)>=1e3?0:2});
const num=v=>(Number(v)||0).toLocaleString("pt-PT"),dia=v=>v?new Date(v).toLocaleDateString("pt-PT",{day:"numeric",month:"short"}):"—";
const ESTADO={aprovacao:["Aprovação","azul"],agendamento:["Agendamento","azul"],recolha:["Recolha","azul"],armazenamento:["Em armazém","cinza"],expedicao:["Expedição","azul"],
  em_transito:["Em trânsito","azul"],destino:["No destino","ok"],disponivel:["Disponível","ok"],entregue:["Levantada","ok"],cancelada:["Cancelada","cinza"]};
const IC={euro:"M17 6.5A7 7 0 1 0 17 17.5M4 10h9M4 14h9",caixa:"M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5zM3.5 7.5 12 12l8.5-4.5M12 12v9",relogio:"M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2",
  alerta:"M12 3l10 18H2zM12 10v5M12 18v.5",navio:"M3 17c2 1.5 4 1.5 6 0s4-1.5 6 0 4 1.5 6 0M5 14l1.5-5h11L19 14M12 9V4l4 2",camiao:"M2 16V6h11v10M13 9h4l4 4v3h-8M7 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM17 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4z",
  armazem:"M3 10l9-6 9 6v10H3zM8 20v-6h8v6"};
const ico=(p,s)=>`<svg width="${s||18}" height="${s||18}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${p}"/></svg>`;
const pill=(t,c)=>`<span class="pv-pill pv-${c}">${esc(t)}</span>`;
let dados=null,erro="",ed=0,sel=0,mapa=false,zoom=1,ecra=false,q="",ord="atualizada",dir=-1,carregando=false,temp=null;

function demo(){const h=new Date(),d=n=>new Date(h.getTime()+n*864e5).toISOString().slice(0,10);return{demo:true,gerado_em:h.toISOString(),
  kpis:{receita_hoje:1284,comissoes_hoje:1046,planos_hoje:238,receita_media_14d:1088,em_curso:156,novas_30d:142,novas_30d_anteriores:131,prazo_pct:94.8,prazo_pct_anterior:96,risco_valor:3140,risco_pagamentos:4,atrasadas:2},
  viagens:[{navio:"Ilhéu das Rolas",viagem:"118",origem:"Lisboa",destino:"São Tomé",encomendas:16,codigos:["EL-000245","EL-000243"],partida:d(-6),chegada:d(12),em_transito:true,atrasada:false,prestadores:["Atlântico Cargo (demo)"]},
    {navio:"Monte Cara",viagem:"54",origem:"Lisboa",destino:"Praia",encomendas:6,codigos:["EL-000242"],partida:d(-8),chegada:d(1),em_transito:true,atrasada:false,prestadores:["Tejo Transitários (demo)"]},
    {navio:"Atlântico Sul",viagem:"31",origem:"Leixões",destino:"Luanda",encomendas:4,codigos:["EL-000241"],partida:d(-25),chegada:d(-2),em_transito:true,atrasada:true,prestadores:["Luso Freight (demo)"]}],
  portos:[{cidade:"Lisboa",n:34},{cidade:"São Tomé",n:29},{cidade:"Leixões",n:9},{cidade:"Praia",n:6},{cidade:"Luanda",n:4}],
  veiculos:[{matricula:"LX-42-AB",descricao:"Carrinha de recolhas",empresa:"Atlântico Cargo (demo)",servicos_hoje:3,por_fazer:1},{matricula:"PT-19-CD",descricao:"Camião 7,5 t",empresa:"Luso Freight (demo)",servicos_hoje:0,por_fazer:0}],
  armazens:[{nome:"Alverca",empresa:"Atlântico Cargo (demo)",encomendas:17,volumes:86},{nome:"Matosinhos",empresa:"Luso Freight (demo)",encomendas:8,volumes:41},{nome:"Neves",empresa:"Atlântico Cargo (demo)",encomendas:6,volumes:30}],
  recentes:(window.__ELOLOG_INTERNO?.painelDados?.()?.operacoes_recentes||[]).slice(0,8).map((o,i)=>({codigo:o.ref,origem:o.origem,destino:o.destino,chegada:d(i*3-2),transporte:i%2?"Ilhéu das Rolas 118":null,prestador:o.prestador,
    cliente:o.cliente,estado:{"Em trânsito":"em_transito","Armazém":"armazenamento","Recolha":"recolha","Expedição":"expedicao","Aprovação":"aprovacao","No destino":"destino","Entregue":"entregue"}[o.estado]||"aprovacao",atrasada:i===3,pagamento_pendente:i===1,atualizada:o.quando}))}}

const exc=()=>recs().filter(r=>r.atrasada||r.pagamento_pendente||r.suspensa);
const recs=()=>dados?.demo&&!(dados.recentes||[]).length?(dados.recentes=demo().recentes):(dados?.recentes||[]);
async function contarDiretas(){try{const l=await window.elologED?.listar?.();if(Array.isArray(l))ed=l.filter(x=>["pendente_validacao","em_analise_admin","validada","recusada"].includes(x.estado)).length}catch(_){}}
async function carregar(){const i=I();contarDiretas().then(()=>{if(dados)desenhar()});if(i.sessaoDemo?.()){dados=demo();erro="";return desenhar()}if(!i.sessaoServidor?.()||carregando)return;carregando=true;
  try{const sb=await window.ELOLogServidor.cliente();const{data,error}=await sb.rpc("painel_vivo");if(error)throw error;dados=data;erro=""}
  catch(e){erro=window.ELOLogServidor?.mensagem?.(e)||e.message}finally{carregando=false;desenhar()}}

/* Frase grande do painel principal: muda sozinha de 7 em 7 s (pára com o rato ou o foco em cima, e não muda com «reduzir movimento») */
let fi=0,fT=null;
function frase(k,p,d){const F=S().frases(k,p,d,ed);if(fi>=F.length)fi=0;
  return`<div class="pv-frases" aria-roledescription="carrossel" aria-label="Estado da plataforma"><ul class="pv-frases-l">${F.map((x,i)=>`<li class="${i===fi?"on":""}" aria-hidden="${i!==fi}">
    <button type="button" class="pv-frase" ${x.i?`data-pv-ir="${x.i}"`:`data-pv-rolar="${x.r}"`} tabindex="${i===fi?0:-1}">${esc(x.t)}</button></li>`).join("")}</ul>
    <div class="pv-frases-p">${F.map((x,i)=>`<button type="button" class="${i===fi?"on":""}" data-pv-frase="${i}" aria-label="Frase ${i+1} de ${F.length}" aria-pressed="${i===fi}"></button>`).join("")}<span class="pv-frases-t" aria-hidden="true"><i></i></span></div></div>`}
function mostrarFrase(n){const c=document.querySelector("#pvPainel .pv-frases");if(!c)return;const L=[...c.querySelectorAll(".pv-frases-l li")],B=[...c.querySelectorAll("[data-pv-frase]")];if(!L.length)return;
  const velho=L[fi];fi=(n+L.length)%L.length;if(velho&&velho!==L[fi]){velho.classList.add("sai");setTimeout(()=>velho.classList.remove("sai"),650)}L.forEach((li,i)=>{li.classList.toggle("on",i===fi);li.setAttribute("aria-hidden",String(i!==fi));li.querySelector("button").tabIndex=i===fi?0:-1});
  B.forEach((b,i)=>{b.classList.toggle("on",i===fi);b.setAttribute("aria-pressed",String(i===fi))});const t=c.querySelector(".pv-frases-t i");if(t){t.style.animation="none";void t.offsetWidth;t.style.animation=""}}
function rodarFrases(){clearInterval(fT);if(window.matchMedia?.("(prefers-reduced-motion: reduce)").matches)return;
  fT=setInterval(()=>{const c=document.querySelector("#pvPainel .pv-frases");if(!c||document.hidden||c.matches(":hover,:focus-within"))return;mostrarFrase(fi+1)},7000)}

/** Posição real sem ligação nossa: com IMO (vem do AIS) abre a página do navio no VesselFinder; sem IMO, pesquisa pelo nome. */
const real=v=>v.ais?.imo&&/^\d{7}$/.test(String(v.ais.imo))?`https://www.vesselfinder.com/vessels/details/${v.ais.imo}`:`https://www.google.com/search?q=${encodeURIComponent(`"${v.navio}" vessel position AIS`)}`;
function viagens(vs){if(!vs.length)return'<div class="pv-vazio-n"><strong>Nenhum navio com carga Elolog.</strong><span>Quando um prestador expedir uma encomenda, o navio aparece aqui com a rota e a data de chegada.</span></div>';return vs.map((v,i)=>{const p=Math.round(M().progresso(v)*100),c=M().corViagem(v),pos=M().posicao(v);
  const on=mapa&&i===sel;
  return`<div class="pv-viagem ${on?"on":""}"><button type="button" class="pv-viagem-b" data-pv-viagem="${i}" aria-pressed="${on}" title="${on?"Navio no mapa":"Ver este navio no mapa"}">
    <span class="pv-row"><strong>${esc(v.navio)}${v.viagem?` <small>viagem ${esc(v.viagem)}</small>`:""}</strong>${pill(v.atrasada?"Atrasada":v.em_transito?"Em rota":"No porto",v.atrasada?"verm":v.em_transito?"azul":"cinza")}</span>
    <span class="pv-rota"><span><b>${esc((v.origem||"").split(",")[0])}</b></span><span class="pv-barra"><i style="width:${p}%;background:${c}"></i><i class="pv-pt" style="left:calc(${p}% - 5px);border-color:${c}"></i></span><span><b>${esc((v.destino||"").split(",")[0])}</b></span></span>
    <span class="pv-sub pv-1l">${num(v.encomendas)} ${v.encomendas==1?"encomenda":"encomendas"}, ${esc((v.prestadores||[]).join(", "))}</span>
    <span class="pv-row pv-sub"><span>Chega a ${dia(v.chegada)}</span><span class="pv-pos pv-pos-${pos[2]==="AIS"?"ais":"est"}">Posição ${pos[2]}${v.ais?.nos!=null?`, ${String(v.ais.nos).replace(".",",")} nós`:""}</span></span></button>
    ${on?`<div class="pv-codigos">${(v.codigos||[]).slice(0,8).map(c=>`<button type="button" class="pv-cod" data-ficha="${esc(c)}">${esc(c)}</button>`).join("")}
      <a class="pv-real" href="${real(v)}" target="_blank" rel="noopener noreferrer">${v.ais?.imo?"Ver a posição real (VesselFinder)":"Procurar a posição real deste navio"}</a></div>`:""}</div>`}).join("")}

const COL=[["codigo","Código"],["origem","Origem"],["destino","Destino"],["chegada","Chegada prevista"],["transporte","Transporte"],["prestador","Prestador"],["estado","Estado"]];
function tabela(rs){const f=q.trim().toLowerCase();let l=rs.filter(r=>!f||[r.codigo,r.origem,r.destino,r.cliente,r.prestador,r.transporte].join(" ").toLowerCase().includes(f));
  l=l.slice().sort((a,b)=>String(a[ord]??"").localeCompare(String(b[ord]??""),"pt")*dir);
  const th=COL.map(([k,t])=>`<th scope="col" aria-sort="${ord===k?(dir>0?"ascending":"descending"):"none"}"><button type="button" class="pv-th" data-pv-ord="${k}">${t}<span aria-hidden="true">${ord===k?(dir>0?"▲":"▼"):"↕"}</span></button></th>`).join("");
  const tr=l.map(r=>{const e=ESTADO[r.estado]||[r.estado,"cinza"],est=r.suspensa?pill("Suspensa","verm"):r.atrasada?pill("Atrasada","verm"):pill(e[0],e[1]);
    return`<tr class="pv-tr" data-ficha="${esc(r.codigo)}" tabindex="0" title="Abrir a ficha da operação"><td data-label="Código"><span><strong>${esc(r.codigo)}</strong><small>${esc(r.cliente||"")}</small></span></td><td data-label="Origem">${esc(r.origem||"—")}</td><td data-label="Destino">${esc(r.destino||"—")}</td>
      <td data-label="Chegada">${dia(r.chegada)}</td><td data-label="Transporte">${r.transporte?`<span class="pv-tr-ic">${ico(IC.navio,16)}${esc(r.transporte)}</span>`:"—"}</td><td data-label="Prestador">${esc(r.prestador||"—")}</td><td data-label="Estado">${est}${r.pagamento_pendente?' <span class="pv-pill pv-amb pv-pend-t" title="Há um pagamento por confirmar (ver Faturação)">Pagamento</span>':""}</td></tr>`}).join("");
  return`<table class="pv-tab"><thead><tr>${th}</tr></thead><tbody>${tr||`<tr><td colspan="7" class="pv-vazio">Nenhuma encomenda corresponde à procura.</td></tr>`}</tbody></table>`}


const S=()=>window.elologPVS,P=()=>window.__ELOLOG_INTERNO?.painelDados?.(),PA=()=>window.__ELOLOG_INTERNO?.painelAnterior?.(),DIAS=()=>window.__ELOLOG_INTERNO?.painelDias?.()||30;
function html(){const d=dados,k=d.kpis||{},p=P(),hora=new Date(d.gerado_em||Date.now()).toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"});
  return`<section class="pv-escuro pv-heroi" aria-label="Estado do negócio agora">
    <div class="pv-barra-sup"><span class="pv-vivo"><i></i>${d.demo?"Demonstração":"Ao vivo"}, ${hora}</span>${erro?`<span class="pv-erro">Não foi possível atualizar (${esc(erro)}).</span>`:""}
      <div class="pv-acoes"><button type="button" class="btn-primary pv-bt" data-pv-acao="contacto">${ico("M12 5v14M5 12h14",15)}Pedido por contacto</button><button type="button" class="btn-secondary pv-bt" data-pv-acao="auditoria">${ico("M9 4h6v3H9zM7 5H5v16h14V5h-2M9 13l2 2 4-4",15)}Auditoria de prestador</button>
        <button type="button" class="btn-secondary pv-bt pv-bt-i" data-pv-acao="ecra" aria-label="Ecrã inteiro (modo apresentação)" title="Ecrã inteiro">${ico("M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5",16)}</button><button type="button" class="btn-secondary pv-bt pv-bt-i" data-pv-acao="atualizar" aria-label="Atualizar agora" title="Atualizar agora">${ico("M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7",16)}</button></div></div>
    <div class="pv-heroi-n pv-heroi-so">${frase(k,p,d)}</div>
    ${mapa?"":`<div class="pv-mapa-g pv-sem-mapa" id="pvMapa"><div class="pv-acomp pv-acomp-larga"><div class="pv-acomp-c"><strong>Navios com carga Elolog</strong><span>${(d.viagens||[]).length?"Escolha um navio para o ver no mapa do corredor atlântico.":""}</span></div><div class="pv-acomp-l">${viagens(d.viagens||[])}</div></div></div>`}
    ${!mapa?"":`<div class="pv-mapa-g" id="pvMapa"><div class="pv-mapa ${ecra?"grande":""}">${M().svg(d,sel,zoom)}
        <div class="pv-zoom"><button type="button" class="pv-btn-i" data-pv-zoom="1" aria-label="Aproximar o mapa">+</button><button type="button" class="pv-btn-i" data-pv-zoom="-1" aria-label="Afastar o mapa">−</button>
          <button type="button" class="pv-btn-i" data-pv-ecra aria-label="${ecra?"Reduzir":"Aumentar"} o mapa">${ico("M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5",15)}</button></div>
        <button type="button" class="btn-secondary pv-fechar-mapa" data-pv-fechar-mapa>Fechar o mapa</button>
        <div class="pv-legenda" aria-hidden="true"><span><i style="background:#1F5F8B"></i>Em rota</span><span><i style="background:#1F7A5C"></i>Chega em breve</span><span><i style="background:#C27A12"></i>Atrasado</span></div>
        <span class="pv-mapa-t">${zoom>1?`Aproximado ${zoom.toFixed(1).replace(".",",")}×`:"Corredor atlântico"}</span></div>
      <div class="pv-acomp"><div class="pv-acomp-c"><strong>Navios com carga Elolog</strong><span>Toque noutro navio para o ver</span></div><div class="pv-acomp-l">${viagens(d.viagens||[])}</div></div></div>`}</section>
  ${S().atencao(p,ed)}
  <section class="pv-cartao pv-tab-c" aria-labelledby="pvEnc"><div class="pv-cab"><div><h3 id="pvEnc">Encomendas a acompanhar</h3><p class="pv-cab-p">Com atraso, pagamento pendente ou suspensas, entre as atualizadas mais recentemente</p></div>
      <button type="button" class="pv-lig" data-pv-ir="adminOperations">Ver todas as operações</button></div>
      <div class="pv-tab-w">${exc().length?tabela(exc()):'<p class="pv-vazio pv-vazio-ok">Nenhuma encomenda com atraso, pagamento pendente ou suspensão.</p>'}</div></section>
  ${S().corrente(p)}
  ${S().negocio(p,PA(),DIAS())}`}

/* o painel antigo continua a ser desenhado (dados, simulações, apresentação), mas fica escondido; este ecrã fica no lugar dele */
function seccao(){const sec=document.querySelector("#adminDashboardProviders .pa-centro");if(!sec)return null;let p=sec.querySelector("#pvPainel");
  if(!p){sec.insertAdjacentHTML("afterbegin",'<div id="pvPainel" class="pv"><div class="pv-corpo"></div><div class="pv-fim"></div></div>');
    p=sec.querySelector("#pvPainel");sec.addEventListener("click",clique);
    sec.addEventListener("keydown",ev=>{const tr=ev.target.closest?.(".pv-tr");if(tr&&(ev.key==="Enter"||ev.key===" ")){ev.preventDefault();tr.click()}})}
  sec.classList.add("pv-ativo");return p}
function simulacoes(){const s=document.getElementById("paSimulacoes"),f=document.querySelector("#pvPainel .pv-fim");if(s&&f&&!f.contains(s))f.appendChild(s)}
function nomeMenu(){const b=document.getElementById("menuDashboard");if(!b||typeof currentUser==="undefined"||currentUser?.role!=="admin")return;
  for(const n of b.childNodes)if(n.nodeType===3&&/Dashboard/.test(n.textContent))n.textContent=n.textContent.replace("Dashboard","Centro de comando");
  b.querySelectorAll(".mi-l,span").forEach(x=>{if(x.childElementCount===0&&x.textContent.trim()==="Dashboard")x.textContent="Centro de comando"});
  const pm=document.getElementById("menuPersonalizar");if(pm&&pm.style.display!=="none")pm.style.display="none"/* o ecrã único tem composição fixa */}
function desenhar(){const p=seccao();nomeMenu();if(!p)return;const c=p.querySelector(".pv-corpo");if(!dados){c.innerHTML=`<p class="pv-vazio">${erro?esc(erro):"A carregar o centro de comando…"}</p>`;return}
  c.innerHTML=html();simulacoes();if(!fT)rodarFrases()}
function clique(ev){const b=ev.target.closest("[data-pv-ir],[data-pv-viagem],[data-pv-zoom],[data-pv-ecra],[data-pv-acao],[data-pv-ord],[data-pv-periodo],[data-pv-frase],[data-pv-rolar],[data-pv-fechar-mapa]");if(!b)return;
  if(b.hasAttribute("data-pv-fechar-mapa")){mapa=false;zoom=1;ecra=false;desenhar();return document.getElementById("pvMapa")?.scrollIntoView({behavior:"smooth",block:"nearest"})}
  if(b.dataset.pvIr==="adminDirectOrders")return window.elologEncDiretasGestao?.abrir(document.querySelector("#sidebar [data-ed-menu]"));
  if(b.dataset.pvIr){const pg=b.dataset.pvIr;try{showAdminPage(pg,document.querySelector(`#sidebar [onclick*="'${pg}'"],#sidebar [onclick*='"${pg}"']`))}catch(_){}return}
  if(b.dataset.pvFrase!=null)return mostrarFrase(+b.dataset.pvFrase);
  if(b.dataset.pvRolar){const alvo=document.getElementById(b.dataset.pvRolar);alvo?.scrollIntoView({behavior:"smooth",block:"start"});return}
  if(b.dataset.pvViagem!=null){const abrir=!mapa;sel=+b.dataset.pvViagem;mapa=true;zoom=Math.max(zoom,1.8);desenhar();if(abrir)document.getElementById("pvMapa")?.scrollIntoView({behavior:"smooth",block:"center"});return}
  if(b.dataset.pvZoom){zoom=Math.max(1,Math.min(3.2,zoom+(+b.dataset.pvZoom)*.6));return desenhar()}
  if(b.hasAttribute("data-pv-ecra")){ecra=!ecra;return desenhar()}
  if(b.dataset.pvPeriodo)return window.painelAdminPeriodo?.(+b.dataset.pvPeriodo);
  const a=b.dataset.pvAcao;if(a==="contacto")return window.elologPedidoContacto?.();if(a==="auditoria")return window.abrirAuditoria?.();if(a==="ecra")return window.painelAdminApresentar?.();
  if(a==="atualizar"){window.painelAdminAtualizar?.();window.elologSimulacoesAdmin?.carregar?.();return carregar()}
  if(b.dataset.pvOrd){const k=b.dataset.pvOrd;dir=ord===k?-dir:1;ord=k;const w=document.querySelector("#pvPainel .pv-tab-w");if(w&&dados)w.innerHTML=tabela(exc())}}

function ligar(){const alvo=document.getElementById("adminDashboardProviders");if(!alvo)return setTimeout(ligar,500);
  new MutationObserver(()=>{if(alvo.querySelector(".pa-centro")&&!alvo.querySelector("#pvPainel")){desenhar();if(!dados||(dados.demo&&!(dados.recentes||[]).length))carregar()}else simulacoes()}).observe(alvo,{childList:true,subtree:true});
  clearInterval(temp);temp=setInterval(()=>{if(document.visibilityState==="visible"&&document.getElementById("pvPainel")?.offsetParent)carregar()},3e4)}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
window.elologPainelVivo={carregar,desenhar,dados:()=>dados};
})();
