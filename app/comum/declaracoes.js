/* Elolog — Declarações da encomenda: os dados preenchem-se uma vez (cliente: pessoas, viatura e bens; prestador: embarque)
   e servem aos 6 modelos de declaração (declaracoes-pdf.js). Servidor: declaracoes_ler / declaracoes_gravar (00145).
   O PDF pode ser descarregado para imprimir e assinar e fica guardado nos documentos da encomenda. Sem servidor: guarda no navegador. */
(function(){"use strict";
const P=()=>window.elologProducao,online=()=>!!P()?.online?.(),PDF=()=>window.elologDeclaracoesPdf;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(m,t)=>window.showPlatformNotice?window.showPlatformNotice(m,t||"info"):alert(m);
const ops=()=>typeof operations!=="undefined"&&Array.isArray(operations)?operations:[],eu=()=>typeof currentUser!=="undefined"?currentUser:null;
const CHAVE=c=>"elolog_declaracoes_"+c;
let st=null;   // {base, dados, papel}

/* ---- carregar e guardar ---- */
async function carregar(codigo){
  if(online()){const c=await P().sb(),{data,error}=await c.rpc("declaracoes_ler",{p_codigo:codigo});if(error)throw new Error(error.message||"Não foi possível abrir as declarações.");
    return{base:data,dados:data.dados||{},papel:data.papel}}
  const o=ops().find(x=>x.id===codigo)||{},papel=eu()?.role==="cliente"?"cliente":"empresa";let dados={};try{dados=JSON.parse(localStorage.getItem(CHAVE(codigo))||"{}")}catch(_){}
  return{base:{codigo,origem:o.origin||"",destino:o.destination||"",cliente:{nome:o.client||(papel==="cliente"?eu()?.name:"")},empresa:{nome:o.provider||o.company||eu()?.company||""}},dados,papel}}
async function gravar(){ler();if(online()){const c=await P().sb(),{error}=await c.rpc("declaracoes_gravar",{p_codigo:st.base.codigo,p_dados:st.dados});if(error)throw new Error(error.message||"Não foi possível guardar.")}
  else try{localStorage.setItem(CHAVE(st.base.codigo),JSON.stringify(st.dados))}catch(_){}}

/* ---- formulário ---- */
const campo=(k,r,{tipo="text",max=120,larga=false,lista,so}={})=>{const v=k.split(".").reduce((o,p)=>o?.[p],st.dados)??"",dis=so?" disabled":"";
  return`<label class="${larga?"dc-larga":""}">${esc(r)}${lista?`<select data-k="${k}"${dis}>${lista.map(([a,b])=>`<option value="${a}"${String(v)===a?" selected":""}>${esc(b)}</option>`).join("")}</select>`
  :`<input data-k="${k}" type="${tipo}" maxlength="${max}" value="${esc(v)}"${dis}>`}</label>`};
const grelha=h=>`<div class="dc-grelha">${h}</div>`;
const PASSOS=["Pessoas","Viatura","Bens","Embarque","Documentos"];
function html(i){const d=st.dados;
  if(i===0)return`<h4 class="dc-sub">Proprietário</h4>${grelha(campo("proprietario.nome","Nome completo")+campo("proprietario.documento","N.º do documento (CC/BI/passaporte)",{max:40})+campo("proprietario.nif","NIF",{max:20})+campo("proprietario.telefone","Telefone",{max:30})+campo("proprietario.morada","Morada",{larga:true,max:200})+campo("proprietario.email","Email",{tipo:"email",larga:true}))}
    <h4 class="dc-sub">Destinatário</h4>${grelha(campo("destinatario.nome","Nome completo")+campo("destinatario.documento","N.º do documento",{max:40})+campo("destinatario.morada","Morada",{max:200})+campo("destinatario.cidade","Cidade e país",{max:80})+campo("destinatario.telefone","Telefone",{max:30}))}
    <h4 class="dc-sub">Finalidade</h4>${grelha(campo("finalidade","Finalidade do envio",{lista:[["pessoal","Uso pessoal e familiar"],["mudanca","Mudança de residência"],["oferta","Oferta a familiares"],["comercial","Fins comerciais"],["outra","Outra"]]})+campo("finalidade_texto","Se «Outra», qual?",{max:120}))}`;
  if(i===1)return`<label class="dc-check"><input type="checkbox" data-k="viatura.inclui"${d.viatura?.inclui?" checked":""}> Este processo inclui uma viatura</label>
    ${grelha(campo("viatura.matricula","Matrícula",{max:20})+campo("viatura.marca","Marca",{max:40})+campo("viatura.modelo","Modelo",{max:60})+campo("viatura.vin","VIN / n.º de chassis",{max:30})+campo("viatura.ano","Ano",{tipo:"number"})+
    campo("viatura.combustivel","Combustível",{lista:[["",""],["Gasolina","Gasolina"],["Gasóleo","Gasóleo"],["Híbrido","Híbrido"],["Elétrico","Elétrico"],["GPL","GPL"]]})+campo("viatura.cilindrada","Cilindrada (cm³)",{tipo:"number"})+campo("viatura.cor","Cor",{max:30})+campo("viatura.valor","Valor estimado (€)",{tipo:"number"}))}`;
  if(i===2){const bens=(d.bens&&d.bens.length?d.bens:[{}]);return`<p class="dc-nota">Uma linha por objeto ou grupo de objetos. O valor é o valor estimado da linha.</p><div class="dc-bens" id="dcBens">${bens.map(linhaBem).join("")}</div>
    <button type="button" class="btn-secondary" id="dcMais">+ Linha</button> <strong class="dc-total" id="dcTotal"></strong>`}
  if(i===3){const so=st.papel==="cliente";return`${so?'<p class="dc-nota">Estes dados são preenchidos pelo prestador.</p>':""}${grelha(campo("embarque.porto_saida","Porto de saída",{so})+campo("embarque.porto_destino","Porto de destino",{so})+campo("embarque.transportadora","Transportadora",{so})+campo("embarque.navio","Navio / viagem",{so})+
    campo("embarque.contentor","Contentor",{so,max:20})+campo("embarque.bl","Conhecimento de embarque (BL)",{so,max:40})+campo("embarque.data_embarque","Data de embarque",{tipo:"date",so})+campo("embarque.anexos","Documentos anexos",{so,larga:true,max:300}))}`}
  const via=!!d.viatura?.inclui;return`<p class="dc-nota">Escolha os modelos. Os dados já preenchidos entram em todos. São documentos internos de apoio ao processo.</p><div class="dc-modelos">${PDF().MODELOS.map(m=>{const off=m.so&&!m.so(d);
    return`<label class="dc-check${off?" dc-off":""}"><input type="checkbox" value="${m.id}"${off?" disabled":" checked"}> ${m.n}. ${esc((m.titulo&&m.titulo(d))||m.nome)}${off?" <small>(sem viatura)</small>":""}</label>`}).join("")}</div>
    ${grelha(campo("local","Local",{max:60})+campo("data","Data",{tipo:"date"}))}`}
const linhaBem=(b={})=>`<div class="dc-bem"><input data-b="descricao" placeholder="Descrição" maxlength="140" value="${esc(b.descricao)}" aria-label="Descrição"><input data-b="quantidade" type="number" min="1" placeholder="Qtd." value="${esc(b.quantidade??1)}" aria-label="Quantidade">
  <select data-b="estado" aria-label="Estado">${["Usado","Novo"].map(e=>`<option${b.estado===e?" selected":""}>${e}</option>`).join("")}</select><input data-b="valor" type="number" min="0" step="0.01" placeholder="Valor €" value="${esc(b.valor)}" aria-label="Valor (€)"><button type="button" class="btn-secondary" data-tirar aria-label="Tirar linha">×</button></div>`;
function ler(){const c=document.querySelector("#pmJanela .pm-corpo");if(!c||!st)return;
  c.querySelectorAll("[data-k]").forEach(x=>{if(x.disabled)return;const ps=x.dataset.k.split("."),u=ps.pop();let o=st.dados;ps.forEach(p=>{o=o[p]=o[p]||{}});o[u]=x.type==="checkbox"?x.checked:x.value.trim()});
  const bens=c.querySelector("#dcBens");if(bens)st.dados.bens=[...bens.querySelectorAll(".dc-bem")].map(l=>Object.fromEntries([...l.querySelectorAll("[data-b]")].map(x=>[x.dataset.b,x.value.trim()]))).filter(b=>b.descricao||Number(b.valor))}
function ligarBens(){const box=document.getElementById("dcBens");if(!box)return;const total=()=>{const t=[...box.querySelectorAll('[data-b="valor"]')].reduce((s,x)=>s+(Number(x.value)||0),0);document.getElementById("dcTotal").textContent="Total: "+t.toLocaleString("pt-PT",{style:"currency",currency:"EUR"})};
  document.getElementById("dcMais").onclick=()=>{box.insertAdjacentHTML("beforeend",linhaBem());box.lastElementChild.querySelector("input").focus()};
  box.oninput=total;box.onclick=e=>{if(e.target.closest("[data-tirar]")){const l=e.target.closest(".dc-bem");box.children.length>1?l.remove():l.querySelectorAll("input").forEach(x=>x.value="");total()}};total()}

function nomeFicheiro(){return`Declaracoes_${st.base.codigo}.pdf`.replace(/[^\w.-]+/g,"_")}
function pdf(){const ids=[...document.querySelectorAll("#pmJanela .dc-modelos input:checked")].map(x=>x.value);return PDF().gerar(st.base,st.dados,ids)}
function mostrar(j,i){j.passo(i);const ult=i===PASSOS.length-1,bot=[];
  if(i>0)bot.push({texto:"Anterior",acao:async()=>{ler();mostrar(j,i-1)}});
  if(!ult)bot.push({texto:"Seguinte",principal:true,acao:async()=>{try{await gravar()}catch(e){return aviso(e.message,"error")}mostrar(j,i+1)}});
  else{bot.push({texto:"Descarregar PDF",acao:async()=>{try{await gravar();const u=URL.createObjectURL(pdf()),a=document.createElement("a");a.href=u;a.download=nomeFicheiro();document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),4000)}catch(e){aviso(e.message,"error")}}});
    bot.push({texto:online()?"Guardar na encomenda":"Guardar",principal:true,acao:async()=>{try{await gravar();if(online()){await P().enviarDocumento(new File([pdf()],nomeFicheiro(),{type:"application/pdf"}),{encomenda:st.base.codigo,categoria:"declaracao",visibilidade:"cliente"});
      aviso("Declarações guardadas nos documentos da encomenda.","success")}else aviso("Dados guardados neste navegador.","success");j.fechar()}catch(e){aviso(e.message,"error")}}})}
  j.mostrar(html(i),bot);if(i===2)ligarBens()}

async function abrir(codigo){if(!PDF()||!P()?.janela)return;let r;try{r=await carregar(codigo)}catch(e){return aviso(e.message,"error")}st=r;const d=st.dados,b=st.base;
  if(!d.proprietario?.nome&&b.cliente?.nome&&st.papel==="cliente")d.proprietario={nome:b.cliente.nome,nif:b.cliente.nif||"",telefone:b.cliente.telefone||"",morada:b.cliente.morada||"",email:b.cliente.email||"",...(d.proprietario||{})};
  if(!d.proprietario?.nome&&b.cliente?.nome)d.proprietario={...(d.proprietario||{}),nome:b.cliente.nome,nif:d.proprietario?.nif||b.cliente.nif||""};
  d.local=d.local||(b.origem||"").split(",")[0];d.data=d.data||new Date().toISOString().slice(0,10);d.embarque=d.embarque||{};
  const j=P().janela({eyebrow:"ENCOMENDA "+b.codigo,titulo:"Declarações do processo",passos:PASSOS});j.corpo.closest(".pm-caixa")?.classList.add("dc-janela");mostrar(j,0)}

/* ---- botões nas encomendas (cliente, prestador e detalhe da operação) ---- */
const botao=c=>`<button type="button" class="btn-secondary dc-abrir" data-dc="${esc(c)}">📄 Declarações (6 modelos)</button>`;
document.addEventListener("click",e=>{const b=e.target.closest?.(".dc-abrir");if(b){e.stopPropagation();abrir(b.dataset.dc)}},true);
function porNoCliente(){document.querySelectorAll(".client-order-card").forEach(card=>{const p=card.querySelector(".client-order-details-panel"),c=card.querySelector(".client-order-summary-item strong")?.textContent.trim();
  if(p&&c&&c!=="—"&&!p.querySelector(".dc-abrir"))p.insertAdjacentHTML("beforeend",`<div class="dc-acoes">${botao(c)}</div>`)})}
const envolver=(nome,depois)=>{const f=window[nome];if(typeof f==="function")window[nome]=function(){const r=f.apply(this,arguments);try{depois(...arguments)}catch(_){}return r}};
envolver("renderClientTracking",porNoCliente);
envolver("openProviderOrderDetail",i=>{const o=ops()[i],d=document.getElementById("providerOrderDetail");if(o&&d&&!d.querySelector(".dc-abrir"))d.insertAdjacentHTML("beforeend",`<div class="dc-acoes">${botao(o.id)}</div>`)});
envolver("showOperationDetail",id=>{const d=document.getElementById("detailContent");if(d&&!d.querySelector(".dc-abrir"))d.insertAdjacentHTML("afterbegin",`<div class="dc-acoes">${botao(id)}</div>`)});
window.elologDeclaracoes={abrir};
})();
