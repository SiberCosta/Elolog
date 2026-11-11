/* Elolog — Terreno ao vivo (v127): página «Serviços ao vivo» do motorista (telemóvel primeiro).
   Cada serviço: quem e onde, «Iniciar percurso» (partilha a posição e calcula a chegada prevista), «Navegar» e o comprovativo
   (quem recebeu, volumes conferidos, fotografias, assinatura no ecrã). Sem rede, o comprovativo fica guardado no telemóvel e segue depois. */
(function(){"use strict";
const D=()=>window.elologTerrenoDados,esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(m,t)=>typeof showPlatformNotice==="function"?showPlatformNotice(m,t||"info"):console.info(m);
const hora=v=>v?new Date(v).toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"}):"";
const NOME={entrega:"Entrega",recolha:"Recolha"};
let lista=[],parar=null;

function pagina(id,titulo,botao){let s=document.getElementById(id);if(!s){const irma=document.querySelector("section.page");if(!irma)return null;s=document.createElement("section");s.id=id;s.className="page";irma.parentElement.appendChild(s)}
  document.querySelectorAll(".page").forEach(p=>p.classList.remove("active"));s.classList.add("active");
  document.querySelectorAll("#sidebar .menu button,.provider-desktop-nav button").forEach(b=>{b.classList.remove("active","client-menu-active");b.removeAttribute("aria-current")});
  if(botao){botao.classList.add("active");botao.setAttribute("aria-current","page")}const t=document.getElementById("pageTitle");if(t)t.textContent=titulo;try{closeSidebar()}catch(_){}return s}
window.elologPaginaPropria=pagina;

async function abrir(botao){const s=pagina("terrenoMotorista","Serviços ao vivo",botao);if(!s)return;s.innerHTML='<div class="card tv"><p role="status">A carregar os serviços…</p></div>';
  parar?.();parar=D().ouvir(()=>faixa());try{lista=await D().servicos()}catch(e){lista=[];aviso("Não conseguimos ler os serviços: "+D().erroTexto(e),"error")}desenhar()}
async function filaHtml(){let l=[];try{l=await D().pendentes()}catch(_){}if(!l.length)return"";
  return`<section class="tv-fila" aria-live="polite"><b>${l.length===1?"1 comprovativo por enviar":l.length+" comprovativos por enviar"}</b>${l.some(c=>!c.erro)?`<span>Seguem sozinhos quando houver rede.</span><button type="button" class="btn-secondary" data-tv="enviar">Enviar agora</button>`:""}
    ${l.filter(c=>c.erro).map(c=>`<p class="tv-erro">Recusado pelo servidor: ${esc(c.erro)} <button type="button" class="btn-secondary" data-tv-descartar="${esc(c.id_local)}">Descartar</button></p>`).join("")}</section>`}
function faixa(){const f=document.getElementById("tvFaixa");if(!f)return;const e=D().estado();if(!e.ativo){f.hidden=true;return}f.hidden=false;
  f.innerHTML=`<span class="tv-pulso" aria-hidden="true"></span><div><b>A partilhar a sua posição · ${esc(e.trabalho?.encomenda?.codigo||"")}</b><span>${e.eta?`Chegada prevista às ${hora(e.eta)}${e.distancia!=null?` · ${String(e.distancia).replace(".",",")} km`:""}`:"A calcular a chegada prevista…"}. Mantenha esta página aberta.</span></div>
    <button type="button" class="btn-secondary" data-tv="parar">Parar partilha</button>`}
async function desenhar(){const s=document.getElementById("terrenoMotorista");if(!s)return;const rede=navigator.onLine,demo=!D().online();
  s.innerHTML=`<div class="card tv"><div class="tv-topo"><div><h2>Serviços de hoje</h2><p>${demo?"<b>Exemplos de demonstração.</b> ":""}Inicie o percurso ao sair, para a empresa e o cliente verem a chegada prevista.</p></div>
    <span class="tv-rede ${rede?"ok":"sem"}">${rede?"Com rede":"Sem rede: o que registar fica guardado"}</span></div><div class="tv-faixa" id="tvFaixa" hidden></div><div id="tvFila">${await filaHtml()}</div>
    <div class="tv-lista">${lista.length?lista.map(cartao).join(""):'<p class="tv-vazio">Não tem serviços planeados para hoje. Quando a empresa lhe atribuir uma recolha ou entrega, aparece aqui.</p>'}</div></div>`;
  faixa();ligar(s)}
function cartao(t){const e=t.encomenda||{},p=D().pessoa(t),m=D().morada(t),ativo=D().estado().trabalho?.id===t.id;
  return`<article class="tv-cartao${ativo?" tv-ativo":""}" data-id="${esc(t.id)}"><header><span class="tv-tipo tv-${esc(t.tipo)}">${NOME[t.tipo]||esc(t.tipo)}</span><b class="tv-cod">${esc(e.codigo||"")}</b>${t.estado==="em_curso"?'<span class="tv-curso">Em curso</span>':""}</header>
    <strong class="tv-nome">${esc(p.nome||"—")}</strong>${p.telefone?`<a class="tv-tel" href="tel:${esc(String(p.telefone).replace(/[^\d+]/g,""))}">${esc(p.telefone)}</a>`:""}
    <p class="tv-morada">${esc(m||"Morada por indicar")}</p>${e.quantidade?`<p class="tv-vol">${esc(e.quantidade)} volume(s)</p>`:""}${t.notas?`<p class="tv-nota">${esc(t.notas)}</p>`:""}
    <div class="tv-acoes">${ativo?"":`<label class="tv-hora">Combinado até <input type="time" data-tv-hora aria-label="Hora combinada com o cliente"></label><button type="button" class="btn-secondary" data-tv="iniciar">Iniciar percurso</button>`}
      ${m?`<a class="btn-secondary" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(m)}">Navegar</a>`:""}
      <button type="button" class="btn-primary" data-tv="registar">Registar ${t.tipo==="recolha"?"recolha":"entrega"}</button></div></article>`}
function ligar(s){s.onclick=async ev=>{const b=ev.target.closest("[data-tv],[data-tv-descartar]");if(!b)return;
  if(b.dataset.tvDescartar){await D().descartar(b.dataset.tvDescartar);return desenhar()}
  const a=b.dataset.tv;if(a==="enviar"){b.disabled=true;await D().enviarPendentes();return desenhar()}if(a==="parar"){D().parar();return desenhar()}
  const c=b.closest(".tv-cartao"),t=lista.find(x=>x.id===c?.dataset.id);if(!t)return;
  if(a==="iniciar"){const h=c.querySelector("[data-tv-hora]")?.value;let prev=null;if(h){const d=new Date();const[hh,mm]=h.split(":");d.setHours(+hh,+mm,0,0);prev=d.toISOString()}
    b.disabled=true;b.textContent="A obter a localização…";try{await D().iniciar(t,prev);t.estado="em_curso";aviso("Percurso iniciado. A empresa e o cliente veem a chegada prevista.","success");desenhar()}
    catch(e){aviso(D().erroTexto(e),"error");b.disabled=false;b.textContent="Iniciar percurso"}}
  if(a==="registar")window.elologComprovativo.abrir(t,()=>{lista=lista.filter(x=>x.id!==t.id);desenhar()})}}
window.addEventListener("elolog-terreno-fila",async()=>{const f=document.getElementById("tvFila");if(f)f.innerHTML=await filaHtml()});
["online","offline"].forEach(e=>window.addEventListener(e,()=>{if(document.getElementById("terrenoMotorista")?.classList.contains("active"))desenhar()}));

/* ---------- comprovativo: assinatura no ecrã, fotografias, quem recebeu ---------- */
function comprimir(f){return new Promise((ok,falha)=>{const i=new Image(),u=URL.createObjectURL(f);i.onload=()=>{const k=Math.min(1,1280/Math.max(i.width,i.height)),c=document.createElement("canvas");
  c.width=Math.round(i.width*k);c.height=Math.round(i.height*k);c.getContext("2d").drawImage(i,0,0,c.width,c.height);URL.revokeObjectURL(u);let d=c.toDataURL("image/jpeg",.72);if(d.length>650000)d=c.toDataURL("image/jpeg",.5);ok(d)};
  i.onerror=()=>falha(new Error("Não conseguimos ler esta fotografia."));i.src=u})}
function quadro(cv){const ctx=cv.getContext("2d"),r=window.devicePixelRatio||1;let traco=false,ultimo=null,pontos=0;
  const medir=()=>{const b=cv.getBoundingClientRect();cv.width=b.width*r;cv.height=b.height*r;ctx.scale(r,r);ctx.lineWidth=2.4;ctx.lineCap="round";ctx.lineJoin="round";ctx.strokeStyle="#0F2233"};medir();
  const pt=e=>{const b=cv.getBoundingClientRect();return{x:e.clientX-b.left,y:e.clientY-b.top}};
  cv.onpointerdown=e=>{traco=true;ultimo=pt(e);cv.setPointerCapture(e.pointerId)};cv.onpointerup=cv.onpointercancel=()=>{traco=false};
  cv.onpointermove=e=>{if(!traco)return;const p=pt(e);ctx.beginPath();ctx.moveTo(ultimo.x,ultimo.y);ctx.lineTo(p.x,p.y);ctx.stroke();ultimo=p;pontos++};
  return{vazio:()=>pontos<8,limpar:()=>{ctx.clearRect(0,0,cv.width,cv.height);pontos=0},png:()=>{const o=document.createElement("canvas"),k=Math.min(1,600/cv.width);o.width=cv.width*k;o.height=cv.height*k;
    const g=o.getContext("2d");g.fillStyle="#fff";g.fillRect(0,0,o.width,o.height);g.drawImage(cv,0,0,o.width,o.height);return o.toDataURL("image/png")}}}
function abrirComprovativo(t,depois){const e=t.encomenda||{},rec=t.tipo==="recolha",fotos=[];
  const v=document.createElement("div");v.className="tv-modal";v.setAttribute("role","dialog");v.setAttribute("aria-modal","true");v.setAttribute("aria-labelledby","tvModalTit");
  v.innerHTML=`<form class="tv-form" novalidate><header><h3 id="tvModalTit">Comprovativo de ${rec?"recolha":"entrega"} · <span class="tv-cod">${esc(e.codigo||"")}</span></h3><button type="button" class="btn-secondary" data-f="fechar">Fechar</button></header>
    <fieldset class="tv-res"><legend>O que aconteceu</legend>${[[rec?"recolhido":"entregue",rec?"Recolhido":"Entregue"],["cliente_ausente","Cliente ausente"],["recusado","Recusado"]].map(([k,l],i)=>`<label><input type="radio" name="res" value="${k}"${i?"":" checked"}> ${l}</label>`).join("")}</fieldset>
    <div class="tv-campos"><label>${rec?"Quem entregou a carga":"Quem recebeu"}<input name="nome" autocomplete="off" maxlength="120" value="${esc(D().pessoa(t).nome||"")}"></label>
      <label>Documento de identificação (opcional)<input name="ident" autocomplete="off" maxlength="60" placeholder="Ex.: CC 12345678"></label>
      <label>Volumes conferidos<span class="tv-de"><input name="vol" type="number" min="0" inputmode="numeric" value="${esc(e.quantidade??"")}"> de ${esc(e.quantidade??"—")}</span></label></div>
    <div class="tv-bloco"><b>Fotografias</b><div class="tv-fotos" data-f="fotos"></div><label class="btn-secondary tv-foto-bt">Tirar ou escolher fotografia<input type="file" accept="image/*" capture="environment" multiple hidden></label></div>
    <div class="tv-bloco tv-assin"><b>Assinatura de ${rec?"quem entregou":"quem recebeu"}</b><canvas aria-label="Área para assinar com o dedo"></canvas><button type="button" class="btn-secondary" data-f="limpar">Limpar assinatura</button></div>
    <label class="tv-bloco">Notas (opcional)<textarea name="notas" maxlength="1000" rows="2" placeholder="Ex.: caixa 2 com o canto amolgado"></textarea></label>
    <p class="tv-msg" role="status"></p><button type="submit" class="btn-primary tv-guardar">Guardar comprovativo</button></form>`;
  document.body.appendChild(v);const f=v.querySelector("form"),msg=v.querySelector(".tv-msg"),assin=quadro(v.querySelector("canvas")),boxF=v.querySelector('[data-f="fotos"]');
  const fechar=()=>v.remove();v.querySelector('[data-f="fechar"]').onclick=fechar;v.querySelector('[data-f="limpar"]').onclick=()=>assin.limpar();
  const mostrarFotos=()=>{boxF.innerHTML=fotos.map((d,i)=>`<figure><img src="${d}" alt="Fotografia ${i+1}"><button type="button" data-rm="${i}" aria-label="Remover fotografia ${i+1}">×</button></figure>`).join("")};
  boxF.onclick=ev=>{const b=ev.target.closest("[data-rm]");if(b){fotos.splice(+b.dataset.rm,1);mostrarFotos()}};
  v.querySelector('input[type="file"]').onchange=async ev=>{const lim=window.elologLimitesAnexos?.restantes?.("fotos","prestador",fotos.length)??Infinity;
    for(const x of [...ev.target.files].slice(0,lim))try{fotos.push(await comprimir(x))}catch(er){aviso(er.message,"error")}if([...ev.target.files].length>lim)aviso("Atingiu o número de fotografias que a empresa permite.","warning");ev.target.value="";mostrarFotos()};
  f.onsubmit=async ev=>{ev.preventDefault();const res=f.res.value,ok=["entregue","recolhido"].includes(res);msg.className="tv-msg";
    if(ok&&f.nome.value.trim().length<2){msg.textContent=`Escreva o nome de ${rec?"quem entregou":"quem recebeu"}.`;msg.classList.add("erro");return f.nome.focus()}
    if(ok&&assin.vazio()){msg.textContent="Peça para assinar na área branca.";msg.classList.add("erro");return}
    const bt=f.querySelector(".tv-guardar");bt.disabled=true;bt.textContent="A guardar…";let pos=null;
    try{pos=await Promise.race([new Promise(r=>navigator.geolocation?.getCurrentPosition(p=>r(p),()=>r(null),{enableHighAccuracy:true,timeout:8000,maximumAge:60000})),new Promise(r=>setTimeout(()=>r(null),9000))])}catch(_){}
    await D().guardar({trabalho:t.id,resultado:res,recebido_por:f.nome.value.trim()||null,identificacao:f.ident.value.trim()||null,volumes:f.vol.value===""?null:+f.vol.value,notas:f.notas.value.trim()||null,
      assinatura:ok&&!assin.vazio()?assin.png():null,fotos,lat:pos?+pos.coords.latitude.toFixed(6):null,lon:pos?+pos.coords.longitude.toFixed(6):null,precisao:pos?Math.round(pos.coords.accuracy):null});
    if(D().estado().trabalho?.id===t.id)D().parar(true);fechar();aviso(navigator.onLine?"Comprovativo guardado e a enviar.":"Sem rede: o comprovativo ficou guardado no telemóvel e segue quando houver ligação.","success");depois?.()}}
window.elologComprovativo={abrir:abrirComprovativo};
window.elologTerreno=Object.assign(window.elologTerreno||{},{motorista:abrir});
})();
