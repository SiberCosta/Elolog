/* Elolog — Centro de Gestão de Tarifários (v114): página da administração «Tarifários e comissões».
   Separadores: Por aprovar · Tarifas dos prestadores · Tarifários gerais · Comissões · Suplementos · Histórico · Testar um preço.
   Tudo o que aqui se decide é o que o motor de preços usa nas simulações (fonte única). Formulários em tarifarios-forms.js. */
(function(){"use strict";
const T=()=>window.elologTarifarios,F=()=>window.elologTarifariosForms,esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const ABAS=[["aprovar","Por aprovar","clock"],["prestadores","Tarifas dos prestadores","building"],["gerais","Tarifários gerais","tag"],["comissoes","Comissões","wallet"],["suplementos","Suplementos","clipboard"],["historico","Histórico","file"],["testar","Testar um preço","calc"]];
let aba="aprovar",cache={},filtro={empresa:"",estado:""};

function garantirPagina(){if(document.getElementById("adminTariffs"))return;const ref=document.getElementById("adminCommissions");if(!ref)return;
  const s=document.createElement("section");s.id="adminTariffs";s.className="page admin-platform-page";s.innerHTML='<div class="card tf-pagina"><div id="adminTariffsContent"></div></div>';ref.after(s);
  const btn=document.querySelector('#sidebar [onclick*="showAdminPage(\'adminCommissions\'"]');if(btn&&!document.querySelector('#sidebar [onclick*="adminTariffs"]')){
    const b=btn.cloneNode(true);b.setAttribute("onclick","showAdminPage('adminTariffs',this)");b.textContent="Tarifários e comissões";btn.before(b)}
  const n=document.createElement("div");n.className="tf-topo tf-aviso-comissoes";n.innerHTML='<p>As regras de comissão que o motor de preços usa (por prestador, modalidade, rota e período) gerem-se agora em «Tarifários e comissões».</p><button type="button" class="btn-secondary" onclick="showAdminPage(\'adminTariffs\');window.elologTarifariosAdmin.abrirAba(\'comissoes\')">Abrir comissões</button>';
  ref.querySelector(".card")?ref.querySelector(".card").prepend(n):ref.prepend(n)}

const pill=e=>{const[x,c]=T().ESTADO[e]||[e,"neutro"];return`<span class="tf-estado ${c}">${esc(x)}</span>`};
const vazio=(t,d)=>`<div class="provider-order-empty vz vz2" data-vz="1" role="status"><span class="vz-ic" aria-hidden="true"><i class="ic ic-tag"></i></span><strong>${esc(t)}</strong><p>${esc(d)}</p></div>`;
const linhaPreco=t=>`${T().eur(t.valor,t.moeda)} ${esc(T().METODO[t.metodo]||t.metodo)}${Number(t.preco_minimo)>0?`, mínimo ${T().eur(t.preco_minimo,t.moeda)}`:""}${t.preco_maximo?`, máximo ${T().eur(t.preco_maximo,t.moeda)}`:""}`;
const limites=t=>t.limite_min!=null||t.limite_max!=null?`Aplica-se de ${t.limite_min??0} a ${t.limite_max??"sem limite"} ${t.metodo==="peso"?"kg":t.metodo==="unidade"?"unidades":"m³"}`:"Sem limites de medida";

/* comparação com a referência geral da Elolog para a mesma rota e modalidade */
function referencia(t){const g=(cache.gerais||[]).find(g=>g.uso==="referencia"&&g.estado==="ativa"&&g.metodo===t.metodo&&(!g.origem||t.origem&&g.origem.toLowerCase()===t.origem.toLowerCase())&&(!g.destino||t.destino&&g.destino.toLowerCase()===t.destino.toLowerCase()));
  if(!g||!(Number(g.valor)>0))return"";const dif=Math.round((Number(t.valor)-Number(g.valor))*100/Number(g.valor));
  return`<p class="tf-ref ${Math.abs(dif)>20?"longe":""}">Referência Elolog (${esc(g.codigo||g.nome)}): ${T().eur(g.valor,g.moeda)} ${esc(T().METODO[g.metodo])}. ${dif===0?"Igual à referência.":`${Math.abs(dif)} % ${dif>0?"acima":"abaixo"} da referência.`}</p>`}

function cartaoPendente(t){const ant=(cache.tarifas||[]).find(x=>x.id===t.tarifa_pai_id);
  const mud=ant?`<p class="tf-mudanca">Versão ${ant.versao}: ${linhaPreco(ant)}. <b>Passa a ${linhaPreco(t)}.</b></p>`:`<p class="tf-mudanca">Tarifa nova: ${linhaPreco(t)}.</p>`;
  return`<article class="tf-cartao"><header><div><small>${esc(t.empresas?.nome||"Prestador")}, versão ${t.versao}</small><h4>${esc(t.nome)}</h4></div>${pill(t.estado)}</header>
    <p>${esc(T().rota(t))}${t.tipo_carga?`, ${esc(t.tipo_carga)}`:""}${t.transporte?`, ${esc(t.transporte)}`:""}. ${esc(limites(t))}.${t.validade_fim?` Válida até ${new Date(t.validade_fim).toLocaleDateString("pt-PT")}.`:""}</p>${mud}${referencia(t)}
    <footer><button type="button" class="btn-primary" data-tf="aprovar" data-id="${t.id}">Aprovar tarifa</button><button type="button" class="btn-secondary" data-tf="pedir_alteracoes" data-id="${t.id}">Pedir alterações</button><button type="button" class="btn-secondary tf-perigo" data-tf="rejeitar" data-id="${t.id}">Rejeitar</button></footer></article>`}

const R={
  aprovar(){const p=(cache.tarifas||[]).filter(t=>t.estado==="pendente"),s=(cache.suplementos||[]).filter(x=>x.estado==="pendente"&&x.empresa_id);
    if(!p.length&&!s.length)return vazio("Não há nada à espera de aprovação","Quando um prestador submeter uma tarifa ou um suplemento, aparece aqui com a diferença para a versão anterior e para a referência Elolog.");
    return`${p.map(cartaoPendente).join("")}${s.map(x=>`<article class="tf-cartao"><header><div><small>${esc(x.empresas?.nome||"Prestador")}, suplemento</small><h4>${esc(x.nome)}</h4></div>${pill(x.estado)}</header>
      <p>${x.tipo==="percentual"?`${x.valor} % sobre o preço`:x.tipo==="por_km"?`${T().eur(x.valor)} por km`:T().eur(x.valor)} ${x.automatico?"(aplica-se sempre)":"(só quando pedido)"}.</p>
      <footer><button type="button" class="btn-primary" data-sup="aprovar" data-id="${x.id}">Aprovar suplemento</button><button type="button" class="btn-secondary tf-perigo" data-sup="rejeitar" data-id="${x.id}">Rejeitar</button></footer></article>`).join("")}`},
  prestadores(){const emp=[...new Map((cache.tarifas||[]).map(t=>[t.empresa_id,t.empresas?.nome||"Prestador"])).entries()];
    const l=(cache.tarifas||[]).filter(t=>(!filtro.empresa||t.empresa_id===filtro.empresa)&&(!filtro.estado||t.estado===filtro.estado));
    const sel=`<div class="tf-filtros"><select data-filtro="empresa" aria-label="Prestador"><option value="">Todos os prestadores</option>${emp.map(([id,n])=>`<option value="${id}" ${filtro.empresa===id?"selected":""}>${esc(n)}</option>`).join("")}</select>
      <select data-filtro="estado" aria-label="Estado"><option value="">Todos os estados</option>${Object.entries(T().ESTADO).filter(([k])=>!["ativa","aprovado","rejeitado","suspenso","inativo"].includes(k)).map(([k,[n]])=>`<option value="${k}" ${filtro.estado===k?"selected":""}>${n}</option>`).join("")}</select></div>`;
    if(!l.length)return sel+vazio("Nenhuma tarifa com estes filtros","Os prestadores criam as tarifas no Financeiro; depois de aprovadas, entram nas simulações.");
    return sel+`<div class="tf-tabela" role="table">${l.map(t=>`<div class="tf-linha" role="row"><div><strong>${esc(t.nome)}</strong><small>${esc(t.empresas?.nome||"")}, versão ${t.versao}, ${esc(T().rota(t))}</small></div>
      <div>${linhaPreco(t)}<small>${esc(limites(t))}</small></div><div>${T().expirada(t)?'<span class="tf-estado erro">Expirada</span>':pill(t.estado)}</div>
      <div class="tf-acoes">${t.estado==="aprovada"?`<button type="button" class="btn-secondary" data-tf="suspender" data-id="${t.id}">Suspender</button>`:t.estado==="suspensa"?`<button type="button" class="btn-secondary" data-tf="reativar" data-id="${t.id}">Reativar</button>`:t.estado==="pendente"?`<button type="button" class="btn-secondary" data-ir="aprovar">Rever</button>`:""}</div></div>`).join("")}</div>`},
  gerais(){const l=cache.gerais||[];return`<div class="tf-topo"><p>Preços de referência (para comparar o que os prestadores pedem) e tarifários comerciais da Elolog, que valem para os prestadores a que os associar quando eles não têm tarifa própria.</p><button type="button" class="btn-primary" data-novo="geral">Novo tarifário geral</button></div>
    ${l.length?`<div class="tf-tabela">${l.map(g=>`<div class="tf-linha"><div><strong>${esc(g.nome)}</strong><small>${esc(g.codigo||"")}, ${g.uso==="comercial"?`comercial, ${g.prestadores?.length||0} prestador(es)`:"referência"}, versão ${g.versao}, ${esc(T().rota(g))}</small></div>
      <div>${linhaPreco(g)}<small>${esc(limites(g))}</small></div><div>${T().expirada(g)?'<span class="tf-estado erro">Expirado</span>':pill(g.estado)}</div><div class="tf-acoes"><button type="button" class="btn-secondary" data-editar="geral" data-id="${g.id}">Alterar</button></div></div>`).join("")}</div>`
      :vazio("Ainda não há tarifários gerais","Crie preços de referência para comparar as tarifas dos prestadores, ou um tarifário comercial para os prestadores que associar.")}`},
  comissoes(){const l=cache.comissoes||[];return`<div class="tf-topo"><p>A regra mais específica ganha: prestador, modalidade e rota. Em empate, a promocional e depois a de maior prioridade. «Incluída»: retida ao preço do prestador. «Separada»: o cliente vê uma taxa de serviço à parte.</p><button type="button" class="btn-primary" data-novo="comissao">Nova regra de comissão</button></div>
    ${l.length?`<div class="tf-tabela">${l.map(c=>`<div class="tf-linha"><div><strong>${esc(c.nome||"Regra sem nome")}</strong><small>${esc(c.empresas?.nome||"Todos os prestadores")}, ${esc(c.metodo?T().METODO[c.metodo]:"todas as modalidades")}, ${esc(c.rota_origem||c.rota_destino?`${c.rota_origem||"qualquer origem"} para ${c.rota_destino||"qualquer destino"}`:"todas as rotas")}</small></div>
      <div>${c.tipo_valor==="percentagem"?`${c.valor} %`:T().eur(c.valor)} ${c.apresentacao==="separada"?"(separada)":"(incluída)"}<small>${c.inicio||c.fim?`De ${c.inicio?new Date(c.inicio).toLocaleDateString("pt-PT"):"sempre"} a ${c.fim?new Date(c.fim).toLocaleDateString("pt-PT"):"sem fim"}`:"Sem período"}${c.promocional?", promocional":""}</small></div>
      <div>${c.ativa?(c.fim&&c.fim<new Date().toISOString().slice(0,10)?'<span class="tf-estado neutro">Terminou</span>':'<span class="tf-estado ok">Ativa</span>'):'<span class="tf-estado neutro">Desligada</span>'}</div><div class="tf-acoes"><button type="button" class="btn-secondary" data-editar="comissao" data-id="${c.id}">Alterar</button></div></div>`).join("")}</div>`
      :vazio("Ainda não há regras de comissão","Sem regra, a Elolog não aplica comissão aos preços. Crie uma regra geral e, se precisar, regras por prestador, modalidade ou rota.")}`},
  suplementos(){const l=cache.suplementos||[];return`<div class="tf-topo"><p>Suplementos gerais da Elolog e dos prestadores. Só os aprovados entram no preço; o do prestador vale mais do que o geral da mesma natureza.</p><button type="button" class="btn-primary" data-novo="suplemento">Novo suplemento geral</button></div>
    ${l.length?`<div class="tf-tabela">${l.map(x=>`<div class="tf-linha"><div><strong>${esc(x.nome)}</strong><small>${esc(x.empresas?.nome||"Elolog, geral")}${x.servico?`, ${esc(x.servico)}`:""}</small></div><div>${x.tipo==="percentual"?`${x.valor} %`:x.tipo==="por_km"?`${T().eur(x.valor)} por km`:T().eur(x.valor)}<small>${x.automatico?"Aplica-se sempre":"Só quando pedido"}</small></div><div>${pill(x.estado)}</div>
      <div class="tf-acoes">${x.estado==="aprovado"?`<button type="button" class="btn-secondary" data-sup="suspender" data-id="${x.id}">Suspender</button>`:x.estado==="suspenso"?`<button type="button" class="btn-secondary" data-sup="reativar" data-id="${x.id}">Reativar</button>`:x.estado==="pendente"?`<button type="button" class="btn-secondary" data-ir="aprovar">Rever</button>`:""}</div></div>`).join("")}</div>`
      :vazio("Ainda não há suplementos","Sem suplemento de recolha configurado, a recolha na morada custa 1 € por km (o valor de sempre).")}`},
  historico(){const l=cache.historico||[],NOME={tarifas:"Tarifa",tarifas_gerais:"Tarifário geral",tarifa_suplementos:"Suplemento",regras_comissao:"Comissão"};
    if(!l.length)return vazio("Ainda sem alterações","Cada criação, alteração ou decisão fica aqui: quem, quando, valor anterior e novo, estado e motivo.");
    return`<ol class="tf-hist">${l.map(h=>{const a=h.antes||{},d=h.depois||{},val=a.valor!=null&&String(a.valor)!==String(d.valor)?`${a.valor} passou a ${d.valor}`:d.valor!=null?`valor ${d.valor}`:"";
      return`<li><time>${new Date(h.created_at).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"})}</time><div><strong>${esc(NOME[h.entidade]||h.entidade)}: ${esc(d.nome||a.nome||"")}</strong>
        <small>${esc(h.user_nome||"Sistema")}${d.versao?`, versão ${d.versao}`:""}${h.estado_anterior!==h.estado_novo?`, ${esc((T().ESTADO[h.estado_anterior]||[h.estado_anterior||"novo"])[0])} para ${esc((T().ESTADO[h.estado_novo]||[h.estado_novo])[0])}`:""}${val?`, ${esc(val)}`:""}</small>${h.motivo?`<p>«${esc(h.motivo)}»</p>`:""}</div></li>`}).join("")}</ol>`},
  testar(){return F()?.testarHtml?.(cache.empresas||[])||""}};

async function carregar(){const A=T().API;try{const[tarifas,gerais,comissoes,suplementos,historico,empresas]=await Promise.all([A.tarifas(),A.gerais(),A.comissoes(),A.suplementos(),A.historico(),A.empresas()]);
  cache={tarifas,gerais,comissoes,suplementos,historico,empresas}}catch(e){cache.erro=e.message}desenhar()}
function desenhar(){const box=document.getElementById("adminTariffsContent");if(!box)return;const n=(cache.tarifas||[]).filter(t=>t.estado==="pendente").length+(cache.suplementos||[]).filter(x=>x.estado==="pendente"&&x.empresa_id).length;
  box.innerHTML=`<div class="admin-section-heading"><div><h3>Tarifários e comissões</h3><p>A fonte única de preços da Elolog: o que aprovar aqui é o que os clientes veem nas simulações.${T().API.online()?"":" Na demonstração, os dados são exemplos só de leitura."}</p></div></div>
    <div class="fs-filtros tf-abas" role="tablist">${ABAS.map(([k,nome,ic])=>`<button type="button" role="tab" aria-selected="${aba===k}" class="fs-filtro ${aba===k?"on":""} ${k==="aprovar"&&n?"aviso":""}" data-aba="${k}"><i class="ic ic-${ic}" aria-hidden="true"></i><span>${nome}</span>${k==="aprovar"?`<b>${n}</b>`:""}</button>`).join("")}</div>
    ${cache.erro?`<div class="provider-order-empty vz vz2 vz-orfa" role="status"><strong>Não conseguimos ler os tarifários</strong><p>${esc(cache.erro)}</p><button type="button" class="btn-secondary vz-acao" data-recarregar="1">Tentar outra vez</button></div>`:`<div class="tf-corpo">${R[aba]()}</div>`}`}

document.addEventListener("click",async e=>{const box=document.getElementById("adminTariffsContent");if(!box||!box.contains(e.target))return;const b=e.target.closest("button");if(!b)return;
  if(b.dataset.aba){aba=b.dataset.aba;return desenhar()}if(b.dataset.ir){aba=b.dataset.ir;return desenhar()}if(b.dataset.recarregar)return carregar();
  if(b.dataset.tf)return F().decidir("tarifa",b.dataset.id,b.dataset.tf,carregar);if(b.dataset.sup)return F().decidir("suplemento",b.dataset.id,b.dataset.sup,carregar);
  if(b.dataset.novo)return F().abrir(b.dataset.novo,null,cache,carregar);if(b.dataset.editar)return F().abrir(b.dataset.editar,b.dataset.id,cache,carregar);if(b.dataset.testar)return F().testar(carregar)});
document.addEventListener("change",e=>{const s=e.target.closest?.("#adminTariffsContent [data-filtro]");if(!s)return;filtro[s.dataset.filtro]=s.value;desenhar()});
document.addEventListener("DOMContentLoaded",()=>{garantirPagina();const ir=window.showAdminPage;if(typeof ir==="function")window.showAdminPage=function(page){const r=ir.apply(this,arguments);
  if(page==="adminTariffs"){const t=document.getElementById("pageTitle");if(t)t.textContent="Tarifários e comissões";carregar()}return r}});
window.elologTarifariosAdmin={carregar,desenhar,abrirAba:k=>{aba=k;desenhar()}};
})();
