/* Elolog — Centro de Controlo «Painel ao vivo» (v101), para a administração.
   Dados reais pela função painel_vivo (só leitura) através da ligação Supabase existente (ELOLogServidor.cliente); atualiza a cada 30 s.
   Não muda fluxos, permissões, comissões nem planos: cada botão leva a uma página ou ação que já existe (ficha da operação, Operações,
   Faturação, Comissões…). A vista anterior continua disponível no separador «Indicadores e simulações». */
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
let dados=null,erro="",aba="vivo",sel=0,zoom=1,ecra=false,q="",ord="atualizada",dir=-1,soServico=false,carregando=false,temp=null;

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

const recs=()=>dados?.demo&&!(dados.recentes||[]).length?(dados.recentes=demo().recentes):(dados?.recentes||[]);
async function carregar(){const i=I();if(i.sessaoDemo?.()){dados=demo();erro="";return desenhar()}if(!i.sessaoServidor?.()||carregando)return;carregando=true;
  try{const sb=await window.ELOLogServidor.cliente();const{data,error}=await sb.rpc("painel_vivo");if(error)throw error;dados=data;erro=""}
  catch(e){erro=window.ELOLogServidor?.mensagem?.(e)||e.message}finally{carregando=false;desenhar()}}

function kpis(k){const delta=(a,b,inv)=>{if(b==null||!b)return["",""];const p=(a-b)/b*100,bom=inv?p<=0:p>=0;return[(p>=0?"↑ ":"↓ ")+Math.abs(p).toFixed(1).replace(".",",")+" %",bom?"ok":"verm"]};
  const r=delta(k.receita_hoje,k.receita_media_14d),c=delta(k.novas_30d,k.novas_30d_anteriores),z=k.prazo_pct!=null&&k.prazo_pct_anterior!=null?[(k.prazo_pct>=k.prazo_pct_anterior?"↑ ":"↓ ")+Math.abs(k.prazo_pct-k.prazo_pct_anterior).toFixed(1).replace(".",",")+" pp",k.prazo_pct>=k.prazo_pct_anterior?"ok":"verm"]:["",""];
  const C=[["euro","ok","Receita da Elolog hoje",eur(k.receita_hoje),`${eur(k.comissoes_hoje)} comissões, ${eur(k.planos_hoje)} planos`,r[0]&&r[0]+" vs média",r[1],"adminCommissions"],
    ["caixa","azul","Encomendas em curso",num(k.em_curso),"novas nos últimos 30 dias",c[0],c[1],"adminOperations"],
    ["relogio","mar","Levantadas no prazo",k.prazo_pct==null?"—":String(k.prazo_pct).replace(".",",")+" %","últimos 30 dias",z[0],z[1],"adminOperations"],
    ["alerta","amb","Dinheiro em risco",eur(k.risco_valor),`${num(k.risco_pagamentos)} pagamento(s) pendente(s)`,k.atrasadas?`${k.atrasadas} atrasada(s)`:"",k.atrasadas?"amb":"","adminBilling"]];
  return C.map(x=>`<button type="button" class="pv-kpi" data-pv-ir="${x[7]}"><span class="pv-kpi-t"><span class="pv-ic pv-ic-${x[1]}">${ico(IC[x[0]],16)}</span>${x[2]}</span>
    <strong>${x[3]}</strong><span class="pv-kpi-b"><span>${esc(x[4])}</span>${x[5]?`<b class="pv-delta pv-${x[6]||"cinza"}">${esc(x[5])}</b>`:""}</span></button>`).join("")}

function viagens(vs){if(!vs.length)return'<p class="pv-vazio">Sem navios com carga Elolog neste momento.</p>';return vs.map((v,i)=>{const p=Math.round(M().progresso(v)*100),c=M().corViagem(v),pos=M().posicao(v);
  return`<div class="pv-viagem ${i===sel?"on":""}"><button type="button" class="pv-viagem-b" data-pv-viagem="${i}" aria-pressed="${i===sel}">
    <span class="pv-row"><strong>${esc(v.navio)}${v.viagem?` <small>viagem ${esc(v.viagem)}</small>`:""}</strong>${pill(v.atrasada?"Atrasada":v.em_transito?"Em rota":"No porto",v.atrasada?"verm":v.em_transito?"azul":"cinza")}</span>
    <span class="pv-rota"><span><b>${esc((v.origem||"").split(",")[0])}</b></span><span class="pv-barra"><i style="width:${p}%;background:${c}"></i><i class="pv-pt" style="left:calc(${p}% - 5px);border-color:${c}"></i></span><span><b>${esc((v.destino||"").split(",")[0])}</b></span></span>
    <span class="pv-sub pv-1l">${num(v.encomendas)} encomenda(s), ${esc((v.prestadores||[]).join(", "))}</span>
    <span class="pv-row pv-sub"><span>Chega a ${dia(v.chegada)}</span><span class="pv-pos pv-pos-${pos[2]==="AIS"?"ais":"est"}">Posição ${pos[2]}${v.ais?.nos!=null?`, ${String(v.ais.nos).replace(".",",")} nós`:""}</span></span></button>
    ${i===sel?`<div class="pv-codigos">${(v.codigos||[]).slice(0,8).map(c=>`<button type="button" class="pv-cod" data-ficha="${esc(c)}">${esc(c)}</button>`).join("")}</div>`:""}</div>`}).join("")}

function meios(d){const L=[];(d.viagens||[]).forEach((v,i)=>L.push({ic:"navio",tipo:"Navio",cod:v.navio,nome:`${v.origem||"—"} para ${v.destino||"—"}`,est:v.atrasada?["Atrasado","verm"]:["Em rota","azul"],det:`${num(v.encomendas)} encomenda(s)`,acao:`data-pv-viagem="${i}"`,servico:true}));
  (d.veiculos||[]).forEach(v=>L.push({ic:"camiao",tipo:"Viatura",cod:v.matricula,nome:`${v.descricao||"Viatura"}, ${v.empresa}`,est:v.servicos_hoje?["Em serviço","ok"]:["Disponível","cinza"],det:v.servicos_hoje?`${v.por_fazer} de ${v.servicos_hoje} por fazer`:"sem serviços hoje",acao:'data-pv-ir="adminOperations"',servico:!!v.servicos_hoje}));
  const l=soServico?L.filter(x=>x.servico):L;if(!l.length)return'<p class="pv-vazio">Sem meios em serviço.</p>';
  return l.map(x=>`<button type="button" class="pv-meio" ${x.acao}><span class="pv-meio-ic" title="${x.tipo}">${ico(IC[x.ic],20)}</span><span class="pv-meio-t"><strong>${esc(x.cod)}</strong><span title="${esc(x.nome)}">${esc(x.nome)}</span></span>
    <span class="pv-meio-e">${pill(x.est[0],x.est[1])}<small>${esc(x.det)}</small></span></button>`).join("")}

const COL=[["codigo","Código"],["origem","Origem"],["destino","Destino"],["chegada","Chegada prevista"],["transporte","Transporte"],["prestador","Prestador"],["estado","Estado"]];
function tabela(rs){const f=q.trim().toLowerCase();let l=rs.filter(r=>!f||[r.codigo,r.origem,r.destino,r.cliente,r.prestador,r.transporte].join(" ").toLowerCase().includes(f));
  l=l.slice().sort((a,b)=>String(a[ord]??"").localeCompare(String(b[ord]??""),"pt")*dir);
  const th=COL.map(([k,t])=>`<th scope="col" aria-sort="${ord===k?(dir>0?"ascending":"descending"):"none"}"><button type="button" class="pv-th" data-pv-ord="${k}">${t}<span aria-hidden="true">${ord===k?(dir>0?"▲":"▼"):"↕"}</span></button></th>`).join("");
  const tr=l.map(r=>{const e=ESTADO[r.estado]||[r.estado,"cinza"],est=r.suspensa?pill("Suspensa","verm"):r.atrasada?pill("Atrasada","verm"):pill(e[0],e[1]);
    return`<tr class="pv-tr" data-ficha="${esc(r.codigo)}" tabindex="0" title="Abrir a ficha da operação"><td data-label="Código"><span><strong>${esc(r.codigo)}</strong><small>${esc(r.cliente||"")}</small></span></td><td data-label="Origem">${esc(r.origem||"—")}</td><td data-label="Destino">${esc(r.destino||"—")}</td>
      <td data-label="Chegada">${dia(r.chegada)}</td><td data-label="Transporte">${r.transporte?`<span class="pv-tr-ic">${ico(IC.navio,16)}${esc(r.transporte)}</span>`:"—"}</td><td data-label="Prestador">${esc(r.prestador||"—")}</td><td data-label="Estado">${est}${r.pagamento_pendente?' <span class="pv-pend" title="Pagamento pendente">€</span>':""}</td></tr>`}).join("");
  return`<table class="pv-tab"><thead><tr>${th}</tr></thead><tbody>${tr||`<tr><td colspan="7" class="pv-vazio">Nenhuma encomenda corresponde à procura.</td></tr>`}</tbody></table>`}

function armazens(as){if(!as.length)return'<p class="pv-vazio">Sem armazéns ativos registados.</p>';const max=Math.max(1,...as.map(a=>a.volumes||a.encomendas||0));
  return as.map(a=>{const v=a.volumes||a.encomendas||0,p=Math.round(v*100/max);return`<button type="button" class="pv-arm" data-pv-ir="adminOperations"><span class="pv-row"><strong>${esc(a.nome)}</strong><span>${num(a.volumes)} vol., ${num(a.encomendas)} enc.</span></span>
    <span class="pv-arm-b" aria-hidden="true"><i style="width:${p}%"></i></span><small>${esc(a.empresa||"")}</small></button>`}).join("")}

function html(){const d=dados,k=d.kpis||{},hora=new Date(d.gerado_em||Date.now()).toLocaleTimeString("pt-PT");
  return`<div class="pv-topo"><span class="pv-vivo"><i></i>${d.demo?"Demonstração":"Ao vivo"}, atualizado às ${hora}</span>${erro?`<span class="pv-erro">Não foi possível atualizar (${esc(erro)}).</span>`:""}
    <button type="button" class="pv-btn" data-pv-atualizar>Atualizar agora</button></div>
  <section class="pv-kpis" aria-label="Indicadores">${kpis(k)}</section>
  <section class="pv-cartao pv-mapa-c" aria-labelledby="pvMapa"><div class="pv-cab"><h3 id="pvMapa">Navios ao vivo</h3><span>${zoom>1?`Aproximado ${zoom.toFixed(1).replace(".",",")}×`:"Vista geral do corredor"}</span></div>
    <div class="pv-mapa-g"><div class="pv-mapa ${ecra?"grande":""}">${M().svg(d,sel,zoom)}
        <div class="pv-zoom"><button type="button" class="pv-btn-i" data-pv-zoom="1" aria-label="Aproximar o mapa">+</button><button type="button" class="pv-btn-i" data-pv-zoom="-1" aria-label="Afastar o mapa">−</button>
          <button type="button" class="pv-btn-i" data-pv-ecra aria-label="${ecra?"Reduzir":"Aumentar"} o mapa">${ico("M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5",15)}</button></div>
        <div class="pv-legenda" aria-hidden="true"><span><i style="background:#1F5F8B"></i>Em rota</span><span><i style="background:#1F7A5C"></i>Chega em breve</span><span><i style="background:#C27A12"></i>Atrasado</span></div></div>
      <div class="pv-acomp"><div class="pv-cab"><strong>Acompanhamento</strong><span>${num((d.viagens||[]).length)} viagem(ns)</span></div><div class="pv-acomp-l">${viagens(d.viagens||[])}</div></div></div></section>
  <section class="pv-cartao pv-tab-c" aria-labelledby="pvEnc"><div class="pv-cab"><h3 id="pvEnc">Encomendas recentes</h3>
      <label class="pv-q"><span class="pv-sr">Procurar nas encomendas recentes</span>${ico("M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-3.5-3.5",14)}<input type="search" data-pv-q value="${esc(q)}" placeholder="Código, cidade, cliente ou prestador"></label></div>
      <div class="pv-tab-w">${tabela(recs())}</div></section>
  <div class="pv-linha"><section class="pv-cartao pv-meios-c" aria-labelledby="pvMeios"><div class="pv-cab"><h3 id="pvMeios">Meios em serviço</h3><button type="button" class="pv-btn" data-pv-filtro>${soServico?"Ver todos":"Só em serviço"}</button></div><div class="pv-meios">${meios(d)}</div></section>
    <section class="pv-cartao pv-lado" aria-labelledby="pvArm"><div class="pv-cab"><h3 id="pvArm">Carga nos armazéns</h3><span>volumes guardados</span></div>${armazens(d.armazens||[])}</section></div>`}

function seccao(){const sec=document.querySelector("#adminDashboardProviders .pa-centro");if(!sec)return null;let p=sec.querySelector("#pvPainel");
  if(!p){const cab=sec.querySelector(".pa-cabecalho");if(!cab)return null;cab.insertAdjacentHTML("afterend",'<div class="pv-abas" role="tablist"><button type="button" role="tab" data-pv-tab="vivo">Ao vivo</button><button type="button" role="tab" data-pv-tab="classico">Indicadores e simulações</button></div><div id="pvPainel" class="pv"></div>');
    p=sec.querySelector("#pvPainel");sec.addEventListener("click",clique);sec.addEventListener("input",ev=>{if(ev.target.matches("[data-pv-q]")){q=ev.target.value;const w=p.querySelector(".pv-tab-w");if(w&&dados)w.innerHTML=tabela(recs())}});
    sec.addEventListener("keydown",ev=>{const tr=ev.target.closest?.(".pv-tr");if(tr&&(ev.key==="Enter"||ev.key===" ")){ev.preventDefault();tr.click()}})}
  sec.classList.toggle("pv-ativo",aba==="vivo");sec.querySelectorAll("[data-pv-tab]").forEach(b=>b.setAttribute("aria-selected",String(b.dataset.pvTab===aba)));return p}
function desenhar(){const p=seccao();if(!p)return;if(!dados){p.innerHTML=`<p class="pv-vazio">${erro?esc(erro):"A carregar o painel ao vivo…"}</p>`;return}
  const foco=document.activeElement?.matches?.("[data-pv-q]");p.innerHTML=html();if(foco){const i=p.querySelector("[data-pv-q]");i.focus();i.setSelectionRange(i.value.length,i.value.length)}}
function clique(ev){const b=ev.target.closest("[data-pv-tab],[data-pv-ir],[data-pv-viagem],[data-pv-zoom],[data-pv-ecra],[data-pv-atualizar],[data-pv-filtro],[data-pv-ord]");if(!b)return;
  if(b.dataset.pvTab){aba=b.dataset.pvTab;seccao();return}
  if(b.dataset.pvIr){const pg=b.dataset.pvIr;try{showAdminPage(pg,document.querySelector(`#sidebar [onclick*="'${pg}'"]`))}catch(_){}return}
  if(b.dataset.pvViagem!=null){sel=+b.dataset.pvViagem;zoom=Math.max(zoom,1.8);return desenhar()}
  if(b.dataset.pvZoom){zoom=Math.max(1,Math.min(3.2,zoom+(+b.dataset.pvZoom)*.6));return desenhar()}
  if(b.hasAttribute("data-pv-ecra")){ecra=!ecra;return desenhar()}
  if(b.hasAttribute("data-pv-atualizar"))return carregar();
  if(b.hasAttribute("data-pv-filtro")){soServico=!soServico;return desenhar()}
  if(b.dataset.pvOrd){const k=b.dataset.pvOrd;dir=ord===k?-dir:1;ord=k;const w=document.querySelector("#pvPainel .pv-tab-w");if(w&&dados)w.innerHTML=tabela(recs())}}

function ligar(){const alvo=document.getElementById("adminDashboardProviders");if(!alvo)return setTimeout(ligar,500);
  new MutationObserver(()=>{if(alvo.querySelector(".pa-centro")&&!alvo.querySelector("#pvPainel")){desenhar();if(!dados||(dados.demo&&!(dados.recentes||[]).length))carregar()}}).observe(alvo,{childList:true});
  clearInterval(temp);temp=setInterval(()=>{if(document.visibilityState==="visible"&&document.getElementById("pvPainel")?.offsetParent&&aba==="vivo")carregar()},3e4)}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
window.elologPainelVivo={carregar,desenhar,dados:()=>dados};
})();
