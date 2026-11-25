/* Elolog — o cliente avalia o prestador depois da entrega (v172, migração 00205).
   No Início do cliente aparece «Avalie os seus envios» com as encomendas entregues nos últimos 120 dias que ainda não avaliou.
   Estrelas de 1 a 5 (obrigatório), três critérios opcionais (pontualidade, comunicação, cuidado com a carga) e comentário curto.
   Grava pela função avaliar_prestador (o servidor confirma que a encomenda é do cliente e está entregue). Pode corrigir até 30 dias. */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k||"info"):alert(t);
const CRIT=[["pontualidade","Pontualidade"],["comunicacao","Comunicação"],["cuidado","Cuidado com a carga"]];
let lista=[],aberta=null;
const cliente=()=>typeof currentUser!=="undefined"&&currentUser?.role==="cliente";
const escala=(nome,rot,v,grande)=>`<fieldset class="av-escala${grande?" grande":""}"><legend>${rot}</legend>${[1,2,3,4,5].map(n=>`<label><input type="radio" name="${nome}" value="${n}" ${+v===n?"checked":""}><span aria-hidden="true">★</span><b class="av-sr">${n} ${n===1?"estrela":"estrelas"}</b></label>`).join("")}</fieldset>`;

function desenhar(){const pag=$("dashboard");if(!pag)return;let box=$("avaliarEnvios");
  const pend=lista.filter(x=>x.nota==null),feitas=lista.filter(x=>x.nota!=null&&x.pode_corrigir);
  if(!pend.length&&!aberta){box?.remove();return}
  if(!box){box=document.createElement("section");box.id="avaliarEnvios";box.className="card av-cartao";pag.prepend(box)}
  const item=x=>`<div class="av-linha"><div><strong>${esc(x.prestador)}</strong><small>${esc(x.codigo||"")} · ${esc(x.origem||"")} → ${esc(x.destino||"")}</small></div>
    <button type="button" class="btn-secondary" data-av-abrir="${esc(x.encomenda_id)}">${x.nota!=null?"Corrigir":"Avaliar"}</button></div>`;
  const form=aberta?(()=>{const x=lista.find(l=>l.encomenda_id===aberta);if(!x)return"";
    return`<form class="av-form" data-av-form="${esc(x.encomenda_id)}"><h4>Como correu o envio com ${esc(x.prestador)}?</h4>${escala("nota","Avaliação geral",x.nota,true)}
      <div class="av-crit">${CRIT.map(([k,t])=>escala(k,t,null)).join("")}</div>
      <label class="av-com">Comentário (opcional)<textarea name="comentario" maxlength="500" rows="2" placeholder="O que correu bem ou podia melhorar.">${esc(x.comentario||"")}</textarea></label>
      <div class="av-acoes"><button type="submit" class="btn-secondary">Enviar avaliação</button><button type="button" class="av-cancelar" data-av-fechar>Agora não</button></div></form>`})():"";
  box.innerHTML=`<header><h3>Avalie os seus envios</h3><p>A sua avaliação ajuda outros clientes a escolher e aparece no site (sem o seu nome).</p></header>
    ${form||`<div class="av-lista">${pend.slice(0,4).map(item).join("")}</div>${feitas.length?`<details class="av-feitas"><summary>Já avaliou ${feitas.length}</summary>${feitas.map(item).join("")}</details>`:""}`}`}
async function carregar(){if(!cliente()||!S()?.ativo?.())return;
  try{const sb=await S().cliente();const{data,error}=await sb.rpc("avaliacoes_minhas");if(error)throw error;lista=Array.isArray(data)?data:[];desenhar()}catch(_){}}
document.addEventListener("click",e=>{const a=e.target.closest("[data-av-abrir]");if(a){aberta=a.dataset.avAbrir;desenhar();$("avaliarEnvios")?.scrollIntoView({block:"nearest"});return}
  if(e.target.closest("[data-av-fechar]")){aberta=null;desenhar()}});
document.addEventListener("submit",async e=>{const f=e.target.closest("[data-av-form]");if(!f)return;e.preventDefault();
  const v=n=>+(f.querySelector(`input[name="${n}"]:checked`)?.value||0)||null;if(!v("nota"))return aviso("Escolha de 1 a 5 estrelas na avaliação geral.","warning");
  const btn=f.querySelector("[type=submit]");btn.disabled=true;
  try{const sb=await S().cliente();const{error}=await sb.rpc("avaliar_prestador",{p_encomenda:f.dataset.avForm,p_nota:v("nota"),p_pontualidade:v("pontualidade"),
      p_comunicacao:v("comunicacao"),p_cuidado:v("cuidado"),p_comentario:f.querySelector("textarea").value.trim()||null});if(error)throw error;
    aviso("Obrigado! A avaliação foi registada.","success");aberta=null;await carregar()}catch(err){btn.disabled=false;aviso(S()?.mensagem?.(err)||err.message,"error")}});
const ini=window.startApp;if(typeof ini==="function")window.startApp=async function(){const r=await ini.apply(this,arguments);setTimeout(carregar,1500);return r};
setTimeout(carregar,3000);window.elologAvaliar={carregar};
})();
