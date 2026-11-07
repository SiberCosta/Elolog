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
function tend(atual,ant,pior){if(ant==null)return"";const v=ant?(atual-ant)*100/Math.abs(ant):atual?100:0;if(Math.abs(v)<.5)return'<b class="pv-delta pv-cinza">sem alteração</b>';
  const bom=v>0!==!!pior;return`<b class="pv-delta pv-${bom?"ok":"verm"}">${v>0?"↑":"↓"} ${Math.abs(Math.round(v))} %</b>`}

/* Corrente operacional: a cadeia logística numa só barra contínua, proporcional às encomendas em cada etapa */
function corrente(P){const pl=P?.pipeline||{},tot=ETAPAS.reduce((t,[k])=>t+(pl[k]||0),0);
  const banda=tot?ETAPAS.filter(([k])=>pl[k]).map(([k,n,c])=>`<i style="flex:${pl[k]};background:${c}" title="${esc(n)}: ${num(pl[k])}"></i>`).join(""):'<i style="flex:1;background:#DCE4EA"></i>';
  const col=ETAPAS.map(([k,n,c],i)=>`<button type="button" class="pv-et ${pl[k]?"":"zero"}" data-pv-ir="adminOperations" title="Abrir as operações">
    <span class="pv-et-n">${num(pl[k])}</span><span class="pv-et-l"><i style="background:${c}"></i>${esc(n)}</span><small>${tot?Math.round((pl[k]||0)*100/tot):0} %</small></button>`).join("");
  return`<section class="pv-faixa pv-corrente" aria-labelledby="pvCor"><div class="pv-faixa-cab"><div><h3 id="pvCor">Onde estão as encomendas</h3><p>Operações em curso por etapa da cadeia logística</p></div>
    <div class="pv-faixa-tot"><strong>${num(tot)}</strong><span>em curso</span><span class="pv-faixa-sep"></span><strong>${num(pl.entregue)}</strong><span>levantadas</span></div></div>
    <div class="pv-banda" aria-hidden="true">${banda}</div><div class="pv-etapas">${col}</div></section>`}

/* Atenção necessária: as regras do painel da administração (pagamentos por confirmar, registos à espera, encomendas paradas, apoio)
   e, à frente, as encomendas diretas que esperam validação ou decisão da administração */
function atencao(P,ed){if(!P)return"";const lis=(I().alertas?.(P)||"").match(/<li[\s\S]*?<\/li>/g)||[];
  if(ed>0)lis.unshift(`<li class="alta" tabindex="0" role="link" data-pv-ir="adminDirectOrders"><span class="ct-ic amb"><i class="ic ic-file" aria-hidden="true"></i></span><div><strong>Encomendas diretas por tratar</strong>
    <small>${num(ed)} ${ed===1?"encomenda espera":"encomendas esperam"} validação ou decisão da administração</small></div><span class="ct-ir2">Ver encomendas diretas</span></li>`);
  const urg=lis.filter(l=>/class="alta"/.test(l)).length;
  const corpo=lis.length?`<ul class="ct-alertas">${lis.join("")}</ul>`:'<p class="pa-vazio">Tudo em ordem: não há assuntos por tratar.</p>';
  return`<section class="pv-faixa pv-atencao" aria-labelledby="pvAt"><div class="pv-faixa-cab"><div><h3 id="pvAt">Atenção necessária</h3><p>${lis.length?`${lis.length} ${lis.length===1?"assunto precisa":"assuntos precisam"} de uma decisão da administração${urg?`, ${urg} ${urg===1?"urgente":"urgentes"}`:""}`:"O que precisa de uma decisão da administração"}</p></div></div>${corpo}</section>`}

/* Negócio no período (7, 30 ou 90 dias) — painel escuro com os números do período, evolução semanal e horas dos pedidos */
function serie(P){const s=P.serie_semanal||[];if(!s.length)return'<p class="pv-vazio">Sem dados semanais.</p>';const max=Math.max(1,...s.map(x=>x.encomendas)),tot=s.reduce((t,x)=>t+x.encomendas,0);
  return`<ol class="pv-serie" role="img" aria-label="Encomendas por semana: ${s.map(x=>x.encomendas).join(", ")}">${s.map((x,i)=>`<li class="${i===s.length-1?"atual":""}"><b>${num(x.encomendas)}</b><i style="height:${Math.max(4,Math.round(x.encomendas*100/max))}%"></i><small>${esc(String(x.semana).slice(8,10)+"/"+String(x.semana).slice(5,7))}</small></li>`).join("")}</ol>
    <p class="pv-nota">${num(tot)} encomendas em 8 semanas; a última ainda está a decorrer.</p>`}
function negocio(P,A,dias){if(!P)return"";const e=P.encomendas||{},p=P.prestadores||{},c=P.clientes||{};
  const per=[7,30,90].map(n=>`<button type="button" class="pv-per ${n===dias?"on":""}" aria-pressed="${n===dias}" data-pv-periodo="${n}">${n} dias</button>`).join("");
  const N=[["Serviços contratados",eur(e.valor_periodo),tend(e.valor_periodo,A?.e?.valor_periodo),"adminOperations"],["Recibos de subscrição",eur(P.receita?.periodo),tend(P.receita?.periodo,A?.r),"adminBilling"],
    ["Novos prestadores",num(p.novos_periodo),tend(p.novos_periodo,A?.np),"adminProviderRequests"],["Novos clientes",num(c.novos_periodo),"","adminClients"],["Encomendas canceladas",num(e.canceladas_periodo),tend(e.canceladas_periodo,A?.e?.canceladas_periodo,true),"adminOperations"]];
  return`<section class="pv-escuro pv-negocio" aria-labelledby="pvNeg"><div class="pv-esc-cab"><h3 id="pvNeg">Negócio nos últimos ${dias} dias</h3><div class="pv-pers" role="group" aria-label="Período">${per}</div></div>
    <div class="pv-neg-n">${N.map(x=>`<button type="button" class="pv-neg" data-pv-ir="${x[3]}"><span>${x[0]}</span><strong>${x[1]}</strong>${x[2]}</button>`).join("")}</div>
    <div class="pv-neg-g"><div><h4>Encomendas por semana</h4>${serie(P)}</div></div></section>`}

/* Números secundários do painel escuro (ao lado da receita de hoje) */
function numeros(k,P){const s=P?.subscricoes||{},d=(a,b)=>b?Math.round((a-b)*1000/b)/10:null,nv=d(k.novas_30d,k.novas_30d_anteriores),pp=k.prazo_pct!=null&&k.prazo_pct_anterior!=null?Math.round((k.prazo_pct-k.prazo_pct_anterior)*10)/10:null;
  const et=(v,suf,inv)=>v==null?"":`<b class="pv-delta pv-${(inv?v<=0:v>=0)?"ok":"verm"}">${v>=0?"↑":"↓"} ${String(Math.abs(v)).replace(".",",")}${suf}</b>`;
  const L=[["Encomendas em curso",num(k.em_curso),`${num(k.novas_30d)} novas em 30 dias`,et(nv," %"),"adminOperations"],
    ["Levantadas no prazo",k.prazo_pct==null?"—":String(k.prazo_pct).replace(".",",")+" %","nos últimos 30 dias",et(pp," pp"),"adminOperations"],
    ["Dinheiro em risco",eur(k.risco_valor),`${num(k.risco_pagamentos)} pagamento(s) pendente(s)`,k.atrasadas?`<b class="pv-delta pv-amb">${num(k.atrasadas)} atrasada(s)</b>`:"","adminBilling"],
    ["Subscrições por mês",eur(s.mrr),`${num(s.ativas)} prestadores com plano ativo`,s.pagamentos_por_confirmar?`<b class="pv-delta pv-amb">${num(s.pagamentos_por_confirmar)} por confirmar</b>`:"","adminBilling"]];
  return L.map(x=>`<button type="button" class="pv-sec" data-pv-ir="${x[4]}"><span>${x[0]}</span><strong>${x[1]}</strong><small>${esc(x[2])}</small>${x[3]}</button>`).join("")}

window.elologPVS={corrente,atencao,negocio,numeros,tend};
})();
