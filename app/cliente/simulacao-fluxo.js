/* Elolog — fluxo da simulação do cliente (v153).
   1) Depois de «Avançar para propostas», esse botão sai: ficam «Rever simulação» e «Criar encomenda».
   2) Depois de criar a encomenda, o cartão mostra só o registo do pedido (número, prestador, valor e o que acontece a seguir). */
(function(){"use strict";
const $=id=>document.getElementById(id);
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const botaoAvancar=()=>document.querySelector('#clientSimulation .client-simulation-primary');
function mostrarAvancar(v){const b=botaoAvancar();if(b)b.hidden=!v}
const correr=window.runClientSimulation;
if(typeof correr==="function")window.runClientSimulation=function(){const r=correr.apply(this,arguments);
  if(typeof clienteSimulacaoCriada!=="undefined"&&clienteSimulacaoCriada)mostrarAvancar(false);return r};
const rever=window.editarSimulacaoCliente;
if(typeof rever==="function")window.editarSimulacaoCliente=function(){mostrarAvancar(true);const box=$("clientCreateShipment");if(box)box.classList.remove("sim-concluida");return rever.apply(this,arguments)};

/** Cartão final: só o registo do pedido. d = {codigo, prestador, valor, aguardaPreco} */
window.elologSimFinal=function(d){const box=$("clientCreateShipment");if(!box)return;const card=box.querySelector(".shipment-create-card")||box;
  box.hidden=false;box.classList.add("sim-concluida");mostrarAvancar(false);
  ["clientProviderProposals","clientSimulationResult"].forEach(id=>{const el=$(id);if(el){el.hidden=true;el.setAttribute("aria-hidden","true")}});
  card.innerHTML=`<div class="sim-final" role="status">
    <div class="sim-final-topo"><span class="sim-final-icone" aria-hidden="true"><i class="ic ic-circle-check"></i></span><div><span class="eyebrow">Pedido enviado</span>
      <h4>${d.aguardaPreco?"O prestador vai indicar o preço":"A aguardar a confirmação do prestador"}</h4></div></div>
    <dl class="sim-final-dados"><div><dt>N.º do pedido</dt><dd>${esc(d.codigo||"—")}</dd></div><div><dt>Prestador</dt><dd>${esc(d.prestador||"—")}</dd></div>
      <div><dt>Valor</dt><dd>${d.aguardaPreco?"A aguardar preço":esc(d.valor||"—")}</dd></div></dl>
    <p class="sim-final-nota">Recebe uma notificação quando o prestador responder. Pode acompanhar o pedido em «Encomendas».</p>
    <div class="sim-final-acoes"><button type="button" class="btn-secondary" onclick="showPage('tracking')">Ver as minhas encomendas</button>
      <button type="button" class="btn-secondary" onclick="window.elologManterEcra?.guardar('showPage','clientSimulation');location.reload()">Fazer outra simulação</button></div></div>`;
  card.scrollIntoView?.({behavior:"smooth",block:"start"})};
})();
