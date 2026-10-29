/* Elolog — prestador criado pela equipa Elolog com CÓDIGO DE ACESSO TEMPORÁRIO (v76).
   Administração: «+ Criar prestador» deixa de pedir palavra-passe; a plataforma gera o código (72 h) e envia-o por email ao administrador
   da empresa; «Primeiros acessos por concluir» permite reenviar. Prestador: no primeiro início de sessão é obrigatório criar a
   palavra-passe da empresa e a pessoal (janela que não se fecha). Servidor: Edge Function «criar-prestador» + migração 00146. */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor,online=()=>!!S()?.ativo?.();
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const aviso=(m,t)=>window.showPlatformNotice?window.showPlatformNotice(m,t||"info"):alert(m);
const eu=()=>typeof currentUser!=="undefined"?currentUser:null;
const fraca=s=>s.length<8||s.length>72||!/[a-zA-Z]/.test(s)||!/\d/.test(s);
function codigoDemo(){const A="ABCDEFGHJKMNPQRSTUVWXYZ",D="23456789",T=A+D,r=crypto.getRandomValues(new Uint8Array(8));const c=[...r].map((b,i)=>(i===0?A:i===1?D:T)[b%(i===0?A.length:i===1?D.length:T.length)]);return`ELO-${c.slice(0,4).join("")}-${c.slice(4).join("")}`}
const quando=iso=>new Date(iso).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"});

/* ---- janela simples (resultado do código / primeiro acesso) ---- */
function janela(html,{fixa=false}={}){$("paJanela")?.remove();const f=document.createElement("div");f.id="paJanela";f.className="pa-fundo";
  f.innerHTML=`<section class="pa-caixa" role="dialog" aria-modal="true" aria-labelledby="paTitulo">${html}</section>`;document.body.appendChild(f);
  if(!fixa)f.addEventListener("click",e=>{if(e.target===f||e.target.closest("[data-fechar]"))f.remove()});setTimeout(()=>f.querySelector("input,button")?.focus(),50);return f}
function mostrarCodigo(r,email){janela(`<h3 id="paTitulo">Prestador criado</h3>${r.enviado?`<p>O código de acesso temporário foi enviado para <strong>${esc(email)}</strong>. É válido até ${quando(r.expira_em)}.</p>`
  :`<p>O email não foi enviado. Entregue este código ao administrador da empresa por um meio seguro (válido até ${quando(r.expira_em)}):</p><p class="pa-codigo">${esc(r.codigo)}</p>`}
  <p class="pa-nota">No primeiro acesso, o administrador usa o código nos dois passos do login e é obrigado a criar a palavra-passe da empresa e a pessoal.</p><div class="pa-acoes"><button type="button" class="btn-primary" data-fechar>Fechar</button></div>`)}

/* ---- administração: criar prestador com código ---- */
function prepararFormulario(){[$("newProviderPassword"),$("newProviderPasswordConfirm")].forEach(i=>{const l=i?.closest("label");if(l){l.hidden=true;l.style.display="none"}if(i)i.required=false});
  const l=$("newProviderAdminEmail")?.closest("label");if(l&&!$("paNotaCodigo"))l.insertAdjacentHTML("afterend",'<p id="paNotaCodigo" class="pa-nota wide">A palavra-passe não é definida aqui: a Elolog gera um <strong>código de acesso temporário (72 h)</strong> e envia-o para o email do administrador. No primeiro acesso ele cria as palavras-passe definitivas.</p>')}
const valor=id=>$(id)?.value.trim()||"";
const base=window.submitAdminProvider;
window.submitAdminProvider=async function(ev){ev?.preventDefault?.();if(eu()?.role!=="admin")return;const erroF=(m,c)=>window.adminProviderFormError?window.adminProviderFormError(m,c):aviso(m,"error");
  const empresa={nome:valor("newProviderLegalName"),nome_comercial:valor("newProviderTradeName"),nif:valor("newProviderNif").replace(/\s/g,""),email:valor("newProviderEmail").toLowerCase(),telefone:valor("newProviderPhone"),
    morada:valor("newProviderAddress"),codigo_postal:valor("newProviderPostalCode"),cidade:valor("newProviderCity"),pais:valor("newProviderCountry")},adm={nome:valor("newProviderAdminName"),email:valor("newProviderAdminEmail").toLowerCase()};
  if(!empresa.nome)return erroF("Indique o nome legal da empresa.","newProviderLegalName");if(!/^\d{9}$/.test(empresa.nif))return erroF("O NIF da empresa deve ter 9 algarismos.","newProviderNif");
  if(!/^\S+@\S+\.\S+$/.test(empresa.email))return erroF("Indique um e-mail corporativo válido.","newProviderEmail");if(!adm.nome)return erroF("Indique o nome do administrador da empresa.","newProviderAdminName");
  if(!/^\S+@\S+\.\S+$/.test(adm.email))return erroF("Indique um e-mail de acesso válido.","newProviderAdminEmail");
  if(online()){const b=document.querySelector("#adminProviderDrawer [type=submit]");if(b)b.disabled=true;
    try{const r=await S().chamarFuncao("criar-prestador",{acao:"criar",empresa,admin:adm,plano:valor("newProviderPlan"),aprovada:valor("newProviderStatus")==="Ativo"});
      window.closeAdminProviderDrawer?.();mostrarCodigo(r,adm.email);window.renderAdminPlatformPages?.();pendentes(true)}catch(e){erroF(e.message||"Não foi possível criar o prestador.","newProviderLegalName")}finally{if(b)b.disabled=false}return}
  const cod=codigoDemo(),expira=new Date(Date.now()+72*3600e3).toISOString();$("newProviderPassword").value=cod;$("newProviderPasswordConfirm").value=cod;const alerta=window.alert;window.alert=()=>{};
  try{base?.call(this,ev)}finally{window.alert=alerta}
  const emp=(typeof getProviderEmployees==="function"?getProviderEmployees():[]),x=emp.find(f=>String(f.email).toLowerCase()===adm.email);if(x){x.mustChangePassword=true;x.tempExpiresAt=expira;saveProviderEmployees(emp)}
  const perfis=JSON.parse(localStorage.getItem("elolog_profiles")||"[]"),p=perfis.find(q=>q.type==="prestador"&&String(q.nif)===empresa.nif);if(p){p.tempAccess={expiresAt:expira};localStorage.setItem("elolog_profiles",JSON.stringify(perfis))}
  if(x)mostrarCodigo({enviado:false,codigo:cod,expira_em:expira},adm.email)};
const abrir=window.openAdminProviderDrawer;if(typeof abrir==="function")window.openAdminProviderDrawer=function(){const r=abrir.apply(this,arguments);prepararFormulario();return r};

/* ---- administração: primeiros acessos por concluir (reenviar código) ---- */
let lidoEm=0;
async function pendentes(forcar){const pag=$("adminActiveProviders");if(!pag||eu()?.role!=="admin"||!online())return;if(!forcar&&Date.now()-lidoEm<60000&&$("paPendentes"))return;lidoEm=Date.now();
  let lista=[];try{const sb=await S().cliente(),{data,error}=await sb.rpc("acessos_temporarios_pendentes");if(error)throw error;lista=data||[]}catch(_){return}
  let card=$("paPendentes");if(!lista.length){card?.remove();return}if(!card){card=document.createElement("div");card.id="paPendentes";card.className="card";pag.appendChild(card)}
  card.innerHTML=`<div class="admin-section-heading"><div><h3>Primeiros acessos por concluir</h3><p>Prestadores criados pela Elolog que ainda não trocaram o código temporário.</p></div></div><div class="table-wrapper"><table><thead><tr><th>Empresa</th><th>NIF</th><th>Administrador</th><th>Código válido até</th><th></th></tr></thead><tbody>
    ${lista.map(l=>`<tr><td>${esc(l.empresa)}</td><td>${esc(l.nif)}</td><td>${esc(l.admin_email)}</td><td>${l.expirado?'<span class="pa-expirado">Expirado</span>':quando(l.expira_em)}</td><td><button type="button" class="btn-secondary" data-reenviar="${esc(l.empresa_id)}" data-email="${esc(l.admin_email)}">Reenviar código</button></td></tr>`).join("")}</tbody></table></div>`;
  card.querySelectorAll("[data-reenviar]").forEach(b=>b.onclick=async()=>{b.disabled=true;try{const r=await S().chamarFuncao("criar-prestador",{acao:"reenviar",empresa_id:b.dataset.reenviar});mostrarCodigo(r,b.dataset.email);pendentes(true)}
    catch(e){aviso(e.message||"Não foi possível reenviar.","error")}finally{b.disabled=false}})}
const rap=window.renderAdminPlatformPages;let t=0;if(typeof rap==="function")window.renderAdminPlatformPages=function(){const r=rap.apply(this,arguments);clearTimeout(t);t=setTimeout(pendentes,250);return r};

/* ---- prestador: primeiro acesso obrigatório ---- */
function sair(){try{window.logout?.()}catch(_){location.reload()}}
function exigir({expirado,expira,demo}){if(expirado)return janela(`<h3 id="paTitulo">O código temporário expirou</h3><p>Peça um novo código à equipa Elolog (contacto@elolog.pt) e volte a entrar.</p><div class="pa-acoes"><button type="button" class="btn-primary" id="paSair">Sair</button></div>`,{fixa:true}).querySelector("#paSair").onclick=sair;
  const f=janela(`<h3 id="paTitulo">Primeiro acesso: crie as suas palavras-passe</h3><p>Entrou com um código temporário${expira?` (válido até ${quando(expira)})`:""}. Para continuar, defina as palavras-passe definitivas.</p>
    <form id="paForm" novalidate><fieldset><legend>Palavra-passe da empresa <small>(1.º passo do login)</small></legend><label>Nova<input id="paEmp1" type="password" autocomplete="new-password" maxlength="72"></label><label>Repetir<input id="paEmp2" type="password" autocomplete="new-password" maxlength="72"></label></fieldset>
    <fieldset><legend>A sua palavra-passe <small>(2.º passo do login)</small></legend><label>Nova<input id="paPes1" type="password" autocomplete="new-password" maxlength="72"></label><label>Repetir<input id="paPes2" type="password" autocomplete="new-password" maxlength="72"></label></fieldset>
    <p class="pa-nota">8 a 72 caracteres, com letras e números. Use palavras-passe diferentes.</p><p id="paErro" class="pa-erro" role="alert"></p>
    <div class="pa-acoes"><button type="button" class="btn-secondary" id="paSair">Sair</button><button type="submit" class="btn-primary">Guardar e continuar</button></div></form>`,{fixa:true});
  f.querySelector("#paSair").onclick=sair;f.querySelector("#paForm").onsubmit=async e=>{e.preventDefault();const v=id=>$(id).value,err=m=>{$("paErro").textContent=m};
    if(fraca(v("paEmp1"))||fraca(v("paPes1")))return err("As palavras-passe devem ter 8 a 72 caracteres, com letras e números.");if(v("paEmp1")!==v("paEmp2"))return err("As palavras-passe da empresa não coincidem.");
    if(v("paPes1")!==v("paPes2"))return err("As suas palavras-passe não coincidem.");if(v("paEmp1")===v("paPes1"))return err("Use palavras-passe diferentes para a empresa e para a sua conta.");
    const b=e.submitter;if(b)b.disabled=true;try{if(demo)demo(v("paEmp1"),v("paPes1"));else await S().chamarFuncao("criar-prestador",{acao:"concluir",senha_empresa:v("paEmp1"),senha_pessoal:v("paPes1")});
      $("paJanela")?.remove();aviso("Palavras-passe criadas. Bem-vindo à Elolog!","success");if(!demo)setTimeout(()=>location.reload(),900)}catch(x){err(x.message||"Não foi possível guardar.")}finally{if(b)b.disabled=false}}}
async function verificar(){const u=eu();if(!u||u.role!=="prestador")return;
  if(online()){try{const sb=await S().cliente(),{data}=await sb.rpc("primeiro_acesso");if(data?.pendente)exigir({expirado:data.expirado,expira:data.expira_em})}catch(_){}return}
  const emp=typeof getProviderEmployees==="function"?getProviderEmployees():[],x=emp.find(f=>String(f.email).toLowerCase()===String(u.email).toLowerCase()&&f.mustChangePassword);if(!x)return;
  exigir({expirado:x.tempExpiresAt&&Date.parse(x.tempExpiresAt)<Date.now(),expira:x.tempExpiresAt,demo:(se,sp)=>{const l=getProviderEmployees(),y=l.find(f=>f.id===x.id);y.password=sp;delete y.mustChangePassword;delete y.tempExpiresAt;saveProviderEmployees(l);
    const perfis=JSON.parse(localStorage.getItem("elolog_profiles")||"[]"),p=perfis.find(q=>q.type==="prestador"&&q.tempAccess&&(q.adminEmail||"").toLowerCase()===String(u.email).toLowerCase());if(p){p.password=se;delete p.tempAccess;localStorage.setItem("elolog_profiles",JSON.stringify(perfis))}}})}
const st=window.startApp;if(typeof st==="function")window.startApp=function(){const r=st.apply(this,arguments);Promise.resolve(r).then(()=>setTimeout(verificar,400));return r};
window.elologPrimeiroAcesso={verificar,pendentes};
})();
