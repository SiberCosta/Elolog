/* Elolog — Regras de cobrança: peças de ecrã partilhadas pela administração e pelo prestador (v115).
   Só mostram dados; nenhuma peça calcula preços (o preço vem sempre do motor no servidor). */
(function(){"use strict";
const T=()=>window.elologTarifarios,esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const data=d=>d?new Date(d).toLocaleDateString("pt-PT"):"";
const pill=e=>{const[x,c]=T().ESTADO[e]||[e,"neutro"];return`<span class="tf-estado ${c}">${esc(x)}</span>`};
const vazio=(t,d,ic="tag")=>`<div class="provider-order-empty vz vz2" data-vz="1" role="status"><span class="vz-ic" aria-hidden="true"><i class="ic ic-${ic}"></i></span><strong>${esc(t)}</strong><p>${esc(d)}</p></div>`;
const linhaPreco=t=>`${T().eur(t.valor,t.moeda)} ${esc(T().METODO[t.metodo]||t.metodo||"")}${Number(t.preco_minimo)>0?`, mínimo ${T().eur(t.preco_minimo,t.moeda)}`:""}${t.preco_maximo?`, máximo ${T().eur(t.preco_maximo,t.moeda)}`:""}`;
const limites=t=>t.limite_min!=null||t.limite_max!=null?`Aplica-se de ${t.limite_min??0} a ${t.limite_max??"sem limite"} ${t.metodo==="peso"?"kg":t.metodo==="unidade"?"unidades":"m³"}`:"Sem limites de medida";
const palavras=t=>{const p=t.regras?.palavras||[];return p.length||t.regras?.so_descricao?`<small class="tf-palavras">${t.regras?.so_descricao?"Só pela descrição. ":""}${p.length?`Palavras: ${esc(p.join(", "))}`:""}</small>`:""};
const custoVeiculo=v=>`${T().eur(v.preco_saida,v.moeda)} de saída + ${T().eur(v.preco_km,v.moeda)} por km${Number(v.preco_minimo)>0?`, mínimo ${T().eur(v.preco_minimo,v.moeda)}`:""}`;
const capacidade=v=>[v.capacidade_kg?`até ${Number(v.capacidade_kg).toLocaleString("pt-PT")} kg`:"",v.capacidade_m3?`até ${Number(v.capacidade_m3).toLocaleString("pt-PT")} m³`:""].filter(Boolean).join(", ")||"Sem limite de capacidade";

/* indicadores da visão geral */
const kpis=l=>`<div class="tf-kpis">${l.map(([n,v,c])=>`<div class="tf-kpi ${c||""}"><strong>${esc(v)}</strong><span>${esc(n)}</span></div>`).join("")}</div>`;

/* linhas de listas (acoes: html dos botões, já montado por quem chama) */
const linhaTarifa=(t,acoes="",comEmpresa=true)=>`<div class="tf-linha" role="row"><div><strong>${esc(t.nome)}</strong><small>${comEmpresa&&t.empresas?.nome?esc(t.empresas.nome)+", ":""}versão ${t.versao||1}, ${esc(T().rota(t))}${t.tipo_carga?`, ${esc(t.tipo_carga)}`:""}</small>${palavras(t)}</div>
  <div>${linhaPreco(t)}<small>${esc(limites(t))}</small></div><div>${T().expirada(t)?'<span class="tf-estado erro">Expirada</span>':pill(t.estado)}</div><div class="tf-acoes">${acoes}</div></div>`;
const linhaVeiculo=(v,acoes="")=>`<div class="tf-linha" role="row"><div><strong>${esc(v.nome)}</strong><small>${esc(T().VEICULO[v.veiculo]||v.veiculo)}, ${esc(v.empresas?.nome||(v.empresa_id?"":"Elolog, geral"))}${v.empresas?.nome||!v.empresa_id?", ":""}versão ${v.versao||1}</small></div>
  <div>${custoVeiculo(v)}<small>${esc(capacidade(v))}</small></div><div>${T().expirada(v)?'<span class="tf-estado erro">Expirada</span>':pill(v.estado)}</div><div class="tf-acoes">${acoes}</div></div>`;
const linhaComissao=(c,acoes="")=>`<div class="tf-linha" role="row"><div><strong>${esc(c.nome||"Regra sem nome")}</strong><small>${esc(c.empresas?.nome||(c.geral===false||c.empresa_id?"A sua empresa":"Todos os prestadores"))}, ${esc(c.metodo?T().METODO[c.metodo]:"todas as modalidades")}, ${esc(c.rota_origem||c.rota_destino?`${c.rota_origem||"qualquer origem"} para ${c.rota_destino||"qualquer destino"}`:"todas as rotas")}</small></div>
  <div>${c.tipo_valor==="percentagem"?`${c.valor} %`:T().eur(c.valor)} ${c.apresentacao==="separada"?"(taxa de serviço à parte)":"(incluída no preço)"}<small>${c.inicio||c.fim?`De ${c.inicio?data(c.inicio):"sempre"} a ${c.fim?data(c.fim):"sem fim"}`:"Sem período"}${c.promocional?", promocional":""}</small></div>
  <div>${c.ativa===false?'<span class="tf-estado neutro">Desligada</span>':c.fim&&c.fim<new Date().toISOString().slice(0,10)?'<span class="tf-estado neutro">Terminou</span>':'<span class="tf-estado ok">Ativa</span>'}</div><div class="tf-acoes">${acoes}</div></div>`;
const tabela=linhas=>`<div class="tf-tabela" role="table">${linhas}</div>`;

/* histórico e auditoria */
const NOME={tarifas:"Tarifa",tarifas_gerais:"Tarifário geral",tarifa_suplementos:"Suplemento",regras_comissao:"Comissão",tarifas_veiculos:"Tarifa de veículo"};
function historico(l){if(!l.length)return vazio("Ainda sem alterações","Cada criação, alteração ou decisão fica aqui: quem, quando, valor anterior e novo, estado, versão e motivo.","file");
  return`<ol class="tf-hist">${l.map(h=>{const a=h.antes||{},d=h.depois||{},va=a.valor??a.preco_km,vd=d.valor??d.preco_km,val=va!=null&&String(va)!==String(vd)?`${va} passou a ${vd}`:vd!=null?`valor ${vd}`:"";
    return`<li><time>${new Date(h.created_at).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"})}</time><div><strong>${esc(NOME[h.entidade]||h.entidade)}: ${esc(d.nome||a.nome||"")}</strong>
      <small>${esc(h.user_nome||"Sistema")}${d.versao?`, versão ${d.versao}`:""}${h.estado_anterior!==h.estado_novo?`, ${esc((T().ESTADO[h.estado_anterior]||[h.estado_anterior||"novo"])[0])} para ${esc((T().ESTADO[h.estado_novo]||[h.estado_novo])[0])}`:""}${val?`, ${esc(val)}`:""}</small>${h.motivo?`<p>«${esc(h.motivo)}»</p>`:""}</div></li>`}).join("")}</ol>`}

/* motor de busca: procura em todas as regras pela descrição da carga ou pelo nome (mesma regra que o motor de preços usa) */
function busca(texto,c){const t=String(texto||"").trim();if(t.length<3)return"";const P=T().procura,n=T().normal(t),contem=x=>T().normal(x).includes(n);
  const res=[...(c.tarifas||[]).map(x=>({x,tipo:"Tarifa do prestador",termo:P(t,x.nome,x.regras?.palavras)||(contem(x.nome)?x.nome:""),preco:linhaPreco(x),dono:x.empresas?.nome})),
    ...(c.gerais||[]).map(x=>({x,tipo:x.uso==="comercial"?"Tarifário geral comercial":"Referência Elolog",termo:P(t,x.nome,x.regras?.palavras)||(contem(x.nome)?x.nome:""),preco:linhaPreco(x),dono:x.codigo})),
    ...(c.veiculos||[]).map(x=>({x,tipo:"Tarifa de veículo",termo:P(t,x.nome,[T().VEICULO[x.veiculo]])||(contem(x.nome)?x.nome:""),preco:custoVeiculo(x),dono:x.empresas?.nome||(x.empresa_id?"":"Elolog")})),
    ...(c.suplementos||[]).map(x=>({x,tipo:"Suplemento",termo:P(t,x.nome)||(contem(x.nome)?x.nome:""),preco:x.tipo==="percentual"?`${x.valor} %`:T().eur(x.valor)+(x.tipo==="por_km"?" por km":""),dono:x.empresas?.nome||"Elolog"})),
    ...(c.comissoes||[]).map(x=>({x,tipo:"Comissão",termo:P(t,x.nome)||(contem(x.nome)?x.nome:""),preco:x.tipo_valor==="percentagem"?`${x.valor} %`:T().eur(x.valor),dono:x.empresas?.nome||"Todos"}))].filter(r=>r.termo);
  if(!res.length)return`<div class="tf-busca-res" role="status"><p>Nenhuma regra de cobrança tem um nome que coincida com «${esc(t)}». No simulador, esta descrição usaria a tarifa geral da rota (ou pediria cotação).</p></div>`;
  return`<div class="tf-busca-res" role="status"><p>${res.length} regra(s) coincidem com «${esc(t)}». A tarifa do prestador com nome igual à descrição ganha no simulador.</p><ul>${res.slice(0,12).map(r=>`<li><span class="tf-estado neutro">${esc(r.tipo)}</span><strong>${esc(r.x.nome)}</strong><span>${r.preco}</span><small>${esc([r.dono,r.x.estado?(T().ESTADO[r.x.estado]||[r.x.estado])[0]:""].filter(Boolean).join(", "))}</small></li>`).join("")}</ul></div>`}
const caixaBusca=v=>`<div class="tf-busca"><label for="tfBusca">Motor de busca</label><div><input id="tfBusca" type="search" autocomplete="off" value="${esc(v||"")}" placeholder="Escreva a descrição da carga ou o nome de uma regra (ex.: frigorífico, palete, carrinha)"><i class="ic ic-search" aria-hidden="true"></i></div><div id="tfBuscaRes" aria-live="polite"></div></div>`;

window.elologTarifariosVistas={esc,pill,vazio,linhaPreco,limites,kpis,linhaTarifa,linhaVeiculo,linhaComissao,tabela,historico,busca,caixaBusca,custoVeiculo,capacidade};
})();
