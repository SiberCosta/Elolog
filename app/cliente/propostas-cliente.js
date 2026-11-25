/* Elolog — preços para o cliente aceitar (v179, auditoria A-14).
   Quando o prestador indica um preço que o cliente ainda não viu (pedido de cotação, ou preço acima do calculado), o servidor
   guarda uma proposta «enviada» (válida 7 dias) em vez de criar logo a encomenda. Aqui o cliente vê-a no Início e decide:
   «Aceitar» (aceitar_proposta → a encomenda é criada a esse preço) ou «Recusar» (recusar_proposta, com motivo opcional;
   o prestador pode indicar outro preço). Sem propostas por decidir, nada aparece. */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k||"info"):alert(t);
const eur=(v,m)=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:m||"EUR"});
const dia=v=>v?new Date(v+"T12:00").toLocaleDateString("pt-PT",{day:"numeric",month:"long"}):"";
let lista=[],ocupado=false;
const cliente=()=>typeof currentUser!=="undefined"&&currentUser?.role==="cliente";

function desenhar(){const pag=$("dashboard");if(!pag)return;let box=$("propostasCliente");
  if(!lista.length){box?.remove();return}
  if(!box){box=document.createElement("section");box.id="propostasCliente";box.className="card pc-cartao";pag.prepend(box)}
  box.innerHTML=`<header><h3>${lista.length===1?"Tem um preço para aceitar":"Tem "+lista.length+" preços para aceitar"}</h3>
    <p>O prestador indicou o preço do seu pedido. A encomenda só é criada se aceitar.</p></header>
    ${lista.map(p=>`<div class="pc-linha"><div><strong>${esc(eur(p.preco,p.moeda))}</strong>
      <small>${esc(p.simulacoes?.codigo||"")}${p.simulacoes?` · ${esc(p.simulacoes.origem)} → ${esc(p.simulacoes.destino)}`:""}${p.validade?` · válido até ${esc(dia(p.validade))}`:""}</small>
      ${p.mensagem?`<p>${esc(p.mensagem)}</p>`:""}</div>
      <span class="pc-acoes"><button type="button" class="btn-secondary" data-pc-recusar="${esc(p.id)}">Recusar</button><button type="button" class="btn-primary" data-pc-aceitar="${esc(p.id)}">Aceitar ${esc(eur(p.preco,p.moeda))}</button></span></div>`).join("")}`}
async function carregar(){if(!cliente()||!S()?.ativo?.())return;
  try{const sb=await S().cliente();const hoje=new Date().toISOString().slice(0,10);
    const{data,error}=await sb.from("propostas").select("id,preco,moeda,validade,mensagem,simulacoes(codigo,origem,destino)").eq("estado","enviada").or(`validade.is.null,validade.gte.${hoje}`).order("created_at",{ascending:false}).limit(10);
    if(error)throw error;lista=data||[];desenhar()}catch(_){/* sem propostas: nada muda */}}
async function decidir(id,aceitar){if(ocupado)return;ocupado=true;const sb=await S().cliente();
  try{if(aceitar){const{data,error}=await sb.rpc("aceitar_proposta",{p_proposta:id});if(error)throw error;const e=Array.isArray(data)?data[0]:data;
      aviso(`Aceite. Encomenda ${e?.codigo||""} criada; o prestador trata da aprovação.`,"success")}
    else{const motivo=document.querySelector(`[data-pc-motivo="${id}"]`)?.value.trim()||null;
      const{error}=await sb.rpc("recusar_proposta",{p_proposta:id,p_motivo:motivo});if(error)throw error;aviso("Preço recusado. O prestador pode indicar outro.","info")}
    await carregar();window.elologAtualizarCliente?.()}
  catch(e){aviso(S()?.mensagem?.(e)||e.message,"error")}finally{ocupado=false}}
document.addEventListener("click",e=>{const a=e.target.closest("[data-pc-aceitar]"),r=e.target.closest("[data-pc-recusar]");
  const c=e.target.closest("[data-pc-confirmar]"),v=e.target.closest("[data-pc-voltar]");
  if(a){a.disabled=true;decidir(a.dataset.pcAceitar,true).finally(()=>{a.disabled=false})}
  else if(r){const id=r.dataset.pcRecusar;r.closest(".pc-acoes").innerHTML=`<label class="pc-motivo">Motivo (opcional)<input data-pc-motivo="${esc(id)}" maxlength="300" placeholder="Ex.: acima do meu orçamento"></label><button type="button" class="btn-secondary" data-pc-voltar>Voltar</button><button type="button" class="btn-primary" data-pc-confirmar="${esc(id)}">Recusar preço</button>`;document.querySelector(`[data-pc-motivo="${id}"]`)?.focus()}
  else if(c)decidir(c.dataset.pcConfirmar,false);else if(v)desenhar()});
const ini=window.startApp;if(typeof ini==="function")window.startApp=async function(){const r=await ini.apply(this,arguments);setTimeout(carregar,1300);return r};
setTimeout(carregar,2800);setInterval(()=>{if(document.visibilityState==="visible")carregar()},120000);window.elologPropostasCliente={carregar};
})();
