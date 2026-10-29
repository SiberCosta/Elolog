/* Elolog — verificação em dois passos do ADMINISTRADOR DA EMPRESA (v81).
   Depois da palavra-passe da empresa e da pessoal, o servidor pede o código de 6 dígitos da aplicação de autenticação
   (Google Authenticator, Microsoft Authenticator, Authy…). Na primeira vez mostra o código QR para registar a aplicação.
   Sem o 2.º passo a base de dados não abre a sessão da empresa (migração 00150). */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const FUNCAO={admin_empresa:"admin",operador:"operador",operador_terreno:"field_operator",armazem:"armazem",financeiro:"financeiro"};
const card=document.querySelector("#loginScreen .login-card");if(!card)return;
card.querySelector("#providerEmployeePage")?.insertAdjacentHTML("afterend",`<div id="providerMfaPage" style="display:none">
  <span class="auth-step-label">ADMINISTRADOR · PASSO 3 · VERIFICAÇÃO</span><h1 id="mfaTitulo">Código de verificação</h1>
  <p id="mfaTexto">Abra a aplicação de autenticação no telemóvel e escreva o código de 6 dígitos da Elolog.</p>
  <div id="mfaRegisto" hidden><ol class="mfa-passos"><li>Instale no telemóvel uma aplicação de autenticação (Google Authenticator, Microsoft Authenticator ou Authy).</li>
    <li>Na aplicação, escolha «Adicionar conta» e leia este código QR.</li><li>Escreva abaixo o código de 6 dígitos que a aplicação mostrar.</li></ol>
    <img id="mfaQr" alt="Código QR para a aplicação de autenticação" width="170" height="170"><p class="mfa-segredo">Sem câmara? Escreva esta chave na aplicação: <code id="mfaSegredo"></code></p></div>
  <div class="form-group"><label for="mfaCodigo">Código de 6 dígitos</label><input id="mfaCodigo" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="000000"></div>
  <p id="mfaErro" class="func-erro" role="alert"></p>
  <button type="button" id="mfaVerificar" class="btn-primary full">Verificar e entrar</button>
  <button type="button" id="mfaCancelar" class="btn-secondary full" style="margin-top:8px">Cancelar</button></div>`);
const pag=$("providerMfaPage");if(!pag)return;
const orig=window.showAuthPage;window.showAuthPage=function(){pag.style.display="none";return orig.apply(this,arguments)};
let cred=null,fator=null;
const erro=m=>{$("mfaErro").textContent=m||""};
async function preparar(sb){const{data:f}=await sb.auth.mfa.listFactors(),v=(f?.totp||[]).find(x=>x.status==="verified");if(v)return{tipo:"verificar",fator:v.id};
  for(const x of(f?.all||[]).filter(x=>x.status!=="verified")){try{await sb.auth.mfa.unenroll({factorId:x.id})}catch(_){}}
  const{data:e,error}=await sb.auth.mfa.enroll({factorType:"totp",friendlyName:"Elolog empresa "+new Date().toISOString().slice(0,10)});if(error)throw new Error("Não foi possível preparar o código. Tente novamente.");
  return{tipo:"registar",fator:e.id,qr:e.totp.qr_code,segredo:e.totp.secret}}
window.elologMfaEmpresa=async function(c){cred=c;erro("");let m;try{const sb=await S().cliente();m=await preparar(sb)}catch(e){alert(e.message||"Erro na verificação.");return}fator=m.fator;
  ["authPage1","providerCompanyPage","providerEmployeePage","providerFuncPage"].forEach(id=>{const el=$(id);if(el)el.style.display="none"});pag.style.display="block";
  const reg=m.tipo==="registar";$("mfaRegisto").hidden=!reg;$("mfaTitulo").textContent=reg?"Proteja a conta da empresa":"Código de verificação";
  $("mfaTexto").textContent=reg?"A partir de agora, o administrador da empresa confirma cada entrada com um código do telemóvel. É só configurar uma vez.":"Abra a aplicação de autenticação no telemóvel e escreva o código de 6 dígitos da Elolog.";
  if(reg){$("mfaQr").src=m.qr;$("mfaSegredo").textContent=m.segredo}$("mfaCodigo").value="";setTimeout(()=>$("mfaCodigo").focus(),60)};
async function verificar(){const codigo=$("mfaCodigo").value.trim(),b=$("mfaVerificar");if(!/^\d{6}$/.test(codigo))return erro("Escreva os 6 dígitos do código.");b.disabled=true;erro("");
  try{const sb=await S().cliente(),{data:ch,error}=await sb.auth.mfa.challenge({factorId:fator});if(error)throw error;
    const{error:e2}=await sb.auth.mfa.verify({factorId:fator,challengeId:ch.id,code:codigo});if(e2)return erro("Código errado ou expirado. Use o código que está agora na aplicação.");
    const{data,error:e3}=await sb.rpc("abrir_sessao_empresa",{p_nome:cred.nome,p_nif:cred.nif,p_senha:cred.senha});if(e3)throw e3;const r=Array.isArray(data)?data[0]:data;
    if(!r?.ok)return erro(r?.mensagem||"Não foi possível abrir a sessão da empresa.");
    currentUser={email:r.email,role:"prestador",name:r.funcionario_nome,providerFunction:FUNCAO[r.papel]||"operador",providerCompany:{id:r.empresa_id,name:r.empresa_nome,nif:cred.nif||"",server:true}};
    cred=null;sessionStorage.setItem("th_user",JSON.stringify(currentUser));localStorage.removeItem("th_user");startApp()}
  catch(e){erro(S()?.mensagem?S().mensagem(e):"Não foi possível verificar o código.")}finally{b.disabled=false}}
$("mfaVerificar").onclick=verificar;$("mfaCodigo").addEventListener("keydown",e=>{if(e.key==="Enter")verificar()});
$("mfaCancelar").onclick=async()=>{cred=null;try{(await S().cliente()).auth.signOut()}catch(_){}window.showAuthPage("providerCompanyPage")};
})();
