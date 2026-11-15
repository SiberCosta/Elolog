/* Elolog — administração com dados do servidor (v139).
   Com sessão real de administrador, a página «Clientes» e o cartão de cada prestador em «Documentação dos prestadores»
   (Equipa e Atividade) passam a contar o que está no servidor: clientes registados, funcionários de cada empresa, encomendas
   e clientes associados. Antes contavam só o que estava guardado neste navegador (por isso apareciam 0 funcionários e
   «Ainda não há clientes» enquanto o Centro de comando, que já lia do servidor, mostrava 2 clientes novos).
   A leitura usa a permissão de leitura do administrador da plataforma (políticas «admin_plataforma_le»). */
(function(){"use strict";
const P=()=>window.elologProducao,esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="admin"&&currentUser?.authenticatedBy==="servidor"&&!!P()?.online?.();
const norm=v=>String(v||"").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"");
let dados=null,lidoEm=0,aLer=null;

async function ler(forcar){if(!ativo())return null;if(!forcar&&dados&&Date.now()-lidoEm<60000)return dados;if(aLer)return aLer;
  aLer=(async()=>{try{const sb=await P().sb();
    const[emp,fun,cli,enc]=await Promise.all([sb.from("empresas").select("id,nome,nome_comercial,nif"),sb.from("funcionarios").select("id,empresa_id,nome,ativo"),
      sb.from("clientes").select("id,nome,email,telefone,nif,estado,created_at").order("created_at",{ascending:false}).limit(1000),
      sb.from("encomendas").select("id,codigo,empresa_id,cliente_id,cliente_nome,estado,origem,destino,preco_total,created_at").limit(5000)]);
    const erro=[emp,fun,cli,enc].find(r=>r.error);if(erro)throw erro.error;
    dados={empresas:emp.data||[],funcionarios:fun.data||[],clientes:cli.data||[],encomendas:enc.data||[]};lidoEm=Date.now();return dados}
  catch(e){console.warn("Administração: dados do servidor indisponíveis",e?.message||e);return dados}finally{aLer=null}})();return aLer}

const empresaDe=perfil=>dados?.empresas.find(e=>String(e.id)===String(perfil?.id)||(perfil?.nif&&String(e.nif)===String(perfil.nif))||norm(e.nome)===norm(perfil?.name)||norm(e.nome_comercial)===norm(perfil?.name||perfil?.tradeName));

/* cartão do prestador: troca os blocos «Equipa» e «Atividade» pelos números do servidor */
function ligarCartao(){const f=window.providerAdminDocumentCard;if(typeof f!=="function"||f.__srv)return;
  const novo=function(perfil){const html=f.apply(this,arguments);if(!ativo()||!dados)return html;const e=empresaDe(perfil);if(!e)return html;
    const fs=dados.funcionarios.filter(x=>x.empresa_id===e.id),at=fs.filter(x=>x.ativo!==false).length,os=dados.encomendas.filter(x=>x.empresa_id===e.id),
      cl=new Set(os.map(x=>x.cliente_id||x.cliente_nome).filter(Boolean)).size;
    return html.replace(/<div><small>Equipa<\/small>[\s\S]*?<\/div><div><small>Atividade<\/small>[\s\S]*?<\/span><\/div>/,
      `<div><small>Equipa</small><strong>${at}/${fs.length} ativos</strong><span>${fs.length} ${fs.length===1?"funcionário registado":"funcionários registados"}</span></div><div><small>Atividade</small><strong>${os.length} ${os.length===1?"operação":"operações"}</strong><span>${cl} ${cl===1?"cliente associado":"clientes associados"}</span></div>`)};
  novo.__srv=1;window.providerAdminDocumentCard=novo}

/* página «Clientes»: os clientes registados no servidor, com as encomendas de cada um */
function desenharClientes(){const box=document.getElementById("adminClientsList");if(!box||!ativo()||!dados)return;if(window.elologAdminClientes)return window.elologAdminClientes.desenhar(dados);const cs=dados.clientes;
  if(!cs.length){box.innerHTML='<div class="provider-order-empty">Ainda não há clientes registados.</div>';return}
  const emp=id=>{const e=dados.empresas.find(x=>x.id===id);return e?(e.nome_comercial||e.nome):""};
  box.innerHTML=`<p class="ac-conta">${cs.length} ${cs.length===1?"cliente registado":"clientes registados"} na plataforma</p>`+cs.map(c=>{const os=dados.encomendas.filter(o=>o.cliente_id===c.id),pres=[...new Set(os.map(o=>emp(o.empresa_id)).filter(Boolean))];
    return`<div class="admin-record-row"><div><strong>${esc(c.nome||c.email||"Cliente")}</strong><small>${esc([c.email,c.telefone,c.nif?"NIF "+c.nif:""].filter(Boolean).join(", "))}</small>
      <small>Registado a ${new Date(c.created_at).toLocaleDateString("pt-PT")}, ${os.length} ${os.length===1?"encomenda":"encomendas"}${c.estado&&c.estado!=="ativo"?`, ${esc(c.estado)}`:""}</small></div>
      <span>${esc(pres.join(", ")||"Sem encomendas")}</span><div class="admin-action-menu"><button class="btn-secondary" onclick="adminClientHistory('${esc(c.nome||c.email||"")}')">Histórico</button></div></div>`}).join("")}

async function atualizar(forcar){if(!ativo())return;await ler(forcar);ligarCartao();
  const pag=document.querySelector(".page.active")?.id;if(pag==="adminProviderDocuments"&&typeof renderAdminPlatformPages==="function")try{renderAdminPlatformPages()}catch(_){}
  desenharClientes()}
function ligar(){ligarCartao();const r=window.renderAdminPlatformPages;if(typeof r==="function"&&!r.__srv){const n=function(){const x=r.apply(this,arguments);if(ativo()&&dados)desenharClientes();return x};n.__srv=1;window.renderAdminPlatformPages=n}
  const sp=window.showAdminPage;if(typeof sp==="function"&&!sp.__srv){const n=function(pg){const x=sp.apply(this,arguments);if(ativo()&&/adminClients|adminProviderDocuments/.test(pg||""))atualizar();return x};n.__srv=1;window.showAdminPage=n}}
ligar();window.addEventListener("load",()=>{ligar();setTimeout(()=>atualizar(true),2500)});setInterval(()=>{if(ativo())atualizar()},60000);
window.elologAdminServidor={ler,atualizar};
})();
