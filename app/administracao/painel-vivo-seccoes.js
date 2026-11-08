/* Elolog — Centro de comando (v103): secções que vinham de «Indicadores e simulações», agora no mesmo ecrã.
   Usam os mesmos dados do painel da administração (painel.js → painel_admin) e as mesmas ações (abrir Operações, Inscrições,
   Faturação, Apoio…). Só apresentação: nada aqui altera dados. */
(function(){"use strict";
const IN=()=>window.__ELOLOG_INTERNO||{},I=()=>IN()["painel@administracao"]||{};
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const num=v=>(Number(v)||0).toLocaleString("pt-PT"),eur=v=>(Number(v)||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR",minimumFractionDigits:0,maximumFractionDigits:Math.abs(Number(v)||0)>=1e3?0:2});
const ETAPAS=[["aprovacao","Aprovação","#9FB3C2"],["agendamento","Agendamento","#7FA9C6"],["recolha","Recolha","#5F95BC"],["armazenamento","Armazém","#3F7FAE"],
  ["expedicao","Expedição","#1F5F8B"],["em_transito","Em trânsito","#13293D"],["destino","No destino","#1F7A5C"]];

/** Variação face ao período anterior, numa etiqueta de cor (verde melhora, vermelho piora). */
function tend(atual,ant,pior){if(ant==null||(!Number(atual)&&!Number(ant)))return"";const v=ant?(atual-ant)*100/Math.abs(ant):atual?100:0;if(Math.abs(v)<.5)return'<b class="pv-delta pv-cinza">sem alteração</b>';
  const bom=v>0!==!!pior;return`<b class="pv-delta pv-${bom?"ok":"verm"}">${v>0?"↑":"↓"} ${Math.abs(Math.round(v))} %</b>`}

/* Corrente operacional: a cadeia logística numa só barra contínua, proporcional às encomendas em cada etapa */
function corrente(P){const pl=P?.pipeline||{},tot=ETAPAS.reduce((t,[k])=>t+(pl[k]||0),0);
  const banda=tot?ETAPAS.filter(([k])=>pl[k]).map(([k,n,c])=>`<i style="flex:${pl[k]};background:${c}" title="${esc(n)}: ${num(pl[k])}"></i>`).join(""):'<i style="flex:1;background:#DCE4EA"></i>';
  const col=ETAPAS.map(([k,n,c],i)=>`<button type="button" class="pv-et ${pl[k]?"":"zero"}" data-pv-ir="adminOperations" title="Abrir as operações">
    <span class="pv-et-n">${num(pl[k])}</span><span class="pv-et-l"><i style="background:${c}"></i>${esc(n)}</span><small>${tot?Math.round((pl[k]||0)*100/tot):0} %</small></button>`).join("");
  return`<section class="pv-faixa pv-corrente" aria-labelledby="pvCor"><div class="pv-faixa-cab"><div><h3 id="pvCor">Onde estão as encomendas</h3><p>Operações em curso por etapa da cadeia logística</p></div>
    <div class="pv-faixa-tot"><strong>${num(tot)}</strong><span>em curso</span><span class="pv-faixa-sep"></span><strong>${num(pl.entregue)}</strong><span>levantadas</span></div></div>
    <div class="pv-banda" aria-hidden="true">${banda}</div>${tot?`<div class="pv-etapas">${col}</div>`:'<p class="pv-vazio">Ainda não há encomendas em curso. As etapas enchem-se quando a primeira encomenda for aprovada.</p>'}</section>`}

/* Atenção necessária: as regras do painel da administração (pagamentos por confirmar, registos à espera, encomendas paradas, apoio)
   e, à frente, as encomendas diretas que esperam validação ou decisão da administração */
function atencao(P,ed){if(!P)return"";const lis=alertasVisiveis(P).map(l=>l.replace(/\s*\([^()]*€\)/g,""));
  if(ed>0)lis.unshift(`<li class="alta" tabindex="0" role="link" data-pv-ir="adminDirectOrders"><span class="ct-ic amb"><i class="ic ic-file" aria-hidden="true"></i></span><div><strong>${ed===1?"Uma encomenda direta espera a sua decisão":num(ed)+" encomendas diretas esperam a sua decisão"}</strong>
    <small>Valide ou recuse para o cliente saber o que acontece a seguir.</small></div><span class="ct-ir2">Decidir sobre as encomendas</span></li>`);
    const corpo=lis.length?`<ul class="ct-alertas">${lis.join("")}</ul>`:'<p class="pa-vazio">Tudo em ordem. Não há nada à espera de si.</p>';
  return`<section class="pv-faixa pv-atencao" aria-labelledby="pvAt"><div class="pv-faixa-cab"><div><h3 id="pvAt">Atenção necessária</h3><p>O que está à espera de si, do mais urgente para o menos urgente.</p></div></div>${corpo}</section>`}

/* Negócio no período (7, 30 ou 90 dias) — painel escuro com os números do período, evolução semanal e horas dos pedidos */
function serie(P){const s=P.serie_semanal||[],tot=s.reduce((t,x)=>t+(x.encomendas||0),0);if(!s.length||!tot)return'<div class="pv-vazio-g"><p><strong>Ainda não há encomendas nas últimas 8 semanas.</strong><br>O gráfico enche-se quando os clientes criarem as primeiras encomendas.</p></div>';const max=Math.max(1,...s.map(x=>x.encomendas));
  return`<ol class="pv-serie" role="img" aria-label="Encomendas por semana: ${s.map(x=>x.encomendas).join(", ")}">${s.map((x,i)=>`<li class="${i===s.length-1?"atual":""}"><b>${num(x.encomendas)}</b><i style="height:${Math.max(4,Math.round(x.encomendas*100/max))}%"></i><small>${esc(String(x.semana).slice(8,10)+"/"+String(x.semana).slice(5,7))}</small></li>`).join("")}</ol>
    <p class="pv-nota">${num(tot)} encomendas em 8 semanas; a última ainda está a decorrer.</p>`}
function negocio(P,A,dias){if(!P)return"";const e=P.encomendas||{},p=P.prestadores||{},c=P.clientes||{};
  const per=[7,30,90].map(n=>`<button type="button" class="pv-per ${n===dias?"on":""}" aria-pressed="${n===dias}" data-pv-periodo="${n}">${n} dias</button>`).join("");
  const f=P.funil||{};
  const N=[["Simulações feitas",num(f.simulacoes),tend(f.simulacoes,A?.f?.simulacoes),"adminClients"],["Encomendas criadas",num(f.encomendas),tend(f.encomendas,A?.f?.encomendas),"adminOperations"],
    ["Novos prestadores",num(p.novos_periodo),tend(p.novos_periodo,A?.np),"adminProviderRequests"],["Novos clientes",num(c.novos_periodo),"","adminClients"],["Encomendas canceladas",num(e.canceladas_periodo),tend(e.canceladas_periodo,A?.e?.canceladas_periodo,true),"adminOperations"]];
  return`<section class="pv-escuro pv-negocio" aria-labelledby="pvNeg"><div class="pv-esc-cab"><h3 id="pvNeg">Negócio nos últimos ${dias} dias</h3><div class="pv-pers" role="group" aria-label="Período">${per}</div></div>
    <div class="pv-neg-n">${N.map(x=>`<button type="button" class="pv-neg" data-pv-ir="${x[3]}"><span>${x[0]}</span><strong>${x[1]}</strong>${x[2]}</button>`).join("")}</div>
    <div class="pv-neg-g"><div><h4>Encomendas por semana</h4>${serie(P)}</div></div></section>`}

/* Frases do painel principal: o estado da plataforma dito por extenso, uma de cada vez (dados reais, sem valores de receita) */
function frases(k,P,d,ed){const pl=(n,um,varios)=>`${num(n)} ${Number(n)===1?um:varios}`,F=[],at=contarAtencao(P,ed),nv=(d.viagens||[]).length,pr=P?.prestadores||{};
  /* cada frase diz algo que não está escrito noutro bloco do ecrã (a lista de cada assunto fica no seu bloco) */
  F.push(at?{t:`${pl(at,"assunto espera","assuntos esperam")} por uma decisão sua.`,r:"pvAt"}:{t:"Não há nada à espera de uma decisão sua.",r:"pvAt"});
  F.push(nv?{t:`${pl(nv,"navio leva","navios levam")} carga Elolog neste momento.`,r:"pvMapa"}:{t:"Nenhum navio leva carga Elolog neste momento.",r:"pvMapa"});
  if(k.prazo_pct!=null)F.push({t:`${String(k.prazo_pct).replace(".",",")} % das encomendas foram levantadas dentro do prazo nos últimos 30 dias.`,i:"adminOperations"});
  if(pr.ativos!=null)F.push({t:pr.ativos?`${pl(pr.ativos,"prestador trabalha","prestadores trabalham")} hoje com a Elolog.`:"Ainda não há prestadores ativos na Elolog.",i:"adminActiveProviders"});
  return F}
/** Conta exatamente o que o bloco «Atenção necessária» mostra (mesmo filtro). */
const alertasVisiveis=P=>((I().alertas?.(P)||"").match(/<li[\s\S]*?<\/li>/g)||[]).filter(l=>!/Encomendas paradas há mais/.test(l));
function contarAtencao(P,ed){if(!P)return ed||0;return alertasVisiveis(P).length+(ed>0?1:0)}

window.elologPVS={corrente,atencao,negocio,frases,tend};
})();
