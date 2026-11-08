/* Elolog — verificação em dois passos do ADMINISTRADOR DA EMPRESA (v81; v107: código por email).
   Depois da palavra-passe da empresa e da pessoal, o administrador confirma a entrada com um código de 6 dígitos:
   - por email (por omissão): o servidor envia o código para o email pessoal do administrador (Edge Function recuperar-acesso,
     ação «codigo_entrada»); vale 10 minutos, só nesta sessão (migração 00165);
   - ou pela aplicação de autenticação (Google Authenticator, Microsoft Authenticator, Authy…), para quem a preferir.
   Sem o 2.º passo a base de dados não abre a sessão da empresa (migração 00150). */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor;
const FUNCAO={admin_empresa:"admin",operador:"operador",operador_terreno:"field_operator",armazem:"armazem",financeiro:"financeiro"};
const card=document.querySelector("#loginScreen .login-card");if(!card)return;
card.querySelector("#providerEmployeePage")?.insertAdjacentHTML("afterend",`<div id="providerMfaPage" style="display:none">
  <span class="auth-step-label">ADMINISTRADOR, PASSO 3: VERIFICAÇÃO</span><h1 id="mfaTitulo">Código de verificação</h1>
  <p id="mfaTexto"></p>
  <div id="mfaRegisto" hidden><ol class="mfa-passos"><li>Instale no telemóvel uma aplicação de autenticação (Google Authenticator, Microsoft Authenticator ou Authy).</li>
    <li>Na aplicação, escolha «Adicionar conta» e leia este código QR.</li><li>Escreva abaixo o código de 6 dígitos que a aplicação mostrar.</li></ol>
    <img id="mfaQr" alt="Código QR para a aplicação de autenticação" width="170" height="170"><p class="mfa-segredo">Sem câmara? Escreva esta chave na aplicação: <code id="mfaSegredo"></code></p></div>
  <div class="form-group"><label for="mfaCodigo">Código de 6 dígitos</label><input id="mfaCodigo" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="000000"></div>
  <p id="mfaErro" class="func-erro" role="alert"></p><p id="mfaInfo" class="mfa-info" role="status"></p>
  <button type="button" id="mfaVerificar" class="btn-primary full">Verificar e entrar</button>
  <div class="mfa-alternativas"><button type="button" id="mfaReenviar" class="mfa-lig" hidden>Enviar outro código</button>
    <button type="button" id="mfaPorEmail" class="mfa-lig" hidden>Receber o código por email</button>
    <button type="button" id="mfaPorApp" class="mfa-lig" hidden>Prefiro usar uma aplicação de autenticação</button></div>
  <button type="button" id="mfaCancelar" class="btn-secondary full" style="margin-top:8px">Voltar ao início</button></div>`);
const pag=$("providerMfaPage");if(!pag)return;
const orig=window.showAuthPage;window.showAuthPage=function(){pag.style.display="none";return orig.apply(this,arguments)};
let cred=null,fator=null,modo="email",temApp=false,espera=null;
const erro=m=>{$("mfaErro").textContent=m||""},info=m=>{$("mfaInfo").textContent=m||""};
const msg=e=>S()?.mensagem?S().mensagem(e):(e?.message||"Não foi possível concluir.");

function ecra(m){modo=m;const reg=m==="registar";$("mfaRegisto").hidden=!reg;erro("");
  $("mfaTitulo").textContent=reg?"Configurar a aplicação de autenticação":"Código de verificação";
  if(m==="app")$("mfaTexto").textContent="Abra a aplicação de autenticação no telemóvel e escreva o código de 6 dígitos da Elolog.";
  if(reg)$("mfaTexto").textContent="Leia o código QR com a aplicação e escreva o código que ela mostrar. Só é preciso fazer isto uma vez.";
  $("mfaReenviar").hidden=m!=="email";$("mfaPorEmail").hidden=m==="email";$("mfaPorApp").hidden=m!=="email";
  $("mfaCodigo").value="";setTimeout(()=>$("mfaCodigo").focus(),60)}

/** Pede ao servidor que envie o código para o email pessoal do administrador. */
async function enviarEmail(){const b=$("mfaReenviar");b.disabled=true;info("A enviar o código…");erro("");
  try{const r=await S().chamarFuncao("recuperar-acesso",{acao:"codigo_entrada"});
    $("mfaTexto").textContent=`Enviámos um código de 6 dígitos para ${r?.para||"o seu email"}. Vale 10 minutos e só funciona neste aparelho.`;
    info("Pode demorar 1 a 2 minutos. Se não o vir, procure na pasta de spam ou de promoções.")}
  catch(e){info("");$("mfaTexto").textContent="Não conseguimos enviar o código por email. Tente «Enviar outro código» daqui a pouco ou use a aplicação de autenticação.";erro(msg(e));if(temApp)ecra("app")}
  finally{clearTimeout(espera);espera=setTimeout(()=>{b.disabled=false},30000)}}

/** Prepara a aplicação de autenticação (só quando o administrador a escolhe). */
async function prepararApp(){const sb=await S().cliente();const{data:f}=await sb.auth.mfa.listFactors(),v=(f?.totp||[]).find(x=>x.status==="verified");
  if(v){fator=v.id;return ecra("app")}
  for(const x of(f?.all||[]).filter(x=>x.status!=="verified")){try{await sb.auth.mfa.unenroll({factorId:x.id})}catch(_){}}
  const{data:e,error}=await sb.auth.mfa.enroll({factorType:"totp",friendlyName:"Elolog empresa "+new Date().toISOString().slice(0,10)});
  if(error)throw new Error("Não foi possível preparar a aplicação. Tente novamente ou use o código por email.");
  fator=e.id;$("mfaQr").src=e.totp.qr_code;$("mfaSegredo").textContent=e.totp.secret;ecra("registar")}

window.elologMfaEmpresa=async function(c){cred=c;erro("");info("");
  ["authPage1","providerCompanyPage","providerEmployeePage","providerFuncPage"].forEach(id=>{const el=$(id);if(el)el.style.display="none"});pag.style.display="block";
  temApp=false;fator=null;
  try{const sb=await S().cliente(),{data:f}=await sb.auth.mfa.listFactors(),v=(f?.totp||[]).find(x=>x.status==="verified");if(v){temApp=true;fator=v.id}}catch(_){}
  if(temApp)return ecra("app");   // quem já usa a aplicação continua a usá-la (e pode pedir o código por email)
  ecra("email");$("mfaTexto").textContent="A enviar um código de 6 dígitos para o seu email…";enviarEmail()};

async function verificar(){const codigo=$("mfaCodigo").value.trim(),b=$("mfaVerificar");if(!/^\d{6}$/.test(codigo))return erro("Escreva os 6 dígitos do código.");b.disabled=true;erro("");
  try{const sb=await S().cliente();
    if(modo==="email"){const{data,error}=await sb.rpc("confirmar_codigo_email",{p_codigo:codigo});if(error)throw error;
      if(data!==true)return erro("Código errado ou expirado. Confirme os 6 dígitos ou peça outro código.");}
    else{const{data:ch,error}=await sb.auth.mfa.challenge({factorId:fator});if(error)throw error;
      const{error:e2}=await sb.auth.mfa.verify({factorId:fator,challengeId:ch.id,code:codigo});if(e2)return erro("Código errado ou expirado. Use o código que está agora na aplicação.");
      await window.elologReserva?.depoisDoTelemovel()}
    await concluir()}
  catch(e){erro(msg(e))}finally{b.disabled=false}}
/** Abre a sessão da empresa depois do 2.º passo (código por email, da aplicação OU de reserva). */
async function concluir(){const sb=await S().cliente();if(!cred)throw new Error("Recomece a entrada da empresa.");
    const{data,error:e3}=await sb.rpc("abrir_sessao_empresa",{p_nome:cred.nome,p_nif:cred.nif,p_senha:cred.senha});if(e3)throw e3;const r=Array.isArray(data)?data[0]:data;
    if(!r?.ok)return erro(r?.mensagem==="MFA_NECESSARIO"?"A verificação não ficou registada. Peça outro código e tente de novo.":(r?.mensagem||"Não foi possível abrir a sessão da empresa."));
    currentUser={email:r.email,role:"prestador",name:r.funcionario_nome,providerFunction:FUNCAO[r.papel]||"operador",providerCompany:{id:r.empresa_id,name:r.empresa_nome,nif:cred.nif||"",server:true}};
    cred=null;sessionStorage.setItem("th_user",JSON.stringify(currentUser));localStorage.removeItem("th_user");startApp()}
window.elologMfaEmpresaConcluir=async()=>{try{await concluir()}catch(e){erro(msg(e))}};
$("mfaVerificar").onclick=verificar;$("mfaCodigo").addEventListener("keydown",e=>{if(e.key==="Enter")verificar()});
$("mfaReenviar").onclick=enviarEmail;
$("mfaPorEmail").onclick=()=>{ecra("email");enviarEmail()};
$("mfaPorApp").onclick=async()=>{info("");try{await prepararApp()}catch(e){erro(msg(e))}};
$("mfaCancelar").onclick=async()=>{cred=null;try{(await S().cliente()).auth.signOut()}catch(_){}window.showAuthPage("providerCompanyPage")};
})();
