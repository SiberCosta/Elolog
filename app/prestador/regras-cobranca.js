/* Elolog — Regras de cobrança do prestador: centro de controlo comercial e tarifário (Financeiro › Regras de cobrança, v115).
   Separadores: Visão geral · Tarifários gerais ELOLog · Tarifários dos prestadores · Tarifários de veículos · Comissões · Simulador de preços · Histórico e auditoria.
   O prestador cria e gere as suas regras: entram logo em vigor (a Elolog só pode suspender). Os preços vêm sempre do motor no servidor (simular_preco). */
(function(){"use strict";
const T=()=>window.elologTarifarios,F=()=>window.elologTarifariosForms,V=()=>window.elologTarifariosVistas;
const ABAS=[["visao","Visão geral","chart"],["gerais","Tarifários gerais ELOLog","tag"],["prestadores","Tarifários dos prestadores","building"],["veiculos","Tarifários de veículos","truck"],
  ["comissoes","Comissões","wallet"],["simulador","Simulador de preços","calc"],["historico","Histórico e auditoria","file"]];
const MET={"por peso":"peso","por volume":"volume","por quantidade":"unidade","por unidade":"unidade","preço fixo":"fixo","preco fixo":"fixo"};
const EST={"Ativa":"aprovada","Por aprovar":"pendente","Alterações pedidas":"alteracoes_pedidas","Rejeitada":"rejeitada","Suspensa pela Elolog":"suspensa","Inativa":"inativa","Substituída":"substituida","Rascunho":"rascunho"};
let aba="visao",cache={},busca="",base=()=>"",dadosLocais=null,carregado=false;
const podeEditar=()=>["admin","financeiro"].includes(typeof providerFunction==="function"?providerFunction():"");
const b=(txt,attrs,cl="btn-secondary")=>`<button type="button" class="${cl}" ${attrs}>${txt}</button>`;

/* as tarifas da empresa, como o Financeiro as tem (já sincronizadas com o servidor quando há ligação) */
const minhas=()=>(dadosLocais?.tariffs||[]).map(t=>({id:t.serverId||t.id,local:t.id,nome:t.name,valor:t.value,moeda:t.currency,metodo:MET[String(t.method||"").toLowerCase()]||"volume",preco_minimo:t.minimumPrice,
  origem:t.origin,destino:t.destination,tipo_carga:t.cargoType,versao:t.version,estado:t.estado||EST[t.status]||"inativa",validade_fim:t.endDate,regras:t.rules||{},motivo:t.notes}));

async function carregar(){const A=T().API,r=await Promise.allSettled([A.gerais(),A.veiculos(),A.minhasComissoes(),A.historico()]);
  const ok=i=>r[i].status==="fulfilled"?r[i].value:(cache.avisos=[...(cache.avisos||[]),r[i].reason?.message],[]);cache={avisos:[]};
  cache.gerais=ok(0);cache.veiculos=ok(1);cache.comissoes=ok(2);cache.historico=ok(3);carregado=true;desenhar()}

const R={
  visao(){const l=minhas(),hoje=new Date().toISOString().slice(0,10),em30=new Date(Date.now()+30*864e5).toISOString().slice(0,10),e=V().esc;
    const corrigir=l.filter(t=>["alteracoes_pedidas","rejeitada","suspensa"].includes(t.estado)),pend=l.filter(t=>t.estado==="pendente"),exp=l.filter(t=>t.estado==="aprovada"&&t.validade_fim&&t.validade_fim>=hoje&&t.validade_fim<=em30);
    const vei=(cache.veiculos||[]).filter(v=>v.empresa_id);
    return V().kpis([["Tarifas em vigor",l.filter(t=>t.estado==="aprovada").length],["Desativadas ou rascunho",l.filter(t=>["inativa","rascunho"].includes(t.estado)).length],
      ["Para corrigir",corrigir.length,corrigir.length?"erro":""],["Veículos aprovados",vei.filter(v=>v.estado==="aprovado").length],["Expiram em 30 dias",exp.length,exp.length?"aviso":""]])
    +`<h4 class="tf-sub">O que fazer agora</h4>${corrigir.length||exp.length?`<div class="tf-tabela">${[...corrigir.map(t=>`<div class="tf-linha"><div><strong>${e(t.nome)}</strong><small>${e(t.motivo||"A Elolog pediu alterações.")}</small></div><div>${V().linhaPreco(t)}</div><div>${V().pill(t.estado)}</div><div class="tf-acoes">${podeEditar()?b("Corrigir e submeter",`data-corrigir="${e(t.local)}"`,"btn-primary"):""}</div></div>`),
      ...exp.map(t=>`<div class="tf-linha"><div><strong>${e(t.nome)}</strong><small>Válida até ${new Date(t.validade_fim).toLocaleDateString("pt-PT")}</small></div><div>${V().linhaPreco(t)}</div><div><span class="tf-estado aviso">Expira em breve</span></div><div class="tf-acoes">${podeEditar()?b("Criar nova versão",`data-corrigir="${e(t.local)}"`):""}</div></div>`)].join("")}</div>`
      :V().vazio("Está tudo em dia","Nenhuma tarifa precisa de correção nem está a expirar. Se a Elolog suspender alguma, aparece aqui com o motivo.","check")}
    <div class="tf-como"><h4 class="tf-sub">Como se forma o preço que o cliente vê</h4><ol><li>A sua tarifa aprovada mais específica para a rota; se a descrição da carga tiver o nome de uma tarifa (ou uma das palavras dela), essa ganha.</li><li>Recolha: o veículo aprovado mais barato que leva a carga.</li><li>Suplementos aprovados.</li><li>Comissão Elolog, incluída no preço ou à parte, conforme a regra.</li></ol></div>`},
  gerais(){const l=cache.gerais||[];return`<div class="tf-topo"><p>Preços de referência da Elolog (para alinhar os seus) e tarifários comerciais a que a sua empresa está associada. Só a Elolog os altera.</p></div>
    ${l.length?V().tabela(l.map(g=>V().linhaTarifa({...g,empresas:{nome:`${g.codigo||""}, ${g.uso==="comercial"?"comercial (usado quando não tem tarifa própria)":"referência"}`}})).join("")):V().vazio("Sem tarifários gerais para mostrar","A Elolog ainda não publicou preços de referência.")}`},
  prestadores(){return`<div class="tf-topo"><p>As tarifas da sua empresa. Cada tarifa que guardar entra logo em vigor, sem esperar pela Elolog. Alterar uma tarifa cria uma nova versão: as encomendas já aceites mantêm o preço antigo. Dê-lhes nomes iguais ao que os clientes escrevem (ex.: «Frigorífico», «Palete»): o motor encontra-as pela descrição da carga.</p></div>${base()}`},
  veiculos(){const l=cache.veiculos||[],meus=l.filter(v=>v.empresa_id),gerais=l.filter(v=>!v.empresa_id);
    return`<div class="tf-topo"><p>Quanto custa ir buscar ou entregar a carga, por tipo de veículo: saída + km, com mínimo. Com recolha, o motor escolhe o seu veículo aprovado mais barato que leva o peso e o volume; sem nenhum, usa os gerais da Elolog.</p>${podeEditar()?b("Nova tarifa de veículo",'data-novo-vei="1"',"btn-primary"):""}</div>
    <h4 class="tf-sub">Os seus veículos</h4>${meus.length?V().tabela(meus.map(v=>V().linhaVeiculo(v,podeEditar()&&!/inativo|rejeitado/.test(v.estado)?b("Alterar",`data-editar-vei="${v.id}"`)+(v.estado!=="inativo"?b("Desativar",`data-desativar-vei="${v.id}"`):""):"")+(podeEditar()?b("Eliminar",`data-eliminar-vei="${v.id}"`,"btn-secondary tf-perigo"):"")).join("")):V().vazio("Ainda não tem tarifas de veículos","Crie uma por tipo de veículo (ex.: carrinha até 1 200 kg, camião até 7 500 kg). Entra logo nas simulações.","truck")}
    ${gerais.length?`<h4 class="tf-sub">Gerais da Elolog</h4>${V().tabela(gerais.map(v=>V().linhaVeiculo(v)).join(""))}`:""}`},
  comissoes(){const l=cache.comissoes||[];return`<div class="tf-topo"><p>As comissões Elolog que se aplicam à sua empresa. «Incluída»: é retida ao seu preço. «À parte»: o cliente paga uma taxa de serviço e o seu preço não muda.</p></div>
    ${l.length?V().tabela(l.map(c=>V().linhaComissao(c)).join("")):V().vazio("Sem comissões ativas","Neste momento a Elolog não aplica comissão às suas tarifas.","wallet")}`},
  simulador(){return F()?.testarHtml?.([],{prestador:true})||""},
  historico(){return V().historico(cache.historico||[])}};

function desenhar(){const box=document.getElementById("rcCentro");if(!box)return;const n=minhas().filter(t=>["alteracoes_pedidas","rejeitada"].includes(t.estado)).length;
  box.innerHTML=`${V().caixaBusca(busca)}<div class="fs-filtros tf-abas" role="tablist">${ABAS.map(([k,nome,ic])=>`<button type="button" role="tab" aria-selected="${aba===k}" class="fs-filtro ${aba===k?"on":""} ${k==="visao"&&n?"aviso":""}" data-rc-aba="${k}"><i class="ic ic-${ic}" aria-hidden="true"></i><span>${nome}</span>${k==="visao"&&n?`<b>${n}</b>`:""}</button>`).join("")}</div>
    ${!T().API.online()?'<p class="tf-nota">Demonstração: os tarifários gerais, veículos e comissões são exemplos. As suas tarifas são as que criar aqui.</p>':""}${(cache.avisos||[]).filter(Boolean).length&&aba!=="prestadores"?`<p class="tf-nota">Parte da informação não carregou: ${V().esc(cache.avisos.filter(Boolean)[0])}</p>`:""}
    <div class="tf-corpo">${!carregado&&!["prestadores","simulador"].includes(aba)?'<p class="tf-nota">A carregar…</p>':R[aba]()}</div>`;
  {const t=box.querySelector('.tf-abas [aria-selected="true"]');if(t)t.parentElement.scrollLeft=t.offsetLeft-t.parentElement.offsetLeft-16}
  if(busca)document.getElementById("tfBuscaRes").innerHTML=V().busca(busca,{...cache,tarifas:minhas()})}

/* chamado pelo Financeiro ao abrir «Regras de cobrança»: devolve o ecrã e carrega o resto em segundo plano */
function html(data,baseFn){dadosLocais=data;base=baseFn;setTimeout(()=>{const t=document.getElementById("pageTitle");if(t)t.textContent="Regras de cobrança";desenhar();if(!carregado)carregar()},0);
  return`<div class="tf-pagina rc-pagina"><div class="admin-section-heading tf-cabeca"><div><h3>Regras de cobrança</h3><p>Centro de controlo comercial e tarifário da sua empresa.</p></div></div><div id="rcCentro"></div></div>`}

document.addEventListener("click",async e=>{const box=document.getElementById("rcCentro");if(!box||!box.contains(e.target))return;const x=e.target.closest("button");if(!x)return;const d=x.dataset;
  const recarregar=()=>{carregado=false;window.elologTarifas?.sincronizar?.();carregar()};
  if(d.rcAba){aba=d.rcAba;return desenhar()}if(d.corrigir)return window.openFinanceTariff?.(d.corrigir);
  if(d.novoVei)return F().abrir("veiculo",null,cache,recarregar);if(d.editarVei)return F().abrir("veiculo",d.editarVei,cache,recarregar);
  if(d.desativarVei){try{await T().API.guardarVeiculo({estado:"inativo"},d.desativarVei);window.elologProducao?.aviso?.("Tarifa de veículo desativada: deixa de entrar nas simulações.","success");recarregar()}catch(err){window.elologProducao?.aviso?.(err.message,"error")}return}
  if(d.eliminarVei)return F().eliminarVeiculo(d.eliminarVei,(cache.veiculos||[]).find(v=>v.id===d.eliminarVei),recarregar);
  if(d.testar)return F().testar()});
let espera;document.addEventListener("input",e=>{if(e.target.id!=="tfBusca"||!e.target.closest("#rcCentro"))return;busca=e.target.value;clearTimeout(espera);
  espera=setTimeout(()=>{const r=document.getElementById("tfBuscaRes");if(r)r.innerHTML=V().busca(busca,{...cache,tarifas:minhas()})},200)});
window.elologRegrasCobranca={html,carregar,abrirAba:k=>{aba=k;desenhar()}};
})();
