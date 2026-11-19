/* Elolog v2 — novo ecrã de entrada (só apresentação). Primeiro escolhe-se o tipo de acesso (Cliente ou Empresa prestadora);
   depois aparece o formulário de sempre, com «Mudar» para voltar à escolha. Usa a mesma navegação de portas.js
   (?cliente / ?acesso=prestador e a memória elolog_porta). Contas, palavras-passe e Supabase iguais. A Consola (/admin) não muda. */
(function(){"use strict";
  const $=id=>document.getElementById(id),K="elolog_porta";
  const q=new URLSearchParams((window.ELOLOG_RETORNO||location).search||"");
  const porta=q.get("acesso")||"cliente";
  if(porta==="administracao")return;
  let escolhido=q.has("acesso")||q.has("cliente");
  try{if(localStorage.getItem(K))escolhido=true}catch(_){}
  const ir=p=>{try{localStorage.setItem(K,JSON.stringify(p))}catch(_){}location.href=location.pathname+(p==="cliente"?"?cliente":"?acesso="+p)};
  const OPCOES=[
    ["cliente","user","Cliente","Simular envios, acompanhar encomendas e pagar."],
    ["prestador","building","Empresa prestadora","Entrar com o NIF da empresa e o seu n.º de funcionário."]];
  const NOMES={cliente:"Cliente",prestador:"Empresa prestadora"};
  function montar(){
    const card=document.querySelector("#loginScreen .login-card");
    if(!card||$("eloEscolha"))return!!card;
    card.insertAdjacentHTML("afterbegin",
      `<section id="eloEscolha" class="elo-escolha" aria-labelledby="eloEscolhaTitulo" hidden>
        <h1 id="eloEscolhaTitulo">Entrar na Elolog</h1><p>Escolha o tipo de acesso.</p>
        <div class="elo-escolha-opcoes">${OPCOES.map(([p,ic,t,d])=>`<button type="button" class="elo-opcao" data-escolha="${p}">
          <span class="elo-opcao-ic"><i class="ic ic-${ic}" aria-hidden="true"></i></span>
          <span class="elo-opcao-tx"><strong>${t}</strong><small>${d}</small></span>
          <i class="ic ic-arrow" aria-hidden="true"></i></button>`).join("")}</div>
      </section>
      <div id="eloContexto" class="elo-contexto" hidden><span>A entrar como <b>${NOMES[porta]||"Cliente"}</b></span>
        <button type="button" id="eloMudar" class="elo-mudar">Mudar</button></div>`);
    card.addEventListener("click",e=>{
      const b=e.target.closest("[data-escolha]");if(b){if(b.dataset.escolha===porta&&escolhido){mostrar(false);return}ir(b.dataset.escolha);return}
      if(e.target.closest("#eloMudar"))mostrar(true)});
    if(porta==="prestador"){const c=document.querySelector("#loginScreen .auth-brand-copy");
      if(c)c.innerHTML="<h2>A operação da sua empresa,<br>num só lugar.</h2><p>Pedidos, encomendas, recolhas e recebimentos da sua equipa.</p>"}
    return true}
  function mostrar(escolha){
    const card=document.querySelector("#loginScreen .login-card");if(!card)return;
    card.classList.toggle("elo-a-escolher",escolha);
    $("eloEscolha").hidden=!escolha;$("eloContexto").hidden=escolha;
    if(escolha){const b=card.querySelector(`[data-escolha="${porta}"]`);b&&b.classList.add("ultima")}}
  function iniciar(){if(montar())mostrar(!escolhido)}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",()=>setTimeout(iniciar,0));else setTimeout(iniciar,0);
})();
