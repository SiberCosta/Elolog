/* Elolog — Centro Documental (v123): os documentos emitidos de cada encomenda, para o cliente, o prestador e a administração.
   Servidor: tabela documentos_emitidos (o RLS decide quem vê o quê), emitir_documento, reemitir_documento, registar_evento_documento,
   logotipo_empresa. Um documento nunca muda: uma correção cria nova versão com o mesmo número e a anterior fica «substituída».
   Sem servidor (demonstração): documentos de exemplo, claramente marcados. Cada página: guia, guia de receção ou comprovativo. */
(function(){"use strict";
const P=()=>window.elologProducao,M=()=>window.elologDocModelo,PDF=()=>window.elologDocPdf,esc=s=>M().esc(s);
const online=()=>!!P()?.online?.();
const aviso=(m,t)=>typeof showPlatformNotice==="function"?showPlatformNotice(m,t||"info"):console.info(m);
const PAPEL={admin:"admin_empresa",admin_empresa:"admin_empresa",operador:"operador",armazem:"armazem",financeiro:"financeiro",field_operator:"operador_terreno"};
const PODE={guia:["admin_empresa","operador"],rececao:["admin_empresa","operador","armazem"],pagamento:["admin_empresa","financeiro"],entrega:["admin_empresa","operador","operador_terreno"]};
const ABAS=[["todos","Todos"],["guia","Guias"],["rececao","Receções"],["pagamento","Comprovativos"],["entrega","Entregas"],["arquivo","Versões anteriores"]];
const S={docs:[],aba:"todos",busca:"",logos:{},carregado:false};
const perfil=()=>currentUser?.role==="prestador"?"prestador":currentUser?.role==="admin"?"admin":"cliente";
const papel=()=>perfil()==="prestador"?PAPEL[typeof providerFunction==="function"?providerFunction():"operador"]||"":"";
const podeEmitir=t=>perfil()==="prestador"&&(PODE[t]||[]).includes(papel());
const ELOLOG=()=>new URL("../partilhado/imagens/elolog-logo.svg",location.href).href;
const data=v=>v?new Date(v).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"}):"";

/* ---------- dados ---------- */
async function ler(){if(!online())return window.elologDocDemo?.lista()||[];const sb=await P().sb();
  const{data:l,error}=await sb.from("documentos_emitidos").select("id,empresa_id,tipo,numero,versao,estado,referencia,dados,codigo_validacao,sha256,motivo,emitido_em").order("emitido_em",{ascending:false}).limit(500);
  if(error)throw error;return l||[]}
async function logo(d){const id=d.empresa_id||d.dados?.empresa?.id;if(!id)return"";if(id in S.logos)return S.logos[id];
  if(!online())return S.logos[id]=window.elologDocDemo?.logo()||"";try{const sb=await P().sb();const{data:l}=await sb.rpc("logotipo_empresa",{p_empresa:id});S.logos[id]=l||""}catch(_){S.logos[id]=""}return S.logos[id]}
async function evento(d,acao){if(!online())return;try{const sb=await P().sb();await sb.rpc("registar_evento_documento",{p_documento:d.id,p_acao:acao})}catch(_){}}
async function historico(d){if(!online())return window.elologDocDemo?.historico(d)||[];const sb=await P().sb();
  const ids=S.docs.filter(x=>x.numero===d.numero&&x.empresa_id===d.empresa_id).map(x=>x.id);
  const{data:l}=await sb.from("documentos_eventos").select("documento_id,acao,detalhe,em").in("documento_id",ids.length?ids:[d.id]).order("em",{ascending:false}).limit(80);
  return(l||[]).map(e=>({...e,versao:S.docs.find(x=>x.id===e.documento_id)?.versao}))}

/* ---------- página ---------- */
function seccao(){let s=document.getElementById("centroDocumental");if(s)return s;const irma=document.querySelector("section.page");if(!irma)return null;
  s=document.createElement("section");s.id="centroDocumental";s.className="page";s.setAttribute("aria-labelledby","cdocTitulo");irma.parentElement.appendChild(s);return s}
async function abrir(botao){const s=seccao();if(!s)return;document.querySelectorAll(".page").forEach(p=>p.classList.remove("active"));s.classList.add("active");
  document.querySelectorAll("#sidebar .menu button").forEach(b=>{b.classList.remove("active","client-menu-active");b.removeAttribute("aria-current")});
  if(botao){botao.classList.add(perfil()==="cliente"?"client-menu-active":"active");botao.setAttribute("aria-current","page")}
  const t=document.getElementById("pageTitle");if(t)t.textContent="Centro documental";try{closeSidebar()}catch(_){}
  s.innerHTML='<div class="card"><p role="status">A carregar os documentos…</p></div>';await recarregar()}
async function recarregar(){const s=seccao();try{S.docs=await ler();S.carregado=true;desenhar()}
  catch(e){s.innerHTML=`<div class="card cdoc"><h2 id="cdocTitulo">Centro documental</h2><p class="cdoc-msg erro">Não conseguimos ler os documentos agora. Verifique a ligação e tente outra vez.</p><div><button type="button" class="btn-secondary" id="cdocTentar">Tentar outra vez</button></div></div>`;
    document.getElementById("cdocTentar").onclick=recarregar}}
const filtrados=()=>{const q=S.busca.trim().toLowerCase();return S.docs.filter(d=>(S.aba==="arquivo"?d.estado!=="valido":d.estado==="valido"&&(S.aba==="todos"||d.tipo===S.aba))
  &&(!q||[d.numero,d.referencia,d.dados?.cliente?.nome,d.dados?.empresa?.nome,d.dados?.destinatario?.nome].some(v=>String(v||"").toLowerCase().includes(q))))};
const contar=a=>S.docs.filter(d=>a==="arquivo"?d.estado!=="valido":d.estado==="valido"&&(a==="todos"||d.tipo===a)).length;
const INTRO={cliente:"Os documentos das suas encomendas: guia que acompanha a carga, confirmação de receção no armazém e comprovativos dos pagamentos.",
  prestador:"Documentos emitidos automaticamente em cada etapa confirmada: guia quando a encomenda é aprovada, guia de receção quando o armazém confirma, comprovativo quando um pagamento fica pago.",
  admin:"Todos os documentos emitidos na plataforma, com o histórico de emissão, consulta, impressão e validação."};
function desenhar(){const s=seccao(),pf=perfil(),demo=!online();
  const emitir=pf==="prestador"&&Object.keys(PODE).some(podeEmitir)?`<details class="cdoc-emitir"><summary>Emitir um documento em falta</summary><form id="cdocEmitir">
    <label>Código da encomenda<input id="cdocEncomenda" required placeholder="Ex.: ELO-2026-000123" autocomplete="off"></label>
    <label>Documento<select id="cdocTipo">${Object.keys(PODE).filter(podeEmitir).map(t=>`<option value="${t}">${esc(M().NOMES[t])}</option>`).join("")}</select></label>
    <label id="cdocPagRot" hidden>Código do pagamento<input id="cdocPagamento" autocomplete="off"></label><button type="submit" class="btn-secondary">Emitir documento</button>
    <p class="cdoc-msg" id="cdocEmitirMsg" role="status"></p></form><p class="cdoc-msg">Só é emitido quando a etapa está confirmada (encomenda aprovada, receção confirmada ou pagamento pago).</p></details>`:"";
  s.innerHTML=`<div class="card cdoc"><div class="cdoc-topo"><div><h2 id="cdocTitulo">Centro documental</h2><p>${INTRO[pf]}${demo?" <b>Exemplos de demonstração.</b>":""}</p></div></div>
    <div class="cdoc-abas" role="group" aria-label="Tipo de documento">${ABAS.map(([k,t])=>`<button type="button" data-aba="${k}" aria-pressed="${S.aba===k}">${t}<b>${contar(k)}</b></button>`).join("")}</div>
    <div class="cdoc-filtros"><input id="cdocBusca" type="search" placeholder="Procurar por encomenda, número ou nome" value="${esc(S.busca)}" aria-label="Procurar documentos"></div>${emitir}
    <div class="cdoc-lista" id="cdocLista"></div></div>`;
  s.querySelectorAll("[data-aba]").forEach(b=>b.onclick=()=>{S.aba=b.dataset.aba;desenhar()});
  const busca=document.getElementById("cdocBusca");busca.oninput=()=>{S.busca=busca.value;lista()};
  const f=document.getElementById("cdocEmitir");if(f){const tipo=document.getElementById("cdocTipo"),rot=document.getElementById("cdocPagRot");tipo.onchange=()=>{rot.hidden=tipo.value!=="pagamento"};tipo.onchange();f.onsubmit=emitirEmFalta}
  lista()}
function lista(){const box=document.getElementById("cdocLista"),l=filtrados(),pf=perfil();if(!box)return;
  if(!l.length){box.innerHTML=`<div class="cdoc-vazio">${S.docs.length?"Nenhum documento corresponde a esta pesquisa.":pf==="cliente"?"Ainda não há documentos. A guia aparece aqui quando a sua encomenda for aprovada.":"Ainda não há documentos emitidos. A primeira guia é emitida quando aprovar uma encomenda."}</div>`;return}
  box.innerHTML=l.map(d=>{const quem=pf==="cliente"?d.dados?.empresa?.nome:d.dados?.cliente?.nome;
    return`<article class="cdoc-item"><div><span class="cdoc-tipo">${esc(M().NOMES[d.tipo])}</span><strong>${esc(d.numero)}${d.versao>1?` · versão ${d.versao}`:""}</strong><small>Encomenda ${esc(d.referencia)}${quem?` · ${esc(quem)}`:""}</small></div>
      <div><small>Emitido em</small>${esc(data(d.emitido_em))}</div><span class="cdoc-estado ${esc(d.estado)}">${d.estado==="valido"?"Válido":d.estado==="anulado"?"Anulado":"Substituído"}</span>
      <div class="cdoc-acoes"><button type="button" class="btn-secondary" data-cdoc-abrir="${esc(d.id)}">Abrir</button><button type="button" class="btn-secondary" data-cdoc-pdf="${esc(d.id)}">Descarregar PDF</button></div></article>`}).join("");
  box.querySelectorAll("[data-cdoc-abrir]").forEach(b=>b.onclick=()=>ver(S.docs.find(d=>d.id===b.dataset.cdocAbrir),b));
  box.querySelectorAll("[data-cdoc-pdf]").forEach(b=>b.onclick=()=>descarregar(S.docs.find(d=>d.id===b.dataset.cdocPdf),b))}

/* ---------- ações ---------- */
const marcas=async d=>({elolog:ELOLOG(),prestador:await logo(d)});
const nomeFicheiro=(d,extra="")=>`${d.numero}${d.versao>1?"-v"+d.versao:""}${extra}_${d.referencia}.pdf`.replace(/[^\w.-]+/g,"_");
async function ocupado(b,texto,fn){const t=b?.textContent;if(b){b.disabled=true;b.textContent=texto}try{await fn()}catch(e){aviso(e?.message||"Não foi possível concluir.","error")}finally{if(b){b.disabled=false;b.textContent=t}}}
const descarregar=(d,b,etq)=>ocupado(b,"A preparar o PDF…",async()=>{await PDF().qr();const m=await marcas(d);await PDF().pdf(etq?M().etiquetas(d,m):M().paginas(d,m),nomeFicheiro(d,etq?"-etiquetas":""));evento(d,"descarregado")});
const imprimir=(d,b,etq)=>ocupado(b,"A preparar…",async()=>{const m=await marcas(d);await PDF().imprimir(etq?M().etiquetas(d,m):M().paginas(d,m),d.numero);evento(d,"impresso")});
async function emitirEmFalta(e){e.preventDefault();const msg=document.getElementById("cdocEmitirMsg"),b=e.submitter,enc=document.getElementById("cdocEncomenda").value.trim(),tipo=document.getElementById("cdocTipo").value,
  pag=document.getElementById("cdocPagamento").value.trim();msg.className="cdoc-msg";msg.textContent="";
  await ocupado(b,"A emitir…",async()=>{try{let r;if(online()){const sb=await P().sb();const{data:x,error}=await sb.rpc("emitir_documento",{p_encomenda:enc,p_tipo:tipo,p_pagamento:pag||null});if(error)throw error;r=x}
      else r=window.elologDocDemo.emitir(enc,tipo);await recarregar();const d=S.docs.find(x=>x.id===r.id)||S.docs.find(x=>x.numero===r.numero);
      aviso(`Documento ${r.numero} disponível.`,"success");if(d)ver(d)}
    catch(err){msg.className="cdoc-msg erro";msg.textContent=String(err?.message||err).replace(/^.*?ERROR:\s*/,"")}})}

/* ---------- visualizador ---------- */
async function ver(d,origem){if(!d)return;await PDF().qr();const m=await marcas(d),pf=perfil(),pode=d.estado==="valido"&&podeEmitir(d.tipo);
  const v=document.createElement("div");v.className="cdoc-ver";v.setAttribute("role","dialog");v.setAttribute("aria-modal","true");v.setAttribute("aria-label",`${M().NOMES[d.tipo]} ${d.numero}`);
  v.innerHTML=`<div class="cdoc-ver-caixa"><div class="cdoc-ver-topo"><div><strong>${esc(M().NOMES[d.tipo])} ${esc(d.numero)}</strong> <small>versão ${esc(d.versao)} · encomenda ${esc(d.referencia)}</small></div>
    <div class="cdoc-ver-acoes" data-acoes="1"><button type="button" class="btn-secondary" data-a="pdf">Descarregar PDF</button><button type="button" class="btn-secondary" data-a="imp">Imprimir</button>
    ${d.tipo==="guia"&&d.estado==="valido"?'<button type="button" class="btn-secondary" data-a="etq">Etiquetas dos volumes</button>':""}</div><button type="button" class="btn-secondary cdoc-fechar" data-a="fechar">Fechar</button></div>
    <div class="cdoc-ver-corpo"><div class="cdoc-folhas">${M().paginas(d,m).map(h=>`<div class="cdoc-moldura"><div class="cdoc-escala">${h}</div></div>`).join("")}</div>
    <aside class="cdoc-hist"><h4>Histórico</h4><ol id="cdocHist"><li><small>A carregar…</small></li></ol>${pode?`<form id="cdocReemitir"><label for="cdocMotivo"><b>Corrigir este documento</b></label>
      <small>Cria a versão ${d.versao+1} com os dados atuais da encomenda. Esta versão continua consultável como «substituída».</small><textarea id="cdocMotivo" required minlength="5" placeholder="Motivo da correção"></textarea>
      <button type="submit" class="btn-secondary">Emitir nova versão</button><p class="cdoc-msg" id="cdocReemitirMsg" role="status"></p></form>`:""}</aside></div></div>`;
  document.body.appendChild(v);const fechar=()=>{v.remove();document.removeEventListener("keydown",tecla);origem?.focus?.()},tecla=e=>{if(e.key==="Escape")fechar()};document.addEventListener("keydown",tecla);
  v.addEventListener("click",e=>{if(e.target===v)fechar()});const ac=a=>v.querySelector(`[data-a="${a}"]`);ac("fechar").onclick=fechar;ac("fechar").focus();
  ac("pdf").onclick=()=>descarregar(d,ac("pdf"));ac("imp").onclick=()=>imprimir(d,ac("imp"));if(ac("etq")){ac("etq").onclick=()=>descarregar(d,ac("etq"),true);
    const ei=document.createElement("button");ei.type="button";ei.className="btn-secondary";ei.textContent="Imprimir etiquetas";ei.onclick=()=>imprimir(d,ei,true);ac("etq").after(ei)}
  /* v125: no ecrã a folha não encolhe: ocupa a largura disponível (máx. A4) e, num telemóvel, os cartões empilham-se */

  evento(d,"consultado");historico(d).then(h=>{const o=v.querySelector("#cdocHist");const N={emitido:"Emitido",reemitido:"Nova versão emitida",consultado:"Consultado",impresso:"Impresso",descarregado:"Descarregado em PDF",validado:"Validado pelo QR"};
    o.innerHTML=h.length?h.map(e=>`<li>${N[e.acao]||esc(e.acao)}${e.versao?` (versão ${e.versao})`:""}${e.detalhe?`: ${esc(e.detalhe)}`:""}<br><small>${esc(data(e.em))}</small></li>`).join(""):"<li><small>Sem registos.</small></li>"}).catch(()=>{});
  const f=v.querySelector("#cdocReemitir");if(f)f.onsubmit=async e=>{e.preventDefault();const msg=v.querySelector("#cdocReemitirMsg"),motivo=v.querySelector("#cdocMotivo").value.trim();
    await ocupado(e.submitter,"A emitir…",async()=>{try{let r;if(online()){const sb=await P().sb();const{data:x,error}=await sb.rpc("reemitir_documento",{p_documento:d.id,p_motivo:motivo});if(error)throw error;r=x}
        else r=window.elologDocDemo.reemitir(d,motivo);fechar();await recarregar();const n=S.docs.find(x=>x.id===r.id);aviso(`Versão ${r.versao} do documento ${r.numero} emitida.`,"success");if(n)ver(n)}
      catch(err){msg.className="cdoc-msg erro";msg.textContent=String(err?.message||err).replace(/^.*?ERROR:\s*/,"")}})}}

window.elologCentroDoc={abrir,ver,recarregar,_estado:S};
})();
