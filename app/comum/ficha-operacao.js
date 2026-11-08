/* Elolog — Ficha da operação (v100): abre cada encomenda num painel lateral, sem sair do Centro de comando / Centro Operacional.
   Separadores: Resumo, Percurso (11 etapas), Carga, Financeiro e Histórico. Em baixo, o próximo passo com os requisitos em falta;
   as ações de etapa (receção no armazém, expedição, processamento no destino, levantamento) e o avanço passam sempre pelo servidor. */
(function(){"use strict";
const F=()=>window.elologFichaDados;
const esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const eur=v=>v==null?"—":Number(v).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const dt=v=>v?new Date(v).toLocaleString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit"}).replace(", 00:00",""):"—";
const dia=v=>v?new Date(v).toLocaleDateString("pt-PT"):"—";
const aviso=(t,k)=>window.showPlatformNotice?.(t,k||"info");
const linha=(t,v)=>v==null||v===""?"":`<div><dt>${esc(t)}</dt><dd>${esc(v)}</dd></div>`;
const pessoa=p=>p&&(p.nome||p.telefone||p.email)?[p.nome,p.telefone,p.email,p.morada].filter(Boolean).map(esc).join("<br>"):"—";
let f=null,cod="",aba="resumo";

function percurso(){const{ETAPAS,RESP,ACAO}=F(),i=f.etapa_idx,fin=f.financeiro||{};const ch=f.chegou_em||{},hist=f.historico||[];
  const quem=k=>hist.find(h=>h.para===k)?.responsavel,quando=ks=>ks.map(k=>ch[k]).filter(Boolean).sort()[0];
  const KEYS=[[],[],["aprovacao"],["agendamento","recolha"],[],["armazenamento"],["expedicao"],["em_transito"],["destino"],["disponivel"],["entregue"]];
  return`<ol class="fo-linha">${ETAPAS.map((n,k)=>{let st=k<i?"feito":k===i?"atual":"";if(k===0)st=f.simulacao||i>0?"feito":st;if(k===1)st=f.proposta||i>1?"feito":st;
    if(k===4)st=fin.preco>0&&fin.em_divida<=0?"feito":fin.pago>0?"parcial":fin.pendentes?"alerta":"";
    const q=quando(KEYS[k]);return`<li class="${st}"><b>${k+1}</b><div><strong>${esc(n)}</strong><small>${esc(ACAO[k])}, ${esc(RESP[k])}</small>
      ${q?`<small>${esc(dt(q))}${quem(KEYS[k][KEYS[k].length-1])?", "+esc(quem(KEYS[k][KEYS[k].length-1])):""}</small>`:""}${k===4&&fin.preco?`<small>${eur(fin.pago)} pagos de ${eur(fin.preco)}</small>`:""}</div></li>`}).join("")}</ol>`}

/* v112: o Fluxo Vivo no topo da ficha, com a última mudança registada (quem, quando) do histórico da plataforma */
function fluxoVivo(){const FV=window.elologFluxo;if(!FV)return"";const e=f.encomenda,h=[...(f.historico||[])].filter(x=>x.em).sort((a,b)=>new Date(b.em)-new Date(a.em))[0],
  u=(()=>{try{return typeof currentUser!=="undefined"?currentUser:null}catch(_){return null}})(),papel=u?.role==="prestador"?"prestador":u?.role==="cliente"?"cliente":"admin";
  return FV.render({id:cod,stage:F().ETAPAS[f.etapa_idx]||e.etapa,status:e.suspensa?"Suspensa":(F().ETAPAS[f.etapa_idx]||e.etapa),date:e.data_prevista,destination:e.destino,
    lastStatusChange:h?{datetime:h.em,employee:h.responsavel||"",previous:h.de?F().nomeEstado?.(h.de)||h.de:"",next:F().nomeEstado?.(h.para)||h.para||""}:null},papel).replace(/(<div class="fv-rodape">[\s\S]*?onclick=")/,"$1elologFicha.fechar();")}
function resumo(){const e=f.encomenda,c=f.cliente||{};return`${fluxoVivo()}${e.suspensa?`<p class="fo-alerta">Suspensa: ${esc(e.suspensa_motivo||"ocorrência")}</p>`:""}
  <dl class="fo-dl">${linha("Estado",F().nomeEstado(e.estado)||e.etapa)}${linha("Prestador",f.prestador)}${linha("Rota",`${e.origem||"—"} → ${e.destino||"—"}`)}${linha("Morada de recolha",e.morada_recolha)}
    ${linha("Data prevista",e.data_prevista?dia(e.data_prevista):"")}${linha("Simulação",f.simulacao?.codigo)}${linha("Proposta aceite",f.proposta?eur(f.proposta.preco):"")}</dl>
  <div class="fo-3"><section><h5>Cliente</h5><p>${pessoa({nome:c.nome,telefone:c.telefone,email:c.email})}${c.nif?`<br>NIF ${esc(c.nif)}`:""}</p></section>
    <section><h5>Remetente</h5><p>${pessoa(e.remetente)}</p></section><section><h5>Destinatário</h5><p>${pessoa(e.destinatario)}</p></section></div>`}

function carga(){const e=f.encomenda,a=f.armazem,vol=Array.isArray(e.volumes)?e.volumes:[],docs=f.documentos||[],fotos=docs.filter(d=>/^image\//.test(d.mime||"")).concat(f.fotos||[]);
  return`<dl class="fo-dl">${linha("Tipo de carga",e.tipo_carga)}${linha("Descrição",e.descricao)}${linha("Volumes",e.quantidade)}${linha("Peso",e.peso_kg!=null?e.peso_kg+" kg":"")}
    ${linha("Volume",e.volume_m3!=null?e.volume_m3+" m³":"")}${linha("Valor declarado",e.valor_declarado!=null?eur(e.valor_declarado):"")}</dl>
  ${vol.length?`<table class="fo-tab"><thead><tr><th>#</th><th>Descrição</th><th>Medidas</th><th>Peso</th></tr></thead><tbody>${vol.map((v,i)=>`<tr><td>${i+1}</td><td>${esc(v.descricao||v.description||v.tipo||"Volume")}</td>
    <td>${[v.comprimento||v.length,v.largura||v.width,v.altura||v.height].filter(Boolean).join(" × ")||"—"}</td><td>${esc(v.peso||v.weight||"—")}</td></tr>`).join("")}</tbody></table>`:""}
  <h5>Armazém</h5>${a?`<dl class="fo-dl">${linha("Armazém",a.armazem)}${linha("Quantidade recebida",a.quantidade_recebida)}${linha("Carga conferida",a.carga_conferida?"Sim":"Não")}
    ${linha("Localização",a.localizacao)}${linha("Ocorrências",a.ocorrencias)}${linha("Confirmado em",dt(a.confirmado_em))}</dl>`:'<p class="fo-vazio">Receção ainda não confirmada.</p>'}
  <h5>Expedição</h5>${e.navio?`<dl class="fo-dl">${linha("Navio",e.navio)}${linha("Viagem",e.viagem)}${linha("Partida prevista",dia(e.partida_prevista))}${linha("Chegada prevista",e.chegada_prevista?dia(e.chegada_prevista):"")}</dl>`:'<p class="fo-vazio">Sem navio associado.</p>'}
  <h5>Fotografias</h5>${fotos.length?`<div class="fo-fotos">${fotos.map((d,i)=>d.caminho?`<button type="button" class="fo-foto" data-foto="${esc(d.caminho)}">${esc(d.nome)}</button>`:d.src||d.dataUrl?`<img src="${esc(d.src||d.dataUrl)}" alt="Fotografia ${i+1}">`:"").join("")}</div>`:'<p class="fo-vazio">Sem fotografias.</p>'}
  <h5>Documentos</h5>${docs.length?`<ul class="fo-docs">${docs.map(d=>`<li>${d.caminho?`<button type="button" class="ed-link" data-doc="${esc(d.caminho)}" data-nome="${esc(d.nome)}">📄 ${esc(d.nome)}</button>`:`📄 ${esc(d.nome)}`} <small>${esc(d.categoria||"")}</small></li>`).join("")}</ul>`:'<p class="fo-vazio">Sem documentos.</p>'}`}

function financeiro(){const x=f.financeiro||{},pg=f.pagamentos||[];return`${x.pendentes?`<p class="fo-alerta">Alerta financeiro: ${x.pendentes} pagamento(s) pendente(s).</p>`:""}
  <div class="fo-kpis"><div><span>Preço</span><strong>${eur(x.preco)}</strong></div><div><span>Comissão Elolog</span><strong>${x.comissao==null?"—":eur(x.comissao)}</strong><small>${esc(x.comissao_regra||"sem regra ativa")}</small></div>
    <div><span>Pago</span><strong>${eur(x.pago)}</strong></div><div class="${x.em_divida>0?"fo-divida":""}"><span>Em dívida</span><strong>${eur(x.em_divida)}</strong></div></div>
  ${pg.length?`<table class="fo-tab"><thead><tr><th>Pagamento</th><th>Tipo</th><th>Valor</th><th>Estado</th><th>Data</th></tr></thead><tbody>${pg.map(p=>`<tr><td>${esc(p.codigo||"—")}</td><td>${esc(p.tipo)}</td><td>${eur(p.valor)}</td>
    <td><span class="fo-chip ${p.estado==="pago"?"ok":p.estado==="pendente"||p.estado==="parcial"?"amb":""}">${esc(p.estado)}</span></td><td>${esc(dt(p.pago_em||p.em))}</td></tr>`).join("")}</tbody></table>`:'<p class="fo-vazio">Sem pagamentos registados.</p>'}`}

function historico(){const N=F().nomeEstado,h=f.historico||[],o=f.ocorrencias||[];return`${h.length?`<ol class="fo-hist">${h.slice().reverse().map(x=>`<li><div class="fo-h1"><strong>${x.de&&x.de!==x.para?`${esc(N(x.de))} → ${esc(N(x.para))}`:esc(x.de===x.para&&x.de?"Registo em "+N(x.para):N(x.para))}</strong><small>${esc(dt(x.em))}</small></div>
    <small>${esc(x.responsavel||"—")}${x.prestador?", "+esc(x.prestador):""}, ${esc(cod)}</small>${x.nota?`<p>${esc(x.nota)}</p>`:""}${x.motivo_excecao?`<p class="fo-exc"><b>Exceção:</b> ${esc(x.motivo_excecao)}</p>`:""}
    ${x.documentos?.length?`<p class="fo-docs-h">📎 ${x.documentos.map(esc).join(", ")}</p>`:""}</li>`).join("")}</ol>`:'<p class="fo-vazio">Sem alterações registadas.</p>'}
  <h5>Ocorrências</h5>${o.length?`<ul class="fo-ocorr">${o.map(x=>`<li><b>${esc(x.codigo||x.tipo)}</b>, ${esc(x.gravidade||"")}, ${esc(x.estado||"")}<p>${esc(x.descricao||"")}</p>${x.resolucao?`<small>Resolução: ${esc(x.resolucao)}</small>`:""}</li>`).join("")}</ul>`:'<p class="fo-vazio">Sem ocorrências.</p>'}`}

const ABAS=[["resumo","Resumo",resumo],["percurso","Percurso",percurso],["carga","Carga",carga],["financeiro","Financeiro",financeiro],["historico","Histórico",historico]];
function desenhar(){const p=document.getElementById("foPainel");if(!p||!f)return;const e=f.encomenda;
  p.querySelector(".fo-topo").innerHTML=`<div><small>Ficha da operação${f.demo?" (demonstração)":""}</small><h3>${esc(cod)}</h3><p>${esc(e.origem||"—")} → ${esc(e.destino||"—")}, ${esc(f.prestador||"—")}</p></div>
    <span class="fo-chip azul">${esc(F().nomeEstado(e.estado)||e.etapa)}</span><button type="button" class="fo-fechar" aria-label="Fechar a ficha">×</button>`;
  p.querySelector(".fo-abas").innerHTML=ABAS.map(([k,t])=>`<button type="button" role="tab" aria-selected="${k===aba}" class="${k===aba?"ativo":""}" data-aba="${k}">${t}</button>`).join("");
  p.querySelector(".fo-corpo").innerHTML=(ABAS.find(x=>x[0]===aba)||ABAS[0])[2]();p.querySelector(".fo-passo").innerHTML=window.elologFichaAcoes?.passo(f)||""}

async function abrir(codigo){cod=String(codigo||"").trim().toUpperCase();if(!cod)return;aba="resumo";let p=document.getElementById("foPainel");
  if(!p){p=document.createElement("aside");p.id="foPainel";p.className="fo-painel";p.setAttribute("role","dialog");p.setAttribute("aria-label","Ficha da operação");
    p.innerHTML='<header class="fo-topo"></header><nav class="fo-abas" role="tablist"></nav><div class="fo-corpo"></div><footer class="fo-passo"></footer>';document.body.appendChild(p);
    p.addEventListener("click",ev=>{const t=ev.target;if(t.closest(".fo-fechar"))return fechar();const a=t.closest("[data-aba]");if(a){aba=a.dataset.aba;return desenhar()}
      const d=t.closest("[data-doc],[data-foto]");if(d){F().url(d.dataset.doc||d.dataset.foto).then(u=>window.open(u,"_blank","noopener")).catch(x=>aviso(F().erro(x),"error"));return}
      window.elologFichaAcoes?.clique(ev,f,recarregar)})}
  document.body.classList.add("fo-aberta");p.querySelector(".fo-topo").innerHTML=`<div><small>FICHA DA OPERAÇÃO</small><h3>${esc(cod)}</h3></div><button type="button" class="fo-fechar" aria-label="Fechar a ficha">×</button>`;
  p.querySelector(".fo-corpo").innerHTML='<p class="fo-vazio">A carregar…</p>';p.querySelector(".fo-abas").innerHTML="";p.querySelector(".fo-passo").innerHTML="";
  try{f=await F().carregar(cod);desenhar()}catch(x){p.querySelector(".fo-corpo").innerHTML=`<p class="campo-erro">${esc(F().erro(x))}</p>`}}
async function recarregar(){try{f=await F().carregar(cod);desenhar();window.dispatchEvent(new CustomEvent("elolog:operacao-alterada",{detail:{codigo:cod}}))}catch(x){aviso(F().erro(x),"error")}}
function fechar(){document.getElementById("foPainel")?.remove();document.body.classList.remove("fo-aberta");f=null}
document.addEventListener("keydown",e=>{if(e.key==="Escape"&&document.getElementById("foPainel")&&!document.getElementById("pmJanela"))fechar()});

/* Qualquer elemento com data-ficha abre a ficha; os cartões de encomenda do prestador ganham o botão «Ficha». */
const COD=/\b(?!ED-|SIM-|AGD-|PAY-|MNF-|JOB-)[A-Z]{2,4}(?:_[A-Z0-9]+)?-\d{3,}(?:-\d+)?\b/;
document.addEventListener("click",ev=>{const x=ev.target.closest("[data-ficha]");if(x){ev.preventDefault();ev.stopPropagation();abrir(x.dataset.ficha)}},true);
function marcar(){document.querySelectorAll(".provider-work-card:not([data-fo])").forEach(c=>{c.dataset.fo=1;const m=(c.querySelector(".work-code")?.textContent||"").match(COD)||c.textContent.match(COD);
  if(!m)return;const alvo=c.querySelector(".provider-work-actions,.provider-order-actions,footer")||c;alvo.insertAdjacentHTML("beforeend",`<button type="button" class="btn-secondary fo-abrir" data-ficha="${esc(m[0])}">Ficha</button>`)})}
new MutationObserver(()=>{clearTimeout(marcar.t);marcar.t=setTimeout(marcar,150)}).observe(document.documentElement,{childList:true,subtree:true});
window.elologFicha={abrir,fechar,recarregar,dados:()=>f};
})();
