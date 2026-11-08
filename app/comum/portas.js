/* Elolog — entrada mais fácil (v79; v118: a equipa Elolog entra pela Consola, em www.elolog.pt/admin, sem passar pela área de cliente),
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
if(!q.has("acesso")&&!q.has("cliente")&&!q.has("repor")&&!q.has("repor-empresa")&&!q.has("confirmado")&&ultimo==="prestador"){
  setTimeout(()=>{if(!logado()&&!sessionStorage.getItem("th_user"))location.replace(location.pathname+"?acesso="+ultimo)},150)}
else if(q.has("acesso")||q.has("cliente"))gravar(K,porta);

/* 2) separadores no topo do cartão de login */
const card=document.querySelector("#loginScreen .login-card");
if(card&&!$("portaTabs")){card.insertAdjacentHTML("afterbegin",`<nav id="portaTabs" class="porta-tabs" aria-label="Tipo de acesso">
    <button type="button" data-porta="cliente" class="${porta==="cliente"?"ativa":""}" aria-current="${porta==="cliente"}">Cliente</button>
    <button type="button" data-porta="prestador" class="${porta==="prestador"?"ativa":""}" aria-current="${porta==="prestador"}">Prestador</button></nav>`);
  const reg=card.querySelector(".auth-register-actions");
  card.addEventListener("click",e=>{const b=e.target.closest("[data-porta]");if(b&&b.dataset.porta!==porta)ir(b.dataset.porta)});
  if(porta==="administracao"){$("portaTabs").hidden=true;consola();setTimeout(consola,400);setTimeout(consola,1500)}}

/* Consola Elolog: a entrada da equipa, sem nada da área de cliente (navegação do site, rodapé, assistente, textos para clientes) */
function consola(){document.documentElement.classList.add("porta-consola");document.title="Consola Elolog";
  const c=document.querySelector("#loginScreen .auth-brand-content");
  if(c){const t=c.querySelector(".auth-brand-copy");if(t)t.innerHTML="<h2>A operação Elolog,<br>num só lugar.</h2><p>Prestadores, encomendas, tarifários e apoio. Acesso reservado à equipa, com verificação em dois passos.</p>";
    const tr=c.querySelector(".auth-brand-trust");if(tr)tr.innerHTML="<span>Acesso protegido</span><span>Cada ação fica registada</span>"}
  const w=document.querySelector("#authPage1 .auth-welcome");if(w)w.textContent="Consola Elolog";
  const h=document.querySelector("#authPage1 h1");if(h&&/Painel Administrativo/i.test(h.textContent))h.textContent="Entrar na consola"}

/* 3) prestador: lembrar a empresa e o email do funcionário neste aparelho */
const nome=$("providerCompanyName"),nif=$("providerCompanyNif"),em=$("providerEmployeeEmail"),guardado=ler(KE,null);
if(nif&&!$("portaLembrar")){nif.closest(".form-group").insertAdjacentHTML("afterend",`<label class="porta-lembrar"><input type="checkbox" id="portaLembrar"${guardado?" checked":""}> Lembrar a empresa neste aparelho</label>`);
  if(guardado){nome.value=guardado.nome||"";nif.value=guardado.nif||"";if(em&&guardado.email)em.value=guardado.email;setTimeout(()=>$("providerCompanyPassword")?.focus(),300)}
  const guardar=()=>{if($("portaLembrar").checked)gravar(KE,{nome:nome.value.trim(),nif:nif.value.trim(),email:(em?.value||guardado?.email||"").trim()});else gravar(KE,null)};
  $("providerCompanyContinue")?.addEventListener("click",guardar,true);$("providerEmployeeLogin")?.addEventListener("click",()=>{if($("portaLembrar").checked){const g=ler(KE,{});g.email=(em?.value||"").trim();gravar(KE,g)}},true);
  $("portaLembrar").addEventListener("change",guardar)}
window.elologPortas={ir};
})();
