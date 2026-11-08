/* Elolog — Regras de cobrança, centro de controlo comercial e tarifário (administração, v115).
   Separadores: Visão geral · Tarifários gerais ELOLog · Tarifários dos prestadores · Tarifários de veículos · Comissões · Simulador de preços · Histórico e auditoria.
   Tudo o que aqui se decide é o que o motor de preços usa (fonte única). Peças em tarifarios-vistas.js, formulários em tarifarios-forms.js. */
(function(){"use strict";
const T=()=>window.elologTarifarios,F=()=>window.elologTarifariosForms,V=()=>window.elologTarifariosVistas;
const ABAS=[["visao","Visão geral","chart"],["gerais","Tarifários gerais ELOLog","tag"],["prestadores","Tarifários dos prestadores","building"],["veiculos","Tarifários de veículos","truck"],
  ["comissoes","Comissões","wallet"],["simulador","Simulador de preços","calc"],["historico","Histórico e auditoria","file"]];
let aba="visao",cache={},filtro={empresa:"",estado:""},busca="";
const b=(txt,attrs,cl="btn-secondary")=>`<button type="button" class="${cl}" ${attrs}>${txt}</button>`;

function garantirPagina(){if(document.getElementById("adminTariffs"))return;const ref=document.getElementById("adminCommissions");if(!ref)return;
  const s=document.createElement("section");s.id="adminTariffs";s.className="page admin-platform-page";s.innerHTML='<div class="card tf-pagina"><div id="adminTariffsContent"></div></div>';ref.after(s);
  const btn=document.querySelector('#sidebar [onclick*="showAdminPage(\'adminCommissions\'"]');if(btn&&!document.querySelector('#sidebar [onclick*="adminTariffs"]')){
    const x=btn.cloneNode(true);x.setAttribute("onclick","showAdminPage('adminTariffs',this)");x.textContent="Regras de cobrança";btn.before(x)}
  const n=document.createElement("div");n.className="tf-topo tf-aviso-comissoes";n.innerHTML='<p>As regras de comissão que o motor de preços usa (por prestador, modalidade, rota e período) gerem-se agora em «Regras de cobrança».</p><button type="button" class="btn-secondary" onclick="showAdminPage(\'adminTariffs\');window.elologTarifariosAdmin.abrirAba(\'comissoes\')">Abrir comissões</button>';
  ref.querySelector(".card")?ref.querySelector(".card").prepend(n):ref.prepend(n)}

const recente=x=>x.estado==="pendente"||Date.now()-Date.parse(x.created_at||x.updated_at||0)<14*864e5;
const pend=()=>({t:(cache.tarifas||[]).filter(t=>["pendente","aprovada"].includes(t.estado)&&recente(t)),s:(cache.suplementos||[]).filter(x=>["pendente","aprovado"].includes(x.estado)&&x.empresa_id&&recente(x)),v:(cache.veiculos||[]).filter(x=>["pendente","aprovado"].includes(x.estado)&&x.empresa_id&&recente(x))});
function referencia(t){const g=(cache.gerais||[]).find(g=>g.uso==="referencia"&&g.estado==="ativa"&&g.metodo===t.metodo&&(!g.origem||t.origem&&g.origem.toLowerCase()===t.origem.toLowerCase())&&(!g.destino||t.destino&&g.destino.toLowerCase()===t.destino.toLowerCase()));
  if(!g||!(Number(g.valor)>0))return"";const dif=Math.round((Number(t.valor)-Number(g.valor))*100/Number(g.valor));
  return`<p class="tf-ref ${Math.abs(dif)>20?"longe":""}">Referência Elolog (${V().esc(g.codigo||g.nome)}): ${T().eur(g.valor,g.moeda)} ${V().esc(T().METODO[g.metodo])}. ${dif===0?"Igual à referência.":`${Math.abs(dif)} % ${dif>0?"acima":"abaixo"} da referência.`}</p>`}
function cartao(sub,nome,estado,corpo,botoes){return`<article class="tf-cartao"><header><div><small>${V().esc(sub)}</small><h4>${V().esc(nome)}</h4></div>${V().pill(estado)}</header>${corpo}<footer>${botoes}</footer></article>`}
function filaAprovacao(){const{t,s,v}=pend(),e=V().esc;if(!t.length&&!s.length&&!v.length)return V().vazio("Nada publicado nos últimos 14 dias","As tarifas, veículos e suplementos que os prestadores publicam entram logo em vigor e aparecem aqui, com a diferença para a versão anterior e para a referência Elolog. Pode suspender o que não estiver correto.","check");
  return t.map(x=>{const ant=(cache.tarifas||[]).find(a=>a.id===x.tarifa_pai_id);return cartao(`${x.empresas?.nome||"Prestador"}, versão ${x.versao}`,x.nome,x.estado,
      `<p>${e(T().rota(x))}${x.tipo_carga?`, ${e(x.tipo_carga)}`:""}. ${e(V().limites(x))}.${x.validade_fim?` Válida até ${new Date(x.validade_fim).toLocaleDateString("pt-PT")}.`:""}</p>${x.regras?.palavras?.length?`<p>Palavras da descrição: ${e(x.regras.palavras.join(", "))}${x.regras.so_descricao?" (só pela descrição)":""}.</p>`:""}
       <p class="tf-mudanca">${ant?`Versão ${ant.versao}: ${V().linhaPreco(ant)}. <b>Passa a ${V().linhaPreco(x)}.</b>`:`Tarifa nova: ${V().linhaPreco(x)}.`}</p>${referencia(x)}`,
      (x.estado==="pendente"?b("Aprovar tarifa",`data-tf="aprovar" data-id="${x.id}"`,"btn-primary")+b("Rejeitar",`data-tf="rejeitar" data-id="${x.id}"`,"btn-secondary tf-perigo"):b("Suspender",`data-tf="suspender" data-id="${x.id}"`,"btn-secondary tf-perigo")))}).join("")
   +v.map(x=>cartao(`${x.empresas?.nome||"Prestador"}, tarifa de veículo`,x.nome,x.estado,`<p>${e(T().VEICULO[x.veiculo]||x.veiculo)}: ${V().custoVeiculo(x)}. ${e(V().capacidade(x))}.</p>`,
      (x.estado==="pendente"?b("Aprovar veículo",`data-vei="aprovar" data-id="${x.id}"`,"btn-primary"):b("Suspender",`data-vei="suspender" data-id="${x.id}"`,"btn-secondary tf-perigo")))).join("")
   +s.map(x=>cartao(`${x.empresas?.nome||"Prestador"}, suplemento`,x.nome,x.estado,`<p>${x.tipo==="percentual"?`${x.valor} % sobre o preço`:x.tipo==="por_km"?`${T().eur(x.valor)} por km`:T().eur(x.valor)} ${x.automatico?"(aplica-se sempre)":"(só quando pedido)"}.</p>`,
      (x.estado==="pendente"?b("Aprovar suplemento",`data-sup="aprovar" data-id="${x.id}"`,"btn-primary"):b("Suspender",`data-sup="suspender" data-id="${x.id}"`,"btn-secondary tf-perigo")))).join("")}
const decidirBtn=(k,x,ok)=>x.estado===ok?b("Suspender",`data-${k}="suspender" data-id="${x.id}"`):/^suspens/.test(x.estado)?b("Reativar",`data-${k}="reativar" data-id="${x.id}"`):/^pendente/.test(x.estado)?b("Rever",'data-ir="visao"'):"";

const R={
  visao(){const{t,s,v}=pend(),hoje=new Date().toISOString().slice(0,10),em30=new Date(Date.now()+30*864e5).toISOString().slice(0,10);
    const exp=[...(cache.tarifas||[]),...(cache.gerais||[])].filter(x=>["aprovada","ativa"].includes(x.estado)&&x.validade_fim&&x.validade_fim>=hoje&&x.validade_fim<=em30).length;
    return V().kpis([["Publicadas nos últimos 14 dias",t.length+s.length+v.length],["Tarifas de prestadores em vigor",(cache.tarifas||[]).filter(x=>x.estado==="aprovada").length],
      ["Tarifários gerais em vigor",(cache.gerais||[]).filter(x=>x.estado==="ativa").length],["Veículos aprovados",(cache.veiculos||[]).filter(x=>x.estado==="aprovado").length],
      ["Comissões ativas",(cache.comissoes||[]).filter(x=>x.ativa).length],["Expiram em 30 dias",exp,exp?"aviso":""]])+`<h4 class="tf-sub">Publicadas pelos prestadores (últimos 14 dias)</h4>${filaAprovacao()}`},
  gerais(){const l=cache.gerais||[],sp=cache.suplementos||[];return`<div class="tf-topo"><p>Preços de referência (para comparar o que os prestadores pedem) e tarifários comerciais da Elolog, que valem para os prestadores associados quando não têm tarifa própria. Um nome igual à descrição da carga faz o motor escolher essa tarifa.</p>${b("Novo tarifário geral",'data-novo="geral"',"btn-primary")}</div>
    ${l.length?V().tabela(l.map(g=>V().linhaTarifa({...g,empresas:{nome:`${g.codigo||""}, ${g.uso==="comercial"?`comercial, ${g.prestadores?.length||0} prestador(es)`:"referência"}`}},b("Alterar",`data-editar="geral" data-id="${g.id}"`))).join("")):V().vazio("Ainda não há tarifários gerais","Crie preços de referência para comparar, ou um tarifário comercial para os prestadores que associar.")}
    <div class="tf-topo"><h4 class="tf-sub">Suplementos</h4>${b("Novo suplemento geral",'data-novo="suplemento"')}</div>
    ${sp.length?V().tabela(sp.map(x=>`<div class="tf-linha"><div><strong>${V().esc(x.nome)}</strong><small>${V().esc(x.empresas?.nome||"Elolog, geral")}</small></div><div>${x.tipo==="percentual"?`${x.valor} %`:x.tipo==="por_km"?`${T().eur(x.valor)} por km`:T().eur(x.valor)}<small>${x.automatico?"Aplica-se sempre":"Só quando pedido"}</small></div><div>${V().pill(x.estado)}</div><div class="tf-acoes">${decidirBtn("sup",x,"aprovado")}</div></div>`).join("")):V().vazio("Ainda não há suplementos","Sem suplemento nem veículo configurado, a recolha na morada custa 1 € por km.")}`},
  prestadores(){const emp=[...new Map((cache.tarifas||[]).map(t=>[t.empresa_id,t.empresas?.nome||"Prestador"])).entries()],l=(cache.tarifas||[]).filter(t=>(!filtro.empresa||t.empresa_id===filtro.empresa)&&(!filtro.estado||t.estado===filtro.estado));
    const sel=`<div class="tf-filtros"><select data-filtro="empresa" aria-label="Prestador"><option value="">Todos os prestadores</option>${emp.map(([id,n])=>`<option value="${id}" ${filtro.empresa===id?"selected":""}>${V().esc(n)}</option>`).join("")}</select>
      <select data-filtro="estado" aria-label="Estado"><option value="">Todos os estados</option>${["rascunho","pendente","alteracoes_pedidas","aprovada","rejeitada","suspensa","inativa","substituida"].map(k=>`<option value="${k}" ${filtro.estado===k?"selected":""}>${T().ESTADO[k][0]}</option>`).join("")}</select></div>`;
    return sel+(l.length?V().tabela(l.map(t=>V().linhaTarifa(t,decidirBtn("tf",t,"aprovada"))).join("")):V().vazio("Nenhuma tarifa com estes filtros","Os prestadores criam as tarifas em Financeiro, «Regras de cobrança»; depois de aprovadas, entram nas simulações."))},
  veiculos(){const l=cache.veiculos||[];return`<div class="tf-topo"><p>Custo da recolha ou entrega por tipo de veículo: saída + km, com mínimo. Com recolha, o motor escolhe o veículo aprovado mais barato que leva o peso e o volume (primeiro os do prestador, depois os gerais).</p>${b("Nova tarifa de veículo",'data-novo="veiculo"',"btn-primary")}</div>
    ${l.length?V().tabela(l.map(x=>V().linhaVeiculo(x,(x.empresa_id?"":b("Alterar",`data-editar="veiculo" data-id="${x.id}"`))+decidirBtn("vei",x,"aprovado")+b("Eliminar",`data-eliminar-vei="${x.id}"`,"btn-secondary tf-perigo"))).join("")):V().vazio("Ainda não há tarifas de veículos","Crie uma tarifa geral (ex.: carrinha até 1 200 kg) ou espere que os prestadores submetam as suas.","truck")}`},
  comissoes(){const l=cache.comissoes||[];return`<div class="tf-topo"><p>A regra mais específica ganha: prestador, modalidade e rota. Em empate, a promocional e depois a de maior prioridade. «Incluída»: retida ao preço do prestador. «À parte»: o cliente vê uma taxa de serviço.</p>${b("Nova regra de comissão",'data-novo="comissao"',"btn-primary")}</div>
    ${l.length?V().tabela(l.map(c=>V().linhaComissao(c,b("Alterar",`data-editar="comissao" data-id="${c.id}"`))).join("")):V().vazio("Ainda não há regras de comissão","Sem regra, a Elolog não aplica comissão aos preços.","wallet")}`},
  simulador(){return F()?.testarHtml?.(cache.empresas||[])||""},
  historico(){return V().historico(cache.historico||[])}};

async function carregar(){const A=T().API;try{const[tarifas,gerais,comissoes,suplementos,historico,empresas,veiculos]=await Promise.all([A.tarifas(),A.gerais(),A.comissoes(),A.suplementos(),A.historico(),A.empresas(),A.veiculos()]);
  cache={tarifas,gerais,comissoes,suplementos,historico,empresas,veiculos}}catch(e){cache.erro=e.message}desenhar()}
function desenhar(){const box=document.getElementById("adminTariffsContent");if(!box)return;const{t,s,v}=pend(),n=[...t,...s,...v].filter(x=>x.estado==="pendente").length;
  box.innerHTML=`<div class="admin-section-heading tf-cabeca"><div><h3>Regras de cobrança</h3><p>Centro de controlo comercial e tarifário. Os prestadores publicam as suas tarifas sem esperar pela Elolog; aqui define as regras gerais e as comissões, e pode suspender o que não estiver correto.${T().API.online()?"":" Na demonstração, os dados são exemplos só de leitura."}</p></div></div>
    ${V().caixaBusca(busca)}
    <div class="fs-filtros tf-abas" role="tablist">${ABAS.map(([k,nome,ic])=>`<button type="button" role="tab" aria-selected="${aba===k}" class="fs-filtro ${aba===k?"on":""} ${k==="visao"&&n?"aviso":""}" data-aba="${k}"><i class="ic ic-${ic}" aria-hidden="true"></i><span>${nome}</span>${k==="visao"&&n?`<b>${n}</b>`:""}</button>`).join("")}</div>
    ${cache.erro?`<div class="provider-order-empty vz vz2 vz-orfa" role="status"><strong>Não conseguimos ler as regras de cobrança</strong><p>${V().esc(cache.erro)}</p><button type="button" class="btn-secondary vz-acao" data-recarregar="1">Tentar outra vez</button></div>`:`<div class="tf-corpo">${R[aba]()}</div>`}`;
  {const t=box.querySelector('.tf-abas [aria-selected="true"]');if(t)t.parentElement.scrollLeft=t.offsetLeft-t.parentElement.offsetLeft-16}
  if(busca)document.getElementById("tfBuscaRes").innerHTML=V().busca(busca,cache)}

document.addEventListener("click",async e=>{const box=document.getElementById("adminTariffsContent");if(!box||!box.contains(e.target))return;const x=e.target.closest("button");if(!x)return;const d=x.dataset;
  if(d.aba){aba=d.aba;return desenhar()}if(d.ir){aba=d.ir;return desenhar()}if(d.recarregar)return carregar();
  if(d.tf)return F().decidir("tarifa",d.id,d.tf,carregar);if(d.sup)return F().decidir("suplemento",d.id,d.sup,carregar);if(d.vei)return F().decidir("veiculo",d.id,d.vei,carregar);
  if(d.eliminarVei)return F().eliminarVeiculo(d.eliminarVei,(cache.veiculos||[]).find(v=>v.id===d.eliminarVei),carregar);
  if(d.novo)return F().abrir(d.novo,null,cache,carregar);if(d.editar)return F().abrir(d.editar,d.id,cache,carregar);if(d.testar)return F().testar(carregar)});
document.addEventListener("change",e=>{const s=e.target.closest?.("#adminTariffsContent [data-filtro]");if(!s)return;filtro[s.dataset.filtro]=s.value;desenhar()});
let espera;document.addEventListener("input",e=>{if(e.target.id!=="tfBusca"||!e.target.closest("#adminTariffsContent"))return;busca=e.target.value;clearTimeout(espera);
  espera=setTimeout(()=>{const r=document.getElementById("tfBuscaRes");if(r)r.innerHTML=V().busca(busca,cache)},200)});
document.addEventListener("DOMContentLoaded",()=>{garantirPagina();const ir=window.showAdminPage;if(typeof ir==="function")window.showAdminPage=function(page){const r=ir.apply(this,arguments);
  if(page==="adminTariffs"){const t=document.getElementById("pageTitle");if(t)t.textContent="Regras de cobrança";carregar()}return r}});
window.elologTarifariosAdmin={carregar,desenhar,abrirAba:k=>{aba=k;desenhar()}};
})();
