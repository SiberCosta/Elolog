/* Elolog — recuperar a palavra-passe com o servidor real (Edge Function «recuperar-acesso»).
   Contas pessoais (clientes, funcionários, equipa Elolog): email com ligação ?repor=… e código de 6 dígitos (1 hora, uma vez).
   Empresa (1.º passo do prestador): nome + NIF → código e ligação ?repor-empresa=… no email oficial da empresa (30 min).
   Sem servidor ativo (modo demo) nada muda: continuam as janelas locais de login.js. */
(function(){"use strict";
const S=()=>window.ELOLogServidor,ativo=()=>!!(S()&&S().ativo&&S().ativo());if(!ativo())return;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const fraca=s=>s.length<8||s.length>72||!/[a-zA-Z]/.test(s)||!/\d/.test(s);
const REGRA='<p class="password-rule">Mínimo 8 caracteres, com letras e números.</p>';
const senhas=p=>`<label>Nova palavra-passe<div class="auth-password-wrap"><input id="${p}1" type="password" autocomplete="new-password" maxlength="72" required><button type="button" class="auth-password-toggle" aria-label="Mostrar palavra-passe" onclick="toggleRecoveryPassword(this,'${p}1')">👁</button></div></label>
<label>Repetir a nova palavra-passe<input id="${p}2" type="password" autocomplete="new-password" maxlength="72" required></label>${REGRA}`;
const val=id=>document.getElementById(id)?.value||"";
function fechar(){document.getElementById("recModal")?.remove();document.body.style.overflow=""}
/** Abre a janela com um ou mais passos (formulários); só o primeiro fica visível. */
function janela(etiqueta,titulo,texto,passos){fechar();const m=document.createElement("div");m.id="recModal";m.className="password-recovery-modal";
m.innerHTML=`<section class="password-recovery-dialog" role="dialog" aria-modal="true" aria-labelledby="recTitulo"><header><div><small>${esc(etiqueta)}</small><h2 id="recTitulo">${esc(titulo)}</h2><p id="recTexto">${texto}</p></div><button type="button" aria-label="Fechar" data-fechar>×</button></header>
${passos.map((p,i)=>`<form id="recPasso${i}" ${i?"hidden":""} novalidate>${p.html}<div class="password-recovery-feedback" id="recAviso${i}" role="status"></div><div class="password-recovery-actions"><button type="button" class="btn-secondary" data-fechar>Cancelar</button><button type="submit" class="btn-primary">${esc(p.botao)}</button></div></form>`).join("")}</section>`;
m.addEventListener("click",e=>{if(e.target===m||e.target.closest("[data-fechar]"))fechar()});
passos.forEach((p,i)=>m.querySelector("#recPasso"+i).addEventListener("submit",async e=>{e.preventDefault();const f=e.currentTarget,b=f.querySelector("[type=submit]"),a=f.querySelector(".password-recovery-feedback");
a.className="password-recovery-feedback";a.textContent="A processar…";b.disabled=true;try{const r=await p.acao();if(r===false){a.textContent="";return}if(typeof r==="string"){a.className="password-recovery-feedback success";a.textContent=r}}
catch(x){a.className="password-recovery-feedback error";a.textContent=x?.message||"Não foi possível concluir. Tente novamente."}finally{b.disabled=false}}));
document.body.appendChild(m);document.body.style.overflow="hidden";setTimeout(()=>m.querySelector("#recPasso0 input")?.focus(),50);return m}
function mostrarPasso(i,texto){document.querySelectorAll("#recModal form").forEach((f,j)=>{f.hidden=j!==i});if(texto)document.getElementById("recTexto").innerHTML=texto;setTimeout(()=>document.querySelector(`#recPasso${i} input`)?.focus(),50)}
function lerSenhas(p){const a=val(p+"1"),b=val(p+"2");if(fraca(a))throw new Error("A palavra-passe deve ter 8 a 72 caracteres, com letras e números.");if(a!==b)throw new Error("As duas palavras-passe não coincidem.");return a}
function traduzir(e){const m=String(e?.message||e||"");if(/expired|invalid|not found|otp/i.test(m))return new Error("A ligação ou o código expirou ou já foi usado. Peça uma nova recuperação.");
if(/same.*password|different from the old/i.test(m))return new Error("A nova palavra-passe tem de ser diferente da anterior.");if(/weak|Password should/i.test(m))return new Error("A palavra-passe não cumpre os requisitos do servidor.");
if(/aal2|insufficient_aal/i.test(m))return new Error("Indique o código da aplicação de autenticação.");return new Error(S().mensagem?S().mensagem(e):m)}
function entrar(email){fechar();if(typeof showPlatformNotice==="function")showPlatformNotice("Palavra-passe alterada. Já pode entrar com a nova palavra-passe.","success");
const c=document.getElementById("directLoginEmail");if(c&&email){c.value=email;document.getElementById("directLoginPassword")?.focus()}}

/* ---- Contas pessoais ---- */
let pendente=null;   // {sb, senha, email} quando falta o código MFA
async function concluir(sb,senha,email){const{data:n}=await sb.auth.mfa.getAuthenticatorAssuranceLevel();
if(n?.nextLevel==="aal2"&&n?.currentLevel!=="aal2"){pendente={sb,senha,email};mostrarPasso(document.querySelectorAll("#recModal form").length-1,"A sua conta tem verificação em dois passos. Indique o código de 6 dígitos da aplicação de autenticação.");return false}
const{error}=await sb.auth.updateUser({password:senha});if(error)throw traduzir(error);
try{await S().chamarFuncao("recuperar-acesso",{acao:"alterada"})}catch(_){}
await sb.auth.signOut({scope:"global"}).catch(()=>{});pendente=null;entrar(email);return false}
const passoMfa={botao:"Confirmar",html:'<label>Código da aplicação de autenticação<input id="recMfa" inputmode="numeric" maxlength="6" autocomplete="one-time-code" required></label>',
acao:async()=>{if(!pendente)throw new Error("Recomece a recuperação.");const c=val("recMfa").trim();if(!/^\d{6}$/.test(c))throw new Error("Indique os 6 dígitos.");
const{data:f}=await pendente.sb.auth.mfa.listFactors(),fator=(f?.totp||[]).find(x=>x.status==="verified");if(!fator)throw new Error("Não foi encontrado o fator de autenticação.");
const{error}=await pendente.sb.auth.mfa.challengeAndVerify({factorId:fator.id,code:c});if(error)throw new Error("Código errado. Tente o código seguinte da aplicação.");return concluir(pendente.sb,pendente.senha,pendente.email)}};

function recuperarConta(email="",etiqueta="ACESSO À CONTA"){let enviado="";
janela(etiqueta,"Recuperar palavra-passe","Indique o email da conta. Enviamos uma ligação e um código para criar uma nova palavra-passe.",[
{botao:"Enviar ligação",html:`<label>Email da conta<input id="recEmail" type="email" autocomplete="email" maxlength="254" value="${esc(email)}" required></label>`,
acao:async()=>{const e=val("recEmail").trim().toLowerCase();if(!/^\S+@\S+\.\S+$/.test(e))throw new Error("Indique um email válido.");await S().chamarFuncao("recuperar-acesso",{acao:"pedir",email:e});enviado=e;
mostrarPasso(1,`Se existir uma conta com <strong>${esc(e)}</strong>, recebe dentro de instantes um email da Elolog. Carregue no botão do email <em>ou</em> escreva aqui o código de 6 dígitos (veja também o spam).`);return false}},
{botao:"Guardar nova palavra-passe",html:`<label>Código de 6 dígitos<input id="recCodigo" inputmode="numeric" maxlength="6" autocomplete="one-time-code" required></label>${senhas("recNova")}`,
acao:async()=>{const c=val("recCodigo").trim();if(!/^\d{6}$/.test(c))throw new Error("Indique os 6 dígitos do email.");const s=lerSenhas("recNova"),sb=await S().cliente();
const{error}=await sb.auth.verifyOtp({email:enviado,token:c,type:"recovery"});if(error)throw traduzir(error);return concluir(sb,s,enviado)}},passoMfa])}

function linkConta(hash){janela("ACESSO À CONTA","Criar nova palavra-passe","Escolha a nova palavra-passe da sua conta Elolog.",[
{botao:"Guardar nova palavra-passe",html:senhas("recNova"),acao:async()=>{const s=lerSenhas("recNova"),sb=await S().cliente();
const{data,error}=await sb.auth.verifyOtp({token_hash:hash,type:"recovery"});if(error)throw traduzir(error);return concluir(sb,s,data?.user?.email||"")}},passoMfa])}

/* ---- Palavra-passe da empresa (1.º passo do prestador) ---- */
function recuperarEmpresa(){let dados=null;
janela("ACESSO DA EMPRESA","Recuperar palavra-passe da empresa","Indique o nome e o NIF da empresa. O código vai para o email oficial da empresa registado na Elolog.",[
{botao:"Enviar código",html:'<label>Nome da empresa<input id="recEmpNome" maxlength="200" autocomplete="organization" required></label><label>NIF<input id="recEmpNif" inputmode="numeric" maxlength="30" required></label>',
acao:async()=>{const nome=val("recEmpNome").trim(),nif=val("recEmpNif").trim();if(!nome||!nif)throw new Error("Indique o nome da empresa e o NIF.");
await S().chamarFuncao("recuperar-acesso",{acao:"empresa_pedir",nome,nif});dados={nome,nif};mostrarPasso(1,"Se os dados estiverem certos, o email oficial da empresa recebe um código de 6 dígitos (válido 30 minutos).");return false}},
{botao:"Guardar nova palavra-passe",html:`<label>Código de 6 dígitos<input id="recEmpCodigo" inputmode="numeric" maxlength="6" autocomplete="one-time-code" required></label>${senhas("recEmpNova")}`,
acao:async()=>{const codigo=val("recEmpCodigo").trim(),senha=lerSenhas("recEmpNova");if(!/^\d{6}$/.test(codigo))throw new Error("Indique os 6 dígitos do email.");
await S().chamarFuncao("recuperar-acesso",{acao:"empresa_confirmar",...dados,codigo,senha});empresaOk();return false}}])}
function linkEmpresa(id,codigo){janela("ACESSO DA EMPRESA","Nova palavra-passe da empresa","Escolha a nova palavra-passe de acesso da empresa (1.º passo do login do prestador).",[
{botao:"Guardar nova palavra-passe",html:senhas("recEmpNova"),acao:async()=>{const senha=lerSenhas("recEmpNova");await S().chamarFuncao("recuperar-acesso",{acao:"empresa_confirmar",id,codigo,senha});empresaOk();return false}}])}
function empresaOk(){fechar();if(typeof showPlatformNotice==="function")showPlatformNotice("Palavra-passe da empresa alterada. Já pode entrar.","success");try{if(typeof showAuthPage==="function")showAuthPage("providerCompanyPage")}catch(_){}}

/* ---- Ligar aos botões existentes e às ligações dos emails ---- */
window.openClientPasswordRecovery=(email="",origem="client")=>recuperarConta(email,origem==="provider"?"ACESSO DO CLIENTE":"ACESSO À CONTA");
window.openProviderPasswordRecovery=(tipo="company")=>tipo==="employee"?recuperarConta(val("providerEmployeeEmail")||"","ACESSO DO FUNCIONÁRIO"):recuperarEmpresa();
const q=new URLSearchParams((window.ELOLOG_RETORNO||location).search||""),rep=q.get("repor"),repE=q.get("repor-empresa");   // login.js já limpou o endereço
if(rep||repE){try{if(location.search)history.replaceState(null,"",location.pathname)}catch(_){}
const abrir=()=>{if(rep&&/^[\w-]{10,200}$/.test(rep))linkConta(rep);else if(repE){const[id,cod]=repE.split(".");if(/^[0-9a-f-]{36}$/i.test(id||"")&&/^\d{6}$/.test(cod||""))linkEmpresa(id,cod)}};
document.readyState==="loading"?document.addEventListener("DOMContentLoaded",()=>setTimeout(abrir,300)):setTimeout(abrir,300)}
window.ELOLogRecuperar={recuperarConta,recuperarEmpresa,linkConta,linkEmpresa,fechar};
})();
