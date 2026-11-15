/* Elolog — apoio e reclamações no servidor (v147).
   Com sessão real, os pedidos de apoio e as reclamações deixam de ficar só no navegador: ficam em «tickets» com a conversa
   em «ticket_mensagens». O servidor decide quem vê o quê:
   - cliente: os seus pedidos; uma reclamação ligada a uma encomenda chega também à empresa dessa encomenda;
   - prestador: os pedidos da empresa (apoio e reclamações), pode responder, mudar o estado e escalar para a Elolog;
   - administração Elolog: todos os pedidos, responde e muda o estado.
   Cada novo pedido gera um aviso para a administração (regra do servidor). */
(function(){"use strict";
const P=()=>window.elologProducao,$=id=>document.getElementById(id);
const real=()=>!!window.elologSoServidor?.real?.()&&!!P()?.online?.(),papel=()=>typeof currentUser!=="undefined"?currentUser?.role:"";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):alert(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"").replace(/^LIMITE_EXCEDIDO:\s*/,"");
const quando=v=>{const d=new Date(v);return isNaN(d)?"":d.toLocaleString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit"})};
const ESTADO={aberto:"Aberto",em_tratamento:"Em tratamento",escalado:"Escalado para a Elolog",resolvido:"Resolvido"};
const reclamacao=t=>t.origem==="reclamacao"||/^reclama/i.test(t.assunto||"");
let lista=[],aLer=null;

async function ler(){if(!real())return null;if(aLer)return aLer;aLer=(async()=>{try{const sb=await P().sb();
    const{data,error}=await sb.from("tickets").select("id,codigo,origem,assunto,estado,escalado,created_at,updated_at,resolvido_em,cliente_id,empresa_id,encomenda:encomendas(codigo),cliente:clientes(nome,email),empresa:empresas(nome,nome_comercial)")
      .order("updated_at",{ascending:false}).limit(200);if(error)throw error;lista=data||[];return lista}
  catch(e){console.warn("Apoio:",erro(e));return null}finally{setTimeout(()=>{aLer=null},300)}})();return aLer}

async function criar({origem,assunto,corpo,codigo}){const sb=await P().sb(),u=await P().utilizador();if(!u)throw new Error("Sessão terminada. Entre outra vez.");
  const en=codigo?await P().encomendaPorCodigo(codigo):null;if(codigo&&!en)throw new Error(`Não encontrámos a encomenda ${codigo}.`);
  const t={origem,assunto:String(assunto).slice(0,200),criado_por:u.id,encomenda_id:en?.id||null};
  if(papel()==="cliente"){t.cliente_id=u.id;if(en?.empresa_id)t.empresa_id=en.empresa_id}else{const emp=await P().minhaEmpresa();t.empresa_id=emp?.empresa_id;if(en?.cliente_id)t.cliente_id=en.cliente_id}
  const{data,error}=await sb.from("tickets").insert(t).select("id,codigo").single();if(error)throw error;
  if(corpo){const r=await sb.from("ticket_mensagens").insert({ticket_id:data.id,autor_id:u.id,corpo:String(corpo).slice(0,4000)});if(r.error)throw r.error}
  await ler();desenhar();return data}

function linhaHtml(t){const quem=papel()==="cliente"?(t.empresa?.nome_comercial||t.empresa?.nome||"Elolog"):(t.cliente?.nome||t.cliente?.email||t.empresa?.nome_comercial||t.empresa?.nome||"—");
  return`<article class="ap-linha ap-${esc(t.estado)}"><div><strong>${esc(t.codigo||"Pedido")}, ${esc(t.assunto)}</strong><small>${esc(quem)}${t.encomenda?.codigo?`, encomenda ${esc(t.encomenda.codigo)}`:""}, atualizado ${esc(quando(t.updated_at))}</small></div>
    <span class="ap-estado">${esc(ESTADO[t.estado]||t.estado)}</span><button type="button" class="btn-secondary" onclick="elologApoio.abrir('${esc(t.id)}')">Abrir</button></article>`}
const vazio=t=>`<div class="provider-order-empty">${t}</div>`;

function desenhar(){if(!real())return;const p=papel();
  if(p==="prestador"){const sup=$("providerSupportList"),rec=$("providerComplaintList"),res=$("providerComplaintSummary");
    const a=lista.filter(t=>!reclamacao(t)),r=lista.filter(reclamacao);
    if(sup)sup.innerHTML=a.length?a.map(linhaHtml).join(""):vazio("Ainda não há pedidos de apoio.");
    if(rec)rec.innerHTML=r.length?r.map(linhaHtml).join(""):vazio("Ainda não há reclamações.");
    if(res)res.innerHTML=[["Total",r.length],["Abertas",r.filter(t=>t.estado==="aberto").length],["Em tratamento",r.filter(t=>t.estado==="em_tratamento").length],["Escaladas",r.filter(t=>t.estado==="escalado").length]]
      .map(([k,v])=>`<div><small>${k}</small><strong>${v}</strong></div>`).join("")}
  if(p==="cliente"){const pag=$("clientSupport");if(pag){let box=$("apoioMeusPedidos");if(!box){box=document.createElement("section");box.id="apoioMeusPedidos";box.className="card ap-meus";(pag.querySelector(".card")||pag).after(box)}
    box.innerHTML=`<h3>Os meus pedidos</h3>${lista.length?lista.map(linhaHtml).join(""):vazio("Ainda não fez pedidos de apoio.")}`}}
  if(p==="admin"){const box=$("adminSupportList");if(box)box.innerHTML=lista.length?lista.map(linhaHtml).join(""):vazio("Ainda não há pedidos de apoio nem reclamações.")}}

async function abrir(id){const t=lista.find(x=>x.id===id);if(!t)return;const sb=await P().sb(),u=await P().utilizador(),p=papel();
  const{data:msgs}=await sb.from("ticket_mensagens").select("autor_id,corpo,created_at").eq("ticket_id",id).order("created_at");
  const autor=m=>m.autor_id===u?.id?"Eu":m.autor_id===t.cliente_id?"Cliente":p==="cliente"?"Equipa de apoio":"Equipa";
  const gere=p==="admin"||p==="prestador";
  const j=P().janela({eyebrow:(reclamacao(t)?"RECLAMAÇÃO ":"PEDIDO DE APOIO ")+(t.codigo||""),titulo:t.assunto});
  j.mostrar(`<p class="ed-intro">${esc(ESTADO[t.estado]||t.estado)}${t.encomenda?.codigo?`, encomenda <b>${esc(t.encomenda.codigo)}</b>`:""}. Aberto a ${esc(quando(t.created_at))}.</p>
    <div class="ap-conversa">${(msgs||[]).map(m=>`<div class="ap-msg ${m.autor_id===u?.id?"eu":""}"><small>${esc(autor(m))}, ${esc(quando(m.created_at))}</small><p>${esc(m.corpo)}</p></div>`).join("")||'<p class="fo-nota">Ainda sem mensagens.</p>'}</div>
    ${t.estado==="resolvido"&&!gere?"":`<div class="pc-campo"><label for="apResp">Resposta</label><textarea id="apResp" rows="3" maxlength="4000"></textarea></div>`}
    ${gere?`<div class="pc-campo"><label for="apEstado">Estado</label><select id="apEstado">${Object.entries(ESTADO).filter(([k])=>p==="admin"||k!=="escalado"||true).map(([k,v])=>`<option value="${k}"${k===t.estado?" selected":""}>${v}</option>`).join("")}</select></div>`:""}
    <p class="campo-erro" id="apErro" role="alert"></p>`,
    [{texto:"Fechar",acao:()=>j.fechar()},{texto:gere?"Guardar":"Enviar resposta",principal:true,acao:async()=>{const txt=$("apResp")?.value.trim()||"",est=$("apEstado")?.value||t.estado,el=$("apErro");
      if(!txt&&est===t.estado)return el.textContent="Escreva uma resposta ou mude o estado.";if(est==="resolvido"&&!txt&&gere)return el.textContent="Registe a resposta ou solução antes de resolver.";
      try{if(txt){const r=await sb.from("ticket_mensagens").insert({ticket_id:id,autor_id:u.id,corpo:txt});if(r.error)throw r.error}
        if(gere&&est!==t.estado){const r=await sb.from("tickets").update({estado:est,escalado:est==="escalado"||t.escalado,resolvido_em:est==="resolvido"?new Date().toISOString():null}).eq("id",id);if(r.error)throw r.error}
        j.fechar();await ler();desenhar();aviso(est!==t.estado?`Pedido atualizado: ${ESTADO[est]}.`:"Resposta enviada.","success")}catch(e){el.textContent=erro(e)}}}])}

/* formulário de novo pedido (prestador) */
function novo(reclama){const ops=(typeof providerCompanyOperations==="function"?providerCompanyOperations():[]).filter(o=>o.servidor?.codigo);
  const j=P().janela({eyebrow:"APOIO",titulo:reclama?"Registar reclamação":"Novo pedido de apoio"});
  j.mostrar(`<div class="pc-grelha"><div class="pc-campo ed-largo"><label for="apAssunto">Assunto *</label><input id="apAssunto" maxlength="160"></div>
    <div class="pc-campo ed-largo"><label for="apEnc">Encomenda</label><select id="apEnc"><option value="">Sem encomenda associada</option>${ops.map(o=>`<option value="${esc(o.servidor.codigo)}">${esc(o.servidor.codigo)}, ${esc(o.client||"")}</option>`).join("")}</select></div>
    <div class="pc-campo ed-largo"><label for="apTexto">Descrição *</label><textarea id="apTexto" rows="4" maxlength="4000"></textarea></div></div><p class="campo-erro" id="apErro" role="alert"></p>`,
    [{texto:"Cancelar",acao:()=>j.fechar()},{texto:reclama?"Registar reclamação":"Criar pedido",principal:true,acao:async()=>{const a=$("apAssunto").value.trim(),d=$("apTexto").value.trim(),el=$("apErro");
      if(a.length<3||d.length<5)return el.textContent="Indique o assunto e a descrição.";
      try{const r=await criar({origem:"prestador",assunto:(reclama?"Reclamação: ":"")+a,corpo:d,codigo:$("apEnc").value});j.fechar();aviso(`Pedido ${r.codigo||""} registado no servidor.`,"success")}catch(e){el.textContent=erro(e)}}}])}

function ligar(){const w=(n,f)=>{const o=window[n];if(typeof o!=="function"||o.__apoio)return;const nv=function(){return real()?f.apply(this,arguments):o.apply(this,arguments)};nv.__apoio=1;window[n]=nv};
  w("providerCreateSupportTicket",()=>novo(false));w("providerCreateComplaint",()=>novo(true));
  w("renderProviderSupport",()=>{desenhar();ler().then(desenhar)});w("renderProviderComplaints",()=>{desenhar();ler().then(desenhar)});
  w("sendClientSupport",async()=>{const s=$("supportSubject")?.value||"Apoio",sub=$("supportSubsubject")?.value.trim(),m=$("supportMessage")?.value.trim(),cod=$("supportOrderCode")?.value.trim().toUpperCase(),fb=$("supportFeedback");
    if(/^outro$/i.test(s)&&!sub)return aviso("Indique o subassunto.","warning");if(!m)return aviso("Escreva a sua mensagem antes de enviar.","warning");
    try{const r=await criar({origem:/reclama/i.test(s)?"reclamacao":"cliente",assunto:s+(sub?`, ${sub}`:""),corpo:m,codigo:cod||null});$("supportMessage").value="";if($("supportSubsubject"))$("supportSubsubject").value="";
      if(fb){fb.style.display="block";fb.textContent=`Pedido ${r.codigo||""} enviado. Acompanhe a resposta em «Os meus pedidos».`}}catch(e){aviso(erro(e),"error")}});
  const rp=window.renderAdminPlatformPages;if(typeof rp==="function"&&!rp.__apoio){const nv=function(){const x=rp.apply(this,arguments);if(real()&&papel()==="admin"){desenhar();ler().then(desenhar)}return x};nv.__apoio=1;window.renderAdminPlatformPages=nv}}
ligar();window.addEventListener("load",()=>{ligar();setTimeout(()=>ler().then(()=>desenhar()),3000)});
const sp=window.showPage;if(typeof sp==="function")window.showPage=function(pg){const r=sp.apply(this,arguments);if(pg==="clientSupport"&&real())ler().then(desenhar);return r};
setInterval(()=>{if(real())ler().then(desenhar)},60000);
window.elologApoio={ler,abrir,criar,desenhar};
})();
