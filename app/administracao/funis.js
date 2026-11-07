/* Elolog — Três funis no Centro de comando (v94): Clientes, Prestadores e Financeiro, lado a lado, com o «Gargalo principal».
   Dados: função painel_funis (servidor) pela ligação Supabase já existente (ELOLogServidor.cliente) — nada é reinicializado.
   Regras: sem prestadores aprovados e disponíveis não há propostas; sem proposta válida não há aceite; sem aceite não há
   valor contratado; sem fatura não há faturado; sem pagamento confirmado não há recebido; planos ≠ comissões.
   Em modo de demonstração mostra dados fictícios, sempre identificados como tal. */
(function(){"use strict";
const I=()=>window.__ELOLOG_INTERNO?.["painel@administracao"]||{};
const esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const nf=new Intl.NumberFormat("pt-PT");const num=v=>nf.format(Math.round(Number(v)||0));
const eur=v=>(Number(v)||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR",maximumFractionDigits:Math.abs(Number(v)||0)>=1e3?0:2});
const FUNIS=[["clientes","Funil de Clientes","users"],["prestadores","Funil de Prestadores","truck"],["financeiro","Funil Financeiro","euro"]];
const AJUDA={simulacoes:"Pedidos de cotação enviados pelos clientes no período (rascunhos não contam).",
  propostas:"Simulações com pelo menos uma proposta válida (dentro da validade) de um prestador aprovado.",
  aceites:"Simulações em que o cliente aceitou uma proposta válida.",encomendas:"Encomendas criadas a partir de uma proposta aceite.",
  entregues:"Encomendas do funil já entregues.",registos:"Empresas registadas na plataforma.",pagos:"Prestadores com subscrição paga ou ativa.",
  aprovados:"Prestadores autorizados pela administração.",disponiveis:"Aprovados com subscrição ativa — os únicos que podem enviar propostas.",
  com_proposta:"Prestadores que enviaram propostas válidas no período.",com_encomenda:"Prestadores com encomendas do funil no período.",
  simulado:"Estimativa das simulações enviadas (não é receita).",proposto:"Soma das propostas válidas.",contratado:"Só propostas aceites.",
  faturado:"Só faturas válidas das encomendas do funil.",recebido:"Só pagamentos confirmados (menos reembolsos).",
  comissoes:"Comissão Elolog calculada sobre o valor recebido, com a regra ativa de cada prestador (ou a global)."};
const EXTRA={expiradas:"propostas expiradas",recusadas:"propostas recusadas",sem_proposta_aceite:"encomendas fora do funil (sem proposta aceite)",
  pendentes:"pedidos pendentes",pendentes_48h:"pendentes há mais de 48 h",sem_regra:"encomendas sem regra de comissão"};
let cache=null,cacheDias=0,cacheEm=0,aPedir=false,erro="";
const abertos=new Set();
let diasSel=30;const diasAtivos=()=>diasSel;

function demo(dias){const k=dias/30,r=x=>Math.round(x*k);const sim=r(48),prop=r(31),ac=r(14),enc=r(12),ent=r(7);
  const contr=r(26400),fat=r(21800),rec=r(15950);
  return{demo:true,gerado_em:new Date().toISOString(),periodo_dias:dias,
    gargalo:{funil:"clientes",etapa:"aceites",titulo:"Propostas não aceites",taxa:Math.round(ac*100/prop),mensagem:`Só ${Math.round(ac*100/prop)} % passam esta etapa.`,acao:"Rever preços e prazos das propostas",pagina:"adminOperations"},
    clientes:{etapas:[{id:"simulacoes",nome:"Simulações",n:sim},{id:"propostas",nome:"Com proposta válida",n:prop,extra:{expiradas:r(5),recusadas:r(9)}},
      {id:"aceites",nome:"Aceites",n:ac},{id:"encomendas",nome:"Encomendas",n:enc,extra:{sem_proposta_aceite:1}},{id:"entregues",nome:"Entregues",n:ent}]},
    prestadores:{etapas:[{id:"registos",nome:"Registados",n:14,extra:{pendentes:3,pendentes_48h:1}},{id:"pagos",nome:"Subscrição paga",n:10},{id:"aprovados",nome:"Aprovados",n:9},
      {id:"disponiveis",nome:"Disponíveis",n:8},{id:"com_proposta",nome:"Com propostas",n:6},{id:"com_encomenda",nome:"Com encomendas",n:4}]},
    financeiro:{etapas:[{id:"simulado",nome:"Valor simulado",v:r(61200)},{id:"proposto",nome:"Valor proposto",v:r(40300)},{id:"contratado",nome:"Valor contratado",v:contr},
      {id:"faturado",nome:"Valor faturado",v:fat},{id:"recebido",nome:"Valor recebido",v:rec},{id:"comissoes",nome:"Comissões Elolog",v:Math.round(rec*.08),extra:{sem_regra:0}}],
      planos:{recebido:r(392),por_confirmar:49,ativos:8,mrr:392}},
    resumo:{prestadores_disponiveis:8,simulacoes:sim,conversao:Math.round(enc*100/sim),valor_contratado:contr,receita_comissoes:Math.round(rec*.08),receita_planos:r(392)}}}

async function pedir(dias){const S=window.ELOLogServidor;const sb=await S.cliente();const{data,error}=await sb.rpc("painel_funis",{p_dias:dias});if(error)throw error;return data}

function carregar(){const i=I(),dias=diasAtivos();
  if(i.sessaoDemo?.()){if(!cache||cacheDias!==dias){cache=demo(dias);cacheDias=dias}return}
  if(!i.sessaoServidor?.())return;
  if(aPedir||(cache&&cacheDias===dias&&Date.now()-cacheEm<60e3))return;
  aPedir=true;pedir(dias).then(d=>{cache=d;cacheDias=dias;cacheEm=Date.now();erro=""}).catch(e=>{erro=window.ELOLogServidor?.mensagem?.(e)||String(e?.message||e)})
    .finally(()=>{aPedir=false;aplicar()})}

function etapa(f,e,i,lista,g){const valor=f==="financeiro",x=valor?Number(e.v)||0:Number(e.n)||0;
  const base=valor?Number(lista[0].v)||0:Number(lista[0].n)||0,ant=i?(valor?Number(lista[i-1].v)||0:Number(lista[i-1].n)||0):null;
  const larg=base>0?Math.max(4,Math.round(x*100/base)):0,taxa=ant>0?Math.round(Math.min(x/ant,1)*100):null;
  const ehG=g&&g.funil===f&&g.etapa===e.id,perdidos=ant!=null&&ant>x?ant-x:0,chave=f+":"+e.id;
  const extras=Object.entries(e.extra||{}).filter(([,v])=>Number(v)>0).map(([k,v])=>`<li><b>${num(v)}</b> ${esc(EXTRA[k]||k)}</li>`).join("");
  const comissao=e.id==="comissoes";
  return`<li class="fn-et ${ehG?"fn-g":""} ${comissao?"fn-com":""}"><details data-k="${esc(chave)}" ${abertos.has(chave)?"open":""} ontoggle="elologFunis.tg(this)">
  <summary><span class="fn-nome">${esc(e.nome)}${ehG?' <em class="fn-tag">Gargalo</em>':""}</span><strong>${valor?eur(x):num(x)}</strong>
    <span class="fn-bar" aria-hidden="true"><i style="width:${comissao?0:larg}%"></i></span>
    <small>${taxa==null||comissao?"&nbsp;":taxa+" % da etapa anterior"}</small></summary>
  <div class="fn-mais"><p>${esc(AJUDA[e.id]||"")}</p>${perdidos&&!comissao?`<p class="fn-perda">− ${valor?eur(perdidos):num(perdidos)} não passaram desta etapa.</p>`:""}
    ${extras?`<ul>${extras}</ul>`:""}${e.pagina?`<button type="button" class="fn-btn" onclick="showAdminPage('${esc(e.pagina)}')">Abrir →</button>`:""}</div></details></li>`}

function funil([f,titulo],d){const L=d[f]?.etapas||[],g=d.gargalo;let nota="";
  let planos="";if(f==="financeiro"){const p=d.financeiro?.planos||{};
    planos=`<div class="fn-planos"><h5>Planos dos prestadores <span>(contabilizados à parte das comissões)</span></h5>
    <dl><div><dt>Recebido no período</dt><dd>${eur(p.recebido)}</dd></div><div><dt>Receita mensal</dt><dd>${eur(p.mrr)}</dd></div>
    <div><dt>Subscrições ativas</dt><dd>${num(p.ativos)}</dd></div><div><dt>Por confirmar</dt><dd>${eur(p.por_confirmar)}</dd></div></dl></div>`}
  return`<section class="fn-col" aria-label="${esc(titulo)}"><h4>${esc(titulo)}</h4>${nota}<ol>${L.map((e,i)=>etapa(f,e,i,L,g)).join("")}</ol>${planos}</section>`}

function html(d){const g=d.gargalo||{},r=d.resumo||{},ok=g.titulo==="Sem gargalo";
  const k=(t,v,s)=>`<div class="fn-kpi"><span>${t}</span><strong>${v}</strong>${s?`<small>${s}</small>`:""}</div>`;
  return`<section class="fn-centro pa-cartao" id="fnCentro" aria-label="Funis da plataforma">
  <div class="pa-titulo"><h4>Funis da plataforma</h4><span>${d.demo?'<b class="pa-demo-tag">Dados fictícios de demonstração</b> · ':""}últimos ${num(d.periodo_dias)} dias · só dados registados</span></div>
  ${erro?`<p class="fn-erro" role="alert">Não foi possível atualizar os funis (${esc(erro)}).</p>`:""}
  <div class="fn-topo">
    <div class="fn-gargalo ${ok?"fn-ok":""}" role="status"><span>Gargalo principal</span><strong>${esc(g.titulo||"—")}</strong>
      <p>${esc(g.mensagem||"")}</p>${g.acao?`<button type="button" class="fn-btn" onclick="showAdminPage('${esc(g.pagina||"dashboard")}')">${esc(g.acao)} →</button>`:""}</div>
    <div class="fn-kpis">${k("Prestadores disponíveis",num(r.prestadores_disponiveis))}${k("Simulações",num(r.simulacoes))}
      ${k("Conversão",r.conversao==null?"—":r.conversao+" %","simulação → encomenda")}${k("Valor contratado",eur(r.valor_contratado),"propostas aceites")}
      ${k("Comissões",eur(r.receita_comissoes),"sobre o recebido")}${k("Planos",eur(r.receita_planos),"subscrições pagas")}</div></div>
  <div class="fn-grelha">${FUNIS.map(f=>funil(f,d)).join("")}</div></section>`}

function aplicar(){const sec=document.querySelector("#adminDashboardProviders .pa-centro");if(!sec)return;carregar();
  const atual=sec.querySelector("#fnCentro");if(!cache){atual?.remove();return}
  const novo=html(cache),h=novo.length+"|"+cache.gerado_em+"|"+erro;if(atual){if(atual.dataset.h!==h){atual.outerHTML=novo;sec.querySelector("#fnCentro").dataset.h=h}return}
  const ancora=sec.querySelector(".cm-painel")||sec.querySelector(".pa-cabecalho");if(!ancora)return;ancora.insertAdjacentHTML("afterend",novo);sec.querySelector("#fnCentro").dataset.h=h}

const ESTILO=`.fn-centro{margin:0 0 18px}.fn-topo{display:grid;grid-template-columns:minmax(240px,1fr) 2fr;gap:14px;margin:6px 0 16px}
.fn-gargalo{border:1.5px solid #e0951a;border-radius:14px;padding:14px 16px;background:rgba(224,149,26,.07)}.fn-gargalo.fn-ok{border-color:#1F7A5C;background:rgba(31,122,92,.07)}
.fn-gargalo span{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:#9a6408;font-weight:700}.fn-ok span{color:#1F7A5C}
.fn-gargalo strong{display:block;font-size:20px;color:#13293D;margin:4px 0}.fn-gargalo p{margin:0 0 10px;color:#4a5a6a;font-size:14px}
.fn-kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.fn-kpi{border:1px solid #dbe4ec;border-radius:12px;padding:10px 12px}
.fn-kpi span{display:block;font-size:12px;color:#5b6b7b}.fn-kpi strong{display:block;font-size:19px;color:#13293D}.fn-kpi small{color:#7c8da0;font-size:11px}
.fn-grelha{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}.fn-col{border:1px solid #dbe4ec;border-radius:14px;padding:12px}
.fn-col h4{margin:0 0 8px;color:#13293D;font-size:15px}.fn-col ol{list-style:none;margin:0;padding:0;display:grid;gap:6px}
.fn-et details{border:1px solid #e6edf3;border-radius:10px;padding:8px 10px}.fn-et summary{cursor:pointer;display:grid;grid-template-columns:1fr auto;gap:2px 8px;list-style:none}
.fn-et summary::-webkit-details-marker{display:none}.fn-nome{font-size:13px;color:#33475b}.fn-et strong{color:#13293D}
.fn-bar{grid-column:1/-1;height:6px;border-radius:4px;background:#eef3f7;overflow:hidden}.fn-bar i{display:block;height:100%;background:#1F5F8B;border-radius:4px}
.fn-col:nth-child(2) .fn-bar i{background:#1F7A5C}.fn-col:nth-child(3) .fn-bar i{background:#13293D}.fn-et small{grid-column:1/-1;color:#7c8da0;font-size:11px}
.fn-g details{border-color:#e0951a;background:rgba(224,149,26,.06)}.fn-g .fn-bar i{background:#e0951a!important}
.fn-tag{font-style:normal;font-size:10px;border:1px solid #e0951a;color:#9a6408;border-radius:8px;padding:0 6px;margin-left:4px}
.fn-com details{border-style:dashed}.fn-mais{font-size:13px;color:#4a5a6a;padding-top:6px}.fn-mais p{margin:0 0 6px}.fn-mais ul{margin:0 0 6px;padding-left:18px}
.fn-perda{color:#b0412e}.fn-btn{background:none;border:1px solid #1F5F8B;color:#1F5F8B;border-radius:9px;padding:6px 12px;font:inherit;font-size:13px;cursor:pointer}
.fn-btn:hover{background:rgba(31,95,139,.08)}.fn-nota{font-size:12px;color:#9a6408;border:1px dashed #e0951a;border-radius:8px;padding:6px 8px;margin:0 0 8px}
.fn-planos{margin-top:10px;border:1px solid #cfe3da;border-radius:10px;padding:8px 10px}.fn-planos h5{margin:0 0 6px;font-size:13px;color:#1F7A5C}
.fn-planos h5 span{font-weight:400;color:#7c8da0}.fn-planos dl{margin:0;display:grid;grid-template-columns:1fr 1fr;gap:6px}.fn-planos dt{font-size:11px;color:#7c8da0}.fn-planos dd{margin:0;font-weight:700;color:#13293D}
.fn-erro{color:#b0412e;font-size:13px}
@media(max-width:1000px){.fn-grelha{grid-template-columns:1fr}.fn-topo{grid-template-columns:1fr}}
@media(max-width:520px){.fn-centro .pa-titulo{flex-direction:column;align-items:flex-start;gap:4px}.fn-kpis{grid-template-columns:1fr 1fr}.fn-kpi strong{font-size:17px}}`;

window.elologFunis={tg(el){const k=el.dataset.k;if(el.open)abertos.add(k);else abertos.delete(k)},atualizar(){cacheEm=0;carregar()},dados:()=>cache};
function ligar(){const alvo=document.getElementById("adminDashboardProviders");if(!alvo)return setTimeout(ligar,500);
  const per=window.painelAdminPeriodo;if(per&&!per.__fn){const w=function(n){if([7,14,30,60,90,180,365].includes(+n))diasSel=+n;return per.apply(this,arguments)};w.__fn=1;window.painelAdminPeriodo=w}
  if(!document.getElementById("fnEstilo")){const s=document.createElement("style");s.id="fnEstilo";s.textContent=ESTILO;document.head.appendChild(s)}
  new MutationObserver(()=>aplicar()).observe(alvo,{childList:true});aplicar()}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
})();
