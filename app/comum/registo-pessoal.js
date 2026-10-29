/* Elolog — Criar perfil (v76): conta Pessoal com nome + telemóvel ou email (confirmados por código/ligação),
   NIF e email obrigatórios só para Empresa, política de privacidade lida antes de aceitar e botões certos para cada tipo.
   Também deixa entrar com o telemóvel. Carrega depois de registo.js. */
(function(){"use strict";
const $=id=>document.getElementById(id),S=()=>window.ELOLogServidor,online=()=>!!S()?.ativo?.();
const tipoConta=()=>document.querySelector("input[name=regTipo]:checked")?.value||"particular";
const pessoal=()=>$("profileType")?.value==="cliente"&&tipoConta()==="particular";
const via=()=>document.querySelector("input[name=regVia]:checked")?.value||"email";
const liga=(el,on)=>{if(!el)return;el.disabled=!on;el.setAttribute("aria-disabled",String(!on))};
const msg=(m,t)=>window.showProfileRegistrationMessage?.(m,t||"error");
/** Telemóvel em formato internacional (+351…). 9 algarismos começados por 9/2 = Portugal. Devolve "" se não for válido. */
function telefone(v){let t=String(v||"").replace(/[\s().-]/g,"");if(t.startsWith("00"))t="+"+t.slice(2);if(/^[29]\d{8}$/.test(t))t="+351"+t;return/^\+\d{8,15}$/.test(t)?t:""}
const pareceTelefone=v=>!/@/.test(v)&&/^[+\d\s().-]{7,}$/.test(String(v||"").trim());
const nifOk=n=>{if(!/^\d{9}$/.test(n))return false;const s=[...n].slice(0,8).reduce((t,d,i)=>t+d*(9-i),0),c=11-s%11;return(c>=10?0:c)==n[8]};

/* ---- campos extra: confirmar por email ou telemóvel, passo do código, leitura da política ---- */
function montar(){if($("regVia"))return;const grelha=$("profileEmail")?.closest(".profile-form-grid");if(!grelha)return;
$("profileEmail").closest("label").insertAdjacentHTML("beforebegin",`<fieldset id="regVia" class="reg-via full"><legend>Confirmar a conta por</legend>
    <label><input type="radio" name="regVia" value="email" checked> E-mail</label><label><input type="radio" name="regVia" value="telemovel"> Telemóvel (SMS)</label></fieldset>`);
  $("profileDataStep").insertAdjacentHTML("afterend",`<section id="regCodigo" class="reg-codigo" hidden><h3>Confirme o seu contacto</h3><p id="regCodigoTexto"></p>
    <label>Código de 6 dígitos<input id="regCodigoValor" inputmode="numeric" maxlength="6" autocomplete="one-time-code"></label>
    <div class="reg-codigo-acoes"><button type="button" class="btn-secondary" id="regCodigoVoltar">Voltar</button><button type="button" class="btn-primary" id="regCodigoOk">Confirmar código</button></div></section>`);
  document.body.insertAdjacentHTML("beforeend",`<div id="regPolitica" class="reg-politica" hidden role="dialog" aria-modal="true" aria-labelledby="regPoliticaTitulo"><div class="reg-politica-caixa">
    <header><h3 id="regPoliticaTitulo">Política de privacidade</h3><button type="button" class="btn-secondary" data-fechar aria-label="Fechar">×</button></header>
    <iframe id="regPoliticaDoc" title="Termos e política de privacidade da Elolog"></iframe>
    <footer><small id="regPoliticaFalta">Leia até ao fim da política de privacidade.</small><button type="button" class="btn-primary" id="regPoliticaLi" disabled>Li a política de privacidade</button></footer></div></div>`);
  document.addEventListener("change",e=>{if(e.target.name==="regVia"||e.target.name==="regTipo")rotulos();if(e.target.id==="profileConsent")botoes()});
  $("regLerPolitica").addEventListener("click",e=>{e.preventDefault();abrirPolitica()});
  $("regPolitica").addEventListener("click",e=>{if(e.target.id==="regPolitica"||e.target.closest("[data-fechar]"))$("regPolitica").hidden=true});
  $("regPoliticaLi").onclick=()=>{lida=true;$("regPolitica").hidden=true;liga($("profileConsent"),true);$("profileConsent").checked=true;$("regPoliticaAviso").hidden=true;botoes();$("profileConsent").focus()};
  $("regCodigoVoltar").onclick=()=>passoCodigo(false);$("regCodigoOk").onclick=()=>confirmarCodigo()}
let lida=false;
function abrirPolitica(){const f=$("regPoliticaDoc"),ok=$("regPoliticaLi");$("regPolitica").hidden=false;liga(ok,lida);
  const ver=()=>{try{const d=f.contentDocument,sec=d.getElementById("privacidade");if(!sec)return;const fim=sec.getBoundingClientRect().bottom;if(fim<=f.contentWindow.innerHeight+30){liga(ok,true);$("regPoliticaFalta").textContent="Pode confirmar a leitura."}}catch(_){liga(ok,true)}};
  f.onload=()=>{try{f.contentDocument.querySelectorAll("header,nav,footer,.whatsapp-float,.elo-assistant").forEach(x=>x.style.display="none");f.contentWindow.addEventListener("scroll",ver,{passive:true});
    f.contentDocument.getElementById("privacidade")?.scrollIntoView();setTimeout(ver,300)}catch(_){liga(ok,true)}};
  if(!f.src)f.src="../site/legal.html#privacidade";else ver();setTimeout(()=>ok.focus(),50)}
/** Rótulos e campos visíveis conforme Pessoal/Empresa e o meio de confirmação. */
function rotulos(){if(!$("regVia"))return;const p=pessoal(),tel=via()==="telemovel";$("regVia").hidden=!p;
  $("regLblEmail").textContent=p&&tel?"E-mail (opcional)":"E-mail";$("regLblTel").textContent=p?(tel?"Telemóvel":"Telemóvel (opcional)"):"Telefone";
  $("profilePhone").placeholder=p?"+351 9xx xxx xxx":$("profilePhone").placeholder;if(p&&$("regLblNif"))$("regLblNif").textContent="NIF pessoal (opcional)";botoes()}
/** «Criar administrador da empresa» só no registo de uma empresa prestadora; criar só depois de aceitar a política. */
function botoes(){const prest=$("profileType")?.value==="prestador",aceite=!!$("profileConsent")?.checked;const adm=$("continueToProviderPlans"),criar=$("createProfileButton");
  if(adm){if(!prest)adm.hidden=true;liga(adm,aceite)}if(criar&&!prest)liga(criar,aceite)}
const envolver=(nome,depois,antes)=>{const f=window[nome];if(typeof f!=="function")return;window[nome]=function(){if(antes){const r=antes.apply(this,arguments);if(r!==undefined)return r}const r=f.apply(this,arguments);try{depois?.()}catch(_){}return r}};
envolver("openProfileRegistration",()=>{montar();passoCodigo(false);if(!lida){$("profileConsent").checked=false;liga($("profileConsent"),false)}$("regPoliticaAviso").hidden=lida;rotulos();botoes()});
envolver("selectProfileType",()=>{rotulos();botoes()});

/* ---- criar conta Pessoal ---- */
let pendente=null;   // {nome, email, phone, nif, password, canal, contacto}
function passoCodigo(mostrar,texto){if(!$("regCodigo"))return;$("regCodigo").hidden=!mostrar;$("profileDataStep").hidden=!!mostrar;$("regTipos").hidden=!!mostrar||$("profileType").value==="prestador";
  document.querySelector(".profile-register-actions-bottom").hidden=!!mostrar;if(mostrar){$("regCodigoTexto").innerHTML=texto;$("regCodigoValor").value="";setTimeout(()=>$("regCodigoValor").focus(),50)}}
envolver("createEloLogProfile",null,function(){if(!pessoal())return;criarPessoal();return false});
async function criarPessoal(){const nome=$("profileName").value.trim(),email=$("profileEmail").value.trim().toLowerCase(),telBruto=$("profilePhone").value.trim(),nif=$("profileNif").value.trim(),
  password=$("profilePassword").value,confirmar=$("profilePasswordConfirm").value,tel=via()==="telemovel",phone=telBruto?telefone(telBruto):"";
  if(nome.length<2)return msg("Indique o seu nome.");
  if(tel&&!phone)return msg("Indique um número de telemóvel válido (ex.: 912 345 678 ou +239 …).");
  if(!tel&&!/^\S+@\S+\.\S+$/.test(email))return msg("Indique um email válido.");
  if(email&&!/^\S+@\S+\.\S+$/.test(email))return msg("O email não é válido.");if(telBruto&&!phone)return msg("O número de telemóvel não é válido.");
  if(nif&&(!nifOk(nif)||/^[5689]/.test(nif)))return msg("O NIF pessoal não é válido. Pode deixá-lo em branco.");
  if(password.length<8)return msg("A palavra-passe deve ter pelo menos 8 caracteres.");if(password!==confirmar)return msg("As palavras-passe não coincidem.");
  if(!$("profileConsent").checked)return msg("Leia e aceite a política de privacidade.");
  pendente={nome,email,phone,nif,password,canal:tel?"telemovel":"email",contacto:tel?phone:email};const b=$("createProfileButton");b.disabled=true;msg("","info");
  try{if(online()){if(tel){const sb=await S().cliente(),{error}=await sb.auth.signUp({phone,password,options:{data:{nome,nif,telefone:phone,email_contacto:email,tipo_conta:"pessoal"}}});
        if(error)throw error;passoCodigo(true,`Enviámos um SMS com um código de 6 dígitos para <strong>${phone}</strong>.`)}
      else{const r=await S().registarCliente({name:nome,nif,email,phone,password,tipoConta:"pessoal"});
        if(r.confirmar){msg("Conta criada. Enviámos um email para "+email+": abra a ligação para confirmar e depois inicie sessão.","success");setTimeout(()=>{window.closeProfileRegistration?.();$("directLoginEmail").value=email},2500)}else fim()}}
    else{const lista=JSON.parse(localStorage.getItem("elolog_profiles")||"[]");if(lista.some(p=>p.type==="cliente"&&String(p.email||"").toLowerCase()===(tel?phone:email)))throw new Error("Já existe um perfil com este "+(tel?"telemóvel.":"email."));
      passoCodigo(true,`Enviámos um código de 6 dígitos para <strong>${tel?phone:email}</strong>.<br><small>Modo de demonstração: o código é <b>123456</b>.</small>`)}}
  catch(e){const t=String(e?.message||e);msg(/sms|phone provider|unsupported phone|phone_provider/i.test(t)?"A confirmação por SMS ainda não está ativa na Elolog. Escolha «E-mail» para confirmar a conta.":(S()?.mensagem?S().mensagem(e):t))}
  finally{liga(b,$("profileConsent").checked)}}
async function confirmarCodigo(){const c=$("regCodigoValor").value.trim(),b=$("regCodigoOk");if(!/^\d{6}$/.test(c))return msg("Indique os 6 dígitos do código.");if(!pendente)return passoCodigo(false);b.disabled=true;
  try{if(online()){const sb=await S().cliente(),{data,error}=await sb.auth.verifyOtp({phone:pendente.phone,token:c,type:"sms"});if(error)throw new Error("Código errado ou expirado.");
      const g=window.__ELOLOG_INTERNO?.["servidor-adaptador@comum"]?.garantirCliente;if(g&&data?.user)await g(sb,data.user);await sb.auth.signOut()}
    else{if(c!=="123456")throw new Error("Código errado. No modo de demonstração use 123456.");const lista=JSON.parse(localStorage.getItem("elolog_profiles")||"[]"),p=pendente;
      lista.push({id:"USR-"+Date.now(),type:"cliente",accountKind:"particular",name:p.nome,nif:p.nif,phone:p.phone,email:p.canal==="telemovel"?p.phone:p.email,contactEmail:p.email,password:p.password,confirmedBy:p.canal,createdAt:new Date().toISOString(),status:"Ativo"});
      localStorage.setItem("elolog_profiles",JSON.stringify(lista))}
    fim()}catch(e){msg(e.message||"Não foi possível confirmar.")}finally{b.disabled=false}}
function fim(){const contacto=pendente?.contacto||"";passoCodigo(false);msg("Conta confirmada. Já pode entrar com "+(pendente?.canal==="telemovel"?"o telemóvel":"o email")+" e a palavra-passe.","success");pendente=null;
  setTimeout(()=>{window.closeProfileRegistration?.();const i=$("directLoginEmail");if(i){i.value=contacto;$("directLoginPassword")?.focus()}},1500)}

/* ---- entrar com o telemóvel ---- */
const login=$("directLoginEmail");if(login){login.placeholder="Email ou telemóvel";login.setAttribute("aria-label","Email ou telemóvel")}
$("directLoginButton")?.addEventListener("click",()=>{const i=$("directLoginEmail");if(i&&pareceTelefone(i.value)){const t=telefone(i.value);if(t)i.value=t}},true);
window.elologRegisto={telefone,abrirPolitica};
})();
