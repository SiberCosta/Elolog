/* Elolog — «Classificações» dos prestadores na administração (v172, migração 00205).
   A administração atribui um nível a cada prestador aprovado (Recomendado, Ouro, Prata, Bronze), com nota interna que só ela vê,
   e acompanha as avaliações dos clientes (1 a 5 estrelas, dadas depois da entrega). Pode ocultar uma avaliação abusiva.
   O site mostra o nível, a média e o n.º de avaliações publicadas (função site_conteudo). */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k||"info"):alert(t);
const NIVEL={"":"Sem nível",recomendado:"Recomendado Elolog",ouro:"Ouro",prata:"Prata",bronze:"Bronze"};
const estrelas=n=>n==null?"—":`<span class="cl-estrelas" aria-label="${n} de 5">${"★".repeat(Math.floor(n+.25))}${"☆".repeat(5-Math.floor(n+.25))}</span>`;
const dia=v=>v?new Date(v).toLocaleDateString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric"}):"";
let d=null,filtro="";

function pagina(){if($("adminClassif"))return;const ref=$("adminSettings");if(!ref)return;const s=document.createElement("section");
  s.id="adminClassif";s.className="page admin-platform-page";s.innerHTML='<div class="card cl-pagina"><div id="adminClassifContent"></div></div>';ref.before(s)}
function botao(){if($("adminClassifBtn"))return;const g=$("adminGrpPrest");if(!g)return;const b=document.createElement("button");b.type="button";b.id="adminClassifBtn";
  b.textContent="Classificações";b.setAttribute("onclick","showAdminPage('adminClassif',this)");g.appendChild(b)}

async function ler(){const sb=await S().cliente();
  const[a,b,c]=await Promise.all([sb.from("empresas").select("id,nome,nome_comercial,cidade").eq("estado","aprovada").order("nome"),
    sb.from("prestador_classificacao").select("empresa_id,nivel,nota_interna,logo"),
    sb.from("avaliacoes_prestador").select("id,empresa_id,encomenda_id,nota,pontualidade,comunicacao,cuidado,comentario,estado,created_at").order("created_at",{ascending:false}).limit(300)]);
  for(const r of[a,b,c])if(r.error)throw r.error;
  const cl={};(b.data||[]).forEach(x=>cl[x.empresa_id]=x);
  d={empresas:(a.data||[]).map(x=>({id:x.id,nome:x.nome_comercial||x.nome,cidade:x.cidade})),cl,av:c.data||[]}}
const nomeEmp=id=>d.empresas.find(e=>e.id===id)?.nome||"Prestador";
function resumo(id){const l=d.av.filter(a=>a.empresa_id===id&&a.estado==="publicada");return{n:l.length,m:l.length?l.reduce((s,a)=>s+a.nota,0)/l.length:null}}

function desenhar(){const box=$("adminClassifContent");if(!box)return;
  const cab=`<header class="cl-cab"><h3>Classificações dos prestadores</h3><p>Atribua um nível a cada prestador e acompanhe as avaliações dos clientes. O site mostra o nível, as estrelas e o n.º de avaliações.</p></header>`;
  if(!S()?.ativo?.())return box.innerHTML=cab+'<div class="sp-vazio">Disponível com o servidor ligado (fora do modo de demonstração).</div>';
  if(!d)return box.innerHTML=cab+'<div class="sp-vazio">A carregar…</div>';
  const emp=d.empresas.filter(e=>!filtro||e.nome.toLowerCase().includes(filtro));
  const lista=emp.length?`<div class="cl-lista">${emp.map(e=>{const r=resumo(e.id),c=d.cl[e.id]||{};
    const ini=e.nome.split(/\s+/).filter(Boolean).slice(0,2).map(w=>w[0]).join("").toUpperCase();
    return`<div class="cl-linha"><div class="cl-logo">${c.logo?`<img src="${esc(c.logo)}" alt="Logótipo de ${esc(e.nome)}">`:`<span aria-hidden="true">${esc(ini)}</span>`}
      <label class="cl-carregar">${c.logo?"Trocar":"Carregar logótipo"}<input type="file" accept="image/png,image/jpeg,image/webp" data-logo="${e.id}"></label>
      ${c.logo?`<button type="button" class="cl-retirar" data-retirar-logo="${e.id}">Retirar</button>`:""}</div><div class="cl-nome"><strong>${esc(e.nome)}</strong><small>${esc(e.cidade||"")}</small>
      <span class="cl-media">${r.n?`${estrelas(r.m)} <b>${r.m.toLocaleString("pt-PT",{minimumFractionDigits:1,maximumFractionDigits:1})}</b> · ${r.n} ${r.n===1?"avaliação":"avaliações"}`:"Sem avaliações"}</span></div>
      <label>Nível<select data-nivel="${e.id}">${Object.entries(NIVEL).map(([k,t])=>`<option value="${k}" ${(c.nivel||"")===k?"selected":""}>${t}</option>`).join("")}</select></label>
      <label class="cl-nota">Nota interna (só a administração vê)<input data-nota="${e.id}" maxlength="500" value="${esc(c.nota_interna||"")}" placeholder="Ex.: cumpriu prazos em 2026"></label></div>`}).join("")}</div>`
    :'<div class="sp-vazio">Sem prestadores aprovados com esse nome.</div>';
  const av=d.av.length?`<div class="cl-lista">${d.av.slice(0,60).map(a=>`<div class="cl-av ${a.estado}"><div><strong>${estrelas(a.nota)} ${esc(nomeEmp(a.empresa_id))}</strong>
      <small>${dia(a.created_at)}${a.pontualidade?` · pontualidade ${a.pontualidade}/5`:""}${a.comunicacao?` · comunicação ${a.comunicacao}/5`:""}${a.cuidado?` · cuidado com a carga ${a.cuidado}/5`:""}</small>
      ${a.comentario?`<p>${esc(a.comentario)}</p>`:""}</div>
      <label class="sp-lig"><input type="checkbox" data-av="${a.id}" ${a.estado==="publicada"?"checked":""}> Publicada</label></div>`).join("")}</div>`
    :'<div class="sp-vazio">Ainda não há avaliações. Os clientes podem avaliar depois de cada encomenda entregue.</div>';
  box.innerHTML=cab+`<div class="cl-barra"><input type="search" id="clProcura" placeholder="Procurar prestador" value="${esc(filtro)}"></div>${lista}
    <h4 class="sp-sub">Avaliações recentes dos clientes</h4>${av}`;
  if(filtro){const i=$("clProcura");i.focus();i.setSelectionRange(i.value.length,i.value.length)}}
async function recarregar(){try{await ler()}catch(e){d=null;const box=$("adminClassifContent");if(box)box.innerHTML=`<div class="sp-vazio">Não foi possível ler as classificações: ${esc(S()?.mensagem?.(e)||e.message)}</div>`;return}desenhar()}
async function acao(fn,ok){try{await fn();if(ok)aviso(ok,"success");await recarregar()}catch(e){aviso(S()?.mensagem?.(e)||e.message,"error")}}
async function guardar(id,muda){const sb=await S().cliente(),c=d.cl[id]||{};
  const{error}=await sb.from("prestador_classificacao").upsert({empresa_id:id,nivel:c.nivel||null,nota_interna:c.nota_interna||null,logo:c.logo||null,...muda,updated_at:new Date().toISOString()});if(error)throw error}
/* logótipo: PNG, JPEG ou WebP até 1 MB, guardado no armazenamento público «site-publico» (só a administração carrega) */
async function carregarLogo(id,f){if(!f)return;if(!/^image\/(png|jpeg|webp)$/.test(f.type))throw new Error("Use uma imagem PNG, JPEG ou WebP.");
  if(f.size>1048576)throw new Error("A imagem tem mais de 1 MB. Reduza-a e tente de novo.");
  const sb=await S().cliente(),ext={"image/png":"png","image/jpeg":"jpg","image/webp":"webp"}[f.type],caminho=`prestadores/${id}-${Date.now()}.${ext}`;
  const up=await sb.storage.from("site-publico").upload(caminho,f,{contentType:f.type,upsert:false});if(up.error)throw up.error;
  const url=sb.storage.from("site-publico").getPublicUrl(caminho).data.publicUrl;await guardar(id,{logo:url})}

document.addEventListener("click",e=>{const b=e.target.closest("[data-retirar-logo]");if(!b||!confirm("Retirar o logótipo deste prestador?"))return;acao(()=>guardar(b.dataset.retirarLogo,{logo:null}),"Logótipo retirado.")});
document.addEventListener("input",e=>{if(e.target.id!=="clProcura")return;filtro=e.target.value.trim().toLowerCase();desenhar()});
document.addEventListener("change",e=>{const box=$("adminClassifContent"),t=e.target;if(!box||!box.contains(t))return;
  if(t.dataset.nivel!==undefined)return acao(()=>guardar(t.dataset.nivel,{nivel:t.value||null}),t.value?`Nível «${NIVEL[t.value]}» atribuído.`:"Nível retirado.");
  if(t.dataset.nota!==undefined)return acao(()=>guardar(t.dataset.nota,{nota_interna:t.value.trim()||null}),"Nota guardada.");
  if(t.dataset.logo)return acao(()=>carregarLogo(t.dataset.logo,t.files?.[0]),"Logótipo carregado. Já aparece no site.");
  if(t.dataset.av)return acao(async()=>{const{error}=await(await S().cliente()).from("avaliacoes_prestador").update({estado:t.checked?"publicada":"oculta",updated_at:new Date().toISOString()}).eq("id",t.dataset.av);if(error)throw error},t.checked?"Avaliação publicada.":"Avaliação ocultada do site.")});

const orig=window.showAdminPage;if(typeof orig==="function")window.showAdminPage=showAdminPage=function(page){const r=orig.apply(this,arguments);
  if(page==="adminClassif"){const t=$("pageTitle");if(t)t.textContent="Classificações";$("adminGrpPrest")?.classList.add("open");desenhar();recarregar()}return r};
function ligar(){if(typeof currentUser==="undefined"||currentUser?.role!=="admin")return;pagina();botao()}
const ini=window.startApp;if(typeof ini==="function")window.startApp=async function(){const r=await ini.apply(this,arguments);setTimeout(ligar,600);setTimeout(ligar,2000);return r};
setTimeout(ligar,1500);window.elologClassificacoes={recarregar};
})();
