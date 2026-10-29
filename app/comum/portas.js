/* Elolog — entrada mais fácil (v79): separadores «Cliente | Prestador» no topo do login, ligação discreta «Equipa Elolog»,
   o aparelho lembra-se do último acesso usado e (se pedir) do nome e NIF da empresa e do email do funcionário.
   Nunca guarda palavras-passe. Endereços curtos: www.elolog.pt/prestador e www.elolog.pt/admin. */
(function(){"use strict";
const $=id=>document.getElementById(id),K="elolog_porta",KE="elolog_empresa_lembrada";
const ler=(k,d)=>{try{return JSON.parse(localStorage.getItem(k))??d}catch(_){return d}},gravar=(k,v)=>{try{v==null?localStorage.removeItem(k):localStorage.setItem(k,JSON.stringify(v))}catch(_){}};
const q=new URLSearchParams((window.ELOLOG_RETORNO||location).search||""),porta=q.get("acesso")||"cliente";
const logado=()=>{const l=$("loginScreen");return!l||getComputedStyle(l).display==="none"};
const ir=p=>{gravar(K,p);location.href=location.pathname+(p==="cliente"?"?cliente":"?acesso="+p)};

/* 1) voltar sozinho ao último acesso usado neste aparelho (só ao abrir a página sem escolher) */
const ultimo=ler(K,"cliente");
if(!q.has("acesso")&&!q.has("cliente")&&!q.has("repor")&&!q.has("repor-empresa")&&!q.has("confirmado")&&(ultimo==="prestador"||ultimo==="administracao")){
  setTimeout(()=>{if(!logado()&&!sessionStorage.getItem("th_user"))location.replace(location.pathname+"?acesso="+ultimo)},150)}
else if(q.has("acesso")||q.has("cliente"))gravar(K,porta);

/* 2) separadores no topo do cartão de login */
const card=document.querySelector("#loginScreen .login-card");
if(card&&!$("portaTabs")){card.insertAdjacentHTML("afterbegin",`<nav id="portaTabs" class="porta-tabs" aria-label="Tipo de acesso">
    <button type="button" data-porta="cliente" class="${porta==="cliente"?"ativa":""}" aria-current="${porta==="cliente"}">Cliente</button>
    <button type="button" data-porta="prestador" class="${porta==="prestador"?"ativa":""}" aria-current="${porta==="prestador"}">Prestador</button></nav>`);
  const reg=card.querySelector(".auth-register-actions");
  (reg||card).insertAdjacentHTML(reg?"afterend":"beforeend",`<p class="porta-equipa">${porta==="administracao"?'<button type="button" data-porta="cliente">← Voltar ao acesso de clientes</button>':'<button type="button" data-porta="administracao">Equipa Elolog</button>'}</p>`);
  card.addEventListener("click",e=>{const b=e.target.closest("[data-porta]");if(b&&b.dataset.porta!==porta)ir(b.dataset.porta)});
  if(porta==="administracao")$("portaTabs").hidden=true}

/* 3) prestador: lembrar a empresa e o email do funcionário neste aparelho */
const nome=$("providerCompanyName"),nif=$("providerCompanyNif"),em=$("providerEmployeeEmail"),guardado=ler(KE,null);
if(nif&&!$("portaLembrar")){nif.closest(".form-group").insertAdjacentHTML("afterend",`<label class="porta-lembrar"><input type="checkbox" id="portaLembrar"${guardado?" checked":""}> Lembrar a empresa neste aparelho</label>`);
  if(guardado){nome.value=guardado.nome||"";nif.value=guardado.nif||"";if(em&&guardado.email)em.value=guardado.email;setTimeout(()=>$("providerCompanyPassword")?.focus(),300)}
  const guardar=()=>{if($("portaLembrar").checked)gravar(KE,{nome:nome.value.trim(),nif:nif.value.trim(),email:(em?.value||guardado?.email||"").trim()});else gravar(KE,null)};
  $("providerCompanyContinue")?.addEventListener("click",guardar,true);$("providerEmployeeLogin")?.addEventListener("click",()=>{if($("portaLembrar").checked){const g=ler(KE,{});g.email=(em?.value||"").trim();gravar(KE,g)}},true);
  $("portaLembrar").addEventListener("change",guardar)}
window.elologPortas={ir};
})();
