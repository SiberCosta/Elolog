/* Elolog — Ocorrências da encomenda e suspensão (v77).
   Fluxo: registo → classificação → responsável → resolução → comunicação ao cliente → encerramento.
   Uma ocorrência pode suspender a encomenda (o estado logístico mantém-se, mas não avança até «Retomar»).
   O cliente comunica problemas e vê as ocorrências que lhe foram comunicadas. O prestador pode juntar o despacho/manifesto
   feito por um despachante (documento «despacho»): o manifesto da plataforma deixou de ser obrigatório para «em trânsito».
   Servidor: migração 00147 (ocorrencia_criar / ocorrencia_atualizar / ocorrencias_da_encomenda / encomenda_suspender / encomenda_retomar). */
(function(){"use strict";
const P=()=>window.elologProducao,online=()=>!!P()?.online?.();
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(m,t)=>window.showPlatformNotice?window.showPlatformNotice(m,t||"info"):alert(m);
const eu=()=>typeof currentUser!=="undefined"?currentUser:null,ops=()=>typeof operations!=="undefined"&&Array.isArray(operations)?operations:[];
const TIPO={atraso:"Atraso",dano:"Dano na carga",perda:"Perda / falta de volumes",documentacao:"Documentação",alfandega:"Alfândega",pagamento:"Pagamento",endereco:"Morada / contacto",outro:"Outro"};
const GRAV={baixa:"Baixa",media:"Média",alta:"Alta",critica:"Crítica"},EST={aberta:"Aberta",em_resolucao:"Em resolução",resolvida:"Resolvida",encerrada:"Encerrada"};
const opcoes=(m,v)=>Object.entries(m).map(([k,t])=>`<option value="${k}"${k===v?" selected":""}>${esc(t)}</option>`).join("");
const quando=d=>new Date(d).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"});

/* ---- dados: servidor ou demonstração (navegador) ---- */
const CH="elolog_ocorrencias";const lerDemo=()=>{try{return JSON.parse(localStorage.getItem(CH)||"{}")}catch(_){return{}}},gravarDemo=d=>{try{localStorage.setItem(CH,JSON.stringify(d))}catch(_){}};
async function rpc(n,a){const c=await P().sb(),{data,error}=await c.rpc(n,a);if(error)throw new Error(error.message);return data}
function demoOp(cod){return ops().find(o=>o.id===cod)}
function salvarOps(){try{window.saveAll?.()}catch(_){}}
async function ler(cod){if(online())return rpc("ocorrencias_da_encomenda",{p_codigo:cod});const cli=eu()?.role==="cliente",o=demoOp(cod)||{};
  const lista=(lerDemo()[cod]||[]).filter(x=>!cli||x.visivel_cliente).map(x=>cli?{...x,registos:[]}:x);
  return{suspensa:!!o.suspended,motivo:o.suspendedReason||null,cliente:cli,pode_gerir:!cli&&eu()?.providerFunction!=="financeiro",equipa:(typeof getProviderEmployees==="function"?getProviderEmployees():[]).map(f=>({id:f.id,nome:f.name})),lista}}
function demoMudar(cod,fn){const d=lerDemo();d[cod]=d[cod]||[];fn(d[cod]);gravarDemo(d)}
function demoSuspender(cod,motivo,on){const o=demoOp(cod);if(!o)return;o.suspended=on;o.suspendedReason=on?motivo:null;salvarOps()}
async function criar(cod,f){if(online())return rpc("ocorrencia_criar",{p_codigo:cod,p_descricao:f.descricao,p_tipo:f.tipo,p_gravidade:f.gravidade,p_suspender:!!f.suspender,p_visivel_cliente:!!f.visivel});
  const cli=eu()?.role==="cliente",n=Object.values(lerDemo()).flat().length+1,x={id:"oc"+Date.now(),codigo:"ELO_OC-"+String(n).padStart(6,"0"),tipo:cli?"outro":f.tipo,gravidade:cli?"media":f.gravidade,estado:"aberta",descricao:f.descricao,
    visivel_cliente:cli||!!f.visivel,suspendeu:!cli&&!!f.suspender,do_cliente:cli,criada:new Date().toISOString(),registos:[{acao:cli?"Comunicada pelo cliente":"Registada",nota:f.descricao,quando:new Date().toISOString(),quem:eu()?.name||"—"}]};
  demoMudar(cod,l=>l.unshift(x));if(x.suspendeu)demoSuspender(cod,`Ocorrência ${x.codigo}: ${f.descricao}`,true);return x}
async function atualizar(cod,id,f){if(online())return rpc("ocorrencia_atualizar",{p_id:id,p_estado:f.estado||null,p_tipo:f.tipo||null,p_gravidade:f.gravidade||null,p_responsavel:f.responsavel||null,p_resolucao:f.resolucao||null,p_comunicar:!!f.comunicar,p_nota:f.nota||null});
  if(["resolvida","encerrada"].includes(f.estado)&&!(f.resolucao||"").trim()&&!((lerDemo()[cod]||[]).find(x=>x.id===id)?.resolucao))throw new Error("Descreva a resolução antes de resolver ou encerrar.");
  demoMudar(cod,l=>{const x=l.find(y=>y.id===id);if(!x)return;const resp=f.responsavel?(typeof getProviderEmployees==="function"?getProviderEmployees():[]).find(e=>e.id===f.responsavel)?.name:null;
    Object.assign(x,{estado:f.estado||x.estado,tipo:f.tipo||x.tipo,gravidade:f.gravidade||x.gravidade,resolucao:(f.resolucao||"").trim()||x.resolucao,visivel_cliente:x.visivel_cliente||!!f.comunicar},resp?{responsavel:resp,responsavel_id:f.responsavel}:{});
    x.registos.push({acao:`Estado: ${EST[x.estado]}${f.comunicar?" · Comunicada ao cliente":""}`,nota:f.nota||"",quando:new Date().toISOString(),quem:eu()?.name||"—"})})}
async function suspender(cod,motivo,on){if(online())return on?rpc("encomenda_suspender",{p_codigo:cod,p_motivo:motivo}):rpc("encomenda_retomar",{p_codigo:cod,p_nota:motivo||null});
  if(on&&(motivo||"").trim().length<3)throw new Error("Indique o motivo da suspensão.");demoSuspender(cod,motivo,on)}

/* ---- janela ---- */
let j=null,codigo="";
async function abrir(cod){if(!P()?.janela)return;codigo=cod;j=P().janela({eyebrow:"ENCOMENDA "+cod,titulo:"Ocorrências"});j.corpo.closest(".pm-caixa")?.classList.add("oc-janela");await pintar()}
async function pintar(){let d;try{d=await ler(codigo)}catch(e){j.mostrar(`<p>${esc(e.message)}</p>`,[{texto:"Fechar",acao:()=>j.fechar()}]);return}
  const g=d.pode_gerir,cli=d.cliente;
  const topo=d.suspensa?`<div class="oc-suspensa"><strong>⏸ Encomenda suspensa</strong><span>${esc(d.motivo||"")}</span>${g?'<button type="button" class="btn-secondary" data-retomar>Retomar</button>':""}</div>`
    :g?`<div class="oc-barra"><button type="button" class="btn-secondary" data-suspender>⏸ Suspender encomenda</button><span class="oc-motivo" hidden><input data-motivo maxlength="300" placeholder="Motivo da suspensão (o cliente é avisado)" aria-label="Motivo da suspensão"><button type="button" class="btn-primary" data-suspender-ok>Suspender</button></span><label class="btn-secondary oc-ficheiro">📎 Juntar despacho / manifesto do despachante<input type="file" accept=".pdf,.jpg,.jpeg,.png" data-despacho hidden></label></div>`:"";
  const lista=d.lista.length?d.lista.map(o=>`<article class="oc-item oc-${o.gravidade}"><header><strong>${esc(o.codigo)}</strong><span class="oc-estado oc-e-${o.estado}">${EST[o.estado]||o.estado}</span>
      ${cli?"":`<small>${esc(TIPO[o.tipo]||o.tipo)} · ${esc(GRAV[o.gravidade]||o.gravidade)}${o.responsavel?" · Responsável: "+esc(o.responsavel):""}${o.do_cliente?" · comunicada pelo cliente":""}${o.visivel_cliente?" · visível ao cliente":""}</small>`}</header>
    <p>${esc(o.descricao)}</p>${o.resolucao?`<p class="oc-resolucao"><b>Resolução:</b> ${esc(o.resolucao)}</p>`:""}
    ${(o.registos||[]).length?`<details><summary>Histórico (${o.registos.length})</summary><ol class="oc-hist">${o.registos.map(r=>`<li><time>${quando(r.quando)}</time> <b>${esc(r.quem)}</b> — ${esc(r.acao)}${r.nota?`: ${esc(r.nota)}`:""}</li>`).join("")}</ol></details>`:""}
    ${g&&o.estado!=="encerrada"?`<details class="oc-tratar"><summary>Tratar</summary><div class="oc-grelha" data-oc="${esc(o.id)}">
      <label>Estado<select data-f="estado">${opcoes(EST,o.estado)}</select></label><label>Tipo<select data-f="tipo">${opcoes(TIPO,o.tipo)}</select></label>
      <label>Gravidade<select data-f="gravidade">${opcoes(GRAV,o.gravidade)}</select></label><label>Responsável<select data-f="responsavel"><option value="">—</option>${d.equipa.map(e=>`<option value="${esc(e.id)}"${e.id===o.responsavel_id?" selected":""}>${esc(e.nome)}</option>`).join("")}</select></label>
      <label class="oc-larga">Resolução<textarea data-f="resolucao" rows="2" maxlength="2000">${esc(o.resolucao||"")}</textarea></label><label class="oc-larga">Nota interna<input data-f="nota" maxlength="500"></label>
      <label class="oc-check"><input type="checkbox" data-f="comunicar"${o.visivel_cliente?" checked disabled":""}> Comunicar ao cliente</label><button type="button" class="btn-primary" data-guardar>Guardar</button></div></details>`:""}</article>`).join("")
    :`<p class="oc-vazio">${cli?"Não há ocorrências comunicadas nesta encomenda.":"Sem ocorrências registadas."}</p>`;
  const nova=cli?`<h4>Comunicar um problema</h4><label class="oc-larga">Descreva o que aconteceu<textarea data-n="descricao" rows="3" maxlength="2000"></textarea></label>`
    :g?`<details class="oc-nova"><summary>+ Registar ocorrência</summary><div class="oc-grelha"><label>Tipo<select data-n="tipo">${opcoes(TIPO,"outro")}</select></label><label>Gravidade<select data-n="gravidade">${opcoes(GRAV,"media")}</select></label>
      <label class="oc-larga">Descrição<textarea data-n="descricao" rows="3" maxlength="2000"></textarea></label><label class="oc-check"><input type="checkbox" data-n="suspender"> Suspender a encomenda</label>
      <label class="oc-check"><input type="checkbox" data-n="visivel"> Comunicar já ao cliente</label><button type="button" class="btn-primary" data-criar>Registar</button></div></details>`:"";
  j.mostrar(`${topo}<div class="oc-lista">${lista}</div>${nova}`,cli?[{texto:"Fechar",acao:()=>j.fechar()},{texto:"Enviar à Elolog e ao prestador",principal:true,acao:enviarCliente}]:[{texto:"Fechar",acao:()=>j.fechar()}]);
  const c=j.corpo;
  c.querySelector("[data-criar]")?.addEventListener("click",async()=>{const v=k=>c.querySelector(`[data-n="${k}"]`),f={tipo:v("tipo").value,gravidade:v("gravidade").value,descricao:v("descricao").value.trim(),suspender:v("suspender").checked,visivel:v("visivel").checked};
    if(f.descricao.length<3)return aviso("Descreva a ocorrência.","warning");try{await criar(codigo,f);aviso("Ocorrência registada.","success");pintar();atualizarEcra()}catch(e){aviso(e.message,"error")}});
  c.querySelectorAll("[data-guardar]").forEach(b=>b.addEventListener("click",async()=>{const box=b.closest("[data-oc]"),v=k=>box.querySelector(`[data-f="${k}"]`),f={estado:v("estado").value,tipo:v("tipo").value,gravidade:v("gravidade").value,responsavel:v("responsavel").value,
    resolucao:v("resolucao").value.trim(),nota:v("nota").value.trim(),comunicar:v("comunicar").checked&&!v("comunicar").disabled};try{await atualizar(codigo,box.dataset.oc,f);aviso("Ocorrência atualizada.","success");pintar()}catch(e){aviso(e.message,"error")}}));
  c.querySelector("[data-suspender]")?.addEventListener("click",()=>{const m=c.querySelector(".oc-motivo");m.hidden=false;m.querySelector("input").focus()});
  c.querySelector("[data-suspender-ok]")?.addEventListener("click",async()=>{const m=c.querySelector("[data-motivo]").value.trim();if(m.length<3)return aviso("Indique o motivo da suspensão.","warning");try{await suspender(codigo,m,true);aviso("Encomenda suspensa.","warning");pintar();atualizarEcra()}catch(e){aviso(e.message,"error")}});
  c.querySelector("[data-retomar]")?.addEventListener("click",async()=>{try{await suspender(codigo,"",false);aviso("Encomenda retomada.","success");pintar();atualizarEcra()}catch(e){aviso(e.message,"error")}});
  c.querySelector("[data-despacho]")?.addEventListener("change",async e=>{const f=e.target.files[0];if(!f)return;try{if(online())await P().enviarDocumento(f,{encomenda:codigo,categoria:"despacho",visibilidade:"cliente"});
    else{const o=demoOp(codigo);if(o){o.dispatchDocuments=(o.dispatchDocuments||[]).concat({name:f.name,at:new Date().toISOString()});salvarOps()}}aviso("Despacho guardado nos documentos da encomenda.","success")}catch(x){aviso(x.message,"error")}e.target.value=""})}
async function enviarCliente(){const t=j.corpo.querySelector('[data-n="descricao"]')?.value.trim()||"";if(t.length<3)return aviso("Descreva o problema.","warning");
  try{await criar(codigo,{descricao:t});aviso("Problema comunicado. O prestador e a Elolog vão analisar.","success");pintar()}catch(e){aviso(e.message,"error")}}
function atualizarEcra(){try{window.renderEverything?.()}catch(_){}}

/* ---- botões nas encomendas ---- */
const botao=c=>`<button type="button" class="btn-secondary oc-abrir" data-oc-cod="${esc(c)}">⚠ Ocorrências</button>`;
document.addEventListener("click",e=>{const b=e.target.closest?.(".oc-abrir");if(b){e.stopPropagation();abrir(b.dataset.ocCod)}},true);
function porBotoes(){document.querySelectorAll(".client-order-card").forEach(card=>{const p=card.querySelector(".client-order-details-panel"),c=card.querySelector(".client-order-summary-item strong")?.textContent.trim();
    if(p&&c&&c!=="—"&&!p.querySelector(".oc-abrir")){const alvo=p.querySelector(".dc-acoes");alvo?alvo.insertAdjacentHTML("beforeend"," "+botao(c)):p.insertAdjacentHTML("beforeend",`<div class="dc-acoes">${botao(c)}</div>`)}});
  document.querySelectorAll(".provider-work-card").forEach(card=>{const a=card.querySelector(".provider-work-actions"),c=card.querySelector(".work-code")?.textContent.trim();if(a&&/^ELO_/.test(c||"")&&!a.querySelector(".oc-abrir"))a.insertAdjacentHTML("beforeend",botao(c))})}
const envolver=(nome,depois)=>{const f=window[nome];if(typeof f==="function")window[nome]=function(){const r=f.apply(this,arguments);try{depois(...arguments)}catch(_){}return r}};
envolver("renderClientTracking",porBotoes);
envolver("openProviderOrderDetail",i=>{const o=ops()[i],d=document.getElementById("providerOrderDetail");if(o&&d&&!d.querySelector(".oc-abrir")){const a=d.querySelector(".dc-acoes");a?a.insertAdjacentHTML("beforeend"," "+botao(o.id)):d.insertAdjacentHTML("beforeend",`<div class="dc-acoes">${botao(o.id)}</div>`)}});
envolver("showOperationDetail",id=>{const d=document.getElementById("detailContent");if(d&&!d.querySelector(".oc-abrir")){const a=d.querySelector(".dc-acoes");a?a.insertAdjacentHTML("beforeend"," "+botao(id)):d.insertAdjacentHTML("afterbegin",`<div class="dc-acoes">${botao(id)}</div>`)}});
new MutationObserver(()=>{if(document.querySelector(".provider-work-card .provider-work-actions:not(:has(.oc-abrir))"))porBotoes()}).observe(document.body,{childList:true,subtree:true});
window.elologOcorrencias={abrir};
})();
