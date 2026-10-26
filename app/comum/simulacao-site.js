/* Elolog — v62: as simulações da área de cliente, do prestador (simulação direta) e da administração usam o mesmo desenho
   do simulador do site: cada bloco é um cartão com ícone, título, descrição curta e «ETAPA 0n». Só acrescenta um cabeçalho
   e classes; não mexe nos campos nem nos cálculos. */
(function(){
  const SUB={rota:"Origem, destino, data e recolha.",destinatario:"Dados de quem recebe a encomenda.",volumes:"Registe cada carga. O volume é calculado por Comprimento × Largura × Altura.",
    cliente:"Cliente para quem é feita a simulação.",prestador:"Prestador que vai realizar o serviço."};
  const esc=v=>String(v||"").replace(/[&<>"]/g,c=>"&#"+c.charCodeAt(0)+";");
  function tipo(s){return s.classList.contains("sim-route-section")?"rota":s.classList.contains("sim-recipient-section")?"destinatario":s.classList.contains("sim-volumes-section")?"volumes":s.dataset.ssTipo||""}
  function preparar(raiz){if(!raiz)return;let n=0;
    raiz.querySelectorAll(".client-sim-section").forEach(s=>{if(s.dataset.ss)return;n++;s.dataset.ss="1";const t=tipo(s);
      const h=s.querySelector(":scope>h4, :scope>h3, :scope>.sim-section-head h4, :scope>.sim-section-head h3");if(!h)return;
      const ic=h.querySelector(".ic")?.className.replace(/\bic\b/,"").trim()||"ic-box",titulo=h.textContent.trim().replace(/^Destinatário$/,"Destinatário da encomenda");
      const cab=document.createElement("header");cab.className="ss-cabeca";
      cab.innerHTML=`<span class="ss-icone" aria-hidden="true"><i class="ic ${esc(ic)}"></i></span><div><strong>${esc(titulo)}</strong><small>${esc(SUB[t]||(/^remetente/i.test(titulo)?"Dados de quem envia a carga.":""))}</small></div><em aria-hidden="true">Etapa 0${[...raiz.querySelectorAll(".client-sim-section")].indexOf(s)+1}</em>`;
      s.classList.add("ss-cartao");s.prepend(cab);const oc=x=>{x.classList.add("ss-oculto");x.style.setProperty("display","none","important")};oc(h.closest(".sim-section-head")||h);
      s.querySelectorAll(":scope>.section-kicker,:scope>.destinatario-help").forEach(oc)});
    raiz.querySelector(".client-sim-results")?.classList.add("ss-resumo")}
  function tudo(){["clientSimulation","providerDirectSimulation","adminSimulation"].forEach(id=>preparar(document.getElementById(id)))}
  window.elologSimulacaoSite={preparar,tudo};
  const ver=()=>{tudo();new MutationObserver(()=>{clearTimeout(ver.t);ver.t=setTimeout(tudo,60)}).observe(document.body,{childList:true,subtree:true})};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ver);else ver();
})();
