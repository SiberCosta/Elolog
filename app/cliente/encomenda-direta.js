/* Elolog — Área de Cliente: «Registar encomenda direta» (v98).
   O cliente escolhe um prestador ativo e elegível para a rota, anexa o comprovativo da negociação direta e acompanha a validação
   da administração e a decisão do prestador. Depois de uma recusa só o próprio cliente escolhe outro prestador. */
(function(){"use strict";
const D=()=>window.elologED,P=()=>window.elologProducao,esc=v=>D().esc(v);
const aviso=(t,k)=>window.showPlatformNotice?.(t,k||"info");
const campo=(id,rot,tipo,x)=>`<div class="pc-campo"><label for="${id}">${rot}</label><input id="${id}" type="${tipo||"text"}" ${x||""}></div>`;
const v=id=>(document.getElementById(id)?.value||"").trim(),num=id=>{const t=v(id).replace(",",".");return t===""?null:Number(t)};
const hoje=()=>new Date().toISOString().slice(0,10);

async function opcoes(sel,origem,destino,excluir){sel.innerHTML='<option value="">A carregar…</option>';
  try{const l=(await D().prestadores(origem,destino)).filter(p=>p.id!==excluir);
    sel.innerHTML=l.length?'<option value="">Escolha o prestador…</option>'+l.map(p=>`<option value="${esc(p.id)}">${esc(p.nome)}${p.cidade?" · "+esc(p.cidade):""}</option>`).join("")
      :'<option value="">Nenhum prestador ativo serve esta rota</option>'}catch(e){sel.innerHTML=`<option value="">${esc(D().erro(e))}</option>`}}

function nova(){if(!P()||!D())return;
  const j=P().janela({eyebrow:"ENCOMENDA DIRETA",titulo:"Registar encomenda direta"});
  j.mostrar(`<p class="ed-intro">Já negociou com um prestador da Elolog? Registe aqui. A administração valida o comprovativo e encaminha ao prestador, que aceita ou recusa.</p>
  <div class="pc-grelha">
    ${campo("edOrigem","Origem (local de recolha) *","text",'maxlength="120" placeholder="Ex.: Lisboa"')}${campo("edDestino","Destino (local de entrega) *","text",'maxlength="120" placeholder="Ex.: São Tomé"')}
    <div class="pc-campo ed-largo"><label for="edPrest">Prestador *</label><select id="edPrest"></select><small class="campo-ajuda">Só aparecem prestadores ativos que servem a rota.</small></div>
    <div class="pc-campo ed-largo"><label for="edMerc">Mercadoria *</label><input id="edMerc" maxlength="300" placeholder="Descrição da carga"></div>
    ${campo("edVol","Quantidade (volumes) *","number",'min="1" step="1" value="1"')}${campo("edPeso","Peso (kg)","number",'min="0" step="0.1"')}
    ${campo("edM3","Volume (m³)","number",'min="0" step="0.01"')}${campo("edValor","Valor acordado (€) *","number",'min="0" step="0.01"')}
    ${campo("edData","Data prevista","date",`min="${hoje()}"`)}
    <div class="pc-campo"><label for="edDoc">Comprovativo *</label><input id="edDoc" type="file" accept=".pdf,.jpg,.jpeg,.png"><small class="campo-ajuda">Proposta, orçamento, recibo ou documento de transporte.</small></div>
    <div class="pc-campo ed-largo"><label for="edObs">Observações</label><textarea id="edObs" rows="2" maxlength="1000"></textarea></div>
  </div><p class="campo-erro" id="edErro" role="alert"></p>`,
  [{texto:"Cancelar",acao:()=>j.fechar()},{texto:"Submeter para validação",principal:true,acao:async()=>{const erro=document.getElementById("edErro");erro.textContent="";
    const d={origem:v("edOrigem"),destino:v("edDestino"),empresa:v("edPrest"),mercadoria:v("edMerc"),volumes:Math.round(num("edVol")||0),peso_kg:num("edPeso"),volume_m3:num("edM3"),
      valor:num("edValor"),data:v("edData")||null,observacoes:v("edObs")},f=document.getElementById("edDoc").files[0];
    const falta=!d.origem||!d.destino?"Indique a origem e o destino.":!d.empresa?"Escolha o prestador da lista.":d.mercadoria.length<2?"Descreva a mercadoria.":
      !(d.volumes>=1)?"Indique o número de volumes.":d.valor==null||d.valor<0?"Indique o valor acordado.":d.data&&d.data<hoje()?"A data prevista não pode ser no passado.":
      !f?"Anexe o comprovativo da negociação.":f.size>10*1024*1024?"O comprovativo tem mais de 10 MB.":"";
    if(falta){erro.textContent=falta;return}
    try{const r=await D().criar(d,f);j.fechar();aviso(`Encomenda direta ${r?.codigo||""} submetida. Fica «Pendente de validação» até a administração a analisar.`,"success");abrirPagina()}
    catch(e){erro.textContent=D().erro(e)}}}]);
  const sel=document.getElementById("edPrest");let t=0;const rec=()=>{clearTimeout(t);t=setTimeout(()=>opcoes(sel,v("edOrigem"),v("edDestino")),350)};
  ["edOrigem","edDestino"].forEach(id=>document.getElementById(id).addEventListener("input",rec));opcoes(sel,"","")}

function trocar(e){const j=P().janela({eyebrow:"ENCOMENDA "+e.codigo,titulo:"Escolher outro prestador"});
  j.mostrar(`<p>Rota ${esc(e.origem)} → ${esc(e.destino)}. A encomenda volta a ser validada pela administração antes de seguir para o novo prestador.</p>
    <div class="pc-campo"><label for="edNovo">Prestador</label><select id="edNovo"></select></div><p class="campo-erro" id="edErro2" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Confirmar",principal:true,acao:async()=>{const id=v("edNovo");if(!id){document.getElementById("edErro2").textContent="Escolha o prestador.";return}
      try{await D().cliente(e.id,"trocar_prestador",id);j.fechar();aviso("Novo prestador escolhido. A encomenda voltou à validação.","success");desenhar()}catch(x){document.getElementById("edErro2").textContent=D().erro(x)}}}]);
  opcoes(document.getElementById("edNovo"),e.origem,e.destino,e.empresa_id)}
function juntar(e){const j=P().janela({eyebrow:"ENCOMENDA "+e.codigo,titulo:e.pedido_documentos?"Enviar documentos pedidos":"Juntar documento"});
  j.mostrar(`${e.pedido_documentos?`<p class="ed-pedido"><b>A administração pediu:</b> ${esc(e.pedido_documentos)}</p>`:"<p>Junte um documento que ajude a validar a encomenda.</p>"}
    <div class="pc-campo"><label for="edAnexo">Ficheiro * <small>(PDF, JPG ou PNG até 10 MB)</small></label><input id="edAnexo" type="file" accept=".pdf,.jpg,.jpeg,.png"></div>
    <div class="pc-campo"><label for="edAnexoNota">Nota</label><input id="edAnexoNota" maxlength="300" placeholder="Ex.: fatura pró-forma"></div><p class="campo-erro" id="edErroA" role="alert"></p>`,
    [{texto:"Voltar",acao:()=>j.fechar()},{texto:"Enviar",principal:true,acao:async()=>{const f=document.getElementById("edAnexo").files[0],er=document.getElementById("edErroA");
      if(!f){er.textContent="Escolha o ficheiro.";return}if(f.size>10*1024*1024){er.textContent="O ficheiro tem mais de 10 MB.";return}
      try{await D().anexar(e.id,f,v("edAnexoNota"));j.fechar();aviso("Documento enviado. A administração foi avisada.","success");desenhar()}catch(x){er.textContent=D().erro(x)}}}])}
function cancelar(e){const j=P().janela({eyebrow:"ENCOMENDA "+e.codigo,titulo:"Cancelar encomenda direta"});
  j.mostrar("<p>A encomenda fica registada como cancelada (não é apagada). Confirma?</p>",[{texto:"Voltar",acao:()=>j.fechar()},
    {texto:"Cancelar encomenda",principal:true,acao:async()=>{try{await D().cliente(e.id,"cancelar");j.fechar();aviso("Encomenda cancelada.","info");desenhar()}catch(x){aviso(D().erro(x),"error")}}}])}

/* ---------- página «Encomendas diretas» ---------- */
let lista=[];
function pagina(){let s=document.getElementById("clientDirectOrders");if(s)return s;const base=document.getElementById("dashboard");if(!base)return null;
  s=document.createElement("section");s.id="clientDirectOrders";s.className="page";base.parentElement.appendChild(s);
  s.addEventListener("click",ev=>{const b=ev.target.closest("[data-ed]");if(!b)return;const e=lista.find(x=>String(x.id)===b.closest(".ed-cartao")?.dataset.id);if(!e)return;
    ({comprovativo:()=>D().comprovativo(e).catch(x=>aviso(D().erro(x),"error")),anexo:()=>D().comprovativo(e,+b.dataset.i).catch(x=>aviso(D().erro(x),"error")),
      juntar:()=>juntar(e),trocar:()=>trocar(e),cancelar:()=>cancelar(e)})[b.dataset.ed]?.()});return s}
async function desenhar(){const s=pagina();if(!s)return;
  s.innerHTML=`<div class="ed-topo"><div><h2>Encomendas diretas</h2><p>Encomendas negociadas diretamente com um prestador, validadas pela Elolog.</p></div>
    <button type="button" class="btn-primary" onclick="elologEncDireta.nova()">Registar encomenda direta</button></div><div class="ed-lista"><p class="ed-vazio">A carregar…</p></div>`;
  try{lista=await D().listar()}catch(e){s.querySelector(".ed-lista").innerHTML=`<p class="campo-erro">${esc(D().erro(e))}</p>`;return}
  s.querySelector(".ed-lista").innerHTML=lista.length?lista.map(e=>D().cartao(e,(["pendente_validacao","em_analise_admin","validada","nao_validada"].includes(e.estado)?
    `<button type="button" class="${e.pedido_documentos?"btn-primary":"btn-secondary"}" data-ed="juntar">${e.pedido_documentos?"Enviar documentos pedidos":"Juntar documento"}</button>`:"")+(["recusada","nao_validada"].includes(e.estado)?'<button type="button" class="btn-primary" data-ed="trocar">Escolher outro prestador</button>':"")+
    (["pendente_validacao","em_analise_admin","nao_validada","recusada"].includes(e.estado)?'<button type="button" class="btn-secondary" data-ed="cancelar">Cancelar</button>':""))).join("")
    :'<p class="ed-vazio">Ainda não registou encomendas diretas.</p>'}
function abrirPagina(){pagina();showPage("clientDirectOrders",document.getElementById("menuDirectOrders"));desenhar()}

/* ---------- menu: «Encomendas diretas», a seguir a «Encomendas» ---------- */
function menu(){const ref=document.getElementById("menuOrders");if(!ref)return;let b=document.getElementById("menuDirectOrders");
  if(!b){b=document.createElement("button");b.id="menuDirectOrders";b.type="button";b.onclick=function(){abrirPagina.call(this)};
    b.innerHTML='<svg class="mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h12l4 4v6H4z"/><path d="M8 11h5M8 14h8"/><path d="m14 3 3 3-3 3"/></svg>Encomendas diretas';
    (document.getElementById("clientOrdersSubmenu")||ref).after(b)}b.style.order=getComputedStyle(document.getElementById("clientOrdersSubmenu")||ref).order;b.style.display=(typeof currentUser!=="undefined"&&currentUser?.role==="cliente")?"":"none"}
const conf=window.configureRole;if(typeof conf==="function")window.configureRole=function(){const r=conf.apply(this,arguments);try{menu()}catch(_){}return r};
window.elologEncDireta={nova,abrir:abrirPagina,desenhar};
})();
