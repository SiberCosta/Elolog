/* Elolog — página «Clientes» da administração com dados do servidor (v142).
   Antes a lista juntava os nomes escritos nas encomendas deste navegador: aparecia «A&A. Lda» (indicado por um prestador)
   e faltavam os clientes com conta, como quem se registou no site. Agora mostra:
   1) Pedidos dos clientes por tratar (alteração de dados e eliminação de conta), com «Aprovar» e «Recusar» reais;
   2) Clientes com conta na plataforma, com «Histórico» (as encomendas de cada um) e «Bloquear»/«Desbloquear»;
   3) Clientes sem conta, indicados pelos prestadores nas encomendas.
   Os dados vêm de elologAdminServidor (dados-servidor.js); as escritas usam as políticas do administrador da plataforma. */
(function(){"use strict";
const P=()=>window.elologProducao,$=id=>document.getElementById(id);
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const dia=v=>{const d=new Date(v);return isNaN(d)?"—":d.toLocaleDateString("pt-PT")};
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const plural=(n,um,varios)=>`${n} ${n===1?um:varios}`;
const ESTADO={aprovacao:"Aprovação",agendamento:"Recolha por atribuir",recolha:"Recolha",armazenamento:"Armazém",expedicao:"Expedição",em_transito:"Em trânsito",destino:"No destino",disponivel:"Disponível",entregue:"Entregue",cancelada:"Cancelada"};
const CAMPOS=[["nome","Nome / Empresa"],["nif","NIF"],["telefone","Telefone"],["email","E-mail"],["morada","Morada"]];
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):alert(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
let dados=null,pedidos=[],pedidosEm=0;

async function lerPedidos(forcar){if(!forcar&&Date.now()-pedidosEm<20000)return false;pedidosEm=Date.now();try{const sb=await P().sb();const{data,error}=await sb.from("pedidos_cliente").select("id,cliente_id,tipo,estado,dados,created_at")
  .eq("estado","pendente").order("created_at",{ascending:true});if(error)throw error;pedidos=data||[]}catch(e){console.warn("Pedidos dos clientes:",erro(e));pedidos=[]}return true}

const empresa=id=>{const e=dados?.empresas.find(x=>x.id===id);return e?(e.nome_comercial||e.nome):""};
const cliente=id=>dados?.clientes.find(c=>c.id===id);

function linhaPedido(p){const c=cliente(p.cliente_id)||{},d=p.dados||{};
  const mud=p.tipo==="alteracao_dados"?CAMPOS.filter(([k])=>d[k]&&String(d[k]).trim()&&String(d[k]).trim()!==String(c[k]||"").trim())
    .map(([k,r])=>`<li><b>${esc(r)}</b> ${esc(c[k]||"vazio")} → <strong>${esc(d[k])}</strong></li>`).join(""):"";
  return`<article class="acs-pedido"><div><span class="acs-tipo ${p.tipo==="eliminacao_conta"?"acs-risco":""}">${p.tipo==="eliminacao_conta"?"Eliminação de conta":"Alteração de dados"}</span>
    <strong>${esc(c.nome||c.email||"Cliente")}</strong><small>Pedido a ${esc(dia(p.created_at))}${d.notas?`. Nota do cliente: ${esc(d.notas)}`:""}</small>
    ${mud?`<ul>${mud}</ul>`:p.tipo==="alteracao_dados"?"<small>Sem campos novos; leia a nota do cliente.</small>":"<small>A conta passa a «eliminada» e o cliente deixa de poder entrar. As encomendas ficam no histórico.</small>"}</div>
    <div class="acs-acoes"><button type="button" class="btn-secondary" onclick="elologAdminClientes.decidir('${p.id}',true)">${p.tipo==="eliminacao_conta"?"Aprovar eliminação":"Aprovar e aplicar"}</button>
    <button type="button" class="btn-secondary" onclick="elologAdminClientes.decidir('${p.id}',false)">Recusar</button></div></article>`}

function desenhar(d){const box=$("adminClientsList");if(!box)return;dados=d||dados;if(!dados)return;
  const cs=dados.clientes,semConta=new Map();
  dados.encomendas.filter(o=>!o.cliente_id&&o.cliente_nome).forEach(o=>{const k=o.cliente_nome.trim().toLowerCase();const g=semConta.get(k)||{nome:o.cliente_nome.trim(),os:[]};g.os.push(o);semConta.set(k,g)});
  const ped=pedidos.length?`<section class="acs-bloco"><h4>Pedidos por tratar <span class="acs-num">${pedidos.length}</span></h4>${pedidos.map(linhaPedido).join("")}</section>`:"";
  const com=cs.length?cs.map(c=>{const os=dados.encomendas.filter(o=>o.cliente_id===c.id),pres=[...new Set(os.map(o=>empresa(o.empresa_id)).filter(Boolean))],bloq=c.estado==="bloqueado",elim=c.estado==="eliminado";
    return`<div class="admin-record-row acs-linha"><div><strong>${esc(c.nome||c.email||"Cliente")}${c.estado!=="ativo"?` <span class="acs-estado ${bloq?"acs-risco":""}">${bloq?"Bloqueado":elim?"Eliminado":esc(c.estado)}</span>`:""}</strong>
      <small>${esc([c.email,c.telefone,c.nif?"NIF "+c.nif:""].filter(Boolean).join(", ")||"Sem contactos")}</small><small>Registado a ${esc(dia(c.created_at))}, ${plural(os.length,"encomenda","encomendas")}</small></div>
      <span>${esc(pres.join(", ")||"Ainda sem encomendas")}</span><div class="admin-action-menu"><button type="button" class="btn-secondary" onclick="elologAdminClientes.historico('${c.id}')">Histórico</button>
      ${elim?"":`<button type="button" class="btn-secondary${bloq?"":" admin-risk"}" onclick="elologAdminClientes.bloquear('${c.id}',${!bloq})">${bloq?"Desbloquear":"Bloquear"}</button>`}</div></div>`}).join(""):'<div class="provider-order-empty">Ainda não há clientes com conta.</div>';
  const sem=[...semConta.values()].map(g=>{const pres=[...new Set(g.os.map(o=>empresa(o.empresa_id)).filter(Boolean))];
    return`<div class="admin-record-row acs-linha"><div><strong>${esc(g.nome)}</strong><small>${plural(g.os.length,"encomenda","encomendas")}, indicado por ${esc(pres.join(", ")||"um prestador")}</small></div>
      <span>${esc(pres.join(", "))}</span><div class="admin-action-menu"><button type="button" class="btn-secondary" onclick="elologAdminClientes.historico(null,'${esc(encodeURIComponent(g.nome))}')">Histórico</button></div></div>`}).join("");
  box.innerHTML=`${ped}<section class="acs-bloco"><h4>Com conta na plataforma <span class="acs-num">${cs.length}</span></h4><p class="acs-ajuda">Clientes que se registaram no site e entram com email e palavra-passe.</p>${com}</section>
    ${sem?`<section class="acs-bloco"><h4>Sem conta <span class="acs-num">${semConta.size}</span></h4><p class="acs-ajuda">Nomes indicados pelos prestadores nas encomendas que criaram. Não têm acesso à plataforma.</p>${sem}</section>`:""}`}

function historico(id,nomeCod){if(!dados)return;const nome=nomeCod?decodeURIComponent(nomeCod):"";const c=id?cliente(id):null;
  const os=dados.encomendas.filter(o=>c?o.cliente_id===c.id:!o.cliente_id&&String(o.cliente_nome||"").trim().toLowerCase()===nome.toLowerCase())
    .sort((a,b)=>new Date(b.created_at)-new Date(a.created_at));
  const j=P().janela({eyebrow:"Histórico do cliente",titulo:c?.nome||c?.email||nome||"Cliente"});
  j.mostrar(os.length?`<div class="oe-tabela"><table><thead><tr><th>Encomenda</th><th>Data</th><th>Rota</th><th>Prestador</th><th>Estado</th><th>Valor</th></tr></thead><tbody>${os.map(o=>`<tr><td><b>${esc(o.codigo||"—")}</b></td><td>${esc(dia(o.created_at))}</td><td>${esc(o.origem||"—")} → ${esc(o.destino||"—")}</td><td>${esc(empresa(o.empresa_id)||"—")}</td><td>${esc(ESTADO[o.estado]||o.estado||"—")}</td><td>${esc(eur(o.preco_total))}</td></tr>`).join("")}</tbody></table></div>`
    :'<p class="acs-ajuda">Este cliente ainda não tem encomendas.</p>',[{texto:"Fechar",acao:()=>j.fechar()}])}

async function recarregar(){await Promise.all([window.elologAdminServidor?.ler?.(true),lerPedidos(true)]).then(([d])=>desenhar(d||dados))}

function bloquear(id,bloq){const c=cliente(id);if(!c)return;const fazer=async()=>{try{const sb=await P().sb();
    const{error}=await sb.from("clientes").update({estado:bloq?"bloqueado":"ativo"}).eq("id",id);if(error)throw error;
    aviso(bloq?`${c.nome||c.email} foi bloqueado: deixa de conseguir usar a área de cliente.`:`${c.nome||c.email} foi desbloqueado.`,"success");await recarregar()}
  catch(e){aviso("Não foi possível alterar o cliente: "+erro(e),"error")}};
  if(typeof openPlatformConfirmation==="function")openPlatformConfirmation({title:bloq?"Bloquear cliente":"Desbloquear cliente",eyebrow:"SEGURANÇA DO CLIENTE",
    message:bloq?`Bloquear a conta de ${c.nome||c.email}? O cliente deixa de conseguir usar a área de cliente até ser desbloqueado.`:`Desbloquear a conta de ${c.nome||c.email}?`,
    details:"A alteração fica registada na auditoria.",confirmLabel:bloq?"Bloquear":"Desbloquear",danger:bloq,onConfirm:fazer});else if(confirm(bloq?"Bloquear este cliente?":"Desbloquear este cliente?"))fazer()}

async function decidir(pid,aprovar){const p=pedidos.find(x=>x.id===pid);if(!p)return;const c=cliente(p.cliente_id);
  const fazer=async()=>{try{const sb=await P().sb(),u=await P().utilizador();
      if(aprovar){let mud={};if(p.tipo==="alteracao_dados"){CAMPOS.forEach(([k])=>{const v=String(p.dados?.[k]||"").trim();if(v)mud[k]=v})}else mud={estado:"eliminado"};
        if(Object.keys(mud).length){const{error}=await sb.from("clientes").update(mud).eq("id",p.cliente_id);if(error)throw error}}
      const{error}=await sb.from("pedidos_cliente").update({estado:aprovar?"aprovado":"recusado",tratado_por:u?.id||null,tratado_em:new Date().toISOString()}).eq("id",pid);if(error)throw error;
      aviso(aprovar?"Pedido aprovado e aplicado.":"Pedido recusado.","success");await recarregar()}
    catch(e){aviso("Não foi possível tratar o pedido: "+erro(e),"error")}};
  const elim=p.tipo==="eliminacao_conta";
  if(typeof openPlatformConfirmation==="function")openPlatformConfirmation({title:aprovar?(elim?"Aprovar eliminação da conta":"Aprovar alteração de dados"):"Recusar pedido",eyebrow:"PEDIDO DO CLIENTE",
    message:`${aprovar?"Aprovar":"Recusar"} o pedido de ${c?.nome||c?.email||"cliente"}?`,details:aprovar&&elim?"A conta fica «eliminada» e o cliente deixa de entrar. As encomendas ficam no histórico.":"O cliente vê a decisão no perfil.",
    confirmLabel:aprovar?"Aprovar":"Recusar",danger:aprovar&&elim,onConfirm:fazer});else fazer()}

window.elologAdminClientes={desenhar:d=>{desenhar(d);lerPedidos().then(n=>{if(n)desenhar()})},historico,bloquear,decidir,recarregar};
})();
