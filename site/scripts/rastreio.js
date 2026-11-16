/* Elolog — rastreio público no site (v156, migração 00198).
   Com o código completo, pergunta ao servidor (rastrear_encomenda) e mostra o fluxo real da encomenda em 6 fases,
   com a data de cada fase já passada, a fase atual destacada e a chegada prevista. Só dados de seguimento:
   nunca nomes, moradas, contactos ou preços. Sem servidor configurado, diz que o rastreio não está disponível. */
(function(){"use strict";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const FASES=[["Pedido aceite",["aprovacao","agendamento"],"O prestador aceitou e está a organizar a recolha."],["Recolha",["recolha"],"A carga está a ser recolhida."],
  ["No armazém",["armazenamento","expedicao"],"A carga está no armazém e prepara-se a saída."],["Em viagem",["em_transito"],"A carga está a caminho do destino."],
  ["No destino",["destino","disponivel"],"A carga chegou e está a ser preparada para levantamento."],["Entregue",["entregue"],"A encomenda foi entregue."]];
const NOME={aprovacao:"Pedido aceite",agendamento:"Recolha a agendar",recolha:"Em recolha",armazenamento:"No armazém",expedicao:"A preparar a saída",em_transito:"Em viagem",
  destino:"Chegou ao destino",disponivel:"Pronta a levantar",entregue:"Entregue",cancelada:"Cancelada"};
const dia=v=>{if(!v)return"";const d=new Date(String(v).length===10?v+"T12:00":v);return isNaN(d)?"":d.toLocaleDateString("pt-PT",{day:"numeric",month:"long",year:"numeric"})};
const curta=v=>{if(!v)return"";const d=new Date(v);return isNaN(d)?"":d.toLocaleDateString("pt-PT",{day:"2-digit",month:"2-digit"})};
const quando=v=>{const d=new Date(v);if(isNaN(d))return"";const h=Math.floor((Date.now()-d)/36e5);return h<1?"há menos de 1 hora":h<24?`há ${h} ${h===1?"hora":"horas"}`:`a ${d.toLocaleDateString("pt-PT",{day:"numeric",month:"long"})}`};
async function perguntar(codigo){const c=window.ELOLOG_SERVIDOR||{},url=String(c.supabaseUrl||"").replace(/\/$/,""),k=c.supabaseAnonKey||"";
  if(!/^https:\/\//.test(url)||k.length<20)throw new Error("indisponivel");
  const r=await fetch(url+"/rest/v1/rpc/rastrear_encomenda",{method:"POST",headers:{"Content-Type":"application/json",apikey:k,Authorization:"Bearer "+k},body:JSON.stringify({p_codigo:codigo})});
  if(!r.ok)throw new Error("servidor");return r.json()}
function fluxo(d){const atual=FASES.findIndex(f=>f[1].includes(d.estado)),datas={};(d.etapas||[]).forEach(e=>{const i=FASES.findIndex(f=>f[1].includes(e.etapa));if(i>=0&&!datas[i])datas[i]=e.data});
  return`<ol class="rt-fluxo">${FASES.map(([t,,txt],i)=>{const k=i<atual||d.estado==="entregue"?"feito":i===atual?"atual":"";
    return`<li class="${k}"><span class="rt-ponto" aria-hidden="true"></span><div><b>${t}</b>${datas[i]&&k?`<small>${curta(datas[i])}</small>`:""}${k==="atual"?`<p>${txt}</p>`:""}</div></li>`}).join("")}</ol>`}
function desenhar(box,d,codigo){box.classList.remove("hidden");
  if(!d?.encontrada){const m={formato:`Confirme o código: tem a forma ELO_XXXX-000123 (o código que recebeu quando a encomenda foi criada).`,
      nao_existe:`Não encontrámos a encomenda ${esc(codigo)}. Confirme o código ou fale com o prestador.`,limite:"Fez muitas pesquisas seguidas. Tente de novo daqui a alguns minutos."};
    box.innerHTML=`<div class="rt-aviso">${m[d?.motivo]||m.nao_existe}</div>`;return}
  const canc=d.estado==="cancelada",chegada=d.chegada_prevista?dia(d.chegada_prevista):"";
  box.innerHTML=`<div class="rt-topo"><div><small>Encomenda</small><strong class="rt-codigo">${esc(d.codigo)}</strong></div><span class="rt-estado ${canc?"canc":d.suspensa?"susp":d.estado==="entregue"?"fim":""}">${canc?"Cancelada":d.suspensa?"Suspensa":esc(NOME[d.estado]||d.estado)}</span></div>
    <div class="rt-dados"><div><small>Percurso</small><b>${esc(d.origem||"—")} → ${esc(d.destino||"—")}</b></div>
      <div><small>${d.estado==="entregue"?"Entregue":"Chegada prevista"}</small><b>${d.estado==="entregue"?"Concluída":chegada||(["aprovacao","agendamento","recolha","armazenamento"].includes(d.estado)?"A confirmar quando houver viagem marcada":"A confirmar")}</b></div></div>
    ${canc?`<div class="rt-aviso">Esta encomenda foi cancelada. Para mais informação, fale com o prestador.</div>`:fluxo(d)}
    ${d.suspensa&&!canc?`<div class="rt-aviso">A encomenda está suspensa. O prestador vai retomá-la ou contactar o cliente.</div>`:""}
    <p class="rt-nota">Última atualização ${esc(quando(d.atualizada))}. Para documentos e pagamentos, entre na <a href="../app/area-cliente.html">Área de Cliente</a>.</p>`}
window.elologRastreio=async function(codigo,box){if(!box)return;const b=document.querySelector("#form-rastreio .btn-search");box.classList.remove("hidden");box.innerHTML=`<div class="rt-aviso">A procurar ${esc(codigo)}…</div>`;if(b)b.disabled=true;
  try{desenhar(box,await perguntar(codigo),codigo)}catch(e){box.innerHTML=`<div class="rt-aviso">${e.message==="indisponivel"?"O rastreio não está disponível neste momento.":"Não foi possível contactar o servidor. Tente de novo daqui a pouco."} Também pode ver a encomenda na <a href="../app/area-cliente.html">Área de Cliente</a>.</div>`}
  finally{if(b)b.disabled=false}};
})();
