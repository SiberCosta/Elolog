/* Elolog — acesso do prestador (v80).
   Funcionário: NIF da empresa + n.º de funcionário + palavra-passe pessoal (sem a palavra-passe da empresa).
   Administrador da empresa: «Sou administrador da empresa» → nome + NIF + palavra-passe da EMPRESA e depois a sua conta (fluxo antigo).
   Servidor: Edge Function «entrar-funcionario» + migração 00149 (n.º de funcionário automático 0001, 0002…). */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor,online=()=>!!S()?.ativo?.(),K="elolog_func_lembrado";
const ler=()=>{try{return JSON.parse(localStorage.getItem(K))}catch(_){return null}},gravar=v=>{try{v?localStorage.setItem(K,JSON.stringify(v)):localStorage.removeItem(K)}catch(_){}};
const card=document.querySelector("#loginScreen .login-card"),empresaPag=$("providerCompanyPage");if(!card||!empresaPag)return;
let modoAdmin=false;
const g=ler();
empresaPag.insertAdjacentHTML("beforebegin",`<div id="providerFuncPage" style="display:none">
  <span class="auth-step-label">ACESSO DO FUNCIONÁRIO</span><h1>Entrar na empresa</h1><p>Use o NIF da empresa, o seu número de funcionário e a sua palavra-passe.</p>
  <div class="form-group"><label for="funcNif">NIF da empresa</label><input id="funcNif" type="text" inputmode="numeric" maxlength="11" autocomplete="organization" placeholder="9 algarismos" value="${g?.nif||""}"></div>
  <div class="form-group"><label for="funcNumero">N.º de funcionário</label><input id="funcNumero" type="text" maxlength="20" autocomplete="username" placeholder="Ex.: 0002" value="${g?.numero||""}"></div>
  <div class="form-group"><label for="funcSenha">Palavra-passe</label><div class="auth-password-wrap"><input id="funcSenha" type="password" autocomplete="current-password" placeholder="A sua palavra-passe"></div></div>
  <label class="porta-lembrar"><input type="checkbox" id="funcLembrar"${g?" checked":""}> Lembrar o NIF e o número neste aparelho</label>
  <p id="funcErro" class="func-erro" role="alert"></p>
  <button type="button" id="funcEntrar" class="btn-primary full">Entrar</button>
  <button type="button" id="funcEsqueci" class="auth-forgot-password">Esqueceu-se da palavra-passe?</button>
  <div class="func-admin"><span>É o administrador da empresa?</span><button type="button" id="funcAdmin" class="btn-secondary full">Sou administrador da empresa</button></div></div>`);
const funcPag=$("providerFuncPage");
empresaPag.insertAdjacentHTML("afterbegin",'<button type="button" class="func-voltar" data-func-voltar>← Entrar como funcionário</button>');
$("providerEmployeePage")?.insertAdjacentHTML("afterbegin",'<button type="button" class="func-voltar" data-func-voltar>← Entrar como funcionário</button>');
const rotulo=(pag,t)=>{const l=$(pag)?.querySelector(".auth-step-label");if(l)l.textContent=t};
rotulo("providerCompanyPage","ADMINISTRADOR · PASSO 1 · EMPRESA");rotulo("providerEmployeePage","ADMINISTRADOR · PASSO 2 · A SUA CONTA");

/* trocar entre funcionário e administrador */
const orig=window.showAuthPage;
window.showAuthPage=function(id){if(id==="providerCompanyPage"&&!modoAdmin){orig.call(this,"providerCompanyPage");empresaPag.style.display="none";funcPag.style.display="block";setTimeout(()=>(g?$("funcSenha"):$("funcNif")).focus(),60);return}
  funcPag.style.display="none";return orig.apply(this,arguments)};
if(empresaPag.style.display==="block")window.showAuthPage("providerCompanyPage");
$("funcAdmin").onclick=()=>{modoAdmin=true;window.showAuthPage("providerCompanyPage");setTimeout(()=>$("providerCompanyName")?.focus(),60)};
card.addEventListener("click",e=>{if(e.target.closest("[data-func-voltar]")){modoAdmin=false;window.showAuthPage("providerCompanyPage")}});
$("funcEsqueci").onclick=()=>window.openProviderPasswordRecovery?.("employee");

/* entrar */
const erro=m=>{$("funcErro").textContent=m||""};
const FUNCAO={admin_empresa:"admin",operador:"operador",operador_terreno:"field_operator",armazem:"armazem",financeiro:"financeiro"};
const semZeros=v=>String(v||"").trim().toUpperCase().replace(/^0+/,"");
function entrar(u,empresa){currentUser={email:u.email,role:"prestador",name:u.nome,providerFunction:u.funcao,providerCompany:empresa};
  sessionStorage.setItem("th_user",JSON.stringify(currentUser));localStorage.removeItem("th_user");startApp()}
async function submeter(){erro("");const nif=$("funcNif").value.replace(/\s/g,""),numero=$("funcNumero").value.trim(),senha=$("funcSenha").value;
  if(!/^\d{9}$/.test(nif))return erro("Indique o NIF da empresa (9 algarismos).");if(!numero)return erro("Indique o seu número de funcionário.");if(!senha)return erro("Indique a sua palavra-passe.");
  gravar($("funcLembrar").checked?{nif,numero}:null);const b=$("funcEntrar");b.disabled=true;
  try{if(online()){let r;try{r=await S().chamarFuncao("entrar-funcionario",{nif,numero,senha})}catch(e){if(e.codigo==="admin"){$("funcAdmin").click();aviso(e.message)}else erro(e.message);return}
      const sb=await S().cliente(),{error}=await sb.auth.setSession(r.session);if(error)return erro("Não foi possível iniciar a sessão. Tente novamente.");const f=r.funcionario;
      providerCompanyAuth={id:r.funcionario.empresa_id,name:r.funcionario.empresa_nome,nif,server:true};entrar({email:f.email,nome:f.nome,funcao:FUNCAO[f.papel]||"operador"},{id:f.empresa_id,name:f.empresa_nome,nif,server:true});return}
    const perfil=(typeof getProviderProfiles==="function"?getProviderProfiles():[]).find(p=>String(p.nif||"").replace(/\s/g,"")===nif);if(!perfil)return erro("NIF, número de funcionário ou palavra-passe incorretos.");
    if(typeof ensureProviderInitialAdmin==="function")ensureProviderInitialAdmin(perfil);numerar();
    const lista=getProviderEmployees(),nome=String(perfil.name||"").trim().toLowerCase(),f=lista.find(e=>(String(e.providerId||"")===String(perfil.id)||String(e.company||"").trim().toLowerCase()===nome)&&semZeros(e.internalNo)===semZeros(numero));
    if(!f||!f.password||f.password!==senha)return erro("NIF, número de funcionário ou palavra-passe incorretos.");
    if(f.role==="admin"){$("funcAdmin").click();return aviso("O administrador da empresa entra com a palavra-passe da empresa.")}
    if(f.active===false)return erro("Esta conta de funcionário está desativada. Contacte o administrador da empresa.");
    f.lastAccess=new Date().toLocaleString("pt-PT");f.lastAccessAt=new Date().toISOString();saveProviderEmployees(lista);
    providerCompanyAuth={id:perfil.id,name:perfil.name,nif:perfil.nif};entrar({email:f.email,nome:f.name,funcao:f.role},providerCompanyAuth)}
  finally{b.disabled=false}}
const aviso=m=>window.showPlatformNotice?window.showPlatformNotice(m,"info"):alert(m);
$("funcEntrar").onclick=submeter;["funcNif","funcNumero","funcSenha"].forEach(id=>$(id).addEventListener("keydown",e=>{if(e.key==="Enter")submeter()}));

/* modo demonstração: dar n.º a quem não tem (0001, 0002… por empresa) */
function numerar(){if(online()||typeof getProviderEmployees!=="function")return;const l=getProviderEmployees(),por={};let mudou=false;
  l.forEach(e=>{const k=String(e.providerId||e.company||"").toLowerCase();por[k]=por[k]||[];por[k].push(e)});
  Object.values(por).forEach(g=>{let n=g.reduce((m,e)=>Math.max(m,parseInt(e.internalNo,10)||0),0);g.forEach(e=>{if(!String(e.internalNo||"").trim()){e.internalNo=String(++n).padStart(4,"0");mudou=true}})});
  if(mudou)saveProviderEmployees(l)}
try{numerar()}catch(_){}
window.elologLoginFuncionario={numerar};
})();
