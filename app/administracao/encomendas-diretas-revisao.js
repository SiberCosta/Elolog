/* Elolog — Revisão administrativa das encomendas diretas (v99).
   A administração vê o comprovativo (e os documentos adicionais) antes de validar, corrige dados administrativos,
   pede documentos ao cliente e valida/encaminha ao prestador escolhido pelo cliente. Cada passo fica no percurso. */
(function(){"use strict";
const D=()=>window.elologED,P=()=>window.elologProducao,esc=v=>D().esc(v);
const aviso=(t,k)=>window.showPlatformNotice?.(t,k||"info");
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const ANTES_ENVIO=["pendente_validacao","em_analise_admin","validada"];

/* ---------- analisar: comprovativo ao lado dos dados, com as decisões ---------- */
async function rever(e,depois){const j=P().janela({eyebrow:"ENCOMENDA DIRETA "+e.codigo,titulo:"Analisar comprovativo e validar"});
  const docs=[{d:e.documento,t:"Comprovativo"},...(e.anexos||[]).map((a,i)=>({d:a,t:"Documento adicional "+(i+1)}))].filter(x=>x.d);
  const resumo=`<dl class="ed-dados ed-rev-dados"><div><dt>Cliente</dt><dd>${esc(e.cliente_nome)}${e.cliente_email?`<br><small>${esc(e.cliente_email)}</small>`:""}</dd></div>
    <div><dt>Prestador escolhido</dt><dd>${esc(e.prestador)}</dd></div><div><dt>Rota</dt><dd>${esc(e.origem)} → ${esc(e.destino)}</dd></div>
    <div><dt>Mercadoria</dt><dd>${esc(e.mercadoria)}</dd></div><div><dt>Volumes</dt><dd>${esc(e.volumes)}${e.peso_kg?`, ${esc(e.peso_kg)} kg`:""}${e.volume_m3?`, ${esc(e.volume_m3)} m³`:""}</dd></div>
    <div><dt>Valor acordado</dt><dd>${eur(e.valor_acordado)}</dd></div><div><dt>Data prevista</dt><dd>${esc(D().data(e.data_prevista))}</dd></div></dl>
    ${e.observacoes?`<p class="ed-obs">${esc(e.observacoes)}</p>`:""}${e.pedido_documentos?`<p class="ed-pedido"><b>À espera do cliente:</b> ${esc(e.pedido_documentos)}</p>`:""}`;
  const pode=ANTES_ENVIO.includes(e.estado),aval=["pendente_validacao","em_analise_admin"].includes(e.estado);
  const fim=async(t,fn)=>{try{await fn();j.fechar();aviso(t,"success");depois()}catch(x){aviso(D().erro(x),"error")}};
  const botoes=[{texto:"Fechar",acao:()=>j.fechar()}];
  if(pode){botoes.push({texto:"Corrigir dados",acao:()=>corrigir(e,depois)},{texto:"Pedir documentos",acao:()=>pedir(e,depois)})}
  if(aval&&e.pedido_documentos)botoes.push({texto:"Não validar",acao:()=>naoValidar(e,depois)});
  if(aval&&!e.pedido_documentos){botoes.push({texto:"Não validar",acao:()=>naoValidar(e,depois)},{texto:"Validar",acao:()=>fim("Encomenda validada. Pode enviá-la ao prestador.",()=>D().admin(e.id,"validar"))},
    {texto:"Validar e encaminhar",principal:true,acao:()=>fim(`Validada e enviada a ${e.prestador}.`,()=>D().admin(e.id,"validar_enviar"))})}
  if(e.estado==="validada")botoes.push({texto:"Encaminhar ao prestador",principal:true,acao:()=>fim(`Encomenda enviada a ${e.prestador}.`,()=>D().admin(e.id,"enviar"))});
  j.mostrar(`<div class="ed-rev"><div class="ed-rev-doc">${docs.length>1?`<div class="ed-rev-tabs" role="tablist">${docs.map((x,i)=>`<button type="button" class="pa-periodo ${i?"":"ativo"}" data-doc="${i}">${esc(x.t)}</button>`).join("")}</div>`:""}
    <div class="ed-rev-prev"><p class="ed-vazio">A abrir o comprovativo…</p></div></div><div class="ed-rev-info">${resumo}
    <p class="ed-rev-nota">${e.pedido_documentos?"Pode validar depois de o cliente enviar os documentos pedidos.":aval?"A abertura do comprovativo fica registada; só depois é possível validar.":""}</p></div></div>`,botoes);
  const mostra=async i=>{const c=j.corpo.querySelector(".ed-rev-prev");c.innerHTML='<p class="ed-vazio">A abrir…</p>';
    j.corpo.querySelectorAll("[data-doc]").forEach(b=>b.classList.toggle("ativo",+b.dataset.doc===i));
    try{c.innerHTML=docs.length?await D().previsao(docs[i].d):'<p class="ed-vazio">Sem comprovativo.</p>';if(i===0&&docs.length){await D().visto(e.id);
      if(e.estado==="pendente_validacao"){await D().admin(e.id,"analisar");e.estado="em_analise_admin"}}}catch(x){c.innerHTML=`<p class="campo-erro">${esc(D().erro(x))}</p>`}};
  j.corpo.addEventListener("click",ev=>{const b=ev.target.closest("[data-doc]");if(b)mostra(+b.dataset.doc)});
  await mostra(0);depois(true)}

/* ---------- corrigir dados administrativos (o prestador mantém-se: só o cliente o muda) ---------- */
function corrigir(e,depois){const j=P().janela({eyebrow:"ENCOMENDA DIRETA "+e.codigo,titulo:"Corrigir dados administrativos"});
  const c=(id,rot,val,tipo,x)=>`<div class="pc-campo"><label for="${id}">${rot}</label><input id="${id}" type="${tipo||"text"}" value="${esc(val??"")}" ${x||""}></div>`;
  j.mostrar(`<p class="ed-intro">O prestador continua a ser o escolhido pelo cliente. As alterações ficam no percurso (antes → depois) e o cliente é avisado.</p><div class="pc-grelha">
    ${c("ecOrig","Origem",e.origem,"text",'maxlength="120"')}${c("ecDest","Destino",e.destino,"text",'maxlength="120"')}
    <div class="pc-campo ed-largo"><label for="ecMerc">Mercadoria</label><input id="ecMerc" maxlength="300" value="${esc(e.mercadoria)}"></div>
    ${c("ecVol","Volumes",e.volumes,"number",'min="1" step="1"')}${c("ecPeso","Peso (kg)",e.peso_kg,"number",'min="0" step="0.1"')}${c("ecM3","Volume (m³)",e.volume_m3,"number",'min="0" step="0.01"')}
    ${c("ecValor","Valor acordado (€)",e.valor_acordado,"number",'min="0" step="0.01"')}${c("ecData","Data prevista",e.data_prevista?String(e.data_prevista).slice(0,10):"","date")}
    <div class="pc-campo ed-largo"><label for="ecObs">Observações</label><textarea id="ecObs" rows="2" maxlength="1000">${esc(e.observacoes||"")}</textarea></div>
    <div class="pc-campo ed-largo"><label for="ecNota">Razão da correção</label><input id="ecNota" maxlength="200" placeholder="Ex.: valor confirmado com o prestador"></div></div><p class="campo-erro" id="ecErro" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Guardar correção",principal:true,acao:async()=>{const v=id=>(document.getElementById(id).value||"").trim(),n=id=>v(id)===""?null:Number(v(id).replace(",","."));
      const novo={origem:v("ecOrig"),destino:v("ecDest"),mercadoria:v("ecMerc"),volumes:Math.round(n("ecVol")||0),peso_kg:n("ecPeso"),volume_m3:n("ecM3"),valor_acordado:n("ecValor"),data_prevista:v("ecData")||null,observacoes:v("ecObs")||null};
      const antes={origem:e.origem,destino:e.destino,mercadoria:e.mercadoria,volumes:e.volumes,peso_kg:e.peso_kg,volume_m3:e.volume_m3,valor_acordado:e.valor_acordado,data_prevista:e.data_prevista?String(e.data_prevista).slice(0,10):null,observacoes:e.observacoes||null};
      const mud={};Object.keys(novo).forEach(k=>{const a=antes[k]==null?"":String(antes[k]),b=novo[k]==null?"":String(novo[k]);if((typeof novo[k]==="number"&&antes[k]!=null?Number(antes[k])!==novo[k]:a!==b))mud[k]=novo[k]});
      const er=document.getElementById("ecErro");if(!Object.keys(mud).length){er.textContent="Não há alterações.";return}
      if(mud.volumes!=null&&!(mud.volumes>=1)){er.textContent="Indique pelo menos 1 volume.";return}if(!novo.origem||!novo.destino||novo.mercadoria.length<2){er.textContent="Origem, destino e mercadoria são obrigatórios.";return}
      try{await D().corrigir(e.id,mud,v("ecNota"));j.fechar();aviso("Dados corrigidos. O cliente foi avisado.","success");depois()}catch(x){er.textContent=D().erro(x)}}}])}

/* ---------- pedir documentos adicionais ao cliente ---------- */
function pedir(e,depois){const j=P().janela({eyebrow:"ENCOMENDA DIRETA "+e.codigo,titulo:"Pedir documentos ao cliente"});
  const SUG=["Fatura pró-forma da mercadoria","Lista de volumes (packing list)","Documento de identificação do destinatário","Comprovativo de pagamento ao prestador"];
  j.mostrar(`<p class="ed-intro">O cliente recebe o pedido na Área de Cliente e envia os documentos. Não é possível validar enquanto o pedido estiver em aberto.</p>
    <div class="ed-sug">${SUG.map(t=>`<button type="button" class="pa-periodo" data-sug="${esc(t)}">+ ${esc(t)}</button>`).join("")}</div>
    <div class="pc-campo"><label for="epTxt">Documentos pedidos *</label><textarea id="epTxt" rows="3" maxlength="500"></textarea></div><p class="campo-erro" id="epErro" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Enviar pedido ao cliente",principal:true,acao:async()=>{const t=(document.getElementById("epTxt").value||"").trim();
      if(t.length<5){document.getElementById("epErro").textContent="Indique que documentos são precisos.";return}
      try{await D().admin(e.id,"pedir_documentos",t);j.fechar();aviso("Pedido enviado ao cliente.","success");depois()}catch(x){document.getElementById("epErro").textContent=D().erro(x)}}}]);
  j.corpo.addEventListener("click",ev=>{const b=ev.target.closest("[data-sug]");if(!b)return;const a=document.getElementById("epTxt");a.value=(a.value?a.value.replace(/\s*$/,"; "):"")+b.dataset.sug;a.focus()})}

function naoValidar(e,depois){const j=P().janela({eyebrow:"ENCOMENDA DIRETA "+e.codigo,titulo:"Não validar"});
  j.mostrar(`<p>O cliente recebe este motivo e pode juntar documentos ou escolher outro prestador.</p><div class="pc-campo"><label for="nvTxt">Motivo *</label><textarea id="nvTxt" rows="3" maxlength="500"></textarea></div><p class="campo-erro" id="nvErro" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Não validar",principal:true,acao:async()=>{const t=(document.getElementById("nvTxt").value||"").trim();
      if(t.length<5){document.getElementById("nvErro").textContent="Indique o motivo (mínimo 5 caracteres).";return}
      try{await D().admin(e.id,"nao_validar",t);j.fechar();aviso("Cliente avisado da não validação.","info");depois()}catch(x){document.getElementById("nvErro").textContent=D().erro(x)}}}])}

window.elologEDRevisao={rever,corrigir,pedir,naoValidar};
})();
