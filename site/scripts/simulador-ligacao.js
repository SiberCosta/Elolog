/* Elolog — simulador público ligado à plataforma (v148).
   O site público não lê tarifas nem prestadores (só o servidor sabe os preços, e o público não acede ao servidor).
   Depois de preencher a simulação, o visitante passa para a área de cliente com os dados já preenchidos: entra ou cria
   conta, e vê os preços reais calculados pelas tarifas de cada prestador. Nada fica gravado como pedido no navegador. */
(function(){"use strict";
const CHAVE="simulacao_site_eloLog",$=id=>document.getElementById(id);
const val=id=>$(id)?.value.trim()||"";

function recolher(){const vol=[...document.querySelectorAll("#lista-volumes > div")].map(l=>{const n=c=>parseFloat(l.querySelector(c)?.value)||0;
    return{descricao:l.querySelector(".carga")?.value.trim()||"",qtd:n(".qtd")||1,peso:n(".peso"),comp:n(".comp"),larg:n(".larg"),alt:n(".alt")}}).filter(v=>v.descricao);
  return{em:Date.now(),origem:val("origem"),destino:val("destino"),moradaRecolha:val("morada-recolha"),recolha:$("pretende-recolha")?.value||"sim",data:val("data-prevista"),
    carga:$("tipo-carga-detalhe")?.value||"",valorDeclarado:val("preco-declarado"),observacoes:val("observacoes-carga"),volumes:vol,
    destinatario:{nome:val("destinatario-nome"),nif:val("destinatario-nif"),telefone:val("destinatario-telefone"),email:val("destinatario-email"),morada:val("destinatario-morada")}}}

function seguir(){try{localStorage.setItem(CHAVE,JSON.stringify(recolher()))}catch(_){}location.href="../app/area-cliente.html?simulacao=site"}
window.elologSimulacaoSite={seguir};

function ligar(){const r=window.renderizarPrestadores;if(typeof r!=="function"||r.__ligacao)return;
  window.renderizarPrestadores=function(){const sec=$("prestadores-section"),grid=$("prestadores-grid");if(!sec||!grid)return r.apply(this,arguments);
    sec.hidden=false;sec.classList.add("visible");sec.setAttribute("aria-hidden","false");
    grid.innerHTML=`<div class="providers-empty sl-cartao"><strong>Os preços reais estão na sua área de cliente</strong>
      <p>Cada transportadora tem as suas tarifas. Para as comparar e enviar o pedido, entre ou crie conta gratuita: os dados que preencheu passam já preenchidos.</p>
      <button type="button" class="btn-primary sl-botao" onclick="elologSimulacaoSite.seguir()">Ver preços e enviar pedido</button></div>`;
    const acao=$("acao-criar-proposta");if(acao)acao.hidden=true;const st=$("proposta-action-status");if(st)st.textContent=""};window.renderizarPrestadores.__ligacao=1;
  if(typeof window.criarPropostaAoPrestador==="function")window.criarPropostaAoPrestador=seguir}
ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);window.addEventListener("load",ligar);
})();
