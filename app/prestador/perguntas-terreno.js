/* Elolog — perguntas da equipa de terreno num formulário da aplicação (v134), em vez da caixa nativa do navegador (prompt).
   Abre o painel lateral com os campos; ao confirmar, chama a função original com as respostas já dadas (a lógica existente
   não muda). Cobre: adicionar viatura, informação adicional de um pedido de apoio, cliente ausente, assinatura/PIN e ocorrência. */
(function(){"use strict";
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
let pendente=null;

/** perguntas: [{rotulo, valor, obrigatorio, longo}] → Promise<string[]|null> */
function perguntar(titulo,perguntas,botao){return new Promise(ok=>{
  if(typeof openPlatformRecordDrawer!=="function"){ok(perguntas.map(q=>window.prompt(q.rotulo,q.valor||"")));return}
  pendente?.(null);pendente=ok;
  const campos=perguntas.map((q,i)=>`<label class="${q.longo?"wide":""}">${esc(q.rotulo)}${q.obrigatorio?" *":""}${q.longo
      ?`<textarea name="r${i}" ${q.obrigatorio?'required minlength="2"':""}>${esc(q.valor||"")}</textarea>`
      :`<input name="r${i}" value="${esc(q.valor||"")}" ${q.obrigatorio?"required":""} autocomplete="off">`}</label>`).join("");
  openPlatformRecordDrawer(titulo,"EQUIPA DE TERRENO",`<form class="admin-provider-form" id="ptForm"><section class="admin-provider-form-section"><div class="admin-provider-form-grid">${campos}</div></section>
    <div class="admin-provider-form-actions"><button type="button" class="btn-secondary" id="ptCancelar">Cancelar</button><button type="submit" class="btn-primary">${esc(botao||"Guardar")}</button></div></form>`);
  const f=document.getElementById("ptForm");if(!f){pendente=null;ok(null);return}
  const fim=v=>{if(pendente!==ok)return;pendente=null;try{closeProviderDrawer("platformRecordDrawer")}catch(_){}ok(v)};
  f.onsubmit=e=>{e.preventDefault();if(!f.reportValidity())return;fim(perguntas.map((_,i)=>String(f.elements["r"+i].value||"").trim()))};
  document.getElementById("ptCancelar").onclick=()=>fim(null);
  setTimeout(()=>f.querySelector("input,textarea")?.focus(),50)})}

/* chama a função original com as respostas: cada prompt() que ela fizer recebe a resposta seguinte */
function comRespostas(respostas,chamar,manter){const fila=[...respostas],orig=window.prompt;let ativo=true;const repor=()=>{if(ativo){ativo=false;if(window.prompt===falso)window.prompt=orig}};
  const falso=()=>{const v=fila.length?fila.shift():null;if(!fila.length)repor();return v};window.prompt=falso;
  /* manter: a função original ainda pode perguntar mais tarde (ex.: quando o GPS falha); a resposta já dada fica à espera até lá */
  try{return chamar()}finally{if(manter&&fila.length)setTimeout(repor,manter);else repor()}}

function envolver(nome,construir){const f=window[nome];if(typeof f!=="function"||f.__pt)return;
  const novo=function(...a){const pedido=construir(...a);if(!pedido)return f.apply(this,a);
    perguntar(pedido.titulo,pedido.perguntas,pedido.botao).then(r=>{if(r)comRespostas(r,()=>f.apply(this,a),pedido.manter)})};
  novo.__pt=1;window[nome]=novo}

function ligar(){
  envolver("addFieldVehicle",()=>({titulo:"Adicionar viatura",botao:"Adicionar viatura",perguntas:[{rotulo:"Matrícula",obrigatorio:true},{rotulo:"Tipo de viatura",valor:"Carrinha"}]}));
  envolver("addFieldSupportMessage",()=>({titulo:"Informação adicional",botao:"Enviar",perguntas:[{rotulo:"Informação adicional",obrigatorio:true,longo:true}]}));
  envolver("registerFieldClientAbsent",id=>{let morada="",j=null;try{j=getFieldJobs().find(x=>x.id===id);morada=fieldJobOperation(j)?.pickupAddress||""}catch(_){}
    if(!j||j.status!=="No local"||j.absences?.some(x=>Date.now()-Date.parse(x.at)<6e4))return null;   /* a função original explica o que falta (ex.: «Cheguei ao local») */
    return{titulo:"Cliente ausente",botao:"Registar ausência",manter:20000,perguntas:[{rotulo:"Observação da tentativa de recolha",valor:"Cliente não se encontrava no local.",longo:true},
      {rotulo:"Local da tentativa (usado só se o GPS não responder)",valor:morada}]}});
  envolver("fieldJobAction",(id,acao)=>acao==="signature"?{titulo:"Assinatura ou PIN",botao:"Registar",perguntas:[{rotulo:"Nome de quem assina ou PIN de validação",obrigatorio:true}]}
    :acao==="incident"?{titulo:"Registar ocorrência",botao:"Registar ocorrência",perguntas:[{rotulo:"Descreva o problema ou a ocorrência",obrigatorio:true,longo:true}]}:null)}
ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);window.addEventListener("load",ligar);
window.elologPerguntas={perguntar};
})();
