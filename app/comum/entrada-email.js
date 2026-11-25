/* Elolog — entrada por email para todos (v163).
   Uma só entrada: email (ou telemóvel) e palavra-passe. Depois de entrar, o servidor diz que conta é (entrar_por_email,
   migração 00200) e a aplicação abre a área certa:
   · cliente → área de cliente; · funcionário → área do prestador (sessão da empresa aberta no servidor);
   · administrador da empresa → pede a palavra-passe da empresa e o código de verificação (como até aqui);
   · equipa Elolog → passa para a Consola (com o email já escrito).
   A entrada antiga com NIF e n.º de funcionário continua disponível numa ligação discreta. Nada muda nos dados. */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const q=new URLSearchParams((window.ELOLOG_RETORNO||location).search||""),porta=q.get("acesso")||"cliente",modoNif=q.has("nif");
const FUNCAO={admin_empresa:"admin",operador:"operador",operador_terreno:"field_operator",armazem:"armazem",financeiro:"financeiro"};
const card=document.querySelector("#loginScreen .login-card");if(!card)return;
const ir=s=>{try{localStorage.setItem("elolog_porta",JSON.stringify(s==="?cliente"?"cliente":"prestador"))}catch(_){}location.href=location.pathname+s};

/* consola: o email vem escrito quando a conta da equipa entrou pela porta geral */
if(porta==="administracao"){const em=sessionStorage.getItem("elolog_consola_email");
  if(em){sessionStorage.removeItem("elolog_consola_email");setTimeout(()=>{const i=$("directLoginEmail");if(i){i.value=em;$("directLoginPassword")?.focus()}},500)}}

/* ---- vista: uma só entrada ---- */
function vista(){if(porta==="administracao")return;const tabs=$("portaTabs");if(tabs)tabs.hidden=true;
  if(!modoNif){if(porta==="prestador"&&$("authPage1")?.style.display==="none")window.showAuthPage?.("authPage1");
    const h=$("authPage1")?.querySelector("h1");if(h)h.textContent="Entrar";
    const em=$("directLoginEmail");if(em){em.placeholder="Email ou telemóvel";em.setAttribute("aria-label","Email ou telemóvel")}
    const pw=$("directLoginPassword");if(pw)pw.setAttribute("aria-label","Palavra-passe");
    const t=$("directLoginTitle");if(t)t.textContent="Entrar com email ou telemóvel";
    if(!$("entradaNif"))$("forgotClientPasswordButton")?.insertAdjacentHTML("afterend",'<button type="button" id="entradaNif" class="entrada-alt">Entrar com NIF e n.º de funcionário</button>')}
  else if(!$("entradaEmail"))$("providerFuncPage")?.insertAdjacentHTML("afterbegin",'<button type="button" id="entradaEmail" class="entrada-alt entrada-voltar">← Entrar com email</button>')}
card.addEventListener("click",e=>{if(e.target.closest("#entradaNif"))ir("?acesso=prestador&nif");if(e.target.closest("#entradaEmail"))ir("?cliente")});
vista();setTimeout(vista,300);setTimeout(vista,1200);

/* ---- palavra-passe da empresa (só o administrador da empresa) ---- */
$("authPage1")?.insertAdjacentHTML("afterend",`<div id="entradaEmpresaPage" style="display:none">
  <h1>Palavra-passe da empresa</h1><p class="entrada-empresa" id="entradaEmpresaNome"></p>
  <div class="form-group"><label for="entradaEmpresaSenha">Palavra-passe da empresa</label><div class="auth-password-wrap"><input id="entradaEmpresaSenha" type="password" autocomplete="off"></div></div>
  <p id="entradaEmpresaErro" class="func-erro" role="alert"></p>
  <button type="button" id="entradaEmpresaOk" class="btn-primary full">Continuar</button>
  <button type="button" id="entradaEmpresaVoltar" class="entrada-alt">← Voltar</button></div>`);
let pend=null;
const sap=window.showAuthPage;if(typeof sap==="function")window.showAuthPage=function(){const p=$("entradaEmpresaPage");if(p)p.style.display="none";return sap.apply(this,arguments)};
const erro=m=>{const e=$("entradaEmpresaErro");if(e)e.textContent=m||""};
const msg=e=>S()?.mensagem?S().mensagem(e):(e?.message||"Não foi possível concluir.");
function mostrarEmpresa(r){pend=r;["authPage1","providerCompanyPage","providerEmployeePage","providerFuncPage"].forEach(id=>{const el=$(id);if(el)el.style.display="none"});
  $("entradaEmpresaNome").textContent=`${r.empresa_nome} · NIF ${r.empresa_nif}`;$("entradaEmpresaSenha").value="";erro("");
  $("entradaEmpresaPage").style.display="block";setTimeout(()=>$("entradaEmpresaSenha").focus(),60)}
function abrir(u,emp){const user={email:u.email,role:"prestador",name:u.nome,providerFunction:FUNCAO[u.papel]||"operador",providerCompany:{id:emp.id,name:emp.nome,nif:emp.nif||"",server:true}};
  try{providerCompanyAuth={id:emp.id,name:emp.nome,nif:emp.nif||"",server:true}}catch(_){}return user}
async function confirmarEmpresa(){const senha=$("entradaEmpresaSenha").value,b=$("entradaEmpresaOk");if(!pend)return;if(!senha)return erro("Escreva a palavra-passe da empresa.");
  b.disabled=true;erro("");
  try{const sb=await S().cliente(),cred={nome:pend.empresa_nome_registo,nif:pend.empresa_nif,senha};
    const{data,error}=await sb.rpc("abrir_sessao_empresa",{p_nome:cred.nome,p_nif:cred.nif,p_senha:senha});if(error)throw error;const r=Array.isArray(data)?data[0]:data;
    if(r&&!r.ok&&r.mensagem==="MFA_NECESSARIO"){$("entradaEmpresaPage").style.display="none";return window.elologMfaEmpresa?.(cred)}
    if(!r?.ok)return erro(r?.mensagem||"Não foi possível abrir a sessão da empresa.");
    currentUser=abrir({email:r.email,nome:r.funcionario_nome,papel:r.papel},{id:r.empresa_id,nome:r.empresa_nome,nif:cred.nif});pend=null;
    sessionStorage.setItem("th_user",JSON.stringify(currentUser));localStorage.removeItem("th_user");startApp()}
  catch(e){erro(msg(e))}finally{b.disabled=false}}
async function voltar(){pend=null;try{(await S().cliente()).auth.signOut()}catch(_){}$("entradaEmpresaPage").style.display="none";window.showAuthPage?.("authPage1")}
$("entradaEmpresaOk").onclick=confirmarEmpresa;$("entradaEmpresaVoltar").onclick=voltar;
$("entradaEmpresaSenha").addEventListener("keydown",e=>{if(e.key==="Enter")confirmarEmpresa()});
/* «Voltar ao início» no código de verificação: na entrada por email volta ao formulário de email */
$("mfaCancelar")?.addEventListener("click",()=>{if(!modoNif)setTimeout(()=>window.showAuthPage?.("authPage1"),0)});

/* ---- chamado por loginCliente quando a conta não é de cliente ---- */
async function continuar({sb,tipo,email}){
  if(tipo==="equipa"){try{await sb.auth.signOut()}catch(_){}sessionStorage.setItem("elolog_consola_email",email||"");location.href=location.pathname+"?acesso=administracao";return{pendente:true}}
  const{data,error}=await sb.rpc("entrar_por_email");if(error)throw error;const r=Array.isArray(data)?data[0]:data;
  if(!r)throw new Error("Não foi possível identificar a conta.");
  if(r.tipo==="recusado")throw new Error(r.mensagem);
  if(r.tipo==="admin_empresa"){mostrarEmpresa(r);return{pendente:true}}
  if(r.tipo==="funcionario")return{user:abrir({email:r.email,nome:r.funcionario_nome,papel:r.papel},{id:r.empresa_id,nome:r.empresa_nome,nif:r.empresa_nif})};
  return null}
window.elologEntrada={continuar};
})();
